-- Mac App Store in-app purchases are recorded as orders with payment_method
-- 'app_store' and provider_order_id 'apple:<transactionId>'. Apple's own price
-- is kept alongside, since storefront currencies go beyond the order currencies.
ALTER TABLE orders ADD COLUMN store_currency TEXT;
ALTER TABLE orders ADD COLUMN store_price_milli INTEGER;

CREATE TABLE app_store_notifications (
  id TEXT PRIMARY KEY,
  notification_type TEXT NOT NULL,
  subtype TEXT,
  transaction_id TEXT,
  order_id TEXT,
  created_at TEXT NOT NULL
);
