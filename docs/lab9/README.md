# Lab 9 — evidence (route without a Google Cloud account)

I took the route without a Google Cloud account: the free trial asked for a $30
prepayment on my card, so I closed the billing account and ran everything that
does not need billing locally or in free tools.

## 1. The app, ready for Cloud Run, running locally

Cloud Run runs a plain container and sends HTTP to the port in the `PORT`
environment variable (8080). On AWS the API ran on Lambda behind an adapter
(`Dockerfile.lambda` + Mangum). For Google Cloud the plain `backend/Dockerfile`
is used, with no Lambda adapter; the only change is that uvicorn now listens on
`${PORT:-8000}` instead of a hard-coded 8000. The same image therefore runs in
docker compose (8000), and as Cloud Run would run it (8080).

### `local-health.txt` — the API container started as Cloud Run would start it

- PostgreSQL 17 from `docker-compose.yml` (`docker compose up -d db`) stands in
  for Cloud SQL for PostgreSQL.
- The backend image is built from `backend/Dockerfile` and started with
  `-e PORT=8080 -p 8080:8080`, exactly the contract Cloud Run uses.
- `DATABASE_URL` is passed as an environment variable; on Cloud Run it would
  come from Secret Manager (see `gcp/main.tf`).
- Database migrations ran on start (`entrypoint.sh` → `alembic upgrade head`).
- `GET /health` runs `SELECT 1` against the database and answers
  `{"status":"ok","database":"ok"}`.

### `local-frontend-network.png` — the frontend loads and an API call reads from the database

- The Next.js frontend runs on `http://localhost:3000`, built with
  `NEXT_PUBLIC_API_BASE_URL=http://localhost:8080`, so it talks to the
  Cloud Run–style container, not to the old compose backend on 8000.
- I signed in through Cognito (sign-in stays on AWS in this lab).
- The page **Today** shows the meeting *Lab 9 demo*, which was saved to and
  read back from PostgreSQL.
- Chrome DevTools → Network shows the request
  `GET http://localhost:8080/api/v1/meetings` → **200 OK**, `Server: uvicorn`,
  `Content-Type: application/json`, and the CORS header
  `Access-Control-Allow-Origin: http://localhost:3000`.
  (The bearer token is cut off in the screenshot on purpose.)

## 2. Terraform for Google Cloud

The configuration is in [`gcp/`](../../gcp), separate from the AWS one in
`infra/`, with its own HCP Terraform workspace. See
[ADR 0008](../adr/0008-spry-on-google-cloud.md) for the service choices.
`terraform init -backend=false` and `terraform validate` run without Google
credentials — output in `terraform-validate.txt`.
