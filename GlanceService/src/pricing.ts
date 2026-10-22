import type { Env } from './index';
import { authenticatedUser } from './users';

export type Currency = 'CNY' | 'USD';
export type Price = { amount: number | null; points?: number };
/** A Pro tier: one lifetime licence for `deviceLimit` Macs. */
export type Tier = { id: string; name: string; enabled: boolean; recommended: boolean; deviceLimit: number;
  CNY: Price; USD: Price; launchCNY: Price; launchUSD: Price; productID: string };
export type Pricing = {
  enabled: boolean; trialDays: number; signupCredits: number; proBonusCredits: number;
  /** Macs allowed for admin-granted Pro and for licences without a tier. */
  deviceLimit: number; offlineDays: number; releaseLimit: number; confirmationThreshold: number;
  queueMinutes: number; maxAttempts: number;
  proTiers: Tier[];
  /** Launch prices apply to every tier until this instant (ISO 8601), or never when null. */
  launchUntil: string | null;
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
    queueMinutes: 30, maxAttempts: 3,
    proTiers: [
      { id:'personal',name:'Personal',enabled:true,recommended:false,deviceLimit:1,CNY:{amount:9800},USD:{amount:1490},launchCNY:{amount:6800},launchUSD:{amount:990},productID:'' },
      { id:'duo',name:'Duo',enabled:true,recommended:true,deviceLimit:2,CNY:{amount:13800},USD:{amount:1990},launchCNY:{amount:9800},launchUSD:{amount:1490},productID:'' }
    ], launchUntil: null,
    packs: [
      { id:'small',name:'Small',enabled:true,recommended:false,CNY:{amount:1200,points:120},USD:{amount:299,points:120},productID:'' },
      { id:'standard',name:'Standard',enabled:true,recommended:true,CNY:{amount:3000,points:330},USD:{amount:499,points:330},productID:'' },
      { id:'large',name:'Large',enabled:true,recommended:false,CNY:{amount:9800,points:1200},USD:{amount:1499,points:1200},productID:'' }
    ], taxCategory:'software',taxIncluded:true,supportEmail:'',termsURL:'https://glancepreview.com/terms',
    privacyURL:'https://glancepreview.com/privacy',refundURL:'https://glancepreview.com/refunds',lastCompatibleVersionURL:'' };
}
export async function readPricing(env: Env): Promise<Pricing & { revision: number }> {
  const row = await env.DB.prepare('SELECT revision,json FROM billing_settings WHERE id=1').first<{revision:number;json:string}>();
  return { ...(row ? normalizePricing(JSON.parse(row.json)) : defaultPricing(env)), revision:row?.revision ?? 0 };
}
/** Settings saved before Pro tiers existed carry one `pro` product and a renewal; map them to a single tier. */
function normalizePricing(stored: Record<string, unknown>): Pricing {
  if (Array.isArray(stored.proTiers)) return stored as unknown as Pricing;
  const legacy = stored.pro as Record<string, unknown> | undefined;
  const { pro: _pro, renewal: _renewal, updatesMonths: _u, renewalMonths: _r, ...rest } = stored;
  const price = (v: unknown) => (v && typeof v === 'object' ? v : { amount: null }) as Price;
  return { ...rest, launchUntil: typeof legacy?.launchUntil === 'string' ? legacy.launchUntil : null,
    proTiers: [{ id:'standard', name:'Pro', enabled:true, recommended:true, deviceLimit:Number(stored.deviceLimit) || 2,
      CNY:price(legacy?.CNY), USD:price(legacy?.USD), launchCNY:price(legacy?.launchCNY), launchUSD:price(legacy?.launchUSD),
      productID:typeof legacy?.productID === 'string' ? legacy.productID : '' }] } as Pricing;
}
/** Price of a tier in a currency: the launch price while `launchUntil` is in the future and set, else the regular one. */
export function tierPrice(config: Pricing, tier: Tier, currency: Currency): Price {
  const launch = !!config.launchUntil && Date.parse(config.launchUntil) > Date.now() ? tier[currency === 'CNY' ? 'launchCNY' : 'launchUSD'] : null;
  return launch && launch.amount !== null ? launch : tier[currency];
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
/** Mock checkout price: the configured amount, or a 1.00 placeholder while
 *  none is set (orders require amount > 0). Mock orders never collect money. */
export function mockPrice(price: Price): Price { return price.amount == null ? { ...price, amount: 100 } : price; }
function mockProduct<T extends { CNY: Price; USD: Price; productID: string }>(product: T, productID: string): T {
  return { ...product, CNY: mockPrice(product.CNY), USD: mockPrice(product.USD), productID: product.productID || productID };
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
    // The owner's test account can complete every purchase while Pancake is
    // pending: unset prices become a 1.00 placeholder and product IDs get a mock ID.
    packs:mock ? config.packs.map(pack=>({...pack,productID:pack.productID||'mock_credits'})) : config.packs,
    proTiers:mock ? config.proTiers.map(tier=>mockProduct(tier,'mock_pro_'+tier.id)) : config.proTiers,
    mockCheckout:mock,
    paymentsAvailable:config.enabled && paymentReady(env) || mock, serverTime:isoNow() });
}
export function validatePricing(value: unknown): asserts value is Pricing {
  const c = value as Pricing;
  const integer = (v:unknown,min:number,max:number) => Number.isSafeInteger(v) && Number(v)>=min && Number(v)<=max;
  if (!c || typeof c.enabled !== 'boolean' || typeof c.taxIncluded !== 'boolean') throw new BillingError('invalid_pricing','Invalid settings.');
  for (const [key,min,max] of [['trialDays',1,90],['signupCredits',0,1000000],['proBonusCredits',0,1000000],['deviceLimit',1,20],
    ['offlineDays',1,30],['releaseLimit',0,100],['confirmationThreshold',0,1000000],['queueMinutes',1,1440],
    ['maxAttempts',1,10]] as const) {
    if (!integer(c[key],min,max)) throw new BillingError('invalid_pricing',`Invalid ${key}.`);
  }
  if (!Array.isArray(c.packs) || c.packs.length<1 || c.packs.length>12 || new Set(c.packs.map(p=>p.id)).size!==c.packs.length) throw new BillingError('invalid_pricing','Supply 1–12 unique packages.');
  const price = (p:Price, currency:Currency, points=false) => {
    if (!p || !(p.amount===null || integer(p.amount,100,currency==='CNY'?100000:1000000)) ||
      (points && !integer(p.points,1,100000000))) throw new BillingError('invalid_pricing',`Invalid ${currency} price or points.`);
  };
  if (!Array.isArray(c.proTiers) || c.proTiers.length<1 || c.proTiers.length>6 || new Set(c.proTiers.map(t=>t.id)).size!==c.proTiers.length) throw new BillingError('invalid_pricing','Supply 1–6 unique Pro tiers.');
  for (const tier of c.proTiers) {
    if (!/^[a-zA-Z0-9_-]{1,64}$/.test(tier.id) || typeof tier.name!=='string' || tier.name.length>100 || typeof tier.enabled!=='boolean' ||
      typeof tier.recommended!=='boolean' || !integer(tier.deviceLimit,1,20)) throw new BillingError('invalid_pricing','Invalid Pro tier.');
  }
  if (c.proTiers.filter(t=>t.enabled && t.recommended).length>1) throw new BillingError('invalid_pricing','Only one recommended tier is allowed.');
  for (const currency of ['CNY','USD'] as const) {
    for (const tier of c.proTiers) { price(tier[currency],currency); price(tier[currency==='CNY'?'launchCNY':'launchUSD'],currency); }
    for (const pack of c.packs) price(pack[currency],currency,true);
  }
  for (const item of [...c.proTiers,...c.packs]) if (typeof item.productID!=='string' || (item.productID!=='' && !/^PROD_[A-Za-z0-9]{22}$/.test(item.productID))) throw new BillingError('invalid_pricing','Invalid product ID.');
  for (const pack of c.packs) if (!/^[a-zA-Z0-9_-]{1,64}$/.test(pack.id) || typeof pack.name!=='string' || pack.name.length>100 || typeof pack.enabled!=='boolean' || typeof pack.recommended!=='boolean') throw new BillingError('invalid_pricing','Invalid package.');
  if (c.packs.filter(p=>p.enabled && p.recommended).length>1) throw new BillingError('invalid_pricing','Only one recommended package is allowed.');
  if (c.launchUntil!==null && (!c.launchUntil || !Number.isFinite(Date.parse(c.launchUntil)))) throw new BillingError('invalid_pricing','Invalid launch cutoff.');
  for (const field of ['taxCategory','supportEmail','termsURL','privacyURL','refundURL','lastCompatibleVersionURL'] as const) {
    if (typeof c[field]!=='string' || c[field].length>1000) throw new BillingError('invalid_pricing',`Invalid ${field}.`);
    if (field.endsWith('URL') && c[field]) {
      try { const url=new URL(c[field]);if(url.protocol!=='https:' || !url.hostname) throw new Error(); }
      catch { throw new BillingError('invalid_pricing','Policy and download links must use HTTPS.'); }
    }
  }
  if (c.supportEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c.supportEmail)) throw new BillingError('invalid_pricing','Invalid support email.');
  if (!['digital_goods','saas','software','ebook','online_course','consulting','professional_service'].includes(c.taxCategory)) throw new BillingError('invalid_pricing','Invalid tax category.');
  const live=c.proTiers.filter(t=>t.enabled);
  if (c.enabled && (!live.length || !c.taxCategory || !c.supportEmail || live.some(t=>!t.productID || !t.CNY.amount || !t.USD.amount))) throw new BillingError('invalid_pricing','Configure both prices and a product ID for every enabled Pro tier, plus support and tax category, before enabling sales.');
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
