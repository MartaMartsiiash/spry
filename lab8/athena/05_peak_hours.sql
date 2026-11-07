SELECT
  hour(from_iso8601_timestamp(createdDate)) AS hour_of_day,
  COUNT(*) AS payments
FROM lab8.payments
GROUP BY 1
ORDER BY 1;
