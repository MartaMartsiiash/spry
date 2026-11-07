CREATE EXTERNAL TABLE IF NOT EXISTS lab8.payments_stream (
  invoiceId string,
  merchantId string,
  merchantName string,
  status string,
  paymentMethod string,
  device string,
  ccy string,
  finalAmount bigint,
  failureReason string,
  modifiedDate string,
  receivedAt string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://successfulsuccess-lab8-payments-378600555796/stream/raw/'
TBLPROPERTIES ('has_encrypted_data'='false');
