SELECT COUNT(*) AS late_over_1_hour
FROM lab8.payment_events
WHERE date_diff('second', from_iso8601_timestamp(modifiedDate), from_iso8601_timestamp(receivedAt)) > 3600;
