CREATE TABLE lab8.payments_parquet
WITH (
  format = 'PARQUET',
  parquet_compression = 'SNAPPY',
  partitioned_by = ARRAY['dt'],
  external_location = 's3://successfulsuccess-lab8-payments-378600555796/curated/payments/'
) AS
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
FROM lab8.payments;
