import { env } from 'cloudflare:workers';
import { beforeEach, describe, expect, it } from 'vitest';
import { api,seedWidget,USER_TOKEN,WIDGET_ID } from './helpers';
const device='metrics-test-device-001';
const ago=(days:number)=>new Date(Date.now()-days*86400000).toISOString();
const event=(kind:string,journeyID=crypto.randomUUID(),token:string|undefined=USER_TOKEN,extra:Record<string,unknown>={})=>api('/api/v2/billing/events',{
  method:'POST',token,headers:{'X-Glance-Device':device},json:{id:crypto.randomUUID(),kind,journeyID,startedAt:ago(10),...extra}});
async function metrics(){const response=await api('/api/admin/v2/billing/metrics?days=30',{token:env.ADMIN_TOKEN});expect(response.status).toBe(200);return (await response.json() as any).result}
beforeEach(async()=>{
  await env.DB.batch(['DELETE FROM billing_events','DELETE FROM billing_trials','DELETE FROM billing_webhook_events','DELETE FROM licenses','DELETE FROM refund_requests','DELETE FROM orders','DELETE FROM widget_tasks','DELETE FROM user_credit_ledger','DELETE FROM user_auth_limits'].map(sql=>env.DB.prepare(sql)));
  await env.DB.prepare('UPDATE billing_metrics_meta SET started_at=? WHERE id=1').bind(ago(30)).run();await seedWidget();
});
async function paidOrder(id:string,intent:string,userID=1){
  await env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,request_key,request_hash,checkout_expires_at,created_at,billing_intent_id)
    VALUES(?,?,'credits','small','CNY',1200,120,0,'PROD_1234567890123456789012','software',1,?,?,?, ?,?)`)
    .bind(id,userID,crypto.randomUUID(),'hash',new Date(Date.now()+1800000).toISOString(),ago(1),intent).run();
  await env.DB.prepare("UPDATE orders SET status='paid',paid_at=?,paid_amount=1200,payment_method='wechat' WHERE id=?").bind(ago(1),id).run();
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
    await env.DB.prepare('UPDATE users SET credits=0 WHERE id=1').run();
    for(const [id,amount,reason,date] of [['signup:1',100,'signup_bonus',ago(8)],['debit:1',-100,'widget_task',ago(2)],['back:1',100,'task_refund',ago(1)]] as const){
      await env.DB.prepare('INSERT INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at) VALUES(?,1,?,?,?,?)').bind(id,amount,reason,'test',date).run();
    }
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
