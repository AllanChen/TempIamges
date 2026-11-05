import type { Env } from './index';
import { BillingError, billingBody, billingReply, isoNow, sha256 } from './pricing';

const pages = new Set(['home','pricing','widgets','ai-models','install','terms','privacy','refunds','acceptable-use','other']);
const targets = new Set(['download','pricing','install','widgets','ai-models','home','language','currency','download_section','features']);
const placements = new Set(['header','footer','home','install','content']);
const identifier = (value:unknown): value is string => typeof value==='string' && /^[A-Za-z0-9_-]{16,128}$/.test(value);
// Campaign values are short normalized slugs; anything else (emails, URLs, free text) is dropped, not stored.
const campaign = (value:unknown) => typeof value==='string' && /^[a-z0-9._-]{1,64}$/.test(value) ? value : null;

export async function recordWebsiteEvent(env:Env, request:Request) {
  if (!['https://glancepreview.com','https://www.glancepreview.com'].includes(request.headers.get('Origin')||''))
    throw new BillingError('invalid_origin','Website origin required.',403);
  if (request.headers.get('DNT')==='1' || request.headers.get('Sec-GPC')==='1') return billingReply({recorded:false},202);
  const body=await billingBody(request);
  if (!identifier(body.id) || !identifier(body.sessionID) || !['page_view','cta_click'].includes(String(body.kind)) ||
      !pages.has(String(body.page)) || !['zh','en','ja','de'].includes(String(body.language)) ||
      (body.kind==='cta_click' && (!targets.has(String(body.target)) || !placements.has(String(body.placement)))))
    throw new BillingError('invalid_event','Invalid website event.');
  const window=Math.floor(Date.now()/60000);
  // Short-lived abuse counter only. No IP, URL, query, referrer, text or email in events.
  const key='website-events:'+await sha256(window+':'+(request.headers.get('CF-Connecting-IP')||'unknown'));
  const allowed=await env.DB.prepare(`INSERT INTO user_auth_limits(key,count,window_start) VALUES(?,1,?)
    ON CONFLICT(key) DO UPDATE SET count=count+1 WHERE count<300 RETURNING count`).bind(key,window).first();
  if (!allowed) throw new BillingError('rate_limited','Too many events.',429);
  await env.DB.prepare(`INSERT OR IGNORE INTO website_events(session_id,id,kind,page,language,target,placement,
    utm_source,utm_medium,utm_campaign,utm_content,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`).bind(body.sessionID,body.id,body.kind,body.page,body.language,
      body.kind==='cta_click'?body.target:null,body.kind==='cta_click'?body.placement:null,
      campaign(body.utmSource),campaign(body.utmMedium),campaign(body.utmCampaign),campaign(body.utmContent),isoNow()).run();
  return billingReply({recorded:true},202);
}

export async function pruneWebsiteEvents(env:Env) {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM website_events WHERE created_at<?').bind(new Date(Date.now()-90*86400000).toISOString()),
    env.DB.prepare("DELETE FROM user_auth_limits WHERE key LIKE 'website-events:%' AND window_start<?").bind(Math.floor(Date.now()/60000)-60)
  ]);
}

export async function launchMetrics(env:Env, from:string, until:string) {
  const all=async(sql:string,args:unknown[]=[])=>(await env.DB.prepare(sql).bind(from,until,...args).all()).results;
  const [website,clicks,events,proFunnel,grants,redemptions,channels]=await Promise.all([
    all(`WITH visits AS (SELECT session_id,MIN(created_at) started FROM website_events
      WHERE kind='page_view' AND created_at BETWEEN ? AND ? GROUP BY session_id)
      SELECT COUNT(*) sessions,COALESCE(SUM(EXISTS(SELECT 1 FROM website_events e WHERE e.session_id=v.session_id
        AND e.kind='cta_click' AND e.target='download' AND e.created_at>=v.started)),0) downloaded FROM visits v`),
    all(`SELECT page,language,target,placement,COUNT(*) clicks,COUNT(DISTINCT session_id) sessions
      FROM website_events WHERE kind='cta_click' AND created_at BETWEEN ? AND ?
      GROUP BY page,language,target,placement ORDER BY clicks DESC`),
    all(`SELECT kind,feature,billing_mode,COUNT(*) events,COUNT(DISTINCT device_hash) devices
      FROM billing_events WHERE created_at BETWEEN ? AND ? GROUP BY kind,feature,billing_mode ORDER BY events DESC`),
    all(`WITH offers AS (SELECT device_hash,journey_id,MIN(created_at) started FROM billing_events
      WHERE kind='pro_offer' AND billing_mode='prod' AND journey_id IS NOT NULL AND created_at BETWEEN ? AND ? GROUP BY device_hash,journey_id),
      clicks AS (SELECT o.*, (SELECT MIN(e.created_at) FROM billing_events e WHERE e.kind='checkout_click' AND e.billing_mode='prod'
        AND e.feature='pro' AND e.device_hash=o.device_hash AND e.journey_id=o.journey_id
        AND e.created_at>=o.started) clicked FROM offers o),
      conversions AS (SELECT c.*, (SELECT MIN(o.created_at) FROM orders o WHERE o.product='pro'
        AND o.billing_mode='prod' AND COALESCE(o.payment_method,'')!='mock' AND o.billing_intent_id=c.journey_id
        AND o.created_at>=c.clicked AND EXISTS(SELECT 1 FROM billing_events e WHERE e.kind='checkout_click' AND e.billing_mode='prod'
          AND e.feature='pro' AND e.user_id=o.user_id AND e.device_hash=c.device_hash AND e.journey_id=c.journey_id
          AND e.created_at BETWEEN c.started AND o.created_at)) ordered,
        (SELECT MIN(o.paid_at) FROM orders o WHERE o.product='pro' AND o.billing_mode='prod'
          AND COALESCE(o.payment_method,'')!='mock' AND o.billing_intent_id=c.journey_id
          AND o.created_at>=c.clicked AND o.paid_at>=o.created_at AND EXISTS(SELECT 1 FROM billing_events e
            WHERE e.kind='checkout_click' AND e.billing_mode='prod' AND e.feature='pro' AND e.user_id=o.user_id
              AND e.device_hash=c.device_hash AND e.journey_id=c.journey_id AND e.created_at BETWEEN c.started AND o.created_at)) paid
        FROM clicks c)
      SELECT COUNT(*) offered,COUNT(clicked) clicked,COUNT(ordered) ordered,COUNT(paid) paid FROM conversions`),
    all(`SELECT COUNT(*) issued,COUNT(DISTINCT g.user_id) users,
      COALESCE(SUM(EXISTS(SELECT 1 FROM licenses l WHERE l.source_admin_grant=g.id AND l.status='active')),0) active,
      COALESCE(SUM(EXISTS(SELECT 1 FROM licenses l JOIN license_devices d ON d.user_id=l.user_id
        WHERE l.source_admin_grant=g.id AND l.status='active' AND d.released_at IS NULL AND d.activated_at>=g.created_at)),0) activated
      FROM admin_pro_grants g WHERE g.created_at BETWEEN ? AND ?`),
    all(`WITH codes_in_range AS (SELECT * FROM pro_redemption_codes WHERE created_at BETWEEN ? AND ?)
      SELECT c.kind,COUNT(*) issued,COUNT(c.redeemed_at) redeemed,
      COALESCE(SUM(EXISTS(SELECT 1 FROM licenses l WHERE l.source_redemption_code=c.id AND l.status='active'
        AND (l.access_expires_at IS NULL OR l.access_expires_at>?))),0) active,
      COALESCE(SUM(EXISTS(SELECT 1 FROM licenses l JOIN license_devices d ON d.user_id=l.user_id
        WHERE l.source_redemption_code=c.id AND l.status='active' AND d.released_at IS NULL AND d.activated_at>=c.redeemed_at
          AND (l.access_expires_at IS NULL OR l.access_expires_at>?))),0) activated,
      COALESCE(SUM(c.redeemed_at IS NOT NULL AND c.access_expires_at IS NOT NULL AND c.access_expires_at<=?),0) expired
      FROM codes_in_range c GROUP BY c.kind`,[until,until,until]),
    // A session belongs to the first tagged page view at or after its first visit in range; untagged sessions are '(none)'.
    all(`WITH visits AS (SELECT session_id,MIN(created_at) started FROM website_events
      WHERE kind='page_view' AND created_at BETWEEN ? AND ? GROUP BY session_id),
      tagged AS (SELECT v.*,(SELECT e.id FROM website_events e WHERE e.session_id=v.session_id AND e.kind='page_view'
        AND e.utm_source IS NOT NULL AND e.created_at>=v.started ORDER BY e.created_at,e.id LIMIT 1) touch FROM visits v)
      SELECT COALESCE(t.utm_source,'(none)') source,t.utm_medium medium,t.utm_campaign campaign,t.utm_content content,
        COUNT(*) sessions,COALESCE(SUM(EXISTS(SELECT 1 FROM website_events e WHERE e.session_id=v.session_id
          AND e.kind='cta_click' AND e.target='download' AND e.created_at>=v.started)),0) downloaded
      FROM tagged v LEFT JOIN website_events t ON t.session_id=v.session_id AND t.id=v.touch
      GROUP BY source,medium,campaign,content ORDER BY sessions DESC`)
  ]);
  return {website:website[0],clicks,events,proFunnel:proFunnel[0],grants:grants[0],redemptions,channels};
}
