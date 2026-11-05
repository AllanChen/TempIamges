import type { Env } from './index';
import { authenticatedUser } from './users';
import { BillingError, billingBody, billingReply, isoNow, sha256 } from './pricing';

export type EffectiveLicense = {status:string;purchased_at:string;updates_until:string;source_order:string|null;source_admin_grant:string|null;source_redemption_code:string|null;access_expires_at:string|null;device_limit:number|null;tier_id:string|null;team_owner_id?:number};
export async function expireRedemptionLicenses(env:Env) {
  const now=isoNow();
  await env.DB.batch([
    env.DB.prepare(`UPDATE license_devices SET released_at=? WHERE released_at IS NULL AND EXISTS(
      SELECT 1 FROM licenses l WHERE l.user_id=license_devices.user_id AND l.status='active'
      AND l.source_redemption_code IS NOT NULL AND l.access_expires_at IS NOT NULL AND l.access_expires_at<=?)`).bind(now,now),
    env.DB.prepare(`UPDATE licenses SET status='expired' WHERE status='active' AND source_redemption_code IS NOT NULL
      AND access_expires_at IS NOT NULL AND access_expires_at<=?`).bind(now)
  ]);
}
export async function effectiveLicense(env:Env,userID:number):Promise<EffectiveLicense|null> {
  const own=await env.DB.prepare(`SELECT l.* FROM licenses l LEFT JOIN orders o ON o.id=l.source_order
    LEFT JOIN pro_redemption_codes redemption ON redemption.id=l.source_redemption_code
    WHERE l.user_id=? AND (l.source_order IS NULL OR o.billing_mode=?)
    AND (l.source_redemption_code IS NULL OR redemption.billing_mode=?)`).bind(userID,env.WAFFO_ENVIRONMENT||'test',env.WAFFO_ENVIRONMENT||'test').first<EffectiveLicense>();
  if(own?.status==='active'&&own.access_expires_at&&own.access_expires_at<=isoNow()) {
    await expireRedemptionLicenses(env);
    own.status='expired';
  }
  if(own?.status==='active')return own;
  const inherited=await env.DB.prepare(`SELECT l.*,m.owner_id team_owner_id FROM team_members m
    JOIN licenses l ON l.user_id=m.owner_id AND l.source_order=m.source_order
    JOIN users u ON u.id=m.owner_id AND u.status='active' JOIN orders o ON o.id=l.source_order AND o.billing_mode=?
    WHERE m.user_id=? AND l.status='active' AND l.tier_id='team'`).bind(env.WAFFO_ENVIRONMENT||'test',userID).first<EffectiveLicense>();
  return inherited?{...inherited,device_limit:1}:own;
}
async function ownedTeam(env:Env,userID:number) {
  const l=await effectiveLicense(env,userID);
  if(!l || l.status!=='active' || l.tier_id!=='team' || l.team_owner_id || !l.source_order)
    throw new BillingError('team_required','An active five-person Pro licence is required.',409);
  return l;
}
export async function teamInfo(env:Env,request:Request) {
  const user=await authenticatedUser(env,request),l=await effectiveLicense(env,user.id);
  const owner=l?.team_owner_id??(l?.status==='active'&&l.tier_id==='team'?user.id:null);
  if(!owner)return billingReply({role:'none',seatLimit:5,members:[],invites:[]});
  const members=await env.DB.prepare(`SELECT u.id,u.email,u.name,u.status,m.joined_at FROM team_members m JOIN users u ON u.id=m.user_id
    WHERE m.owner_id=? AND m.source_order=? `).bind(owner,l!.source_order).all();
  const invites=owner===user.id?await env.DB.prepare(`SELECT id,email,expires_at FROM team_invites WHERE owner_id=? AND source_order=?
    AND accepted_by IS NULL AND revoked_at IS NULL AND expires_at>?`).bind(owner,l!.source_order,isoNow()).all():{results:[]};
  return billingReply({role:owner===user.id?'owner':'member',ownerID:owner,seatLimit:5,usedSeats:1+members.results.length,
    members:owner===user.id?members.results:[],invites:invites.results});
}
export async function inviteMember(env:Env,request:Request) {
  const user=await authenticatedUser(env,request),l=await ownedTeam(env,user.id),data=await billingBody(request);
  const email=typeof data.email==='string'?data.email.trim().toLowerCase():'';
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254||email===user.email)throw new BillingError('invalid_email','Enter another member’s email address.');
  const count=await env.DB.prepare('SELECT COUNT(*) n FROM team_members WHERE owner_id=? AND source_order=?').bind(user.id,l.source_order).first<{n:number}>();
  if((count?.n??0)>=4)throw new BillingError('team_full','All five seats are in use.',409);
  const pending=await env.DB.prepare('SELECT COUNT(*) n FROM team_invites WHERE owner_id=? AND source_order=? AND expires_at>? AND revoked_at IS NULL AND accepted_by IS NULL').bind(user.id,l.source_order,isoNow()).first<{n:number}>();
  if((pending?.n??0)>=20)throw new BillingError('too_many_invites','Revoke an old invitation before creating another.',429);
  const token=crypto.randomUUID()+crypto.randomUUID(),id='invite_'+crypto.randomUUID(),now=isoNow();
  const expiresAt=new Date(Date.now()+7*86400000).toISOString();
  await env.DB.batch([
    env.DB.prepare('UPDATE team_invites SET revoked_at=? WHERE owner_id=? AND email=? AND accepted_by IS NULL AND revoked_at IS NULL').bind(now,user.id,email),
    env.DB.prepare('INSERT INTO team_invites(id,token_hash,owner_id,source_order,email,expires_at,created_at) VALUES(?,?,?,?,?,?,?)').bind(id,await sha256(token),user.id,l.source_order,email,expiresAt,now)
  ]);
  return billingReply({id,email,expiresAt,invitationCode:token});
}
export async function acceptInvite(env:Env,request:Request) {
  const user=await authenticatedUser(env,request),data=await billingBody(request);
  if(typeof data.code!=='string'||data.code.length!==72)throw new BillingError('invalid_invite','Enter a valid invitation code.');
  const hash=await sha256(data.code),now=isoNow();
  const invite=await env.DB.prepare(`SELECT i.* FROM team_invites i JOIN licenses l ON l.user_id=i.owner_id AND l.source_order=i.source_order
    JOIN users u ON u.id=i.owner_id AND u.status='active' JOIN orders o ON o.id=l.source_order AND o.billing_mode=?
    WHERE i.token_hash=? AND i.email=? AND i.revoked_at IS NULL AND i.expires_at>? AND l.status='active' AND l.tier_id='team'`)
    .bind(env.WAFFO_ENVIRONMENT||'test',hash,user.email,now).first<{id:string;owner_id:number;source_order:string;accepted_by:number|null}>();
  if(!invite)throw new BillingError('invalid_invite','The invitation expired, was revoked, or belongs to another email.',409);
  if(invite.accepted_by===user.id)return teamInfo(env,request);
  if(invite.accepted_by!==null)throw new BillingError('invalid_invite','Invitation already used.',409);
  if((await effectiveLicense(env,user.id))?.status==='active')throw new BillingError('already_pro','This account already has an active Pro licence or team.',409);
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO team_members(user_id,owner_id,source_order,joined_at)
      SELECT ?,?,?,? WHERE (SELECT COUNT(*) FROM team_members WHERE owner_id=? AND source_order=?)<4
      AND NOT EXISTS(SELECT 1 FROM licenses own LEFT JOIN orders o ON o.id=own.source_order WHERE own.user_id=? AND own.status='active' AND (own.source_order IS NULL OR o.billing_mode=?))
      AND EXISTS(SELECT 1 FROM team_invites i JOIN licenses l ON l.user_id=i.owner_id AND l.source_order=i.source_order
        WHERE i.id=? AND i.revoked_at IS NULL AND i.accepted_by IS NULL AND i.expires_at>? AND l.status='active' AND l.tier_id='team')
      ON CONFLICT(user_id) DO UPDATE SET owner_id=excluded.owner_id,source_order=excluded.source_order,joined_at=excluded.joined_at
      WHERE NOT EXISTS(SELECT 1 FROM licenses l JOIN users u ON u.id=l.user_id AND u.status='active' WHERE l.user_id=team_members.owner_id AND l.source_order=team_members.source_order AND l.status='active' AND l.tier_id='team' AND l.source_order IN (SELECT id FROM orders WHERE billing_mode=?))`)
      .bind(user.id,invite.owner_id,invite.source_order,now,invite.owner_id,invite.source_order,user.id,env.WAFFO_ENVIRONMENT||'test',invite.id,now,env.WAFFO_ENVIRONMENT||'test'),
    env.DB.prepare(`UPDATE team_invites SET accepted_by=? WHERE id=? AND EXISTS(SELECT 1 FROM team_members WHERE user_id=? AND owner_id=? AND source_order=?)`).bind(user.id,invite.id,user.id,invite.owner_id,invite.source_order)
  ]);
  const accepted=await env.DB.prepare('SELECT accepted_by FROM team_invites WHERE id=?').bind(invite.id).first<{accepted_by:number|null}>();
  if(accepted?.accepted_by!==user.id)throw new BillingError('team_full','The team is full or your membership changed. Refresh and retry.',409);
  return teamInfo(env,request);
}
export async function removeMember(env:Env,request:Request,memberID:number) {
  const user=await authenticatedUser(env,request);await ownedTeam(env,user.id);
  const member=await env.DB.prepare('SELECT user_id FROM team_members WHERE user_id=? AND owner_id=?').bind(memberID,user.id).first();
  if(!member)throw new BillingError('member_not_found','Member not found.',404);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM team_members WHERE user_id=? AND owner_id=?').bind(memberID,user.id),
    env.DB.prepare("UPDATE license_devices SET released_at=? WHERE user_id=? AND NOT EXISTS(SELECT 1 FROM licenses WHERE user_id=? AND status='active')").bind(isoNow(),memberID,memberID)
  ]);
  return teamInfo(env,request);
}
export async function leaveTeam(env:Env,request:Request) {
  const user=await authenticatedUser(env,request);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM team_members WHERE user_id=?').bind(user.id),
    env.DB.prepare("UPDATE license_devices SET released_at=? WHERE user_id=? AND NOT EXISTS(SELECT 1 FROM licenses WHERE user_id=? AND status='active')").bind(isoNow(),user.id,user.id)
  ]);
  return billingReply({left:true});
}
export async function revokeInvite(env:Env,request:Request,id:string) {
  const user=await authenticatedUser(env,request);await ownedTeam(env,user.id);
  await env.DB.prepare('UPDATE team_invites SET revoked_at=? WHERE id=? AND owner_id=? AND accepted_by IS NULL').bind(isoNow(),id,user.id).run();
  return teamInfo(env,request);
}
