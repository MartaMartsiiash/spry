SELECT
  COUNT(*) AS events,
  COUNT(DISTINCT invoiceId) AS unique_invoices,
  COUNT(*) - COUNT(DISTINCT invoiceId || '|' || status || '|' || modifiedDate || '|' || coalesce(failureReason,'')) AS approx_exact_dup_rows_removed_if_distinct_star
FROM lab8.payment_events;
