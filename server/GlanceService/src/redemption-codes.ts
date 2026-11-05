import type { Env } from './index';
import { entitlements } from './entitlements';
import { BillingError, billingBody, billingReply, isoNow, readPricing, sha256 } from './pricing';
import { effectiveLicense } from './teams';
import { authenticatedUser } from './users';

const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const lifetime = '9999-12-31T00:00:00.000Z';
type Kind = 'lifetime' | 'one_year';
type CodeRow = {
  id: string;
  batch_id: string;
  kind: Kind;
  status: string;
  expires_at: string | null;
  redeemed_by: number | null;
  device_limit: number;
  billing_mode: string;
};

function billingMode(env: Env) {
  return env.WAFFO_ENVIRONMENT === 'prod' ? 'prod' : 'test';
}

function normalizeCode(value: unknown) {
  if (typeof value !== 'string') return null;
  const compact = value.trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (!/^GLG[A-HJ-NP-Z2-9]{16}$/.test(compact)) return null;
  return `GLG-${compact.slice(3, 7)}-${compact.slice(7, 11)}-${compact.slice(11, 15)}-${compact.slice(15, 19)}`;
}

function newCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const raw = Array.from(bytes, value => alphabet[value % alphabet.length]).join('');
  return `GLG-${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 16)}`;
}

function validBatchID(value: unknown): value is string {
  return typeof value === 'string' && /^batch_[A-Za-z0-9_-]{16,80}$/.test(value);
}

export async function createRedemptionBatch(env: Env, request: Request) {
  const data = await billingBody(request);
  const kind = data.kind as Kind;
  const quantity = Number(data.quantity);
  const note = typeof data.note === 'string' ? data.note.trim() : '';
  const config = await readPricing(env);
  const deviceLimit = data.deviceLimit == null ? config.deviceLimit : Number(data.deviceLimit);
  if (!['lifetime', 'one_year'].includes(kind) || !Number.isSafeInteger(quantity) || quantity < 1 || quantity > 100 ||
      !note || note.length > 500 || !Number.isSafeInteger(deviceLimit) || deviceLimit < 1 || deviceLimit > 20) {
    throw new BillingError('invalid_redemption_batch', 'Choose lifetime or one-year Pro, 1-100 codes, a note and a valid Mac limit.');
  }
  let expiresAt: string | null = null;
  if (data.expiresAt != null && data.expiresAt !== '') {
    if (typeof data.expiresAt !== 'string' || !Number.isFinite(Date.parse(data.expiresAt))) {
      throw new BillingError('invalid_redemption_expiry', 'Enter a valid redemption expiry.');
    }
    expiresAt = new Date(data.expiresAt).toISOString();
    if (expiresAt <= isoNow()) throw new BillingError('invalid_redemption_expiry', 'Redemption expiry must be in the future.');
  }
  const batchID = 'batch_' + crypto.randomUUID();
  const createdAt = isoNow();
  const codes = Array.from({ length: quantity }, newCode);
  const hashes = await Promise.all(codes.map(code => sha256(code)));
  const statements = codes.map((code, index) => env.DB.prepare(`INSERT INTO pro_redemption_codes(
    id,batch_id,code_hash,code_hint,kind,status,note,actor_id,device_limit,billing_mode,expires_at,created_at
  ) VALUES(?,?,?,?,?,'active',?,'admin',?,?,?,?)`).bind(
    'code_' + crypto.randomUUID(), batchID, hashes[index], code.slice(-4), kind, note,
    deviceLimit, billingMode(env), expiresAt, createdAt));
  await env.DB.batch(statements);
  return billingReply({
    batch: { id: batchID, kind, quantity, note, deviceLimit, expiresAt, billingMode: billingMode(env), createdAt },
    codes
  }, 201);
}

export async function listRedemptionBatches(env: Env) {
  const now = isoNow();
  const rows = await env.DB.prepare(`SELECT c.batch_id,c.kind,c.note,c.actor_id,c.device_limit,c.billing_mode,c.expires_at,c.created_at,
    COUNT(*) issued,COUNT(c.redeemed_at) redeemed,
    COALESCE(SUM(c.status='revoked' AND c.redeemed_at IS NULL),0) revoked,
    COALESCE(SUM(EXISTS(SELECT 1 FROM licenses l WHERE l.source_redemption_code=c.id AND l.status='active'
      AND (l.access_expires_at IS NULL OR l.access_expires_at>?))),0) active,
    COALESCE(SUM(EXISTS(SELECT 1 FROM licenses l JOIN license_devices d ON d.user_id=l.user_id
      WHERE l.source_redemption_code=c.id AND l.status='active' AND d.released_at IS NULL AND d.activated_at>=c.redeemed_at
        AND (l.access_expires_at IS NULL OR l.access_expires_at>?))),0) activated,
    COALESCE(SUM(c.redeemed_at IS NOT NULL AND ((c.access_expires_at IS NOT NULL AND c.access_expires_at<=?)
      OR EXISTS(SELECT 1 FROM licenses expired WHERE expired.source_redemption_code=c.id AND expired.status='expired'))),0) expired
    FROM pro_redemption_codes c
    GROUP BY c.batch_id,c.kind,c.note,c.actor_id,c.device_limit,c.billing_mode,c.expires_at,c.created_at
    ORDER BY c.created_at DESC,c.batch_id DESC LIMIT 100`).bind(now, now, now).all();
  return billingReply({ batches: rows.results });
}

export async function revokeRedemptionBatch(env: Env, request: Request, batchID: string) {
  if (!validBatchID(batchID)) throw new BillingError('invalid_redemption_batch', 'Invalid redemption batch.');
  const result = await env.DB.prepare(`UPDATE pro_redemption_codes SET status='revoked'
    WHERE batch_id=? AND redeemed_at IS NULL AND status='active'`).bind(batchID).run();
  return billingReply({ batchID, revoked: result.meta.changes ?? 0 });
}

export async function redeemProCode(env: Env, request: Request) {
  const user = await authenticatedUser(env, request);
  const data = await billingBody(request);
  const code = normalizeCode(data.code);
  if (!code) throw new BillingError('invalid_redemption_code', 'Enter a valid Glance Pro redemption code.');
  const now = isoNow();
  const row = await env.DB.prepare('SELECT * FROM pro_redemption_codes WHERE code_hash=?')
    .bind(await sha256(code)).first<CodeRow>();
  if (!row || row.billing_mode !== billingMode(env)) {
    throw new BillingError('invalid_redemption_code', 'This redemption code is invalid.', 404);
  }
  if (row.redeemed_by === user.id) return entitlements(env, request);
  if (row.redeemed_by != null) throw new BillingError('redemption_used', 'This code has already been redeemed.', 409);
  if (row.status !== 'active') throw new BillingError('redemption_revoked', 'This code has been revoked.', 409);
  if (row.expires_at && row.expires_at <= now) throw new BillingError('redemption_expired', 'This code has expired.', 410);
  if ((await effectiveLicense(env, user.id))?.status === 'active') {
    throw new BillingError('already_pro', 'This account already has an active Pro license. The code was not consumed.', 409);
  }
  const accessExpiry = row.kind === 'one_year' ? new Date(now) : null;
  if (accessExpiry) accessExpiry.setUTCFullYear(accessExpiry.getUTCFullYear() + 1);
  const accessExpiresAt = accessExpiry?.toISOString() ?? null;
  const mode = billingMode(env);
  const claim = env.DB.prepare(`UPDATE pro_redemption_codes SET redeemed_by=?,redeemed_at=?,access_expires_at=?
    WHERE id=? AND redeemed_by IS NULL AND status='active' AND (expires_at IS NULL OR expires_at>?)
    AND NOT EXISTS(SELECT 1 FROM licenses l LEFT JOIN orders o ON o.id=l.source_order
      LEFT JOIN pro_redemption_codes source ON source.id=l.source_redemption_code
      WHERE l.user_id=? AND l.status='active' AND (l.source_order IS NULL OR o.billing_mode=?)
      AND (l.source_redemption_code IS NULL OR source.billing_mode=?))
    AND NOT EXISTS(SELECT 1 FROM team_members m JOIN licenses team ON team.user_id=m.owner_id AND team.source_order=m.source_order
      JOIN orders team_order ON team_order.id=team.source_order
      WHERE m.user_id=? AND team.status='active' AND team.tier_id='team' AND team_order.billing_mode=?)`)
    .bind(user.id, now, accessExpiresAt, row.id, now, user.id, mode, mode, user.id, mode);
  const license = env.DB.prepare(`INSERT INTO licenses(
    user_id,status,purchased_at,updates_until,source_order,source_admin_grant,source_redemption_code,device_limit,tier_id,access_expires_at
  ) SELECT ?, 'active', ?, ?, NULL, NULL, ?, ?, NULL, ?
    WHERE EXISTS(SELECT 1 FROM pro_redemption_codes WHERE id=? AND redeemed_by=?)
    ON CONFLICT(user_id) DO UPDATE SET status='active',purchased_at=excluded.purchased_at,
      updates_until=excluded.updates_until,source_order=NULL,source_admin_grant=NULL,
      source_redemption_code=excluded.source_redemption_code,device_limit=excluded.device_limit,
      tier_id=NULL,access_expires_at=excluded.access_expires_at WHERE licenses.status!='active'`)
    .bind(user.id, now, lifetime, row.id, row.device_limit, accessExpiresAt, row.id, user.id);
  const trial = env.DB.prepare(`UPDATE users SET trial_voided=1,updated_at=? WHERE id=?
    AND EXISTS(SELECT 1 FROM pro_redemption_codes WHERE id=? AND redeemed_by=?)`)
    .bind(now, user.id, row.id, user.id);
  const result = await env.DB.batch([claim, license, trial]);
  if (!result[0].meta.changes) {
    const current = await env.DB.prepare('SELECT redeemed_by FROM pro_redemption_codes WHERE id=?').bind(row.id).first<CodeRow>();
    if (current?.redeemed_by === user.id) return entitlements(env, request);
    if ((await effectiveLicense(env, user.id))?.status === 'active') {
      throw new BillingError('already_pro', 'This account already has an active Pro license. The code was not consumed.', 409);
    }
    if (current?.redeemed_by != null) throw new BillingError('redemption_used', 'This code has already been redeemed.', 409);
    throw new BillingError('redemption_conflict', 'The code was not redeemed. Please try again.', 409);
  }
  return entitlements(env, request);
}
