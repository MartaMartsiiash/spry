CREATE OR REPLACE VIEW lab8.payments AS
WITH dedup_exact AS (
  SELECT DISTINCT *
  FROM lab8.payment_events
),
ranked AS (
  SELECT
    *,
    row_number() OVER (
      PARTITION BY invoiceId
      ORDER BY from_iso8601_timestamp(modifiedDate) DESC
    ) AS rn
  FROM dedup_exact
)
SELECT
  invoiceId,
  status,
  failureReason,
  amount,
  finalAmount,
  ccy,
  reference,
  createdDate,
  modifiedDate,
  receivedAt,
  merchantId,
  merchantName,
  mcc,
  customerId,
  paymentMethod,
  device,
  dt
FROM ranked
WHERE rn = 1;
