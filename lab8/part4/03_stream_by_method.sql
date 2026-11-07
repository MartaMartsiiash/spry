SELECT
  paymentMethod,
  COUNT(*) AS n,
  SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS failures,
  ROUND(1.0 * SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) / COUNT(*), 4) AS failure_rate
FROM lab8.payments_stream
GROUP BY paymentMethod
ORDER BY failure_rate DESC;
