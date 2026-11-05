import { env } from 'cloudflare:workers';
import { beforeEach, describe, expect, it } from 'vitest';
import worker from '../src/index';
import { seedUser, USER_TOKEN } from './helpers';
import { effectiveLicense } from '../src/teams';
const now=()=>new Date().toISOString();
async function call(path:string,body?:unknown,token=USER_TOKEN,method=body===undefined?'GET':'POST') {
 const r=await worker.fetch(new Request('https://example.com/api/v2/account/team'+path,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)}),env);
 return {status:r.status,data:await r.json() as any};
}
async function invite(n:number) {return (await call('/invites',{email:`test${n}@example.com`})).data.result.invitationCode as string;}
beforeEach(async()=>{
 await env.DB.batch(['team_invites','team_members','licenses','license_devices','refund_requests','billing_webhook_events','user_credit_ledger','orders'].map(t=>env.DB.prepare('DELETE FROM '+t)));
 for(let n=1;n<=7;n++)await seedUser(n===1?USER_TOKEN:'member-'+n,100,n);
 await env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,device_limit,request_key,request_hash,checkout_expires_at,created_at) VALUES('team-order',1,'pro','team','USD',1999,0,0,'PROD_team','software',1,1,'team-request','hash',?,?)`).bind(now(),now()).run();
 await env.DB.prepare("UPDATE orders SET status='paid',paid_at=? WHERE id='team-order'").bind(now()).run();
});
describe('five independent Pro seats',()=>{
 it('includes the owner and enforces four additional seats under concurrent acceptance',async()=>{
  const codes=await Promise.all([2,3,4,5,6].map(invite));
  const results=await Promise.all(codes.map((code,i)=>call('/accept',{code},'member-'+(i+2))));
  expect(results.filter(r=>r.status===200)).toHaveLength(4);
  expect(results.filter(r=>r.status===409)).toHaveLength(1);
  expect((await call('')).data.result).toMatchObject({usedSeats:5,seatLimit:5,role:'owner'});
 });
 it('requires the invited email, supports retry, and does not share credits',async()=>{
  const code=await invite(2);
  expect((await call('/accept',{code},'member-3')).status).toBe(409);
  expect((await call('/accept',{code},'member-2')).status).toBe(200);
  expect((await call('/accept',{code},'member-2')).status).toBe(200);
  expect(await effectiveLicense(env,2)).toMatchObject({status:'active',device_limit:1,team_owner_id:1});
  expect(await env.DB.prepare('SELECT credits FROM users WHERE id=2').first()).toEqual({credits:100});
 });
 it('revokes effective Pro on removal and team refund',async()=>{
  const code=await invite(2);await call('/accept',{code},'member-2');
  expect((await call('/members/2',undefined,USER_TOKEN,'DELETE')).status).toBe(200);
  expect(await effectiveLicense(env,2)).toBeNull();
  const again=await invite(2);await call('/accept',{code:again},'member-2');
  await env.DB.prepare("UPDATE orders SET status='refunded',refunded_at=? WHERE id='team-order'").bind(now()).run();
  expect(await effectiveLicense(env,2)).toBeNull();
 });
 it('rejects expired/revoked invitations and unauthorized management',async()=>{
  const code=await invite(2);
  await env.DB.prepare("UPDATE team_invites SET expires_at='2000-01-01T00:00:00Z'").run();
  expect((await call('/accept',{code},'member-2')).status).toBe(409);
  expect((await call('/invites',{email:'test3@example.com'},'member-2')).status).toBe(409);
 });
});


describe('licence environment isolation',()=>{
 it('does not grant production access from a sandbox team purchase',async()=>{
  const code=await invite(2);await call('/accept',{code},'member-2');
  const prod={...env,WAFFO_ENVIRONMENT:'prod'};
  expect(await effectiveLicense(prod,1)).toBeNull();
  expect(await effectiveLicense(prod,2)).toBeNull();
  const accept=await worker.fetch(new Request('https://example.com/api/v2/account/team/accept',{method:'POST',headers:{Authorization:'Bearer member-3','Content-Type':'application/json'},body:JSON.stringify({code:await invite(3)})}),prod);
  expect(accept.status).toBe(409);
 });
 it('replaces a sandbox licence on production purchase and does not restore it on refund',async()=>{
  await env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,device_limit,request_key,request_hash,checkout_expires_at,created_at,billing_mode)
    VALUES('prod-personal',1,'pro','personal','USD',999,0,0,'PROD_personal','software',1,1,'prod-request','hash',?,?,'prod')`).bind(now(),now()).run();
  await env.DB.prepare("UPDATE orders SET status='paid',paid_at=? WHERE id='prod-personal'").bind(now()).run();
  expect(await effectiveLicense({...env,WAFFO_ENVIRONMENT:'prod'},1)).toMatchObject({status:'active',tier_id:'personal',source_order:'prod-personal'});
  await env.DB.prepare("UPDATE orders SET status='refunded',refunded_at=? WHERE id='prod-personal'").bind(now()).run();
  expect((await effectiveLicense({...env,WAFFO_ENVIRONMENT:'prod'},1))?.status).toBe('refunded');
 });
});

it('allows an old sandbox member to join a production team',async()=>{
 await call('/accept',{code:await invite(2)},'member-2');
 await env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,device_limit,request_key,request_hash,checkout_expires_at,created_at,billing_mode)
 VALUES('prod-team',7,'pro','team','USD',1999,0,0,'PROD_team','software',1,1,'prod-team-request','hash',?,?,'prod')`).bind(now(),now()).run();
 await env.DB.prepare("UPDATE orders SET status='paid',paid_at=? WHERE id='prod-team'").bind(now()).run();
 const prodCall=(path:string,body:unknown,token:string)=>worker.fetch(new Request('https://example.com/api/v2/account/team'+path,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)}),{...env,WAFFO_ENVIRONMENT:'prod'});
 const invitation=await (await prodCall('/invites',{email:'test2@example.com'},'member-7')).json() as any;
 expect((await prodCall('/accept',{code:invitation.result.invitationCode},'member-2')).status).toBe(200);
 expect(await effectiveLicense({...env,WAFFO_ENVIRONMENT:'prod'},2)).toMatchObject({team_owner_id:7,status:'active'});
});
