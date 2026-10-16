import { WaffoPancake, type PriceSnapshot, type TaxCategory, type WebhookEventData } from '@waffo/pancake-ts';
import type { Env } from './index';
import { authenticatedUser, type User } from './users';
import { BillingError, billingBody, billingReply, isoNow, mockCheckoutUser, paymentReady, readPricing, sha256, type Currency } from './pricing';

type Order = {
  id:string; user_id:number; product:'pro'|'renewal'|'credits'; pack_id:string|null; currency:Currency;
  amount:number; credits:number; bonus_credits:number; product_id:string; tax_category:string; tax_included:number;
  updates_months:number; status:string; request_key:string; request_hash:string; checkout_url:string|null;
  checkout_session_id:string|null; checkout_expires_at:string; provider_order_id:string|null; provider_payment_id:string|null;
  paid_amount:number|null; refunded_amount:number; previous_updates_until:string|null;
  created_at:string; paid_at:string|null; refunded_at:string|null; refund_reason:string|null; refund_status:string|null;
  language:string;billing_intent_id:string|null;payment_method:string|null;
};
export function displayAmount(cents:number) { return (cents/100).toFixed(2); }
function amountCents(value:unknown) {
  if (typeof value!=='string' || !/^\d+(\.\d{1,2})?$/.test(value)) return NaN;
  const [whole,decimal=''] = value.split('.');
  const n=Number(whole)*100+Number(decimal.padEnd(2,'0')); return Number.isSafeInteger(n)?n:NaN;
}
function pancake(env:Env) {
  if (!env.WAFFO_MERCHANT_ID || !env.WAFFO_PRIVATE_KEY || !['test','prod'].includes(env.WAFFO_ENVIRONMENT||'')) throw new BillingError('payments_unavailable','Payments are not configured yet.',503);
  return new WaffoPancake({ merchantId:env.WAFFO_MERCHANT_ID,privateKey:env.WAFFO_PRIVATE_KEY,
    environment:env.WAFFO_ENVIRONMENT as 'test'|'prod',
    webhookPublicKey:{ test:env.WAFFO_WEBHOOK_PUBLIC_KEY_TEST,prod:env.WAFFO_WEBHOOK_PUBLIC_KEY_PROD } });
}
// Hosted URLs include a buyer token; encrypt at rest, never log or expose them
// in admin order listings. Only the owning signed-in user can retrieve one.
async function checkoutCipher(env:Env,value:string,decrypt=false) {
  const key = await crypto.subtle.importKey('raw',await crypto.subtle.digest('SHA-256',new TextEncoder().encode(env.SESSION_SECRET)),'AES-GCM',false,['encrypt','decrypt']);
  if (decrypt) {
    const bytes=Uint8Array.from(atob(value),c=>c.charCodeAt(0));
    return new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes.slice(0,12)},key,bytes.slice(12)));
  }
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const encrypted = new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(value)));
  return btoa(String.fromCharCode(...iv,...encrypted));
}
function orderPublic(order:Order) {
  return { id:order.id,product:order.product,packID:order.pack_id,currency:order.currency,
    amount:order.payment_method==='mock'?0:order.amount,mock:order.payment_method==='mock',credits:order.credits,
    bonusCredits:order.bonus_credits,status:order.status,createdAt:order.created_at,paidAt:order.paid_at,refundedAt:order.refunded_at,
    expiresAt:order.checkout_expires_at,refundStatus:order.refund_status,refundReason:order.refund_reason,intentID:order.billing_intent_id };
}
async function readOrder(env:Env,id:string,userID?:number) {
  return env.DB.prepare(`SELECT * FROM orders WHERE id=?${userID===undefined?'':' AND user_id=?'}`)
    .bind(id,...(userID===undefined?[]:[userID])).first<Order>();
}
async function expireOrders(env:Env) { await env.DB.prepare("UPDATE orders SET status='expired' WHERE status IN ('pending','abandoned') AND checkout_expires_at<?").bind(isoNow()).run(); }
async function checkoutResponse(env:Env,order:Order,user:User) {
  if (order.payment_method==='mock') {
    if (order.status!=='pending') return billingReply({order:orderPublic(order),orderID:order.id,checkoutUrl:null});
    if (!mockCheckoutUser(env,user.id)) throw new BillingError('mock_unavailable','Mock checkout is no longer available.',503);
    const paidAt=isoNow();
    const completed=await env.DB.prepare(`UPDATE orders SET status='paid',paid_at=?,paid_amount=0,
      provider_order_id=?,provider_payment_id=? WHERE id=? AND user_id=? AND status='pending'`)
      .bind(paidAt,'mock_'+order.id,'mock_'+order.id,order.id,user.id).run();
    if (!completed.meta.changes) return billingReply({order:orderPublic((await readOrder(env,order.id,user.id))!),orderID:order.id,checkoutUrl:null});
    const fulfilled=(await readOrder(env,order.id,user.id))!;
    return billingReply({order:orderPublic(fulfilled),orderID:order.id,
      checkoutUrl:`https://api.glance.mcreator.ai/pay/mock/?order=${encodeURIComponent(order.id)}`});
  }
  if (order.status!=='pending') return billingReply({order:orderPublic(order),orderID:order.id,checkoutUrl:null});
  let url:string;
  if (order.checkout_url) url=await checkoutCipher(env,order.checkout_url,true);
  else {
    try {
      const session = await pancake(env).checkout.authenticated.create({ productId:order.product_id,currency:order.currency,
        buyerIdentity:String(user.id),buyerEmail:user.email,orderMerchantExternalId:order.id,
        priceSnapshot:{amount:displayAmount(order.amount),taxCategory:order.tax_category as TaxCategory,taxIncluded:!!order.tax_included} as PriceSnapshot & {taxIncluded:boolean},
        includePaymentMethods:order.currency==='CNY'?['wechat']:['card','applepay','googlepay','wechat'],
        expiresInSeconds:1800,darkMode:true,language:order.language==='zh-Hans'?'zh-Hans':'en',
        successUrl:`https://glance.mcreator.ai/pay/return?order=${encodeURIComponent(order.id)}`,
        metadata:{product:order.product} },{idempotencyKey:order.id});
      const checkout = new URL(session.checkoutUrl);
      if (checkout.protocol!=='https:') throw new Error('Invalid checkout URL');
      url=session.checkoutUrl;
      await env.DB.prepare("UPDATE orders SET checkout_url=?,checkout_session_id=?,checkout_expires_at=? WHERE id=? AND status='pending'")
        .bind(await checkoutCipher(env,url),session.sessionId,session.expiresAt,order.id).run();
      order.checkout_expires_at=session.expiresAt;
    } catch { throw new BillingError('checkout_unavailable','Could not open checkout. Retry this order.',502,{orderID:order.id}); }
  }
  return billingReply({order:orderPublic(order),orderID:order.id,checkoutUrl:url,expiresAt:order.checkout_expires_at});
}
export async function createOrder(env:Env,request:Request) {
  const user=await authenticatedUser(env,request), body=await billingBody(request);
  const mock=body.product==='credits' && mockCheckoutUser(env,user.id);
  const key=request.headers.get('Idempotency-Key')||'';
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key) || !['pro','renewal','credits'].includes(String(body.product)) || !['CNY','USD'].includes(String(body.currency))) throw new BillingError('invalid_order','Product, currency and Idempotency-Key are required.');
  if (body.product==='credits' && typeof body.packID!=='string') throw new BillingError('invalid_pack','Select a credit package.');
  if(body.intentID!=null && (typeof body.intentID!=='string' || !/^[A-Za-z0-9_-]{16,128}$/.test(body.intentID))) throw new BillingError('invalid_order','Invalid purchase context.');
  const hash=await sha256(JSON.stringify([body.product,body.packID??null,body.currency,body.expectedPrice,body.intentID??null]));
  const previous=await env.DB.prepare('SELECT * FROM orders WHERE user_id=? AND request_key=?').bind(user.id,key).first<Order>();
  if (previous) {
    if (previous.request_hash!==hash) throw new BillingError('idempotency_conflict','This request key belongs to a different order.',409);
    await expireOrders(env); return checkoutResponse(env,(await readOrder(env,previous.id,user.id))!,user);
  }
  const config=await readPricing(env);
  if (!mock && (!config.enabled || !paymentReady(env))) throw new BillingError('payments_unavailable','Payments are not available yet.',503);
  const currency=body.currency as Currency;
  const license=await env.DB.prepare('SELECT * FROM licenses WHERE user_id=?').bind(user.id).first<{status:string;updates_until:string}>();
  if (body.product==='pro' && license?.status==='active') throw new BillingError('already_pro','Pro is already active.',409);
  if (body.product==='renewal' && license?.status!=='active') throw new BillingError('pro_required','An active Pro license is required.',409);
  const launch=!!config.pro.launchUntil && Date.parse(config.pro.launchUntil)>Date.now() && config.pro[currency==='CNY'?'launchCNY':'launchUSD'].amount!==null;
  const product=body.product==='credits'?config.packs.find(p=>p.id===body.packID && p.enabled):body.product==='pro'?config.pro:config.renewal;
  if (!product) throw new BillingError('pack_unavailable','This package is no longer available.',409);
  const price=body.product==='pro' && launch?config.pro[currency==='CNY'?'launchCNY':'launchUSD']:product[currency];
  if (!price.amount || (!mock && !product.productID)) throw new BillingError('product_unavailable','This product is not available in this currency.',503);
  const expected=body.expectedPrice as {amount?:number;points?:number}|undefined;
  if (!expected || expected.amount!==price.amount || (body.product==='credits' && expected.points!==price.points)) throw new BillingError('price_changed','The price changed. Confirm the current price.',409,{amount:price.amount,points:price.points,currency});
  await expireOrders(env);
  const pending=await env.DB.prepare("SELECT * FROM orders WHERE user_id=? AND product=? AND COALESCE(pack_id,'')=? AND status='pending'")
    .bind(user.id,body.product,body.product==='credits'?body.packID:'').first<Order>();
  const compatible=(order:Order)=>order.currency===currency && order.amount===price.amount && order.credits===(body.product==='credits'?price.points:0);
  if (pending) {
    if (!compatible(pending)) throw new BillingError('pending_order','Continue the existing pending order before changing its currency or price.',409,orderPublic(pending));
    return checkoutResponse(env,pending,user);
  }
  const bonusAlreadyGranted=body.product==='pro' && !!await env.DB.prepare('SELECT id FROM user_credit_ledger WHERE id=?').bind('pro-bonus:'+user.id).first();
  const id='order_'+crypto.randomUUID(), created=isoNow();
  try {
    await env.DB.prepare(`INSERT INTO orders(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,updates_months,
      request_key,request_hash,checkout_expires_at,previous_updates_until,created_at,language,billing_intent_id,payment_method) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
      .bind(id,user.id,body.product,body.product==='credits'?body.packID:null,currency,price.amount,body.product==='credits'?price.points:0,
        body.product==='pro' && !bonusAlreadyGranted?config.proBonusCredits:0,mock?'mock_credits':product.productID,config.taxCategory,config.taxIncluded?1:0,
        body.product==='renewal'?config.renewalMonths:config.updatesMonths,key,hash,new Date(Date.now()+1800000).toISOString(),license?.updates_until??null,created,body.language==='zh-Hans'?'zh-Hans':'en',body.intentID??null,mock?'mock':currency==='CNY'?'wechat':null).run();
  } catch(error) {
    if (!String(error).includes('UNIQUE')) throw error;
    const winner=await env.DB.prepare("SELECT * FROM orders WHERE user_id=? AND product=? AND COALESCE(pack_id,'')=? AND status='pending'")
      .bind(user.id,body.product,body.product==='credits'?body.packID:'').first<Order>();
    if (!winner || !compatible(winner)) throw new BillingError('pending_order','A pending order already exists.',409);
    return checkoutResponse(env,winner,user);
  }
  return checkoutResponse(env,(await readOrder(env,id))!,user);
}
export async function orders(env:Env,request:Request,id?:string) {
  const user=await authenticatedUser(env,request); await expireOrders(env);
  if (id) {
    const order=await readOrder(env,id,user.id); if (!order) throw new BillingError('order_not_found','Order not found.',404);
    return billingReply({order:orderPublic(order),balance:(await env.DB.prepare('SELECT credits FROM users WHERE id=?').bind(user.id).first<{credits:number}>())!.credits});
  }
  const result=await env.DB.prepare('SELECT * FROM orders WHERE user_id=? ORDER BY created_at DESC LIMIT 100').bind(user.id).all<Order>();
  return billingReply({orders:result.results.map(orderPublic)});
}
export async function resumeOrder(env:Env,request:Request,id:string) {
  const user=await authenticatedUser(env,request);await expireOrders(env);
  const order=await readOrder(env,id,user.id);
  if (!order) throw new BillingError('order_not_found','Order not found.',404);
  return checkoutResponse(env,order,user);
}
export async function billingWebhook(env:Env,request:Request) {
  if (!env.WAFFO_STORE_ID || !env.WAFFO_ENVIRONMENT) throw new BillingError('webhook_unavailable','Webhook is not configured.',503);
  const key=env.WAFFO_ENVIRONMENT==='test'?env.WAFFO_WEBHOOK_PUBLIC_KEY_TEST:env.WAFFO_WEBHOOK_PUBLIC_KEY_PROD;
  if (!key) throw new BillingError('webhook_unavailable','Webhook verification key is not configured.',503);
  if (Number(request.headers.get('Content-Length')||0)>128000) throw new BillingError('payload_too_large','Webhook too large.',413);
  const raw=await request.text(); if (raw.length>128000) throw new BillingError('payload_too_large','Webhook too large.',413);
  let event;
  try { event=pancake(env).webhooks.verify<WebhookEventData>(raw,request.headers.get('X-Waffo-Signature'),{publicKey:key}); }
  catch { throw new BillingError('invalid_signature','Invalid webhook signature.',401); }
  if (event.mode!==env.WAFFO_ENVIRONMENT || event.storeId!==env.WAFFO_STORE_ID) throw new BillingError('wrong_store','Wrong payment environment or store.',400);
  if (!['order.completed','refund.succeeded','refund.failed'].includes(event.eventType)) return billingReply({received:true});
  const order=await readOrder(env,event.data.orderMerchantExternalId||'');
  if (order?.payment_method==='mock') throw new BillingError('order_mismatch','Mock orders cannot receive provider webhooks.',409);
  if (!order || order.currency!==event.data.currency || (order.provider_order_id && order.provider_order_id!==event.data.orderId) ||
    event.data.merchantProvidedBuyerIdentity!==String(order.user_id)) throw new BillingError('order_mismatch','Webhook does not match its order.',409);
  if (await env.DB.prepare('SELECT id FROM billing_webhook_events WHERE id=? OR (event_type=? AND business_id=?)').bind(event.id,event.eventType,event.eventId).first()) return billingReply({received:true,duplicate:true});
  const now=isoNow(); let statement:D1PreparedStatement;
  if (event.eventType==='order.completed') {
    if (amountCents(event.data.listPrice?.total)!==order.amount) throw new BillingError('amount_mismatch','Payment price does not match the order snapshot.',409);
    const paid=amountCents(event.data.chargedAmount||event.data.amount);
    if (!Number.isSafeInteger(paid) || paid<order.amount) throw new BillingError('amount_mismatch','Payment amount is invalid.',409);
    statement=env.DB.prepare(`UPDATE orders SET status='paid',provider_order_id=?,provider_payment_id=?,paid_amount=?,paid_at=?,payment_method=?
      WHERE id=? AND status IN ('pending','expired','abandoned') AND NOT EXISTS(SELECT 1 FROM billing_webhook_events WHERE id=? OR (event_type=? AND business_id=?))`)
      .bind(event.data.orderId,event.eventId,paid,now,['card','applepay','googlepay','wechat'].includes(event.data.paymentMethod??'')?event.data.paymentMethod:order.payment_method,order.id,event.id,event.eventType,event.eventId);
  } else {
    if (!order.paid_at || order.paid_amount===null) throw new BillingError('payment_pending','Payment must complete before processing its refund.',409);
    if (event.eventType==='refund.failed') {
      statement=env.DB.prepare(`UPDATE orders SET status='refund_failed',refund_status='failed' WHERE id=? AND status='paid'
        AND NOT EXISTS(SELECT 1 FROM billing_webhook_events WHERE id=? OR (event_type=? AND business_id=?))`).bind(order.id,event.id,event.eventType,event.eventId);
    } else {
      const refunded=amountCents(event.data.refundedAmount||event.data.amount);
      if (!Number.isSafeInteger(refunded) || refunded<=0 || order.refunded_amount+refunded>order.paid_amount) throw new BillingError('invalid_refund','Refund amount does not match the payment.',409);
      statement=env.DB.prepare(`UPDATE orders SET refunded_amount=refunded_amount+?,
        status=CASE WHEN refunded_amount+?>=paid_amount THEN 'refunded' ELSE status END,
        refund_status=CASE WHEN refunded_amount+?>=paid_amount THEN 'succeeded' ELSE 'partial' END,refunded_at=?
        WHERE id=? AND status IN ('paid','refund_failed') AND NOT EXISTS(SELECT 1 FROM billing_webhook_events WHERE id=? OR (event_type=? AND business_id=?))`)
        .bind(refunded,refunded,refunded,now,order.id,event.id,event.eventType,event.eventId);
    }
  }
  await env.DB.batch([statement,env.DB.prepare('INSERT OR IGNORE INTO billing_webhook_events(id,event_type,business_id,order_id,created_at) VALUES(?,?,?,?,?)')
    .bind(event.id,event.eventType,event.eventId,order.id,now)]);
  if (event.eventType==='refund.failed') await env.DB.prepare("UPDATE refund_requests SET status='failed',updated_at=? WHERE order_id=? AND status='processing'").bind(now,order.id).run();
  return billingReply({received:true});
}
export async function wallet(env:Env,request:Request) {
  const user=await authenticatedUser(env,request);
  const transactions=await env.DB.prepare(`SELECT l.id,l.amount,l.reason,l.note,l.created_at,l.order_id,
    COALESCE(l.task_id,CASE WHEN l.id LIKE 'refund:%' THEN substr(l.id,8) END) task_id,
    w.name widget_name,o.product,o.currency,o.amount order_amount
    FROM user_credit_ledger l LEFT JOIN widget_tasks t ON t.id=COALESCE(l.task_id,CASE WHEN l.id LIKE 'refund:%' THEN substr(l.id,8) END)
    LEFT JOIN widgets w ON w.id=t.widget_id LEFT JOIN orders o ON o.id=l.order_id
    WHERE l.user_id=? ORDER BY l.created_at DESC,l.rowid DESC LIMIT 100`).bind(user.id).all();
  return billingReply({balance:user.credits,transactions:transactions.results});
}
export async function requestRefund(env:Env,request:Request,id:string,admin=false) {
  const user=admin?null:await authenticatedUser(env,request), body=await billingBody(request);
  const order=await readOrder(env,id,user?.id);
  if (!order) throw new BillingError('order_not_found','Order not found.',404);
  if (order.payment_method==='mock') throw new BillingError('mock_order','No payment was collected for this mock order.',409);
  if (!['paid','refund_failed'].includes(order.status)) throw new BillingError('not_refundable','This order cannot be refunded.',409);
  if (typeof body.reason!=='string' || !body.reason.trim() || body.reason.length>1000) throw new BillingError('invalid_reason','Enter a refund reason.');
  const balance=await env.DB.prepare('SELECT credits FROM users WHERE id=?').bind(order.user_id).first<{credits:number}>();
  const withinWindow=!!order.paid_at && Date.now()-Date.parse(order.paid_at)<=14*86400000;
  if (!admin && (!withinWindow || (order.product==='credits' && (balance?.credits??0)<order.credits))) throw new BillingError('refund_ineligible','Refunds require payment within 14 days and an unused credit package.',409);
  let refund=await env.DB.prepare("SELECT * FROM refund_requests WHERE order_id=? AND status IN ('requested','processing')").bind(id)
    .first<{id:string;status:string}>();
  if (!refund) {
    const refID='refund_'+crypto.randomUUID();
    await env.DB.prepare('INSERT OR IGNORE INTO refund_requests(id,order_id,user_id,reason,created_at,updated_at) VALUES(?,?,?,?,?,?)')
      .bind(refID,id,order.user_id,body.reason.trim(),isoNow(),isoNow()).run();
    refund=(await env.DB.prepare("SELECT id,status FROM refund_requests WHERE order_id=? AND status IN ('requested','processing')").bind(id).first<{id:string;status:string}>())!;
  }
  if (refund.status==='requested') await env.DB.prepare("UPDATE orders SET refund_status='requested' WHERE id=? AND status IN ('paid','refund_failed')").bind(id).run();
  if (!admin || refund.status==='processing') return billingReply({refund});
  if (!order.provider_payment_id || !order.paid_amount) throw new BillingError('payment_not_found','Payment reference is missing.',409);
  const claimed=await env.DB.prepare("UPDATE refund_requests SET status='processing',updated_at=? WHERE id=? AND status='requested' RETURNING id").bind(isoNow(),refund.id).first();
  if (!claimed) return billingReply({refund});
  try {
    const client=pancake(env);
    const session=await client.auth.issueSessionToken({storeId:env.WAFFO_STORE_ID!,buyerIdentity:String(order.user_id)});
    const result=await client.customer(session.token).createRefundTicket({paymentId:order.provider_payment_id,reason:body.reason.trim(),
      requestedAmount:{amount:displayAmount(order.paid_amount-order.refunded_amount),currency:order.currency},refundTicketMerchantExternalId:refund.id},
      {idempotencyKey:refund.id});
    await env.DB.prepare("UPDATE orders SET refund_status='processing',refund_reason=?,refund_ticket_id=? WHERE id=? AND status IN ('paid','refund_failed')")
      .bind(body.reason.trim(),result.ticket.id,id).run();
    return billingReply({refund:{id:refund.id,status:'processing'}});
  } catch {
    await env.DB.prepare("UPDATE refund_requests SET status='requested',updated_at=? WHERE id=? AND status='processing'").bind(isoNow(),refund.id).run();
    throw new BillingError('refund_unavailable','Refund request could not be sent. The entitlement is unchanged.',502);
  }
}
export async function adminOrders(env:Env) {
  const rows=await env.DB.prepare(`SELECT o.id,o.user_id,u.email,o.product,o.pack_id,o.currency,o.amount,o.credits,o.status,o.refund_status,o.created_at,o.paid_at,
    (SELECT reason FROM refund_requests WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1) refund_reason,
    (SELECT status FROM refund_requests WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1) refund_request_status
    FROM orders o JOIN users u ON u.id=o.user_id ORDER BY o.created_at DESC LIMIT 200`).all();
  return billingReply({orders:rows.results});
}

export async function denyRefund(env:Env,request:Request,id:string) {
  const body=await billingBody(request);
  if (typeof body.reason!=='string' || !body.reason.trim() || body.reason.length>1000) throw new BillingError('invalid_reason','Enter a refund reason.');
  const result=await env.DB.batch([
    env.DB.prepare("UPDATE refund_requests SET status='rejected',reason=?,updated_at=? WHERE order_id=? AND status='requested'").bind(body.reason.trim(),isoNow(),id),
    env.DB.prepare("UPDATE orders SET refund_status='rejected',refund_reason=? WHERE id=? AND status IN ('paid','refund_failed') AND EXISTS(SELECT 1 FROM refund_requests WHERE order_id=? AND status='rejected') AND NOT EXISTS(SELECT 1 FROM refund_requests WHERE order_id=? AND status IN ('requested','processing'))").bind(body.reason.trim(),id,id,id)
  ]);
  if (!result[0].meta.changes) throw new BillingError('refund_not_pending','There is no pending refund request to reject.',409);
  return billingReply({rejected:true});
}

// Abandoning is local bookkeeping, not a cancellation at the payment provider.
// The old hosted session can still complete; its verified webhook still delivers.
export async function abandonOrder(env:Env,request:Request,id:string) {
  const user=await authenticatedUser(env,request),order=await readOrder(env,id,user.id);
  if(!order) throw new BillingError('order_not_found','Order not found.',404);
  await env.DB.prepare("UPDATE orders SET status='abandoned' WHERE id=? AND user_id=? AND status='pending'").bind(id,user.id).run();
  return billingReply({abandoned:true});
}
