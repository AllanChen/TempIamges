import { env } from 'cloudflare:workers';
import { beforeEach, describe, expect, it } from 'vitest';
import { api,seedWidget,USER_TOKEN,WIDGET_ID } from './helpers';
import { recordBillingEvent } from '../src/billing-metrics';
const device='metrics-test-device-001';
const ago=(days:number)=>new Date(Date.now()-days*86400000).toISOString();
const event=(kind:string,journeyID=crypto.randomUUID(),token:string|undefined=USER_TOKEN,extra:Record<string,unknown>={})=>api('/api/v2/billing/events',{
  method:'POST',token,headers:{'X-Glance-Device':device},json:{id:crypto.randomUUID(),kind,journeyID,startedAt:ago(10),...extra}});
async function metrics(environment='test'){const response=await api('/api/admin/v2/billing/metrics?days=30&environment='+environment,{token:env.ADMIN_TOKEN});expect(response.status).toBe(200);return (await response.json() as any).result}
beforeEach(async()=>{
  await env.DB.batch(['DELETE FROM website_events','DELETE FROM billing_events','DELETE FROM billing_trials','DELETE FROM billing_webhook_events','DELETE FROM licenses','DELETE FROM refund_requests','DELETE FROM orders','DELETE FROM widget_tasks','DELETE FROM user_credit_ledger','DELETE FROM user_auth_limits'].map(sql=>env.DB.prepare(sql)));
  await env.DB.prepare('UPDATE billing_metrics_meta SET started_at=? WHERE id=1').bind(ago(30)).run();await seedWidget();
});
async function paidOrder(id:string,intent:string,userID=1){
  await env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,request_key,request_hash,checkout_expires_at,created_at,billing_intent_id)
    VALUES(?,?,'credits','small','CNY',1200,120,0,'PROD_1234567890123456789012','software',1,?,?,?, ?,?)`)
    .bind(id,userID,crypto.randomUUID(),'hash',new Date(Date.now()+1800000).toISOString(),ago(1),intent).run();
  await env.DB.prepare("UPDATE orders SET status='paid',paid_at=?,paid_amount=1200,payment_method='wechat',billing_mode='test' WHERE id=?").bind(ago(1),id).run();
}
describe('billing analytics',()=>{
  it('protects the admin report, validates events and keeps content out of storage',async()=>{
    expect((await api('/api/admin/v2/billing/metrics',{token:USER_TOKEN})).status).toBe(401);
    expect((await event('invented')).status).toBe(400);
    expect((await event('login_success',undefined,'')).status).toBe(401);
    expect((await event('locked_click',undefined,USER_TOKEN,{feature:'ocr',user_id:2,prompt:'must not be stored'})).status).toBe(202);
    const stored=await env.DB.prepare('SELECT * FROM billing_events').first<any>();expect(stored.user_id).toBe(1);expect(JSON.stringify(stored)).not.toContain('must not be stored');
    expect((await metrics()).lockedClicks).toEqual([{feature:'ocr',clicks:1}]);
  });
  it('joins anonymous login prompts to a signed-in success by device and journey, with replay deduplication',async()=>{
    const journey=crypto.randomUUID();const body={id:crypto.randomUUID(),kind:'login_prompt',journeyID:journey,startedAt:ago(10)};
    for(let i=0;i<2;i++)expect((await api('/api/v2/billing/events',{method:'POST',headers:{'X-Glance-Device':device},json:body})).status).toBe(202);
    await event('login_success',journey);
    expect((await metrics()).login).toEqual({numerator:1,denominator:1,rate:1});
  });
  it('reports no invented conversion rate before cohorts mature',async()=>{
    await event('trial_started',undefined,USER_TOKEN,{startedAt:ago(1)});
    const result=await metrics();expect(result.trialConversion).toEqual({numerator:0,denominator:0,rate:null});expect(result.giftDepletion.rate).toBeNull();
  });
  it('counts comparison activity in an anonymous trial after its device is linked to an account',async()=>{
    await event('trial_started',undefined,'');
    await event('trial_activity',undefined,'',{feature:'compare'});await event('login_success');
    expect((await metrics()).trialActivity).toEqual({numerator:1,denominator:1,rate:1});
  });
  it('counts mature trial conversions only in the seven-day window around trial end',async()=>{
    await event('trial_started',undefined,USER_TOKEN,{startedAt:ago(25)});
    await paidOrder('order_trial_conversion',crypto.randomUUID());
    await env.DB.prepare("UPDATE orders SET product='pro',credits=0,created_at=?,paid_at=? WHERE id='order_trial_conversion'").bind(ago(10),ago(10)).run();
    expect((await metrics()).trialConversion).toEqual({numerator:1,denominator:1,rate:1});
  });
  it('records gift exhaustion once inside seven days even if credits later return',async()=>{
    await event('trial_started');
    await env.DB.prepare('UPDATE users SET credits=0 WHERE id=1').run();
    await env.DB.prepare(`INSERT INTO widget_tasks(id,widget_id,version_id,command_id,owner_id,type,input_json,parameters_json,status,created_at,credit_cost,billing_mode)
      VALUES('task_metrics_gift',?,'version_test','run','user_1','production','{}','{}','queued',?,0,'test')`).bind(WIDGET_ID,ago(2)).run();
    for(const [id,amount,reason,date] of [['signup:1',100,'signup_bonus',ago(8)],['debit:1',-100,'widget_task',ago(2)],['back:1',100,'task_refund',ago(1)]] as const){
      await env.DB.prepare('INSERT INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,task_id) VALUES(?,1,?,?,?,?,?)')
        .bind(id,amount,reason,'test',date,reason==='widget_task'?'task_metrics_gift':null).run();
    }
    expect((await metrics('prod')).giftDepletion).toEqual({numerator:0,denominator:0,rate:null});
    expect(await env.DB.prepare("SELECT billing_mode FROM billing_events WHERE kind='gift_depleted'").first()).toEqual({billing_mode:'test'});
    expect((await metrics()).giftDepletion).toEqual({numerator:1,denominator:1,rate:1});
  });
  it('correlates paid top-ups with actual accepted tasks and refuses cross-account attribution',async()=>{
    const intent=crypto.randomUUID();await event('insufficient',intent);await paidOrder('order_metric_paid',intent);
    const submit=(orderID:string)=>api('/api/v2/tasks',{method:'POST',token:USER_TOKEN,json:{widgetID:WIDGET_ID,commandID:'run',input:{url:'https://example.com/a.png'},billingIntentID:intent,topupOrderID:orderID}});
    expect((await submit('order_metric_paid')).status).toBe(202);
    expect((await metrics()).insufficientTopup).toEqual({numerator:1,denominator:1,rate:1});expect((await metrics()).topupTaskSubmission).toEqual({numerator:1,denominator:1,rate:1});
    await paidOrder('order_other_owner',intent,2);expect((await submit('order_other_owner')).status).toBe(202);
    expect((await env.DB.prepare("SELECT COUNT(*) n FROM widget_tasks WHERE topup_order_id='order_other_owner'").first<any>()).n).toBe(0);
  });
});

it('excludes sandbox payments from production conversion metrics',async()=>{
 await paidOrder('order_sandbox',crypto.randomUUID());
 await env.DB.prepare("UPDATE orders SET billing_mode='test' WHERE id='order_sandbox'").run();
  expect((await metrics('prod')).payments).toEqual([]);
});


it('does not attribute a login success that preceded its prompt',async()=>{
  const journey=crypto.randomUUID();await event('login_success',journey);
  await env.DB.prepare("UPDATE billing_events SET created_at=? WHERE kind='login_success'").bind(ago(1)).run();
  await event('login_prompt',journey);
  expect((await metrics()).login).toEqual({numerator:0,denominator:1,rate:0});
});

it('reports an ordered Pro funnel and excludes cross-account and sandbox purchases',async()=>{
  const journey=crypto.randomUUID();
  await event('pro_offer',journey,USER_TOKEN,{feature:'pro'});
  await event('checkout_click',journey,USER_TOKEN,{feature:'pro'});
  await env.DB.prepare("UPDATE billing_events SET created_at=?,billing_mode='prod'").bind(ago(3)).run();
  await paidOrder('order_launch',journey);
  await env.DB.prepare("UPDATE orders SET billing_mode='prod' WHERE id='order_launch'").run();
  await env.DB.prepare("UPDATE orders SET product='pro',credits=0 WHERE id='order_launch'").run();
  expect((await metrics('prod')).launch.proFunnel).toEqual({offered:1,clicked:1,ordered:1,paid:1});
  await env.DB.prepare("UPDATE orders SET user_id=2 WHERE id='order_launch'").run();
  expect((await metrics('prod')).launch.proFunnel).toEqual({offered:1,clicked:1,ordered:0,paid:0});
  await env.DB.prepare("UPDATE orders SET user_id=1,billing_mode='test' WHERE id='order_launch'").run();
  expect((await metrics('prod')).launch.proFunnel.paid).toBe(0);
  await env.DB.prepare("UPDATE billing_events SET created_at=? WHERE kind='checkout_click'").bind(ago(4)).run();
  expect((await metrics('prod')).launch.proFunnel.clicked).toBe(0);
});

it('validates coarse metadata, deduplicates successful previews across accounts and excludes debug events',async()=>{
  const metadata={appVersion:'1.0.2',appBuild:'8',macOS:'15.6.1',architecture:'arm64',language:'de',mediaKind:'image'};
  expect((await event('first_preview_success',undefined,USER_TOKEN,{...metadata,macOS:'private@example.com'})).status).toBe(400);
  expect((await event('first_preview_success')).status).toBe(400);
  expect((await event('first_preview_success',undefined,'',{...metadata,buildChannel:'private@example.com'})).status).toBe(400);
  await event('first_preview_success',undefined,'',metadata);
  await event('first_preview_success',undefined,USER_TOKEN,metadata);
  const stored=(await env.DB.prepare("SELECT * FROM billing_events WHERE kind='first_preview_success'").all()).results;
  expect(stored).toHaveLength(1);
  expect(stored[0]).toMatchObject({app_version:'1.0.2',app_build:'8',macos_version:'15.6.1',architecture:'arm64',language:'de',media_kind:'image',billing_mode:'test'});
  expect((await metrics()).launch.activation.previewed).toBe(1);
  expect((await metrics('prod')).launch.activation.previewed).toBe(0);
  expect((await api('/api/admin/v2/billing/metrics?environment=unknown',{token:env.ADMIN_TOKEN})).status).toBe(400);
});

it('keeps debug and release event IDs independent on the production endpoint',async()=>{
  const send=(buildChannel:string,kind='first_preview_success')=>recordBillingEvent({...env,WAFFO_ENVIRONMENT:'prod'},new Request('https://example.com/api/v2/billing/events',{
    method:'POST',headers:{'Content-Type':'application/json','X-Glance-Device':device},
    body:JSON.stringify({id:kind==='trial_started'?'trial-started-fixed-id':'first-preview-success',kind,buildChannel,mediaKind:'image',startedAt:ago(buildChannel==='debug'?25:1)})}));
  for(const kind of ['trial_started','first_preview_success']) {
    expect((await send('debug',kind)).status).toBe(202);
    expect((await send('release',kind)).status).toBe(202);
    expect((await send('release',kind)).status).toBe(202);
  }
  expect((await metrics('prod')).launch.activation).toEqual({started:1,previewed:1,image:1,video:0});
  expect((await metrics('test')).launch.activation).toEqual({started:1,previewed:1,image:1,video:0});
  expect((await metrics('prod')).trialConversion.denominator).toBe(0);
  expect((await env.DB.prepare('SELECT COUNT(*) n FROM billing_events').first<any>()).n).toBe(4);
});
