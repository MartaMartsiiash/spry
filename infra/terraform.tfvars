project_name = "successfulsuccess"
region       = "eu-north-1"

callback_urls = [
  "http://localhost:3000/auth/callback/",
  "https://d3u0mle6pgsfus.cloudfront.net/auth/callback/",
]

logout_urls = [
  "http://localhost:3000/",
  "https://d3u0mle6pgsfus.cloudfront.net/",
]

google_client_id = "503685285836-9ptnnraovs2u0j31olgaonh6c915dji0.apps.googleusercontent.com"

# Digests from the live Lambdas (Lab 5/6). Update after make aws-push.
parser_image_uri  = "378600555796.dkr.ecr.eu-north-1.amazonaws.com/successfulsuccess-backend@sha256:da7da704a883e9414ed1211e112682909c078383d57a6085ecf056ea61029ba8"
reports_image_uri = "378600555796.dkr.ecr.eu-north-1.amazonaws.com/successfulsuccess-backend@sha256:ed67fde4875a5f8fdf47fe03d960e03c25499974ecc39fbf854e05b830ce8ee4"

architecture         = "x86_64"
builder_architecture = "arm64"

recipient_email = "martsiiash.pn@ucu.edu.ua"
sender_domain   = ""
app_timezone    = "Europe/Kyiv"
schedule_expression = "cron(0 7 ? * MON *)"
cors_origins    = "https://d3u0mle6pgsfus.cloudfront.net"
parser_model    = "eu.anthropic.claude-sonnet-4-6"

# Secrets (google_client_secret, database_url) live in the HCP workspace
# as sensitive Terraform variables — not in this file.
