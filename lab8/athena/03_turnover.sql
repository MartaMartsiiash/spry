-- Turnover by merchant and currency (successful payments only), whole units
SELECT
  merchantId,
  merchantName,
  ccy,
  COUNT(*) AS success_payments,
  ROUND(SUM(finalAmount) / 100.0, 2) AS turnover
FROM lab8.payments
WHERE status = 'success'
GROUP BY merchantId, merchantName, ccy
ORDER BY turnover DESC;
