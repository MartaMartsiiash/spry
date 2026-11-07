-- Events that arrived more than 60 seconds after they happened
SELECT COUNT(*) AS late_over_60s
FROM lab8.payment_events
WHERE date_diff(
  'second',
  from_iso8601_timestamp(modifiedDate),
  from_iso8601_timestamp(receivedAt)
) > 60;
