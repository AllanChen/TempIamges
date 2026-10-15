# Pancake / Waffo payment setup

The Worker creates authenticated hosted-checkout sessions. It never accepts a
price, credit amount, or user ID from the client. Signed `order.completed`
webhooks grant purchases; signed `refund.succeeded` webhooks reverse them after
the full charged amount has been refunded. Webhook delivery IDs and order status
transitions are idempotent.

## Before deployment

1. Apply D1 migration `0010_billing.sql` in the target environment. Deploy the
   Worker only after the migration succeeds.
2. In the [Pancake dashboard](https://pancake.waffo.ai), create five **one-time**
   CNY products: Pro buyout, annual feature-update renewal, and 100/300/1000
   credit packs. Publish them. CNY one-time checkout currently supports WeChat
   Pay; do not use subscription products for these SKUs.
3. Configure the values below as Wrangler secrets in each environment. Test
   and production merchant credentials, product IDs, and webhook keys must not
   be mixed. Never commit the private key, checkout URLs, or buyer tokens.
4. Register `https://glance-service.allanchanni.workers.dev/api/v2/billing/webhook`
   as the Pancake webhook URL. Enable `order.completed` and `refund.succeeded`.
5. Register `https://glance-service.allanchanni.workers.dev/auth/google/callback`
   as a Google OAuth redirect URI for the consumer login flow. Email login uses
   Resend when `RESEND_API_KEY` and a verified `AUTH_EMAIL_FROM` are configured.

| Name | Purpose |
| --- | --- |
| `WAFFO_MERCHANT_ID` | Merchant ID (`MER_...`), not store ID |
| `WAFFO_STORE_ID` | Store ID (`STO_...`) checked on every webhook |
| `WAFFO_PRIVATE_KEY` | Merchant RSA private key for SDK requests |
| `WAFFO_WEBHOOK_PUBLIC_KEY` | Waffo webhook verification public key |
| `WAFFO_ENVIRONMENT` | `test` or `prod` |
| `WAFFO_PRODUCT_PRO` | Pro one-time product ID |
| `WAFFO_PRODUCT_UPDATES_YEAR` | Update renewal one-time product ID |
| `WAFFO_PRODUCT_CREDITS_100` | 100-credit product ID |
| `WAFFO_PRODUCT_CREDITS_300` | 300-credit product ID |
| `WAFFO_PRODUCT_CREDITS_1000` | 1000-credit product ID |
| `PRO_LIFETIME_CNY` | Optional Pro price override: default `99.00`; set `149.00` after launch |
| `RESEND_API_KEY`, `AUTH_EMAIL_FROM` | Optional email-code delivery |

Existing `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and `SESSION_SECRET` are
also required for sign-in. Set secrets with `wrangler secret put NAME`; do not
place values in `wrangler.toml`.

## API contract

All routes except the webhook require the bearer token from `/auth/native/exchange`
or `/auth/email/verify-code`.

- `GET /api/v2/billing/catalog`: server-owned SKUs and CNY prices.
- `GET /api/v2/billing/wallet`: balance, 14-day trial, Pro and updates state.
- `POST /api/v2/billing/checkout` with `{ "sku": "credits_100" }`: returns
  `orderId`, short-lived `checkoutUrl`, and `expiresAt`. Open the URL externally.
- Pancake sends the buyer to the HTTPS success URL only after they click
  **Done** on its success page. That URL hands the order ID back to Glance; the
  app still checks the service order status before treating it as paid.
- `GET /api/v2/billing/orders/{orderId}`: poll for `pending`, `expired`,
  `completed`, or `refunded`. Do not treat the browser return as proof of payment.
- `POST /api/v2/billing/webhook`: raw-body signed Waffo events only.

The service charges 8 credits for each production Widget task at enqueue time.
Queued cancellation and Worker-reported failure refund the 8 credits exactly
once. A scheduled cleanup also fails and refunds tasks older than one hour
without a result. Cancellation after a Worker claims or starts the task does
not refund.
The Pro buyout grants 100 credits once it is paid. Full payment refunds revoke
unspent or spent credits; a spent balance may become negative until replenished.
The user-facing credit and task-transaction history pages are intentionally not
part of this flow.

This change does not deploy to a live account. Verify test-mode checkout,
webhook signature, duplicate delivery, partial/full refund, and app callback
with the merchant credentials before switching to production.
