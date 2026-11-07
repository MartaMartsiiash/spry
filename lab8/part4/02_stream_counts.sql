SELECT
  COUNT(*) AS events,
  COUNT(DISTINCT invoiceId) AS invoices,
  SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS failures,
  ROUND(100.0 * SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_pct
FROM lab8.payments_stream;
