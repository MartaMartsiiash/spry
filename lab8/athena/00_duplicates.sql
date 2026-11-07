WITH c AS (
  SELECT invoiceId, status, amount, finalAmount, ccy, reference, createdDate, modifiedDate, receivedAt,
         merchantId, merchantName, mcc, customerId, paymentMethod, device, failureReason, COUNT(*) AS n
  FROM lab8.payment_events
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
)
SELECT
  SUM(n) AS total_rows,
  COUNT(*) AS unique_rows,
  SUM(n) - COUNT(*) AS exact_duplicate_extra_rows
FROM c;
