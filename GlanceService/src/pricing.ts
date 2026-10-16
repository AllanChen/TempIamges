import type { Env } from './index';
import { authenticatedUser } from './users';

export type Currency = 'CNY' | 'USD';
export type Price = { amount: number | null; points?: number };
export type Pricing = {
  enabled: boolean; trialDays: number; signupCredits: number; proBonusCredits: number;
  deviceLimit: number; offlineDays: number; releaseLimit: number; confirmationThreshold: number;
  queueMinutes: number; maxAttempts: number; updatesMonths: number; renewalMonths: number;
  pro: { CNY: Price; USD: Price; launchCNY: Price; launchUSD: Price; launchUntil: string | null; productID: string };
  renewal: { CNY: Price; USD: Price; productID: string };
  packs: Array<{ id: string; name: string; enabled: boolean; recommended: boolean; CNY: Price; USD: Price; productID: string }>;
  taxCategory: string; taxIncluded: boolean; supportEmail: string; termsURL: string; privacyURL: string; refundURL: string;
  lastCompatibleVersionURL: string;
};
export const isoNow = () => new Date().toISOString();
export const billingReply = (result: unknown, status = 200) => Response.json({ success: true, result },
  { status, headers: { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' } });
export class BillingError extends Error {
  constructor(public code: string, message: string, public status = 400, public details?: unknown) { super(message); }
}
export async function billingBody(request: Request): Promise<Record<string, unknown>> {
  if (Number(request.headers.get('Content-Length') || 0) > 64000) throw new BillingError('invalid_json','Request too large.');
  const raw = await request.text();
  if (raw.length > 64000) throw new BillingError('invalid_json','Request too large.');
  let data: unknown; try { data = JSON.parse(raw); } catch { throw new BillingError('invalid_json','Invalid JSON.'); }
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new BillingError('invalid_json','Expected a JSON object.');
  return data as Record<string, unknown>;
}
export async function sha256(value: string) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))].map(b=>b.toString(16).padStart(2,'0')).join('');
}
export function defaultPricing(env: Env): Pricing {
  const bonus = Number(env.NEW_USER_CREDITS ?? 100);
  return { enabled: false, trialDays: 14, signupCredits: Number.isSafeInteger(bonus) && bonus >= 0 ? bonus : 100,
    proBonusCredits: 100, deviceLimit: 2, offlineDays: 30, releaseLimit: 3, confirmationThreshold: 20,
    queueMinutes: 30, maxAttempts: 3, updatesMonths: 12, renewalMonths: 12,
    pro: { CNY: { amount: null }, USD: { amount: null }, launchCNY: { amount: null }, launchUSD: { amount: null }, launchUntil: null, productID: '' },
    renewal: { CNY: { amount: null }, USD: { amount: null }, productID: '' },
    packs: [
      { id:'small',name:'Small',enabled:true,recommended:false,CNY:{amount:1200,points:120},USD:{amount:299,points:120},productID:'' },
      { id:'standard',name:'Standard',enabled:true,recommended:true,CNY:{amount:3000,points:330},USD:{amount:499,points:330},productID:'' },
      { id:'large',name:'Large',enabled:true,recommended:false,CNY:{amount:9800,points:1200},USD:{amount:1499,points:1200},productID:'' }
    ], taxCategory:'software',taxIncluded:true,supportEmail:'',termsURL:'https://glance.mcreator.ai/terms',
    privacyURL:'https://glance.mcreator.ai/privacy',refundURL:'https://glance.mcreator.ai/refunds',lastCompatibleVersionURL:'' };
}
export async function readPricing(env: Env): Promise<Pricing & { revision: number }> {
  const row = await env.DB.prepare('SELECT revision,json FROM billing_settings WHERE id=1').first<{revision:number;json:string}>();
  return { ...(row ? JSON.parse(row.json) as Pricing : defaultPricing(env)), revision:row?.revision ?? 0 };
}
export function paymentReady(env: Env) {
  return !!(env.WAFFO_MERCHANT_ID && env.WAFFO_PRIVATE_KEY && env.WAFFO_STORE_ID &&
    ['test','prod'].includes(env.WAFFO_ENVIRONMENT || '') && env.GLANCE_SIGNING_KEY_PKCS8 &&
    (env.WAFFO_ENVIRONMENT==='test'?env.WAFFO_WEBHOOK_PUBLIC_KEY_TEST:env.WAFFO_WEBHOOK_PUBLIC_KEY_PROD));
}
export function mockCheckoutUser(env: Env, userID: number) {
  return env.WAFFO_ENVIRONMENT === 'test' && !paymentReady(env)
    && env.MOCK_CHECKOUT_USER_ID === String(userID);
}
export async function publicPricing(env: Env, request: Request) {
  const config = await readPricing(env);
  const country = (request as Request & {cf?:{country?:string}}).cf?.country || request.headers.get('CF-IPCountry');
  let mock = false;
  if (env.MOCK_CHECKOUT_USER_ID && request.headers.has('Authorization')) {
    try { mock = mockCheckoutUser(env, (await authenticatedUser(env, request)).id); }
    catch { /* Public pricing remains available when a session is invalid. */ }
  }
  return billingReply({ ...config, defaultCurrency:country === 'CN' ? 'CNY' : 'USD',
    packs:mock ? config.packs.map(pack=>({...pack,productID:pack.productID||'mock_credits'})) : config.packs,
    paymentsAvailable:config.enabled && paymentReady(env) || mock, serverTime:isoNow() });
}
export function validatePricing(value: unknown): asserts value is Pricing {
  const c = value as Pricing;
  const integer = (v:unknown,min:number,max:number) => Number.isSafeInteger(v) && Number(v)>=min && Number(v)<=max;
  if (!c || typeof c.enabled !== 'boolean' || typeof c.taxIncluded !== 'boolean') throw new BillingError('invalid_pricing','Invalid settings.');
  for (const [key,min,max] of [['trialDays',1,90],['signupCredits',0,1000000],['proBonusCredits',0,1000000],['deviceLimit',1,20],
    ['offlineDays',1,30],['releaseLimit',0,100],['confirmationThreshold',0,1000000],['queueMinutes',1,1440],
    ['maxAttempts',1,10],['updatesMonths',1,120],['renewalMonths',1,120]] as const) {
    if (!integer(c[key],min,max)) throw new BillingError('invalid_pricing',`Invalid ${key}.`);
  }
  if (!Array.isArray(c.packs) || c.packs.length<1 || c.packs.length>12 || new Set(c.packs.map(p=>p.id)).size!==c.packs.length) throw new BillingError('invalid_pricing','Supply 1–12 unique packages.');
  const price = (p:Price, currency:Currency, points=false) => {
    if (!p || !(p.amount===null || integer(p.amount,100,currency==='CNY'?100000:1000000)) ||
      (points && !integer(p.points,1,100000000))) throw new BillingError('invalid_pricing',`Invalid ${currency} price or points.`);
  };
  if (!c.pro || !c.renewal) throw new BillingError('invalid_pricing','Missing products.');
  for (const currency of ['CNY','USD'] as const) {
    price(c.pro[currency],currency); price(c.pro[currency==='CNY'?'launchCNY':'launchUSD'],currency); price(c.renewal[currency],currency);
    for (const pack of c.packs) price(pack[currency],currency,true);
  }
  for (const item of [c.pro,c.renewal,...c.packs]) if (typeof item.productID!=='string' || (item.productID!=='' && !/^PROD_[A-Za-z0-9]{22}$/.test(item.productID))) throw new BillingError('invalid_pricing','Invalid product ID.');
  for (const pack of c.packs) if (!/^[a-zA-Z0-9_-]{1,64}$/.test(pack.id) || typeof pack.name!=='string' || pack.name.length>100 || typeof pack.enabled!=='boolean' || typeof pack.recommended!=='boolean') throw new BillingError('invalid_pricing','Invalid package.');
  if (c.packs.filter(p=>p.enabled && p.recommended).length>1) throw new BillingError('invalid_pricing','Only one recommended package is allowed.');
  if (c.pro.launchUntil!==null && (!c.pro.launchUntil || !Number.isFinite(Date.parse(c.pro.launchUntil)))) throw new BillingError('invalid_pricing','Invalid launch cutoff.');
  for (const field of ['taxCategory','supportEmail','termsURL','privacyURL','refundURL','lastCompatibleVersionURL'] as const) {
    if (typeof c[field]!=='string' || c[field].length>1000) throw new BillingError('invalid_pricing',`Invalid ${field}.`);
    if (field.endsWith('URL') && c[field]) {
      try { const url=new URL(c[field]);if(url.protocol!=='https:' || !url.hostname) throw new Error(); }
      catch { throw new BillingError('invalid_pricing','Policy and download links must use HTTPS.'); }
    }
  }
  if (c.supportEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c.supportEmail)) throw new BillingError('invalid_pricing','Invalid support email.');
  if (!['digital_goods','saas','software','ebook','online_course','consulting','professional_service'].includes(c.taxCategory)) throw new BillingError('invalid_pricing','Invalid tax category.');
  if (c.enabled && (!c.pro.productID || !c.taxCategory || !c.supportEmail || !c.pro.CNY.amount || !c.pro.USD.amount)) throw new BillingError('invalid_pricing','Configure both Pro prices, product, support and tax category before enabling sales.');
}
export async function savePricing(env: Env, request: Request) {
  const data = await billingBody(request); const config = data.config;
  validatePricing(config);
  if (!Number.isSafeInteger(data.revision)) throw new BillingError('invalid_revision','A revision is required.');
  const result = await env.DB.prepare(`INSERT INTO billing_settings(id,revision,json,updated_at)
    SELECT 1,1,?,? WHERE (?=0 OR EXISTS(SELECT 1 FROM billing_settings WHERE id=1)) ON CONFLICT(id) DO UPDATE SET revision=revision+1,json=excluded.json,updated_at=excluded.updated_at
    WHERE billing_settings.revision=? RETURNING revision`).bind(JSON.stringify(config),isoNow(),data.revision,data.revision).first();
  if (!result) throw new BillingError('revision_conflict','Pricing was changed elsewhere. Refresh before saving.',409);
  return billingReply(await readPricing(env));
}

// Executed by cron and before queue/status requests, even with no active Worker.
export async function expireTasks(env: Env) {
  const config = await readPricing(env), now = isoNow();
  const cutoff = new Date(Date.now()-config.queueMinutes*60000).toISOString();
  await env.DB.batch([
    env.DB.prepare(`UPDATE widget_tasks SET status='expired',error_code='queue_expired',completed_at=?,lease_expires_at=NULL,claim_token_hash=NULL
      WHERE status='queued' AND created_at<?`).bind(now,cutoff),
    env.DB.prepare(`UPDATE widget_tasks SET status='expired',error_code='max_attempts',completed_at=?,lease_expires_at=NULL,claim_token_hash=NULL
      WHERE status IN ('claimed','running') AND lease_expires_at<? AND attempts>=?`).bind(now,now,config.maxAttempts)
  ]);
}
