import { env } from 'cloudflare:workers';
import { beforeAll, beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import worker, { type Env } from '../src/index';
import { defaultPricing, readPricing, expireTasks, tierPrice, paymentPrivateKey } from '../src/pricing';
import { api, seedWidget, USER_TOKEN, WIDGET_ID, claimTask, createTask } from './helpers';

let privateKey: string;
let publicKey: string;
let signingKey: CryptoKey;
let licensePublicKey: CryptoKey;
const device = 'billing-test-device-0001';
let billingEnv: Env;
let checkoutCalls: Record<string, unknown>[];
beforeAll(async () => {
  const rsa = await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']) as CryptoKeyPair;
  signingKey=rsa.privateKey;
  const pem=async (key:CryptoKey,format:'pkcs8'|'spki',label:string)=>'-----BEGIN '+label+'-----\n'+btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey(format,key))))+'\n-----END '+label+'-----';
  privateKey=await pem(rsa.privateKey,'pkcs8','PRIVATE KEY');publicKey=await pem(rsa.publicKey,'spki','PUBLIC KEY');
  const key = await crypto.subtle.generateKey('Ed25519', true, ['sign','verify']) as CryptoKeyPair;
  licensePublicKey=key.publicKey;
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', key.privateKey));
  billingEnv = { ...env, WAFFO_MERCHANT_ID: 'MER_1234567890123456789012', WAFFO_STORE_ID: 'STO_1234567890123456789012',
    WAFFO_PRIVATE_KEY: privateKey, WAFFO_WEBHOOK_PUBLIC_KEY_TEST: publicKey, WAFFO_ENVIRONMENT: 'test',
    GLANCE_SIGNING_KEY_PKCS8: btoa(String.fromCharCode(...pkcs8)) };
});
beforeEach(async () => {
  await env.DB.batch(['DELETE FROM billing_webhook_events','DELETE FROM licenses','DELETE FROM admin_pro_grants','DELETE FROM refund_requests','DELETE FROM orders',
    'DELETE FROM license_devices','DELETE FROM device_releases','DELETE FROM billing_settings','DELETE FROM widget_tasks','DELETE FROM user_credit_ledger'].map(sql=>env.DB.prepare(sql)));
  await seedWidget();
  await env.DB.prepare('UPDATE users SET trial_started_at=NULL,trial_voided=0,widget_notice_seen=0 WHERE id=1').run();
  checkoutCalls = [];
  vi.stubGlobal('fetch',vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
    const url = String(_url), body = JSON.parse(String(init?.body || '{}'));
    if (url.includes('issue-session-token')) return Response.json({data:{token:'test-buyer-token',expiresAt:new Date(Date.now()+1800000).toISOString()}});
    if (url.includes('create-session')) {
      checkoutCalls.push(body);
      return Response.json({data:{sessionId:'CS_1234567890123456789012',checkoutUrl:'https://checkout.example.com/session',expiresAt:new Date(Date.now()+1800000).toISOString()}});
    }
    if (url.includes('refund')) {
      const headers=new Headers(init?.headers);
      expect(headers.has('Authorization')).toBe(false);
      expect(headers.get('X-Merchant-Id')).toBe(billingEnv.WAFFO_MERCHANT_ID);
      expect(headers.get('X-Idempotency-Key')).toBe(body.refundTicketMerchantExternalId);
      const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(String(init?.body)));
      const hash=btoa(String.fromCharCode(...new Uint8Array(digest)));
      const canonical=`POST\n${new URL(url).pathname}\n${headers.get('X-Timestamp')}\n${hash}`;
      const key=await crypto.subtle.importKey('spki',Uint8Array.from(atob(publicKey.replace(/-----BEGIN PUBLIC KEY-----|-----END PUBLIC KEY-----|\s/g,'')),c=>c.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
      expect(await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,Uint8Array.from(atob(headers.get('X-Signature')!),c=>c.charCodeAt(0)),new TextEncoder().encode(canonical))).toBe(true);
      return Response.json({data:{ticket:{id:'RFT_1234567890123456789012'}}});
    }
    throw new Error('Unexpected provider endpoint');
  }));
});
afterEach(()=>{delete billingEnv.TEST_CHECKOUT_USER_ID;vi.unstubAllGlobals();vi.restoreAllMocks()});
async function call(path: string, body?: unknown, token=USER_TOKEN, extra: HeadersInit={}) {
  return worker.fetch(new Request('https://example.com'+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+token,'X-Glance-Device':device,'Content-Type':'application/json',...extra},body:body===undefined?undefined:JSON.stringify(body)}),billingEnv);
}
async function configure() {
  const config=defaultPricing(billingEnv); config.enabled=true;config.supportEmail='support@example.com';
  // Tier prices used by the webhook amounts below: personal 100.00 / 20.00, duo 150.00 / 30.00; no launch price.
  Object.assign(config.proTiers[0],{CNY:{amount:10000},USD:{amount:2000},launchCNY:{amount:null},launchUSD:{amount:null}});
  Object.assign(config.proTiers[1],{id:'duo',deviceLimit:2,CNY:{amount:15000},USD:{amount:3000},launchCNY:{amount:null},launchUSD:{amount:null}});
  config.packs[0].CNY.points=120;config.packs[0].USD.points=120;
  config.launchUntil=null;
  for(const product of [...config.proTiers,...config.packs])product.productID='PROD_1234567890123456789012';
  await env.DB.prepare('INSERT INTO billing_settings(id,revision,json,updated_at) VALUES(1,1,?,?)').bind(JSON.stringify(config),new Date().toISOString()).run();
  return config;
}
async function buy(product='credits', currency='CNY', key=crypto.randomUUID(), expectedPrice?: unknown, tierID='personal') {
  const config=await readPricing(billingEnv), cur=currency as 'CNY'|'USD';
  const price=product==='credits'?config.packs[0][cur]:tierPrice(config,config.proTiers.find(t=>t.id===tierID)!,cur);
  const response=await call('/api/v2/orders',{product,currency,...(product==='credits'?{packID:'small'}:{tierID}),expectedPrice:expectedPrice??price},USER_TOKEN,{'Idempotency-Key':key});
  const body=await response.json() as any;
  return {response,body,id:body.result?.orderID as string};
}
async function balance(){return (await env.DB.prepare('SELECT credits FROM users WHERE id=1').first<{credits:number}>())!.credits}
async function webhook(orderID: string, eventType='order.completed', overrides: Record<string, unknown>={}, eventID=crypto.randomUUID(), businessID?: string) {
  const event={id:eventID,timestamp:new Date().toISOString(),eventType,eventId:businessID??(eventType==='order.completed'?'PAY_'+orderID.replace(/[^A-Za-z0-9]/g,'').slice(-22):'REF_'+eventID),
    storeId:billingEnv.WAFFO_STORE_ID,mode:'test',data:{orderId:'ORD_'+orderID,orderMerchantExternalId:orderID,merchantProvidedBuyerIdentity:'1',currency:'CNY',
      listPrice:{total:'12.00'},chargedAmount:'12.00',refundedAmount:'12.00',...overrides}};
  const raw=JSON.stringify(event),t=String(Date.now());const signature=btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',signingKey,new TextEncoder().encode(t+'.'+raw)))));
  return worker.fetch(new Request('https://example.com/api/v2/payments/waffo/webhook',{method:'POST',headers:{'X-Waffo-Signature':`t=${t},v1=${signature}`},body:raw}),billingEnv);
}

describe('provider sandbox checkout while sales are closed',()=>{
  it('only lets the designated tester buy sandbox products and never auto-fulfills',async()=>{
    const config=await configure(); config.enabled=false;
    await env.DB.prepare('UPDATE billing_settings SET json=? WHERE id=1').bind(JSON.stringify(config)).run();
    billingEnv.TEST_CHECKOUT_USER_ID='1';
    expect(await (await call('/api/v2/pricing')).json()).toMatchObject({result:{enabled:false,paymentsAvailable:true,mockCheckout:false}});
    expect(await (await call('/api/v2/pricing',undefined,'other-user')).json()).toMatchObject({result:{paymentsAvailable:false}});
    const result=await buy();
    expect(result.response.status).toBe(200);
    expect(result.body.result.order).toMatchObject({status:'pending',mock:false});
    const other=await call('/api/v2/orders',{product:'credits',packID:'small',currency:'CNY',expectedPrice:config.packs[0].CNY},'other-user',{'Idempotency-Key':crypto.randomUUID()});
    expect(other.status).toBe(503);
    expect((await buy('pro')).response.status).toBe(200);
  });
  it('does not bypass closed sales with production credentials',async()=>{
    const config=await configure(); config.enabled=false;
    await env.DB.prepare('UPDATE billing_settings SET json=? WHERE id=1').bind(JSON.stringify(config)).run();
    const prodEnv={...billingEnv,WAFFO_ENVIRONMENT:'prod',WAFFO_WEBHOOK_PUBLIC_KEY_PROD:publicKey,TEST_CHECKOUT_USER_ID:'1'};
    const result=await worker.fetch(new Request('https://example.com/api/v2/pricing',{headers:{Authorization:'Bearer '+USER_TOKEN}}),prodEnv);
    expect(await result.json()).toMatchObject({result:{paymentsAvailable:false}});
  });
});

describe('temporary mock credit checkout',()=>{
  it('allows repeat top-ups for the designated account without collecting cash',async()=>{
    const mockEnv:Env={...billingEnv,WAFFO_MERCHANT_ID:undefined,WAFFO_PRIVATE_KEY:undefined,
      WAFFO_STORE_ID:undefined,WAFFO_WEBHOOK_PUBLIC_KEY_TEST:undefined,MOCK_CHECKOUT_USER_ID:'1'};
    const mockCall=(path:string,token?:string,body?:unknown,key?:string)=>worker.fetch(new Request('https://example.com'+path,{
      method:body===undefined?'GET':'POST',headers:{...(token?{Authorization:'Bearer '+token}:{}),
        'Content-Type':'application/json',...(key?{'Idempotency-Key':key}:{})},
      body:body===undefined?undefined:JSON.stringify(body)}),mockEnv);
    const publicPrice=await (await mockCall('/api/v2/pricing')).json() as any;
    expect(publicPrice.result.paymentsAvailable).toBe(false);
    expect((await (await mockCall('/api/v2/pricing','other-user')).json() as any).result.paymentsAvailable).toBe(false);
    const offer=(await (await mockCall('/api/v2/pricing',USER_TOKEN)).json() as any).result;
    expect(offer.paymentsAvailable).toBe(true);
    expect(offer.packs[0].productID).toBe('mock_credits');
    const key=crypto.randomUUID();
    const body={product:'credits',packID:'small',currency:'CNY',expectedPrice:offer.packs[0].CNY};
    const response=await mockCall('/api/v2/orders',USER_TOKEN,body,key);
    expect(response.status).toBe(200);
    const checkout=await response.json() as any;
    expect(checkout.result.order).toMatchObject({status:'paid',mock:true,amount:0,credits:600});
    expect(checkout.result.checkoutUrl).toContain('/pay/mock/');
    expect(await balance()).toBe(10600);
    const stored=await env.DB.prepare('SELECT paid_amount,payment_method,status FROM orders WHERE id=?')
      .bind(checkout.result.orderID).first<any>();
    expect(stored).toMatchObject({paid_amount:0,payment_method:'mock',status:'paid'});
    expect((await env.DB.prepare('SELECT amount FROM user_credit_ledger WHERE id=?')
      .bind('order:'+checkout.result.orderID).first<any>())?.amount).toBe(600);
    expect(checkoutCalls).toHaveLength(0);
    expect((await (await mockCall('/api/v2/pricing',USER_TOKEN)).json() as any).result.paymentsAvailable).toBe(true);
    expect((await mockCall('/api/v2/orders',USER_TOKEN,body,key)).status).toBe(200);
    expect(await balance()).toBe(10600);
    const another=await mockCall('/api/v2/orders',USER_TOKEN,{...body,packID:'large',currency:'USD',expectedPrice:offer.packs[2].USD},crypto.randomUUID());
    expect(another.status).toBe(200);
    expect((await another.json() as any).result.order).toMatchObject({status:'paid',mock:true,amount:0,credits:5000});
    expect(await balance()).toBe(15600);
    expect((await mockCall('/api/v2/orders','other-user',body,crypto.randomUUID())).status).toBe(503);
    expect((await call('/api/v2/orders/'+checkout.result.orderID+'/refund',{reason:'No charge'})).status).toBe(409);
    expect((await webhook(checkout.result.orderID)).status).toBe(409);
    const page=await mockCall('/pay/mock/?order='+checkout.result.orderID);
    expect(page.status).toBe(200);
    expect(await page.text()).toContain('没有发生真实付款');
  });
});

describe('temporary mock Pro checkout',()=>{
  it('activates Pro for the designated account, with a placeholder price when none is set',async()=>{
    const mockEnv:Env={...billingEnv,WAFFO_MERCHANT_ID:undefined,WAFFO_PRIVATE_KEY:undefined,
      WAFFO_STORE_ID:undefined,WAFFO_WEBHOOK_PUBLIC_KEY_TEST:undefined,MOCK_CHECKOUT_USER_ID:'1'};
    const mockCall=(path:string,token?:string,body?:unknown,key?:string)=>worker.fetch(new Request('https://example.com'+path,{
      method:body===undefined?'GET':'POST',headers:{...(token?{Authorization:'Bearer '+token}:{}),
        'Content-Type':'application/json',...(key?{'Idempotency-Key':key}:{})},
      body:body===undefined?undefined:JSON.stringify(body)}),mockEnv);
    const stored=await env.DB.prepare('SELECT json FROM billing_settings WHERE id=1').first<{json:string}>();
    if (stored) {
      const config=JSON.parse(stored.json);
      config.proTiers=config.proTiers.map((t:any)=>({...t,CNY:{amount:null},USD:{amount:null},launchCNY:{amount:null},launchUSD:{amount:null},productID:''}));config.launchUntil=null;
      await env.DB.prepare('UPDATE billing_settings SET json=? WHERE id=1').bind(JSON.stringify(config)).run();
    }
    expect((await (await mockCall('/api/v2/pricing','other-user')).json() as any).result.proTiers[0].productID).not.toContain('mock_pro');
    const offer=(await (await mockCall('/api/v2/pricing',USER_TOKEN)).json() as any).result;
    expect(offer.mockCheckout).toBe(true);
    const tier=offer.proTiers[0];
    expect(tier.productID).toBeTruthy();
    expect(tier.CNY.amount).toBeGreaterThan(0);
    const response=await mockCall('/api/v2/orders',USER_TOKEN,{product:'pro',tierID:tier.id,currency:'CNY',expectedPrice:tier.CNY},crypto.randomUUID());
    expect(response.status).toBe(200);
    const checkout=await response.json() as any;
    expect(checkout.result.order).toMatchObject({product:'pro',status:'paid',mock:true,amount:0});
    expect(checkout.result.checkoutUrl).toContain('/pay/mock/');
    expect((await env.DB.prepare('SELECT status FROM licenses WHERE user_id=1').first<any>())?.status).toBe('active');
    expect(checkoutCalls).toHaveLength(0);
    expect((await mockCall('/api/v2/orders','other-user',{product:'pro',tierID:tier.id,currency:'CNY',expectedPrice:tier.CNY},crypto.randomUUID())).status).toBe(503);
  });
});

describe('administrator Pro grants',()=>{
  const grant=(userID=1,note='Beta tester',key:string=crypto.randomUUID(),token=env.ADMIN_TOKEN)=>
    call('/api/admin/v2/users/'+userID+'/pro',{note},token,{'Idempotency-Key':key});
  it('requires admin, an active existing account, a note and an idempotency key',async()=>{
    expect((await grant(1,'Tester',crypto.randomUUID(),USER_TOKEN)).status).toBe(401);
    expect((await grant(1,'Tester',crypto.randomUUID(),env.DEVELOPER_TEST_TOKEN)).status).toBe(401);
    expect((await grant(1,'   ')).status).toBe(400);
    expect((await grant(1,'Tester','bad')).status).toBe(400);
    expect((await grant(999)).status).toBe(404);
    await env.DB.prepare("UPDATE users SET status='disabled' WHERE id=1").run();
    expect((await grant()).status).toBe(409);
    expect((await env.DB.prepare('SELECT COUNT(*) n FROM admin_pro_grants').first<any>()).n).toBe(0);
  });
  it('grants without a payment setup or fake order, audits once and signs normal device credentials',async()=>{
    const key=crypto.randomUUID();
    expect((await grant(1,'Beta tester',key)).status).toBe(200);
    const license=await env.DB.prepare('SELECT * FROM licenses WHERE user_id=1').first<any>();
    expect(license).toMatchObject({status:'active',source_order:null,source_admin_grant:'admin-pro:'+key});
    expect(license.updates_until).toBe('9999-12-31T00:00:00.000Z');
    expect((await grant(1,'Beta tester',key)).status).toBe(200);
    expect((await grant(1,'Changed reason',key)).status).toBe(409);
    expect((await grant(2,'Beta tester',key)).status).toBe(409);
    expect((await grant()).status).toBe(409);
    expect((await env.DB.prepare('SELECT COUNT(*) n FROM admin_pro_grants').first<any>()).n).toBe(1);
    expect((await env.DB.prepare('SELECT COUNT(*) n FROM orders').first<any>()).n).toBe(0);
    expect(await balance()).toBe(10000);
    const activated=await (await call('/api/v2/account/devices/activate',{deviceID:device,name:'Tester Mac'})).json() as any;
    expect(activated.result).toMatchObject({pro:true,trialVoided:true,deviceLimit:1});
    const credential=activated.result.credential;
    expect(JSON.parse(atob(credential.payload)).sourceOrder).toBe('admin-pro:'+key);
    expect(await crypto.subtle.verify('Ed25519',licensePublicKey,Uint8Array.from(atob(credential.signature),c=>c.charCodeAt(0)),new TextEncoder().encode(credential.payload))).toBe(true);
    const listed=await (await api('/api/admin/v2/users',{token:env.ADMIN_TOKEN})).json() as any;
    expect(listed.result.users.find((user:any)=>user.id===1)).toMatchObject({license_status:'active',license_source:'admin',updates_until:license.updates_until});
    const history=await api('/api/admin/v2/users/1/pro',{token:env.ADMIN_TOKEN});
    expect(history.status).toBe(200);
    expect((await history.json() as any).result.grants).toEqual([expect.objectContaining({id:'admin-pro:'+key,note:'Beta tester',device_limit:1,active:1})]);
    expect((await api('/api/admin/v2/users/1/pro',{token:USER_TOKEN})).status).toBe(401);
    const report=await (await api('/api/admin/v2/billing/metrics',{token:env.ADMIN_TOKEN})).json() as any;
    expect(report.result.launch.grants).toEqual({issued:1,users:1,active:1,activated:1});
    expect(report.result.launch.proFunnel.paid).toBe(0);

  });
  it('uses the configured Mac limit for grants and preserves existing paid Pro unchanged',async()=>{
    const config=await configure();config.deviceLimit=3;
    await env.DB.prepare('UPDATE billing_settings SET json=?').bind(JSON.stringify(config)).run();
    expect((await grant(2)).status).toBe(200);
    const free=await env.DB.prepare('SELECT updates_until,device_limit,tier_id FROM licenses WHERE user_id=2').first<any>();
    expect(free).toMatchObject({device_limit:3,tier_id:null});
    expect(Date.parse(free.updates_until)).toBeGreaterThan(Date.now()+720*86400000);
    const {id}=await buy('pro');await webhook(id,'order.completed',{listPrice:{total:'100.00'},chargedAmount:'100.00'});
    const original=await env.DB.prepare('SELECT * FROM licenses WHERE user_id=1').first();
    expect((await grant()).status).toBe(409);
    expect(await env.DB.prepare('SELECT * FROM licenses WHERE user_id=1').first()).toEqual(original);
  });
  it('keeps the admin grant when a previously pending payment arrives and is refunded',async()=>{
    await configure();const {id}=await buy('pro');
    expect((await grant()).status).toBe(200);
    await call('/api/v2/account/devices/activate',{deviceID:device,name:'Mac'});
    await webhook(id,'order.completed',{listPrice:{total:'100.00'},chargedAmount:'100.00'});
    await webhook(id,'refund.succeeded',{refundedAmount:'100.00'});
    expect(await (await call('/api/v2/account/entitlements')).json()).toMatchObject({result:{pro:true,trialVoided:true,licenseStatus:'active'}});
    expect(await balance()).toBe(10000);
  });
});

describe('pricing and checkout',()=>{
  it('keeps payments unavailable until configured, and requires admin with optimistic revisions',async()=>{
    expect(await (await call('/api/v2/pricing')).json()).toMatchObject({result:{enabled:false,paymentsAvailable:false,launchUntil:null,proTiers:[{id:'personal',deviceLimit:1},{id:'team',deviceLimit:1}]}});
    expect((await buy()).response.status).toBe(503);
    expect((await api('/api/admin/v2/pricing',{token:USER_TOKEN})).status).toBe(401);
    const config=await configure();
    const save=(revision:number)=>worker.fetch(new Request('https://example.com/api/admin/v2/pricing',{method:'PUT',headers:{Authorization:'Bearer '+env.ADMIN_TOKEN,'Content-Type':'application/json'},body:JSON.stringify({revision,config})}),billingEnv);
    expect((await save(1)).status).toBe(200);expect((await save(1)).status).toBe(409);
    expect(await (await call('/api/v2/pricing',undefined,USER_TOKEN,{'CF-IPCountry':'CN'})).json()).toMatchObject({result:{defaultCurrency:'CNY',paymentsAvailable:true}});
  });
  it('snapshots price, coalesces pending orders, protects ownership and rejects stale prices',async()=>{
    await configure();const key=crypto.randomUUID();
    expect((await buy('credits','CNY',crypto.randomUUID(),{amount:1,points:120})).response.status).toBe(409);
    const first=await buy('credits','CNY',key);expect(first.response.status).toBe(200);expect(first.body.result.checkoutUrl).toContain('#token=');
    expect(checkoutCalls[0]).toMatchObject({priceSnapshot:{amount:'12.00'},includePaymentMethods:['wechat'],orderMerchantExternalId:first.id});
    expect((await buy('credits','CNY',key)).id).toBe(first.id);expect((await buy()).id).toBe(first.id);expect(checkoutCalls).toHaveLength(1);
    expect((await buy('credits','USD')).response.status).toBe(409);
    expect((await call('/api/v2/orders/'+first.id,undefined,'other-user')).status).toBe(404);
    const stored=await env.DB.prepare('SELECT checkout_url FROM orders WHERE id=?').bind(first.id).first<{checkout_url:string}>();expect(stored!.checkout_url).not.toContain('test-buyer-token');
    expect(await balance()).toBe(10000);
  });
  it('lets an explicitly abandoned CNY order switch to USD while preserving late payment delivery',async()=>{
    await configure();const first=await buy();
    expect((await call('/api/v2/orders/'+first.id+'/abandon',{},'other-user')).status).toBe(404);
    expect((await call('/api/v2/orders/'+first.id+'/abandon',{})).status).toBe(200);
    const second=await buy('credits','USD');expect(second.response.status).toBe(200);expect(second.id).not.toBe(first.id);
    expect((await webhook(first.id)).status).toBe(200);expect(await balance()).toBe(10120);
  });
  it('uses independent USD price and point totals',async()=>{
    const config=await configure();config.packs[0].USD.points=85;await env.DB.prepare('UPDATE billing_settings SET json=?').bind(JSON.stringify(config)).run();
    const order=await buy('credits','USD');expect(order.body.result.order).toMatchObject({amount:299,credits:85,currency:'USD'});
    expect(checkoutCalls[0]).toMatchObject({includePaymentMethods:['card','applepay','googlepay'],priceSnapshot:{amount:'2.99'}});
  });
});
describe('verified payment and refund accounting',()=>{
  it('rejects invalid signatures, amounts, buyers and environments without fulfillment',async()=>{
    await configure();const {id}=await buy();
    expect((await worker.fetch(new Request('https://example.com/api/v2/payments/waffo/webhook',{method:'POST',body:'{}'}),billingEnv)).status).toBe(401);
    expect((await webhook(id,'order.completed',{listPrice:{total:'0.01'}})).status).toBe(409);
    expect((await webhook(id,'order.completed',{merchantProvidedBuyerIdentity:'2'})).status).toBe(409);
    expect(await balance()).toBe(10000);
  });
  it('credits exactly once including concurrent deliveries, delivery IDs and late success',async()=>{
    await configure();const {id}=await buy();await env.DB.prepare("UPDATE orders SET status='expired' WHERE id=?").bind(id).run();
    const deliveries=await Promise.all([webhook(id),webhook(id)]);expect(deliveries.map(r=>r.status)).toEqual([200,200]);
    expect(await balance()).toBe(10120);expect((await webhook(id)).status).toBe(200);expect(await balance()).toBe(10120);
    const paid=await call('/api/v2/orders/'+id);expect(await paid.json()).toMatchObject({result:{order:{status:'paid'},balance:10120}});
  });
  it('leaves rights on refund failure, revokes on success and deduplicates business IDs',async()=>{
    await configure();const {id}=await buy();await webhook(id);
    expect((await call('/api/v2/orders/'+id+'/refund',{reason:'Unused package'})).status).toBe(200);
    expect(await balance()).toBe(10120);
    expect((await call('/api/admin/v2/orders/'+id+'/refund',{reason:'Approved'},env.ADMIN_TOKEN)).status).toBe(200);
    await webhook(id,'refund.failed');expect(await balance()).toBe(10120);
    expect((await webhook(id,'refund.succeeded',{},undefined,'refund-business-id')).status).toBe(200);expect(await balance()).toBe(10000);
    expect((await webhook(id,'refund.succeeded',{},undefined,'refund-business-id')).status).toBe(200);expect(await balance()).toBe(10000);
  });
  it('allows admin to decline an application without changing credits or rights',async()=>{
    await configure();const {id}=await buy();await webhook(id);await call('/api/v2/orders/'+id+'/refund',{reason:'Unused'});
    expect((await call('/api/admin/v2/orders/'+id+'/refund/deny',{reason:'Needs more information'},USER_TOKEN)).status).toBe(401);
    expect((await call('/api/admin/v2/orders/'+id+'/refund/deny',{reason:'Needs more information'},env.ADMIN_TOKEN)).status).toBe(200);
    expect(await balance()).toBe(10120);
    expect(await (await call('/api/v2/orders/'+id)).json()).toMatchObject({result:{order:{status:'paid',refundStatus:'rejected',refundReason:'Needs more information'}}});
  });
  it('does not allow normal credit refunds after spending or after 14 days',async()=>{
    await configure();const {id}=await buy();await webhook(id);await env.DB.prepare('UPDATE users SET credits=119 WHERE id=1').run();
    expect((await call('/api/v2/orders/'+id+'/refund',{reason:'Refund'})).status).toBe(409);
    await env.DB.prepare("UPDATE orders SET paid_at='2020-01-01T00:00:00Z' WHERE id=?").bind(id).run();
    expect((await call('/api/v2/orders/'+id+'/refund',{reason:'Refund'})).status).toBe(409);
  });
  it('grants Pro bonus once, signs licenses, voids trial permanently and claws back spent bonus',async()=>{
    await configure();const {id}=await buy('pro');expect((await webhook(id,'order.completed',{listPrice:{total:'100.00'},chargedAmount:'100.00'})).status).toBe(200);
    expect(await balance()).toBe(10100);
    const activated=await call('/api/v2/account/devices/activate',{deviceID:device,name:'Test Mac'});expect(activated.status).toBe(200);
    const result=await activated.json() as any;expect(result.result).toMatchObject({pro:true,trialVoided:true,deviceLimit:1,tierID:'personal',credential:{keyID:'glance-market-2026-02'}});
    expect(await crypto.subtle.verify('Ed25519',licensePublicKey,Uint8Array.from(atob(result.result.credential.signature),c=>c.charCodeAt(0)),new TextEncoder().encode(result.result.credential.payload))).toBe(true);
    const claims=JSON.parse(atob(result.result.credential.payload));expect(claims.userID).toBe(1);expect(Date.parse(claims.expiresAt)-Date.parse(claims.issuedAt)).toBe(30*86400000);
    await env.DB.prepare('UPDATE users SET credits=0 WHERE id=1').run();
    expect((await webhook(id,'refund.succeeded',{refundedAmount:'100.00'})).status).toBe(200);expect(await balance()).toBe(-100);
    expect(await (await call('/api/v2/account/entitlements')).json()).toMatchObject({result:{pro:false,trialVoided:true,licenseStatus:'refunded',credential:null}});
    const second=await buy('pro');await webhook(second.id,'order.completed',{listPrice:{total:'100.00'},chargedAmount:'100.00'});expect(await balance()).toBe(-100);
  });
  it('preserves a paid buyout when another late duplicate buyout is refunded',async()=>{
    await configure();const first=await buy('pro');await env.DB.prepare("UPDATE orders SET status='expired' WHERE id=?").bind(first.id).run();
    const second=await buy('pro');
    for(const order of [first,second])expect((await webhook(order.id,'order.completed',{listPrice:{total:'100.00'},chargedAmount:'100.00'})).status).toBe(200);
    await call('/api/v2/account/devices/activate',{deviceID:device,name:'Mac'});
    await webhook(first.id,'refund.succeeded',{refundedAmount:'100.00'});
    expect(await env.DB.prepare('SELECT status,source_order FROM licenses WHERE user_id=1').first()).toEqual({status:'active',source_order:second.id});
    expect(await (await call('/api/v2/account/entitlements')).json()).toMatchObject({result:{pro:true}});
    expect(await balance()).toBe(10000);
    expect(await (await call('/api/v2/orders/'+second.id)).json()).toMatchObject({result:{order:{bonusCredits:0}}});
  });
  it('sells lifetime tiers by Mac count, allows only upgrades, and restores the lower tier when an upgrade is refunded',async()=>{
    await configure();
    const personal=await buy('pro');await webhook(personal.id,'order.completed',{listPrice:{total:'100.00'},chargedAmount:'100.00'});
    expect(await env.DB.prepare('SELECT status,device_limit,tier_id,updates_until FROM licenses WHERE user_id=1').first()).toEqual({status:'active',device_limit:1,tier_id:'personal',updates_until:'9999-12-31T00:00:00.000Z'});
    expect((await buy('pro','CNY',crypto.randomUUID(),undefined,'personal')).response.status).toBe(409);
    expect((await call('/api/v2/orders',{product:'renewal',currency:'CNY',expectedPrice:{amount:5000}},USER_TOKEN,{'Idempotency-Key':crypto.randomUUID()})).status).toBe(400);
    expect((await (await call('/api/v2/account/entitlements')).json() as any).result).toMatchObject({deviceLimit:1,tierID:'personal'});
    const duo=await buy('pro','CNY',crypto.randomUUID(),undefined,'duo');
    expect(duo.response.status).toBe(200);
    expect(duo.body.result.order).toMatchObject({tierID:'duo',deviceLimit:2,bonusCredits:0});
    await webhook(duo.id,'order.completed',{listPrice:{total:'150.00'},chargedAmount:'150.00'});
    expect(await env.DB.prepare('SELECT status,device_limit,tier_id,source_order FROM licenses WHERE user_id=1').first()).toEqual({status:'active',device_limit:2,tier_id:'duo',source_order:duo.id});
    expect(await balance()).toBe(10100);
    await call('/api/v2/account/devices/activate',{deviceID:device,name:'Mac one'});
    await call('/api/v2/account/devices/activate',{deviceID:'second-device-identifier-0001',name:'Mac two'});
    expect((await env.DB.prepare('SELECT COUNT(*) n FROM license_devices WHERE user_id=1 AND released_at IS NULL').first<any>()).n).toBe(2);
    await webhook(duo.id,'refund.succeeded',{refundedAmount:'150.00'});
    expect(await env.DB.prepare('SELECT status,device_limit,tier_id,source_order FROM licenses WHERE user_id=1').first()).toEqual({status:'active',device_limit:1,tier_id:'personal',source_order:personal.id});
    expect((await env.DB.prepare('SELECT COUNT(*) n FROM license_devices WHERE user_id=1 AND released_at IS NULL').first<any>()).n).toBe(1);
    expect(await balance()).toBe(10100);
  });
});
describe('trial, devices and task refunds',()=>{
  it('synchronizes the earliest trial start across devices without extending it',async()=>{
    await configure();const early='2026-01-01T00:00:00Z';
    await call('/api/v2/account/trial',{startedAt:early});await call('/api/v2/account/trial',{startedAt:new Date().toISOString()});
    expect(await (await call('/api/v2/account/entitlements')).json()).toMatchObject({result:{trialStartedAt:'2026-01-01T00:00:00.000Z',trialActive:false}});
  });
  it('enforces device slots, owner isolation and release throttling atomically',async()=>{
    const config=await configure();config.releaseLimit=1;await env.DB.prepare('UPDATE billing_settings SET json=?').bind(JSON.stringify(config)).run();
    const pro=await buy('pro','CNY',crypto.randomUUID(),undefined,'duo');await webhook(pro.id,'order.completed',{listPrice:{total:'150.00'},chargedAmount:'150.00'});
    const activate=(n:number)=>call('/api/v2/account/devices/activate',{deviceID:'test-device-number-000'+n,name:'Mac '+n});
    const results=await Promise.all([activate(1),activate(2),activate(3)]);expect(results.map(r=>r.status).sort()).toEqual([200,200,409]);
    const devices=await env.DB.prepare('SELECT id FROM license_devices WHERE released_at IS NULL').all<{id:string}>();
    expect((await call('/api/v2/account/devices/'+devices.results[0].id+'/release',{},'other-user')).status).toBe(404);
    expect((await call('/api/v2/account/devices/'+devices.results[0].id+'/release',{})).status).toBe(200);
    expect((await call('/api/v2/account/devices/'+devices.results[1].id+'/release',{})).status).toBe(409);
  });
  it('refunds the original task charge once on failure or queue expiry',async()=>{
    await configure();const {taskID}=await createTask();await env.DB.prepare("UPDATE widget_tasks SET status='failed',completed_at=? WHERE id=?").bind(new Date().toISOString(),taskID).run();
    expect(await balance()).toBe(10000);await env.DB.prepare("UPDATE widget_tasks SET status='failed' WHERE id=?").bind(taskID).run();expect(await balance()).toBe(10000);
    const next=await createTask();await env.DB.prepare("UPDATE widget_tasks SET created_at='2020-01-01T00:00:00Z' WHERE id=?").bind(next.taskID).run();await expireTasks(billingEnv);expect(await balance()).toBe(10000);
    expect((await env.DB.prepare("SELECT COUNT(*) n FROM user_credit_ledger WHERE reason='task_refund'").first<any>()).n).toBe(2);
  });
  it('queued-only undo refuses claimed tasks, while explicit cancellation refunds them',async()=>{
    await configure();const {taskID}=await createTask();await claimTask();
    const undo=await api('/api/v2/tasks/'+taskID+'?queuedOnly=true',{method:'DELETE',token:USER_TOKEN});expect(undo.status).toBe(409);expect(await balance()).toBe(9999);
    expect((await api('/api/v2/tasks/'+taskID,{method:'DELETE',token:USER_TOKEN})).status).toBe(200);expect(await balance()).toBe(10000);
  });
  it('expires a task after three failed leases and refunds its original price',async()=>{
    await configure();
    await env.DB.prepare("UPDATE widget_versions SET manifest_json=json_set(manifest_json,'$.creditCost',7) WHERE id='version_test'").run();
    const {taskID}=await createTask();expect(await balance()).toBe(9993);
    for(let attempt=0;attempt<3;attempt++){
      const claimed=await claimTask();expect(claimed.taskId).toBe(taskID);
      await env.DB.prepare("UPDATE widget_tasks SET lease_expires_at='2000-01-01T00:00:00Z' WHERE id=?").bind(taskID).run();
    }
    await env.DB.prepare("UPDATE widget_versions SET manifest_json=json_set(manifest_json,'$.creditCost',99) WHERE id='version_test'").run();
    await expireTasks(billingEnv);expect(await balance()).toBe(10000);
    expect(await env.DB.prepare('SELECT status,attempts,credit_cost FROM widget_tasks WHERE id=?').bind(taskID).first()).toEqual({status:'expired',attempts:3,credit_cost:7});
    await expireTasks(billingEnv);expect(await balance()).toBe(10000);
  });
  it('persists first-paid-widget consent on the account',async()=>{
    expect(await (await call('/api/v2/account/entitlements')).json()).toMatchObject({result:{paidWidgetNoticeSeen:false}});
    expect((await call('/api/v2/account/widget-notice',{})).status).toBe(200);
    expect(await (await call('/api/v2/account/entitlements')).json()).toMatchObject({result:{paidWidgetNoticeSeen:true}});
  });
  it('allows free tasks while refund recovery makes the wallet negative',async()=>{
    await configure();await env.DB.prepare('UPDATE users SET credits=-100 WHERE id=1').run();await env.DB.prepare("UPDATE widget_versions SET manifest_json=json_set(manifest_json,'$.creditCost',0) WHERE id='version_test'").run();
    expect((await createTask()).response.status).toBe(202);expect(await balance()).toBe(-100);
  });
});


describe('regional money and environment isolation',()=>{
 it('uses integer yen and snapshots the payment environment',async()=>{
  await configure();
  const response=await call('/api/v2/orders',{product:'credits',packID:'small',currency:'JPY',expectedPrice:{amount:480,points:600}},USER_TOKEN,{'Idempotency-Key':crypto.randomUUID()});
  expect(response.status).toBe(200);const body=await response.json() as any;
  expect(checkoutCalls[0]).toMatchObject({currency:'JPY',priceSnapshot:{amount:'480'},includePaymentMethods:['card','applepay','googlepay']});
  expect(await env.DB.prepare('SELECT currency,amount,billing_mode FROM orders WHERE id=?').bind(body.result.orderID).first()).toEqual({currency:'JPY',amount:480,billing_mode:'test'});
  expect((await webhook(body.result.orderID,'order.completed',{currency:'JPY',listPrice:{total:'480'},chargedAmount:'480',refundedAmount:'480'})).status).toBe(200);
  expect(await balance()).toBe(10600);
  expect((await webhook(body.result.orderID,'refund.succeeded',{currency:'JPY',refundedAmount:'480'})).status).toBe(200);
  expect(await balance()).toBe(10000);
 });
 it('refuses callbacks from a different order environment',async()=>{
  await configure();const order=await buy();
  await env.DB.prepare("UPDATE orders SET billing_mode='prod' WHERE id=?").bind(order.id).run();
  expect((await webhook(order.id)).status).toBe(409);
  expect(await balance()).toBe(10000);
 });
});

it('selects only the matching environment private key and preserves legacy fallback',()=>{
 const keys={...billingEnv,WAFFO_PRIVATE_KEY_TEST:'test-key',WAFFO_PRIVATE_KEY_PROD:'production-key'};
 expect(paymentPrivateKey({...keys,WAFFO_ENVIRONMENT:'test'})).toBe('test-key');
 expect(paymentPrivateKey({...keys,WAFFO_ENVIRONMENT:'prod'})).toBe('production-key');
 expect(paymentPrivateKey(billingEnv)).toBe(privateKey);
});
