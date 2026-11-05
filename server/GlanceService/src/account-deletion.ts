import type { Env } from './index';
import { authenticatedUser } from './users';
import { BillingError, billingBody, billingReply, isoNow } from './pricing';

// Keep financial records and a pseudonymous user ID so refunds and the ledger
// remain auditable. Media removal is durable and retried by the scheduled job.
export async function deleteAccount(env: Env, request: Request) {
  const user = await authenticatedUser(env, request), body = await billingBody(request);
  if (body.email !== user.email || body.confirm !== 'DELETE')
    throw new BillingError('confirmation_required', 'Enter your account email and confirm permanent deletion.');
  const now = isoNow();
  const result = await env.DB.batch([
    env.DB.prepare(`UPDATE users SET status='deleted',email=?,google_id=NULL,name=NULL,avatar_url=NULL,updated_at=?
      WHERE id=? AND status='active'
      AND NOT EXISTS(SELECT 1 FROM widget_tasks WHERE owner_id=? AND (status IN ('queued','claimed','running') OR (status='succeeded' AND delivery_required=1 AND delivered_at IS NULL)))
      AND NOT EXISTS(SELECT 1 FROM orders WHERE user_id=? AND status='pending')
      AND NOT EXISTS(SELECT 1 FROM refund_requests WHERE user_id=? AND status IN ('requested','processing'))`)
      .bind(`deleted-${user.id}@account.invalid`,now,user.id,`user_${user.id}`,user.id,user.id),
    env.DB.prepare(`INSERT OR IGNORE INTO account_deletions(user_id,requested_at,purge_after)
      SELECT id,?,? FROM users WHERE id=? AND status='deleted'`)
      .bind(now,new Date(Date.now()+7*86400000).toISOString(),user.id),
    ...['user_sessions','user_auth_codes'].map(table => env.DB.prepare(`DELETE FROM ${table} WHERE user_id=? AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?)`).bind(user.id,user.id)),
    env.DB.prepare('DELETE FROM user_email_codes WHERE email=? AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?)').bind(user.email,user.id),
    env.DB.prepare("UPDATE licenses SET status='deleted' WHERE user_id=? AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?)").bind(user.id,user.id),
    env.DB.prepare(`UPDATE license_devices SET released_at=?,name='Deleted device' WHERE user_id=?
      AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?)`).bind(now,user.id,user.id),
    env.DB.prepare(`UPDATE license_devices SET released_at=? WHERE user_id IN (SELECT user_id FROM team_members WHERE owner_id=?)
      AND NOT EXISTS(SELECT 1 FROM licenses WHERE licenses.user_id=license_devices.user_id AND status='active')
      AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?)`).bind(now,user.id,user.id),
    env.DB.prepare('DELETE FROM team_members WHERE (user_id=? OR owner_id=?) AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?)').bind(user.id,user.id,user.id),
    env.DB.prepare('DELETE FROM team_invites WHERE (owner_id=? OR email=?) AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?)').bind(user.id,user.email,user.id),
  ]);
  if (!result[0].meta.changes) throw new BillingError('account_busy', 'Finish or cancel active tasks and pending checkouts, and resolve refund requests before deleting your account.',409);
  return billingReply({deleted:true,mediaCleanup:'pending',financialRecordsRetained:true});
}

export async function purgeDeletedAccounts(env: Env) {
  const jobs = await env.DB.prepare("SELECT user_id,purge_after FROM account_deletions WHERE status='pending' ORDER BY COALESCE(last_attempt_at,'') LIMIT 20").all<{user_id:number;purge_after:string}>();
  for (const job of jobs.results) {
    const owner=`user_${job.user_id}`, now=isoNow();
    await env.DB.prepare('UPDATE account_deletions SET last_attempt_at=? WHERE user_id=?').bind(now,job.user_id).run();
    try {
      const assets=await env.DB.prepare('SELECT id,object_key FROM widget_assets WHERE owner_id=? LIMIT 100').bind(owner).all<{id:string;object_key:string}>();
      // Do not drop the deletion queue/asset records before R2 acknowledges it.
      if (assets.results.length) {
        await env.BUCKET.delete(assets.results.map(a=>a.object_key));
        await env.DB.batch(assets.results.map(a=>env.DB.prepare('DELETE FROM widget_assets WHERE id=? AND owner_id=?').bind(a.id,owner)));
      }
      await env.DB.prepare("UPDATE widget_tasks SET input_json='{}',parameters_json='{}',result_json=NULL,error_code=NULL,phase=NULL WHERE owner_id=?").bind(owner).run();
      await env.DB.prepare("UPDATE task_quotes SET snapshot_json='{}' WHERE owner_id=?").bind(owner).run();
      await env.DB.prepare('UPDATE orders SET checkout_url=NULL WHERE user_id=?').bind(job.user_id).run();
      // Seven days of repeated sweeps also catch uploads already in flight at
      // deletion time. Deleted users cannot create new authenticated requests.
      if (job.purge_after<=now && assets.results.length<100)
        await env.DB.prepare("UPDATE account_deletions SET status='complete',completed_at=? WHERE user_id=?").bind(now,job.user_id).run();
    } catch { /* No media paths, secrets or PII in logs; pending job retries. */ }
  }
}
