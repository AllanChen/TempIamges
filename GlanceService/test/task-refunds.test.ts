import { env } from 'cloudflare:workers';
import { beforeEach, expect, it } from 'vitest';
import { expireTasks } from '../src/pricing';
import { api, seedWidget, claimTask, taskStatus, USER_TOKEN, WIDGET_ID, sha256Hex } from './helpers';

beforeEach(async () => {
  await env.DB.batch(['DELETE FROM widget_tasks','DELETE FROM user_credit_ledger','DELETE FROM task_abandonments','DELETE FROM widget_workers','DELETE FROM billing_settings'].map(sql=>env.DB.prepare(sql)));
  await seedWidget();
  await env.DB.prepare("UPDATE widget_versions SET manifest_json=json_set(manifest_json,'$.creditCost',7) WHERE id='version_test'").run();
});
const iso = (offset=0) => new Date(Date.now()+offset).toISOString();
const balance = async () => (await env.DB.prepare('SELECT credits FROM users WHERE id=1').first<{credits:number}>())!.credits;
async function submit(key=crypto.randomUUID(), deliveryRequired=true) {
  const response=await api('/api/v2/tasks',{method:'POST',token:USER_TOKEN,headers:{'Idempotency-Key':key},json:{widgetID:WIDGET_ID,commandID:'run',input:{url:'https://example.com/a.png'},deliveryRequired}});
  const body=await response.json() as {result?:{taskID:string}};
  return {response,id:body.result?.taskID!,key};
}
const settle = (id:string,outcome:string,token=USER_TOKEN) => api(`/api/v2/tasks/${id}/settle`,{method:'POST',token,json:{outcome}});
const abandon = (key:string,token=USER_TOKEN) => api(`/api/v2/task-requests/${key}/abandon`,{method:'POST',token});
async function succeed() {
  const task=await submit(); const claim=await claimTask();
  const response=await api(`/api/v2/widget-tasks/${task.id}/result`,{method:'POST',token:env.DEVELOPER_TEST_TOKEN,claim:claim.claimToken,json:{status:'succeeded',artifacts:[{type:'text',text:'Usable result'}]}});
  expect(response.status).toBe(200); return task;
}

it.each(['queued','claimed','running'])('refunds cancellation from %s exactly once',async status=>{
  const {id}=await submit();
  if(status!=='queued') { const claim=await claimTask(); if(status==='running') await api(`/api/v2/widget-tasks/${id}/heartbeat`,{method:'POST',token:env.DEVELOPER_TEST_TOKEN,claim:claim.claimToken}); }
  const result=await api(`/api/v2/tasks/${id}`,{method:'DELETE',token:USER_TOKEN});
  expect(await result.json()).toMatchObject({result:{refundedCredits:7,balance:10000}});
  await api(`/api/v2/tasks/${id}`,{method:'DELETE',token:USER_TOKEN});
  await settle(id,'failed'); expect(await balance()).toBe(10000);
  expect((await env.DB.prepare("SELECT COUNT(*) n FROM user_credit_ledger WHERE id=?").bind('refund:'+id).first<{n:number}>())?.n).toBe(1);
});

it('refunds an abandoned first worker lease without any further worker pulls',async()=>{
  const {id}=await submit(); await claimTask();
  await env.DB.prepare('UPDATE widget_tasks SET created_at=?,lease_expires_at=? WHERE id=?').bind(iso(-86400000),iso(-86400000),id).run();
  await expireTasks(env); await expireTasks(env);
  expect((await taskStatus(id)).body).toMatchObject({status:'expired',refundedCredits:7}); expect(await balance()).toBe(10000);
});

it('requeues recent dead leases and refunds them when their queue deadline expires',async()=>{
  const {id}=await submit(); await claimTask();
  await env.DB.prepare('UPDATE widget_tasks SET lease_expires_at=? WHERE id=?').bind(iso(-1000),id).run();
  await expireTasks(env); expect((await taskStatus(id)).body.status).toBe('queued'); expect(await balance()).toBe(9993);
  await env.DB.prepare('UPDATE widget_tasks SET created_at=? WHERE id=?').bind(iso(-86400000),id).run();
  await expireTasks(env); expect(await balance()).toBe(10000);
});

it('expires even a continually heartbeating task at its overall deadline',async()=>{
  const {id}=await submit(); await claimTask();
  await env.DB.prepare('UPDATE widget_tasks SET created_at=?,lease_expires_at=? WHERE id=?').bind(iso(-31*60000),iso(60000),id).run();
  await expireTasks(env); expect(await balance()).toBe(10000);
});

it('refunds failed download/save after generation, and hides its result',async()=>{
  const {id}=await succeed(); expect(await balance()).toBe(9993);
  expect((await settle(id,'failed')).status).toBe(200);
  await settle(id,'failed');
  expect((await taskStatus(id)).body).toMatchObject({status:'failed',refundedCredits:7});
  expect((await taskStatus(id)).body).not.toHaveProperty('result'); expect(await balance()).toBe(10000);
  expect((await settle(id,'delivered')).status).toBe(409);
});

it('refunds unacknowledged delivery even if the app never reconnects',async()=>{
  const {id}=await succeed();
  await env.DB.prepare('UPDATE widget_tasks SET completed_at=? WHERE id=?').bind(iso(-31*60000),id).run();
  await expireTasks(env); expect(await balance()).toBe(10000);
  expect((await taskStatus(id)).body.error).toBe('delivery_timeout');
});

it('keeps exactly one charge for acknowledged delivery and rejects subsequent failure',async()=>{
  const {id,key}=await succeed();
  expect((await settle(id,'delivered')).status).toBe(200);
  expect((await settle(id,'delivered')).status).toBe(200);
  expect((await settle(id,'failed')).status).toBe(409);
  await abandon(key);
  await env.DB.prepare('UPDATE widget_tasks SET completed_at=? WHERE id=?').bind(iso(-86400000),id).run();
  await expireTasks(env); expect(await balance()).toBe(9993);
});

it('serializes concurrent success/failure settlement into one consistent bill',async()=>{
  const {id}=await succeed();
  const responses=await Promise.all([settle(id,'delivered'),settle(id,'failed')]);
  expect(responses.map(r=>r.status).sort()).toEqual([200,409]);
  const state=(await taskStatus(id)).body;
  expect(await balance()).toBe(state.status==='completed'?9993:10000);
});

it('uses one task and one debit when a submission response is lost and retried',async()=>{
  const key=crypto.randomUUID(); const [a,b]=await Promise.all([submit(key),submit(key)]);
  expect(a.id).toBe(b.id); expect(await balance()).toBe(9993);
});

it('abandons an unknown submission before it arrives, without any later debit',async()=>{
  const key=crypto.randomUUID(); expect((await abandon(key)).status).toBe(200);
  expect((await submit(key)).response.status).toBe(409); expect(await balance()).toBe(10000);
});

it('refunds a response-lost task by persisted request key, even racing creation',async()=>{
  const key=crypto.randomUUID(); await Promise.all([submit(key),abandon(key)]);
  await abandon(key); expect(await balance()).toBe(10000);
  expect((await submit(key)).response.status).toBe(409);
});

it('does not allow another account to settle or abandon someone else’s task',async()=>{
  const {id,key}=await succeed(); expect((await settle(id,'failed','other-user')).status).toBe(404);
  await abandon(key,'other-user'); expect(await balance()).toBe(9993);
  expect((await taskStatus(id)).body.status).toBe('completed');
});

it.each([{artifacts:[]},{artifacts:[{type:'text',text:'  '}]}])('refunds invalid legacy-worker output immediately (%j)',async ({artifacts})=>{
  const {id}=await submit(); await claimTask(); const token='legacy-refund-worker';
  await env.DB.prepare("INSERT INTO widget_workers(id,widget_id,owner_id,token_hash,status,created_at) VALUES('legacy-refund',?,'admin',?,'active',?)")
    .bind(WIDGET_ID,await sha256Hex(`${env.WORKER_TOKEN_PEPPER}:${token}`),iso()).run();
  await env.DB.prepare("UPDATE widget_tasks SET worker_id='legacy-refund' WHERE id=?").bind(id).run();
  const report=(json:unknown)=>api(`/api/v2/widget-tasks/${id}/result`,{method:'POST',token,json});
  expect((await report({status:'succeeded',artifacts})).status).toBe(422);
  expect((await report({status:'failed',errorCode:'invalid_input'})).status).toBe(409); expect(await balance()).toBe(10000);
});

it('refunds the actual original debit even if stored task price is changed',async()=>{
  const {id}=await submit();
  await env.DB.prepare('UPDATE widget_tasks SET credit_cost=99 WHERE id=?').bind(id).run();
  await settle(id,'failed'); expect(await balance()).toBe(10000);
  expect((await taskStatus(id)).body).toMatchObject({creditCost:7,refundedCredits:7});
});

it('backfills historical unrefunded failures/cancellations once without refunding successes',async()=>{
  await env.DB.prepare('DROP TRIGGER refund_terminal_task').run();
  const a=await submit(), b=await submit(), c=await submit();
  await env.DB.prepare("UPDATE widget_tasks SET status='cancelled' WHERE id=?").bind(a.id).run();
  await env.DB.prepare("UPDATE widget_tasks SET status='failed' WHERE id=?").bind(b.id).run();
  await env.DB.prepare("UPDATE widget_tasks SET status='succeeded' WHERE id=?").bind(c.id).run();
  expect(await balance()).toBe(9979);
  const migration=env.TEST_MIGRATIONS.find(m=>m.name==='0017_task_failure_refunds.sql')!;
  const backfill=migration.queries[migration.queries.length-1];
  await env.DB.prepare(backfill).run(); await env.DB.prepare(backfill).run();
  expect(await balance()).toBe(9993);
  const trigger=migration.queries.find(q=>q.includes('CREATE TRIGGER refund_terminal_task'))!;
  await env.DB.prepare(trigger).run();
});

it('keeps free task failures free without creating refund credits',async()=>{
  await env.DB.prepare("UPDATE widget_versions SET manifest_json=json_set(manifest_json,'$.creditCost',0) WHERE id='version_test'").run();
  const {id}=await submit(); await settle(id,'failed');
  expect(await balance()).toBe(10000); expect((await taskStatus(id)).body.refundedCredits).toBe(0);
});
