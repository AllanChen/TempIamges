import { env } from 'cloudflare:workers';
import { beforeEach, expect, it } from 'vitest';
import { api, seedWidget, USER_TOKEN, WIDGET_ID, taskStatus } from './helpers';
const evidence = {durationSeconds:60,byteSize:1024,sha256:'a'.repeat(64)};
async function price(unitPrice=100,duration=true) {
  const row=await env.DB.prepare('SELECT manifest_json FROM widget_versions WHERE id=?').bind('version_test').first<{manifest_json:string}>();
  const manifest={...JSON.parse(row!.manifest_json),creditCost:unitPrice,billing:duration?{mode:'duration',unitSeconds:10}:undefined};
  await env.DB.prepare('UPDATE widget_versions SET manifest_json=? WHERE id=?').bind(JSON.stringify(manifest),'version_test').run();
}
const balance=async()=>(await env.DB.prepare('SELECT credits FROM users WHERE id=1').first<{credits:number}>())!.credits;
async function quote(input:unknown=evidence,token=USER_TOKEN) {
  const response=await api('/api/v2/task-quotes',{method:'POST',token,json:{widgetID:WIDGET_ID,commandID:'run',evidence:input}});
  return {response,...(await response.json() as any)};
}
function submit(quoteID?:string,key=crypto.randomUUID(),token=USER_TOKEN,extra={}) {
  return api('/api/v2/tasks',{method:'POST',token,headers:{'Idempotency-Key':key},json:{widgetID:WIDGET_ID,commandID:'run',input:{url:'https://example.com/video.mp4',type:'video'},quoteID,...extra}});
}
async function pull(supported=true) {
  const response=await api('/api/v2/widget-tasks/pull-batch',{method:'POST',token:env.DEVELOPER_TEST_TOKEN,json:{widgets:[{widgetId:WIDGET_ID}],durationBilling:supported?1:undefined}});
  return (await response.json() as any).result.task;
}
const verify=(task:any,actual=evidence)=>api(`/api/v2/widget-tasks/${task.taskId}/verify-input`,{method:'POST',token:env.DEVELOPER_TEST_TOKEN,claim:task.claimToken,json:actual});
const finish=(task:any,status='failed')=>api(`/api/v2/widget-tasks/${task.taskId}/result`,{method:'POST',token:env.DEVELOPER_TEST_TOKEN,claim:task.claimToken,json:{status,artifacts:[{type:'video',url:'https://example.com/result.mp4'}],errorCode:'test_failure'}});
beforeEach(async()=>{
  await env.DB.batch(['DELETE FROM widget_tasks','DELETE FROM task_quotes','DELETE FROM user_credit_ledger'].map(sql=>env.DB.prepare(sql)));
  await seedWidget();await price();
});
it.each([[0.1,100],[10,100],[10.00001,200],[60,600],[187.2,1900]])('quotes %s seconds as %s credits without task/debit',async(durationSeconds,cost)=>{
  const q=await quote({...evidence,durationSeconds});
  expect(q.response.status).toBe(200);
  expect(q.result).toMatchObject({totalCredits:cost,balance:10000,shortfall:0,units:cost/100});
  expect(await balance()).toBe(10000);
  expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM widget_tasks').first<{n:number}>())!.n).toBe(0);
});
it.each([0,-1,1800,187.201])('rejects invalid/unsupported duration %s before debit',async durationSeconds=>{
  expect((await quote({...evidence,durationSeconds})).response.status).toBe(400);expect(await balance()).toBe(10000);
});
it('rejects oversized or missing evidence',async()=>{
  expect((await quote({...evidence,byteSize:50*1024*1024+1})).response.status).toBe(400);
  expect((await quote({})).response.status).toBe(400);
});
it('reports shortage without charging and atomically rejects insufficient balance',async()=>{
  await env.DB.prepare('UPDATE users SET credits=500 WHERE id=1').run();const q=await quote();
  expect(q.result).toMatchObject({totalCredits:600,balance:500,shortfall:100});
  expect((await submit(q.result.quoteID)).status).toBe(402);expect(await balance()).toBe(500);
});
it('rechecks balance after confirmation',async()=>{
  const q=await quote();await env.DB.prepare('UPDATE users SET credits=50 WHERE id=1').run();
  expect((await submit(q.result.quoteID)).status).toBe(402);
});
it('requires quotes and rejects foreign, expired and changed-price quotes',async()=>{
  expect((await submit()).status).toBe(409);const q=await quote();
  expect((await submit(q.result.quoteID,crypto.randomUUID(),'other-user')).status).toBe(409);
  await price(101);expect((await submit(q.result.quoteID)).status).toBe(409);await price();
  await env.DB.prepare("UPDATE task_quotes SET expires_at='2000-01-01' WHERE id=?").bind(q.result.quoteID).run();
  expect((await submit(q.result.quoteID)).status).toBe(409);expect(await balance()).toBe(10000);
});
it('charges once for retries, prevents reuse, and preserves price snapshot',async()=>{
  const q=await quote(),key=crypto.randomUUID();const r=await submit(q.result.quoteID,key);const id=(await r.json() as any).result.taskID;
  expect(r.status).toBe(202);expect((await submit(q.result.quoteID,key)).status).toBe(202);
  expect((await submit(q.result.quoteID)).status).toBe(409);expect(await balance()).toBe(9400);
  expect((await taskStatus(id)).body.quote).toMatchObject({totalCredits:600,units:6,evidence});
});
it('allows only one concurrent use of a quote',async()=>{
  const q=await quote();const results=await Promise.all([submit(q.result.quoteID),submit(q.result.quoteID)]);
  expect(results.map(r=>r.status).sort()).toEqual([202,409]);expect(await balance()).toBe(9400);
});
it('blocks old workers and verifies the actual file before success',async()=>{
  const q=await quote();await submit(q.result.quoteID);expect(await pull(false)).toBeNull();const task=await pull();
  expect((await verify(task)).status).toBe(200);expect((await finish(task,'succeeded')).status).toBe(200);expect(await balance()).toBe(9400);
});
it.each(['sha256','durationSeconds','byteSize'])('refunds actual-file %s mismatch before processing',async field=>{
  const q=await quote();await submit(q.result.quoteID);const task=await pull();
  const actual={...evidence,[field]:field==='sha256'?'b'.repeat(64):field==='durationSeconds'?61:1025};
  expect((await verify(task,actual)).status).toBe(409);expect(await balance()).toBe(10000);
  expect((await taskStatus(task.taskId)).body).toMatchObject({status:'failed',refundedCredits:600});
  await verify(task,actual);expect(await balance()).toBe(10000);
});
it('rejects unverified success and refunds whole task',async()=>{
  const q=await quote();await submit(q.result.quoteID);const task=await pull();
  expect((await finish(task,'succeeded')).status).toBe(422);expect(await balance()).toBe(10000);
});
it('refunds all units on failure once, even after verification',async()=>{
  const q=await quote();await submit(q.result.quoteID);const task=await pull();await verify(task);
  expect((await finish(task)).status).toBe(200);await finish(task);expect(await balance()).toBe(10000);
});
it('strips caller billing snapshots; legacy fixed-price tasks still work',async()=>{
  await price(30,false);const r=await submit(undefined,crypto.randomUUID(),USER_TOKEN,{taskParams:{_billingQuote:{mode:'duration',totalCredits:0}}});
  expect(r.status).toBe(202);expect(await balance()).toBe(9970);expect((await pull(false)).parameters).not.toHaveProperty('_billingQuote');
});
