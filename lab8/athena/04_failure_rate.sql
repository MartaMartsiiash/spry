SELECT
  paymentMethod,
  device,
  COUNT(*) AS payments,
  SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS failures,
  ROUND(
    100.0 * SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS failure_rate_pct
FROM lab8.payments
GROUP BY paymentMethod, device
ORDER BY failure_rate_pct DESC;
