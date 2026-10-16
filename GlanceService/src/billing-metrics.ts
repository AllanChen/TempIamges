import type { Env } from './index';
import { authenticatedUser } from './users';
import { requestDevice } from './entitlements';
import { BillingError, billingBody, billingReply, isoNow, readPricing,sha256 } from './pricing';

const kinds = new Set(['trial_started','login_prompt','login_success','insufficient','pro_offer','locked_click','trial_activity']);
const features = new Set(['widget','compare','convert','compress','copy','export','edit','ocr','base64','pro','account']);
export async function recordBillingEvent(env:Env,request:Request) {
  const body=await billingBody(request),device=await requestDevice(request);
  const user=request.headers.has('Authorization')?await authenticatedUser(env,request):null;
  if (typeof body.id!=='string' || !/^[A-Za-z0-9:_-]{16,128}$/.test(body.id) || !kinds.has(String(body.kind)) ||
    (body.journeyID!=null && (typeof body.journeyID!=='string' || !/^[A-Za-z0-9_-]{16,128}$/.test(body.journeyID))) ||
    (body.feature!=null && !features.has(String(body.feature)))) throw new BillingError('invalid_event','Invalid analytics event.');
  if (['login_success','insufficient'].includes(String(body.kind)) && !user) throw new BillingError('sign_in_required','Sign in is required.',401);
  const now=isoNow(),window=Math.floor(Date.now()/60000);
  const limited=await env.DB.prepare(`INSERT INTO user_auth_limits(key,count,window_start) VALUES(?,1,?)
    ON CONFLICT(key) DO UPDATE SET count=CASE WHEN window_start=excluded.window_start THEN count+1 ELSE 1 END,
    window_start=excluded.window_start WHERE window_start!=excluded.window_start OR count<120 RETURNING count`)
    .bind('billing-events:'+device,window).first();
  if (!limited) throw new BillingError('rate_limited','Too many events.',429);
  const ipKey='billing-events-ip:'+await sha256(request.headers.get('CF-Connecting-IP')??'unknown');
  const ipLimited=await env.DB.prepare(`INSERT INTO user_auth_limits(key,count,window_start) VALUES(?,1,?)
    ON CONFLICT(key) DO UPDATE SET count=CASE WHEN window_start=excluded.window_start THEN count+1 ELSE 1 END,
    window_start=excluded.window_start WHERE window_start!=excluded.window_start OR count<1200 RETURNING count`).bind(ipKey,window).first();
  if (!ipLimited) throw new BillingError('rate_limited','Too many events.',429);
  const trialStart=typeof body.startedAt==='string'?Date.parse(body.startedAt):Date.now();
  if (!Number.isFinite(trialStart) || trialStart<1577836800000) throw new BillingError('invalid_trial','Invalid trial start.');
  const start=new Date(Math.min(trialStart,Date.now())).toISOString();
  // Server identity and device scope are part of the key. A caller cannot
  // overwrite another account's event by guessing its client-generated ID.
  const id=[user?.id??'anonymous',device,body.id].join(':');
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO billing_trials(device_hash,user_id,started_at,updated_at) VALUES(?,?,?,?)
      ON CONFLICT(device_hash) DO UPDATE SET user_id=COALESCE(billing_trials.user_id,excluded.user_id),
      started_at=min(billing_trials.started_at,excluded.started_at),updated_at=excluded.updated_at`).bind(device,user?.id??null,start,now),
    env.DB.prepare(`INSERT OR IGNORE INTO billing_events(id,kind,user_id,device_hash,journey_id,feature,created_at) VALUES(?,?,?,?,?,?,?)`)
      .bind(id,body.kind,user?.id??null,device,body.journeyID??null,body.feature??null,now)
  ]);
  return billingReply({recorded:true},202);
}
const ratio=(numerator:number,denominator:number)=>({numerator,denominator,rate:denominator?numerator/denominator:null});
export async function billingMetrics(env:Env,request:Request) {
  const days=Number(new URL(request.url).searchParams.get('days')??30);
  if (![7,30,90].includes(days)) throw new BillingError('invalid_range','Use 7, 30 or 90 days.');
  const until=isoNow(),requestedFrom=new Date(Date.now()-days*86400000).toISOString(),config=await readPricing(env);
  const since=(await env.DB.prepare('SELECT started_at FROM billing_metrics_meta WHERE id=1').first<{started_at:string}>())!.started_at;
  const from=requestedFrom>since?requestedFrom:since;
  const one=async(sql:string,args:unknown[]=[])=>env.DB.prepare(sql).bind(...args).first<Record<string,number>>();
  const all=async(sql:string,args:unknown[]=[]) => (await env.DB.prepare(sql).bind(...args).all()).results;
  const [login,gift,insufficient,taskResume,trial,payments,methods,taskRefunds,cancellations,refunds,locks]=await Promise.all([
    one(`SELECT COUNT(*) denominator,COALESCE(SUM(EXISTS(SELECT 1 FROM billing_events done WHERE done.kind='login_success'
      AND done.journey_id=p.journey_id AND done.device_hash=p.device_hash)),0) numerator FROM
      (SELECT DISTINCT journey_id,device_hash FROM billing_events WHERE kind='login_prompt' AND created_at>=? AND journey_id IS NOT NULL) p`,[from]),
    one(`SELECT COUNT(*) denominator,COALESCE(SUM(EXISTS(SELECT 1 FROM billing_events e WHERE e.kind='gift_depleted' AND e.user_id=g.user_id)),0) numerator
      FROM user_credit_ledger g WHERE g.reason IN ('signup','signup_bonus') AND g.amount>0 AND g.created_at>=?
      AND julianday(g.created_at)<=julianday(?)-7`,[from,until]),
    one(`SELECT COUNT(*) denominator,COALESCE(SUM(EXISTS(SELECT 1 FROM orders o WHERE o.user_id=e.user_id
      AND o.billing_intent_id=e.journey_id AND o.product='credits' AND o.paid_at IS NOT NULL
      AND COALESCE(o.payment_method,'')!='mock')),0) numerator FROM
      (SELECT DISTINCT user_id,journey_id FROM billing_events WHERE kind='insufficient' AND created_at>=? AND journey_id IS NOT NULL) e`,[from]),
    one(`SELECT COUNT(*) denominator,COALESCE(SUM(EXISTS(SELECT 1 FROM widget_tasks t WHERE t.topup_order_id=o.id
      AND t.billing_intent_id=o.billing_intent_id AND t.owner_id='user_'||o.user_id)),0) numerator
      FROM orders o WHERE o.product='credits' AND o.paid_at>=? AND o.billing_intent_id IS NOT NULL
      AND COALESCE(o.payment_method,'')!='mock'`,[from]),
    one(`WITH subjects AS (SELECT COALESCE('user:'||user_id,'device:'||device_hash) subject,user_id,MIN(started_at) started_at
      FROM billing_trials GROUP BY subject)
      SELECT COUNT(*) denominator,COALESCE(SUM(EXISTS(SELECT 1 FROM billing_events e LEFT JOIN billing_trials t ON t.device_hash=e.device_hash
        WHERE e.kind='trial_activity' AND e.feature IN ('compare','convert','widget') AND COALESCE('user:'||COALESCE(e.user_id,t.user_id),'device:'||e.device_hash)=s.subject
        AND julianday(e.created_at) BETWEEN julianday(s.started_at) AND julianday(s.started_at)+?)),0) active,
      COALESCE(SUM(julianday(s.started_at)+?+7<=julianday(?)),0) mature,
      COALESCE(SUM(julianday(s.started_at)+?+7<=julianday(?) AND EXISTS(SELECT 1 FROM orders o WHERE o.user_id=s.user_id
        AND o.product='pro' AND COALESCE(o.payment_method,'')!='mock'
        AND julianday(o.paid_at) BETWEEN julianday(s.started_at)+?-7 AND julianday(s.started_at)+?+7)),0) converted
      FROM subjects s WHERE s.started_at>=?`,[config.trialDays,config.trialDays,until,config.trialDays,until,config.trialDays,config.trialDays,from]),
    all(`SELECT currency,COUNT(*) created,COUNT(paid_at) paid FROM orders
      WHERE created_at>=? AND COALESCE(payment_method,'')!='mock' GROUP BY currency`,[from]),
    all(`SELECT currency,COALESCE(payment_method,'unreported') method,COUNT(*) orders,COUNT(paid_at) paid
      FROM orders WHERE created_at>=? AND COALESCE(payment_method,'')!='mock' GROUP BY currency,method`,[from]),
    all(`SELECT t.widget_id,w.name,COUNT(*) tasks,COALESCE(SUM(EXISTS(SELECT 1 FROM user_credit_ledger l WHERE l.id='refund:'||t.id)),0) refunded
      FROM widget_tasks t LEFT JOIN widgets w ON w.id=t.widget_id WHERE t.type='production' AND t.credit_cost>0 AND t.created_at>=? GROUP BY t.widget_id`,[from]),
    one(`SELECT COUNT(*) denominator,COALESCE(SUM(status='cancelled'),0) numerator FROM widget_tasks WHERE type='production' AND created_at>=?`,[from]),
    all(`SELECT product,COUNT(paid_at) paid,SUM(status='refunded') refunded FROM orders
      WHERE paid_at>=? AND COALESCE(payment_method,'')!='mock' GROUP BY product`,[from]),
    all(`SELECT feature,COUNT(*) clicks FROM billing_events WHERE kind='locked_click' AND created_at>=? GROUP BY feature ORDER BY clicks DESC`,[from])
  ]);
  return billingReply({from,until,days,instrumentedSince:since,login:ratio(login!.numerator,login!.denominator),giftDepletion:ratio(gift!.numerator,gift!.denominator),
    insufficientTopup:ratio(insufficient!.numerator,insufficient!.denominator),topupTaskSubmission:ratio(taskResume!.numerator,taskResume!.denominator),
    trialActivity:ratio(trial!.active,trial!.denominator),trialConversion:ratio(trial!.converted,trial!.mature),payments,paymentMethods:methods,
    taskRefunds,cancellations:ratio(cancellations!.numerator,cancellations!.denominator),refunds,lockedClicks:locks,
    notes:['Client events are best effort; payment, task and refund counts use server records.',
      'Gift depletion uses cohorts at least 7 days old; trial conversion uses cohorts 7 days past trial end.',
      'Pancake reports the actual payment method on success only. Unpaid USD orders remain unreported; a method-specific failure rate cannot be inferred.']});
}
