CREATE EXTERNAL TABLE IF NOT EXISTS lab8.payment_events (
  invoiceId string,
  status string,
  failureReason string,
  amount bigint,
  finalAmount bigint,
  ccy int,
  reference string,
  createdDate string,
  modifiedDate string,
  receivedAt string,
  merchantId string,
  merchantName string,
  mcc string,
  customerId string,
  paymentMethod string,
  device string
)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true'
)
STORED AS TEXTFILE
LOCATION 's3://successfulsuccess-lab8-payments-378600555796/payments/'
TBLPROPERTIES ('has_encrypted_data'='false');
