#!/usr/bin/env bash
# Deploy Spry's core (frontend, API, database) to Google Cloud.
# Run it in Cloud Shell (gcloud, terraform, docker and node are preinstalled,
# and you are already signed in — no service account key is ever downloaded):
#
#   ./gcp/deploy.sh            full deploy
#   ./gcp/deploy.sh frontend   rebuild and redeploy only the frontend
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

PROJECT_ID=$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' gcp/terraform.tfvars)
REGION=$(sed -n 's/^region *= *"\(.*\)"/\1/p' gcp/terraform.tfvars)
REGION=${REGION:-europe-west1}
TAG=$(git rev-parse --short HEAD)
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/spry/backend:$TAG"
SITE="https://$PROJECT_ID.web.app"

# Sign-in and the agenda parser stay on AWS for now (see docs/adr/0008).
COGNITO_AUTHORITY="https://cognito-idp.eu-north-1.amazonaws.com/eu-north-1_8JgjHup8F"
COGNITO_CLIENT_ID="7ridr6t0t0bqmn16s25uu2qsc5"
COGNITO_DOMAIN="successfulsuccess-378600555796.auth.eu-north-1.amazoncognito.com"
AGENDA_PARSER_URL="https://6o5koyo365khdjek76pzxfvuay0ltkzr.lambda-url.eu-north-1.on.aws"

gcloud config set project "$PROJECT_ID" >/dev/null

deploy_backend() {
  cd "$ROOT/gcp"
  terraform init -input=false

  echo "== 1/3 APIs, registry, database, secret, service account (~10 min, Cloud SQL is slow to create)"
  terraform apply -input=false -auto-approve -var "deploy_service=false"

  echo "== 2/3 Backend image -> Artifact Registry"
  gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
  docker build -t "$IMAGE" "$ROOT/backend"
  docker push "$IMAGE"

  echo "== 3/3 Cloud Run service"
  terraform apply -input=false -auto-approve -var "image_tag=$TAG"

  API=$(terraform output -raw api_url)
  echo "API: $API"
  curl -fsS "$API/health" && echo
  cd "$ROOT"
}

deploy_frontend() {
  echo "== Frontend static export (API on the same origin through the Firebase rewrite)"
  rm -rf frontend/out
  docker build --target export --output type=local,dest=frontend/out \
    --build-arg NEXT_PUBLIC_API_BASE_URL="$SITE" \
    --build-arg NEXT_PUBLIC_AGENDA_PARSER_URL="$AGENDA_PARSER_URL" \
    --build-arg NEXT_PUBLIC_COGNITO_AUTHORITY="$COGNITO_AUTHORITY" \
    --build-arg NEXT_PUBLIC_COGNITO_CLIENT_ID="$COGNITO_CLIENT_ID" \
    --build-arg NEXT_PUBLIC_COGNITO_DOMAIN="$COGNITO_DOMAIN" \
    --build-arg NEXT_PUBLIC_COGNITO_REDIRECT_URI="$SITE/auth/callback/" \
    --build-arg NEXT_PUBLIC_COGNITO_LOGOUT_URI="$SITE/" \
    ./frontend

  echo "== Firebase Hosting"
  # Adds Firebase to the GCP project the first time; harmless afterwards.
  npx -y firebase-tools@latest projects:addfirebase "$PROJECT_ID" 2>/dev/null || true
  (cd frontend && npx -y firebase-tools@latest deploy --only hosting --project "$PROJECT_ID" --non-interactive)
  echo "Site: $SITE"
  curl -fsS "$SITE/health" && echo
}

case "${1:-all}" in
  backend) deploy_backend ;;
  frontend) deploy_frontend ;;
  all) deploy_backend; deploy_frontend ;;
  *) echo "usage: $0 [all|backend|frontend]"; exit 1 ;;
esac
