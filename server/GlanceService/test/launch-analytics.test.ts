import { env } from 'cloudflare:workers';
import { beforeEach, expect, it } from 'vitest';
import { api, seedUser, USER_TOKEN } from './helpers';
import { pruneWebsiteEvents } from '../src/launch-analytics';

const sessionID='website-test-session-001';
const send=(extra:Record<string,unknown>={},headers:Record<string,string>={})=>api('/api/v2/analytics/website',{
  method:'POST',headers:{Origin:'https://glancepreview.com',...headers},
  json:{id:crypto.randomUUID(),sessionID,kind:'page_view',page:'home',language:'zh',...extra}});
beforeEach(async()=>{
  await env.DB.batch(['DELETE FROM website_events','DELETE FROM user_auth_limits'].map(sql=>env.DB.prepare(sql)));
});
it('validates origin and enums, respects privacy signals and stores no arbitrary properties',async()=>{
  expect((await send({}, {Origin:'https://evil.example'})).status).toBe(403);
  expect((await send({page:'/pay/return?token=secret'})).status).toBe(400);
  expect((await send({kind:'cta_click',target:'download',placement:'private text'})).status).toBe(400);
  expect((await send({}, {DNT:'1'})).status).toBe(202);
  expect((await send({}, {'Sec-GPC':'1'})).status).toBe(202);
  expect(await env.DB.prepare('SELECT * FROM website_events').first()).toBeNull();
  const id=crypto.randomUUID();
  for(let i=0;i<2;i++) expect((await send({id,email:'private@example.com',url:'secret'})).status).toBe(202);
  const rows=await env.DB.prepare('SELECT * FROM website_events').all();
  expect(rows.results).toHaveLength(1);
  expect(JSON.stringify(rows)).not.toContain('private@example.com');
  expect(JSON.stringify(rows)).not.toContain('secret');
});
it('counts unique download sessions only after a visit, and reports click totals separately',async()=>{
  await env.DB.prepare('UPDATE billing_metrics_meta SET started_at=? WHERE id=1').bind(new Date(Date.now()-86400000).toISOString()).run();
  await send();
  await env.DB.prepare('UPDATE website_events SET created_at=?').bind(new Date(Date.now()-10000).toISOString()).run();
  for(let i=0;i<2;i++) await send({kind:'cta_click',target:'download',placement:'home'});
  await send({sessionID:'website-unvisited-session',kind:'cta_click',target:'download',placement:'home'});
  const result=await (await api('/api/admin/v2/billing/metrics',{token:env.ADMIN_TOKEN})).json() as any;
  expect(result.result.launch.website).toEqual({sessions:1,downloaded:1});
  expect(result.result.launch.clicks[0]).toMatchObject({clicks:3,sessions:2});
});
it('expires raw website events after 90 days and old abuse counters',async()=>{
  await send();
  await env.DB.prepare('UPDATE website_events SET created_at=?').bind(new Date(Date.now()-91*86400000).toISOString()).run();
  await env.DB.prepare('UPDATE user_auth_limits SET window_start=0').run();
  await pruneWebsiteEvents(env);
  expect(await env.DB.prepare('SELECT * FROM website_events').first()).toBeNull();
  expect(await env.DB.prepare('SELECT * FROM user_auth_limits').first()).toBeNull();
});
it('rate limits public ingestion without accepting unlimited session rotation',async()=>{
  await send();
  await env.DB.prepare('UPDATE user_auth_limits SET count=300').run();
  expect((await send({sessionID:crypto.randomUUID()})).status).toBe(429);
});
it('finds old users beyond the newest 100, paginates and treats wildcards literally',async()=>{
  await seedUser();
  const now=new Date().toISOString();
  await env.DB.batch(Array.from({length:105},(_,i)=>env.DB.prepare(`INSERT INTO users(id,email,auth_provider,created_at,updated_at)
    VALUES(?,?,'email',?,?)`).bind(100+i,`launch-${i}@example.com`,now,now)));
  const list=async(query='')=>(await (await api('/api/admin/v2/users'+query,{token:env.ADMIN_TOKEN})).json() as any).result;
  const first=await list();expect(first.users).toHaveLength(100);expect(first.nextBefore).toBeTruthy();
  const next=await list('?before='+first.nextBefore);expect(next.users.some((u:any)=>u.id===1)).toBe(true);
  expect((await list('?q=test1%40example.com')).users.map((u:any)=>u.id)).toEqual([1]);
  expect((await list('?q=%25')).users).toEqual([]);
  expect((await api('/api/admin/v2/users?before=no',{token:env.ADMIN_TOKEN})).status).toBe(400);
  expect((await api('/api/admin/v2/users?q=test1',{token:USER_TOKEN})).status).toBe(401);
});
it('stores only normalized whitelisted UTM values and groups download sessions by first tagged visit',async()=>{
  await env.DB.prepare('UPDATE billing_metrics_meta SET started_at=? WHERE id=1').bind(new Date(Date.now()-86400000).toISOString()).run();
  const x={utmSource:'x',utmMedium:'social',utmCampaign:'launch',utmContent:'post-1'};
  await send({...x,sessionID:'website-x-session-0001',utmTerm:'secret'});
  await send({utmSource:'v2ex',sessionID:'website-v2ex-session-01'});
  await send({utmSource:'Me@Example.com',utmCampaign:'https://evil.example/',sessionID:'website-bad-utm-session'});
  await send({sessionID:'website-plain-session-1'});
  await env.DB.prepare('UPDATE website_events SET created_at=?').bind(new Date(Date.now()-10000).toISOString()).run();
  await send({...x,sessionID:'website-x-session-0001',kind:'cta_click',target:'download',placement:'home'});
  await send({utmSource:'v2ex',sessionID:'website-x-session-0001'});
  const rows=JSON.stringify((await env.DB.prepare('SELECT * FROM website_events').all()).results);
  expect(rows).not.toContain('secret');expect(rows).not.toContain('example');
  const result=await (await api('/api/admin/v2/billing/metrics?from='+encodeURIComponent(new Date(Date.now()-3600000).toISOString()),{token:env.ADMIN_TOKEN})).json() as any;
  const channels=Object.fromEntries(result.result.launch.channels.map((c:any)=>[c.source,c]));
  expect(channels.x).toMatchObject({medium:'social',campaign:'launch',content:'post-1',sessions:1,downloaded:1});
  expect(channels.v2ex).toMatchObject({medium:null,sessions:1,downloaded:0});
  expect(channels['(none)']).toMatchObject({sessions:2,downloaded:0});
});
it('accepts an explicit start time and rejects invalid ranges',async()=>{
  const get=(query:string)=>api('/api/admin/v2/billing/metrics?'+query,{token:env.ADMIN_TOKEN});
  const start=new Date(Date.now()-3600000).toISOString();
  await env.DB.prepare('UPDATE billing_metrics_meta SET started_at=? WHERE id=1').bind(new Date(Date.now()-86400000).toISOString()).run();
  const ok=(await (await get('from='+encodeURIComponent(start))).json() as any).result;
  expect(ok).toMatchObject({from:start,requestedFrom:start,days:null});
  for (const query of ['from=nope','from='+encodeURIComponent(new Date(Date.now()+60000).toISOString()),
    'from='+encodeURIComponent(new Date(Date.now()-400*86400000).toISOString()),'days=14'])
    expect((await get(query)).status).toBe(400);
});
it('accepts Japanese and German homepage events and rejects other languages',async()=>{
  for (const language of ['ja','de']) expect((await send({language,sessionID:'website-'+language+'-session-0001'})).status).toBe(202);
  expect((await send({language:'fr'})).status).toBe(400);
  expect((await env.DB.prepare("SELECT COUNT(*) n FROM website_events WHERE language IN ('ja','de')").first<{n:number}>())!.n).toBe(2);
});
