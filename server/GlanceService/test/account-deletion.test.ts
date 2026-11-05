import { env } from 'cloudflare:workers';
import { describe,it,expect,vi,afterEach,beforeEach } from 'vitest';
import worker from '../src/index';
import { purgeDeletedAccounts } from '../src/account-deletion';
import { seedUser, USER_TOKEN, api, seedWidget, createTask } from './helpers';
const remove=(body:unknown)=>worker.fetch(new Request('https://example.com/api/v2/account',{method:'DELETE',headers:{Authorization:'Bearer '+USER_TOKEN,'Content-Type':'application/json'},body:JSON.stringify(body)}),env);
afterEach(()=>vi.restoreAllMocks());
beforeEach(async()=>{
 await env.DB.batch(['DELETE FROM account_deletions','DELETE FROM widget_assets','DELETE FROM widget_tasks','DELETE FROM user_credit_ledger',"UPDATE users SET email='test1@example.com',status='active' WHERE id=1"].map(sql=>env.DB.prepare(sql)));
});
describe('account deletion',()=>{
 it('requires explicit confirmation, revokes sessions and queues media deletion without removing ledger history',async()=>{
  await seedUser();
  expect((await remove({email:'test1@example.com'})).status).toBe(400);
  const now=new Date().toISOString();
  await env.DB.prepare("INSERT INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at) VALUES('keep-financial',1,10,'test','test',?)").bind(now).run();
  await env.BUCKET.put('private/test-media','image');
  await env.DB.prepare("INSERT INTO widget_assets(id,owner_id,object_key,mime_type,size_bytes,created_at) VALUES('delete-me','user_1','private/test-media','image/png',5,?)").bind(now).run();
  expect((await remove({email:'test1@example.com',confirm:'DELETE'})).status).toBe(200);
  expect((await api('/api/v2/account/credits',{token:USER_TOKEN})).status).toBe(401);
  expect(await env.DB.prepare('SELECT email,status FROM users WHERE id=1').first()).toEqual({email:'deleted-1@account.invalid',status:'deleted'});
  expect(await env.DB.prepare("SELECT id FROM user_credit_ledger WHERE id='keep-financial'").first()).toBeTruthy();
  await purgeDeletedAccounts(env);
  expect(await env.BUCKET.get('private/test-media')).toBeNull();
  expect(await env.DB.prepare("SELECT id FROM widget_assets WHERE id='delete-me'").first()).toBeNull();
  expect(await env.DB.prepare('SELECT status FROM account_deletions WHERE user_id=1').first()).toEqual({status:'pending'});
  await env.DB.prepare("UPDATE account_deletions SET purge_after='2000-01-01T00:00:00Z'").run();
  await purgeDeletedAccounts(env);
  expect(await env.DB.prepare('SELECT status FROM account_deletions WHERE user_id=1').first()).toEqual({status:'complete'});
 });
 it('blocks active tasks without disabling the account',async()=>{
  await seedWidget();await createTask();
  expect((await remove({email:'test1@example.com',confirm:'DELETE'})).status).toBe(409);
  expect((await api('/api/v2/account/credits',{token:USER_TOKEN})).status).toBe(200);
  expect(await env.DB.prepare('SELECT user_id FROM account_deletions WHERE user_id=1').first()).toBeNull();
 });
 it('retains the purge queue when object storage fails',async()=>{
  await seedUser();const now=new Date().toISOString();
  await env.DB.prepare("INSERT INTO widget_assets(id,owner_id,object_key,mime_type,size_bytes,created_at) VALUES('retry-media','user_1','retry-media','image/png',1,?)").bind(now).run();
  await remove({email:'test1@example.com',confirm:'DELETE'});
  const failing={...env,BUCKET:{...env.BUCKET,delete:async()=>{throw new Error('temporary outage')}} as unknown as R2Bucket};
  await purgeDeletedAccounts(failing);
  expect(await env.DB.prepare("SELECT id FROM widget_assets WHERE id='retry-media'").first()).toBeTruthy();
  expect(await env.DB.prepare('SELECT status FROM account_deletions WHERE user_id=1').first()).toEqual({status:'pending'});
 });
});

it('preserves a member’s separately purchased Pro when the team owner deletes their account',async()=>{
 await seedUser();await seedUser('independent-member',100,2);const now=new Date().toISOString();
 for(const [id,userID,tier] of [['owner-team',1,'team'],['member-personal',2,'personal']] as const){
  await env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,product_id,tax_category,tax_included,device_limit,request_key,request_hash,checkout_expires_at,created_at)
   VALUES(?,?,'pro',?,'USD',999,'PROD_fixture','software',1,1,?,'hash',?,?)`).bind(id,userID,tier,id,now,now).run();
  await env.DB.prepare("UPDATE orders SET status='paid',paid_at=? WHERE id=?").bind(now,id).run();
 }
 await env.DB.prepare("INSERT INTO team_members(user_id,owner_id,source_order,joined_at) VALUES(2,1,'owner-team',?)").bind(now).run();
 await env.DB.prepare("INSERT INTO license_devices(id,user_id,device_hash,name,activated_at,last_seen_at) VALUES('member-mac',2,'member-device-hash','Personal Mac',?,?)").bind(now,now).run();
 expect((await remove({email:'test1@example.com',confirm:'DELETE'})).status).toBe(200);
 expect(await env.DB.prepare("SELECT released_at,name FROM license_devices WHERE id='member-mac'").first()).toEqual({released_at:null,name:'Personal Mac'});
 expect(await env.DB.prepare('SELECT status FROM licenses WHERE user_id=2').first()).toEqual({status:'active'});
 expect(await env.DB.prepare('SELECT user_id FROM team_members WHERE user_id=2').first()).toBeNull();
});
