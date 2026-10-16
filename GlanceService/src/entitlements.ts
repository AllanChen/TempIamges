import type { Env } from './index';
import { authenticatedUser } from './users';
import { BillingError, billingBody, billingReply, isoNow, readPricing, sha256, paymentReady } from './pricing';

export async function requestDevice(request:Request,data?:Record<string,unknown>) {
  const raw=typeof data?.deviceID==='string'?data.deviceID:request.headers.get('X-Glance-Device')||'';
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(raw)) throw new BillingError('device_required','A device identifier is required.');
  return sha256(raw);
}
type License={status:string;purchased_at:string;updates_until:string;source_order:string|null;source_admin_grant:string|null};
export async function entitlements(env:Env,request:Request) {
  const user=await authenticatedUser(env,request), config=await readPricing(env);
  const device=await requestDevice(request);
  const license=await env.DB.prepare('SELECT * FROM licenses WHERE user_id=?').bind(user.id).first<License>();
  const devices=await env.DB.prepare('SELECT id,name,device_hash,last_seen_at,activated_at FROM license_devices WHERE user_id=? AND released_at IS NULL ORDER BY activated_at')
    .bind(user.id).all<{id:string;device_hash:string;name:string;last_seen_at:string;activated_at:string}>();
  const current=devices.results.find(d=>d.device_hash===device);
  const serverTime=isoNow(), expiresAt=new Date(Date.now()+config.offlineDays*86400000).toISOString();
  const pro=license?.status==='active' && !!current;
  if (pro) await env.DB.prepare('UPDATE license_devices SET last_seen_at=? WHERE id=?').bind(serverTime,current!.id).run();
  const trialEnd=user.trial_started_at?new Date(Date.parse(user.trial_started_at)+config.trialDays*86400000).toISOString():null;
  let credential:{payload:string;signature:string;keyID:string}|null=null;
  if (pro && env.GLANCE_SIGNING_KEY_PKCS8) {
    const bytes=Uint8Array.from(atob(env.GLANCE_SIGNING_KEY_PKCS8),c=>c.charCodeAt(0));
    const key=await crypto.subtle.importKey('pkcs8',bytes,'Ed25519',false,['sign']);
    const payload=btoa(JSON.stringify({userID:user.id,deviceHash:device,issuedAt:serverTime,expiresAt,
      updatesUntil:license!.updates_until,sourceOrder:license!.source_order??license!.source_admin_grant,pro:true}));
    const signature=new Uint8Array(await crypto.subtle.sign('Ed25519',key,new TextEncoder().encode(payload)));
    credential={payload,signature:btoa(String.fromCharCode(...signature)),keyID:'glance-market-2026-02'};
  }
  const proBonusEligible=!await env.DB.prepare('SELECT id FROM user_credit_ledger WHERE id=?').bind('pro-bonus:'+user.id).first();
  const releases=await env.DB.prepare('SELECT COUNT(*) n FROM device_releases WHERE user_id=? AND created_at>?')
    .bind(user.id,new Date(Date.now()-30*86400000).toISOString()).first<{n:number}>();
  return billingReply({pro,proBonusEligible,licenseStatus:license?.status??'free',updatesUntil:license?.updates_until??null,purchasedAt:license?.purchased_at??null,
    currentDeviceID:current?.id??null,devices:devices.results.map(({device_hash,...d})=>({...d,current:device_hash===device})),
    deviceLimit:config.deviceLimit,releasesRemaining:Math.max(0,config.releaseLimit-(releases?.n??0)),
    trialStartedAt:user.trial_started_at??null,trialEndsAt:trialEnd,trialVoided:!!user.trial_voided,paidWidgetNoticeSeen:!!user.widget_notice_seen,
    trialActive:!user.trial_voided && !!trialEnd && trialEnd>serverTime,credential,serverTime,
    enforcementEnabled:config.enabled && paymentReady(env)});
}
export async function synchronizeTrial(env:Env,request:Request) {
  const user=await authenticatedUser(env,request), data=await billingBody(request);
  const start=typeof data.startedAt==='string'?Date.parse(data.startedAt):NaN;
  if (!Number.isFinite(start) || start<1577836800000) throw new BillingError('invalid_trial','Invalid trial start time.');
  const normalized=new Date(Math.min(Date.now(),start)).toISOString();
  await env.DB.prepare(`UPDATE users SET trial_started_at=CASE WHEN trial_started_at IS NULL OR trial_started_at>? THEN ? ELSE trial_started_at END
    WHERE id=? AND trial_voided=0`).bind(normalized,normalized,user.id).run();
  return entitlements(env,request);
}
export async function activateDevice(env:Env,request:Request) {
  const user=await authenticatedUser(env,request), data=await billingBody(request), device=await requestDevice(request,data);
  const license=await env.DB.prepare("SELECT user_id FROM licenses WHERE user_id=? AND status='active'").bind(user.id).first();
  if (!license) throw new BillingError('pro_required','An active Pro license is required.',409);
  const name=typeof data.name==='string'?data.name.trim().slice(0,100):'Mac';
  const config=await readPricing(env), now=isoNow();
  const inserted=await env.DB.prepare(`INSERT INTO license_devices(id,user_id,device_hash,name,activated_at,last_seen_at)
    SELECT ?,?,?,?,?,? WHERE (SELECT COUNT(*) FROM license_devices WHERE user_id=? AND released_at IS NULL AND device_hash!=?)<?
    ON CONFLICT(user_id,device_hash) DO UPDATE SET name=excluded.name,last_seen_at=excluded.last_seen_at,released_at=NULL
    WHERE (SELECT COUNT(*) FROM license_devices WHERE user_id=? AND released_at IS NULL AND device_hash!=?)<? RETURNING id`)
    .bind('device_'+crypto.randomUUID(),user.id,device,name||'Mac',now,now,user.id,device,config.deviceLimit,user.id,device,config.deviceLimit).first();
  if (!inserted) throw new BillingError('device_limit','Device slots are full. Release an old Mac to activate this one.',409);
  return entitlements(env,request);
}
export async function releaseDevice(env:Env,request:Request,id:string) {
  const user=await authenticatedUser(env,request), config=await readPricing(env), now=isoNow();
  const device=await env.DB.prepare('SELECT released_at FROM license_devices WHERE id=? AND user_id=?').bind(id,user.id).first<{released_at:string|null}>();
  if (!device) throw new BillingError('device_not_found','Device not found.',404);
  if (device.released_at) return entitlements(env,request);
  const releaseID='release_'+crypto.randomUUID();
  const result=await env.DB.batch([
    env.DB.prepare(`INSERT INTO device_releases(id,user_id,device_id,created_at) SELECT ?,?,?,?
      WHERE (SELECT COUNT(*) FROM device_releases WHERE user_id=? AND created_at>?)<?
      AND EXISTS(SELECT 1 FROM license_devices WHERE id=? AND user_id=? AND released_at IS NULL)`)
      .bind(releaseID,user.id,id,now,user.id,new Date(Date.now()-30*86400000).toISOString(),config.releaseLimit,id,user.id),
    env.DB.prepare('UPDATE license_devices SET released_at=? WHERE id=? AND user_id=? AND EXISTS(SELECT 1 FROM device_releases WHERE id=?)')
      .bind(now,id,user.id,releaseID)
  ]);
  if (!result[0].meta.changes) throw new BillingError('release_limit','The device release limit has been reached. Contact support.',409);
  return entitlements(env,request);
}
