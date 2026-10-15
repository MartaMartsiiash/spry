COMPOSE ?= docker compose

# Windows: the recipes are POSIX shell, and native GNU make (winget install
# ezwinports.make) would hand them to cmd.exe. Run them with the bash, sed, awk,
# curl and friends that Git for Windows ships instead, whichever terminal make is
# started from. Installed Git elsewhere? make GIT_HOME="D:/Tools/Git" ...
# MSYS2/Cygwin make already has a POSIX shell, so it is left alone.
ifeq ($(OS),Windows_NT)
ifeq ($(findstring msys,$(MAKE_HOST))$(findstring cygwin,$(MAKE_HOST)),)
GIT_HOME ?= C:/Program Files/Git
export PATH := $(GIT_HOME)/bin;$(GIT_HOME)/usr/bin;$(PATH)
SHELL := bash.exe
.SHELLFLAGS := -c
endif
endif

# Local configuration (gitignored). These assignments beat variables exported in
# the shell, so override one on the command line instead: make aws-deploy-backend
# AWS_LAMBDA_ARCH=arm64
-include .env
# Every stack (ECR, Lambda, Aurora, S3 + CloudFront) is created in this one region.
AWS_REGION ?= us-east-1
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION PROJECT_NAME
# On Windows, stop Git's bash rewriting container paths such as /aws or
# /dev/null into C:/Program Files/Git/... before docker sees them.
export MSYS_NO_PATHCONV := 1
export MSYS2_ARG_CONV_EXCL := *

# The AWS CLI runs in a container so nothing has to be installed on the host.
# The repository is mounted at /aws (the image's workdir) so the CLI can read
# infra/*.yml. Pass AWS=aws to use a CLI installed on the host instead.
AWS ?= docker run --rm \
	-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
	-e AWS_DEFAULT_REGION=$(AWS_REGION) \
	-v $(CURDIR):/aws -w /aws \
	amazon/aws-cli:latest
# `aws login --profile spry` keeps a rotating session on this machine. The
# container CLI cannot see that session, so a named profile uses the host CLI.
ifneq ($(AWS_PROFILE),)
AWS := aws
export AWS_PROFILE
endif

AUTH_STACK ?= $(PROJECT_NAME)-auth
APP_STACK ?= $(PROJECT_NAME)-backend
ECR_STACK ?= $(PROJECT_NAME)-ecr
FRONTEND_STACK ?= $(PROJECT_NAME)-frontend
REPORTS_STACK ?= $(PROJECT_NAME)-reports
IMAGE_TAG ?= latest
# x86_64 or arm64. arm64 is ~20% cheaper on Lambda and builds natively on
# Apple Silicon; the image platform is derived from it so the two cannot drift.
AWS_LAMBDA_ARCH ?= x86_64
IMAGE_PLATFORM = $(if $(filter arm64,$(AWS_LAMBDA_ARCH)),linux/arm64,linux/amd64)
# Every stack carries this tag, and CloudFormation copies it onto each resource
# that supports tags, so Cost Explorer and Resource Groups can find the project.
STACK_TAGS = --tags "PROJECT_NAME=$(PROJECT_NAME)"

# infra/certificate.sh reuses the CLI configured above. CloudFront only reads
# certificates from us-east-1, so that is where the frontend's goes.
CERT = AWS_CLI="$(AWS)" AWS_CERT_REGION=us-east-1 infra/certificate.sh

# $(call stack-output,<stack>,<output key>)
stack-output = $(AWS) cloudformation describe-stacks --stack-name $(1) \
	--query 'Stacks[0].Outputs[?OutputKey==`$(2)`].OutputValue' --output text

# CloudFormation refuses to update a stack that is still busy, and a Lambda in a
# VPC can keep one in *_CLEANUP_IN_PROGRESS for ~20 minutes while its network
# interfaces are released. Wait that out instead of failing.
# $(call stack-outputs,<stack>): every output as "Key<TAB>Value" lines
stack-outputs = $(AWS) cloudformation describe-stacks --stack-name $(1) \
	--query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output text

# $(call wait-stack-idle,<stack>)
wait-stack-idle = while status=$$($(AWS) cloudformation describe-stacks --stack-name $(1) \
		--query 'Stacks[0].StackStatus' --output text 2>/dev/null | tr -d '[:space:]'); \
		case "$$status" in *_IN_PROGRESS) true ;; *) false ;; esac; do \
		echo "$(1) is $$status — waiting for it to settle..."; sleep 30; done

# A stack whose first create failed sits in ROLLBACK_COMPLETE, which
# CloudFormation can only delete. It holds no resources, so clear it and let the
# deploy start over.
# $(call clear-failed-create,<stack>)
clear-failed-create = status=$$($(AWS) cloudformation describe-stacks --stack-name $(1) \
		--query 'Stacks[0].StackStatus' --output text 2>/dev/null | tr -d '[:space:]'); \
		case "$$status" in ROLLBACK_COMPLETE|REVIEW_IN_PROGRESS) \
		echo "$(1) is $$status — deleting it before retrying"; \
		$(AWS) cloudformation delete-stack --stack-name $(1) && \
		$(AWS) cloudformation wait stack-delete-complete --stack-name $(1);; esac

# Fail early and clearly when .env has no credentials in it.
define require-aws-credentials
	@if [ -z "$(AWS_ACCESS_KEY_ID)" ] || [ -z "$(AWS_SECRET_ACCESS_KEY)" ]; then \
		if [ -z "$(AWS_PROFILE)" ]; then \
			echo "AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are empty — set them in .env"; \
			echo "After aws login, pass the profile: make <target> AWS_PROFILE=spry"; \
			exit 1; \
		fi; \
	fi
endef

define require-db-password
	@test -n "$(AWS_DB_PASSWORD)" || { \
		echo "AWS_DB_PASSWORD is empty — set it in .env (8+ chars, [A-Za-z0-9_-] only)"; \
		exit 1; }
endef

.PHONY: help up up-build down down-v logs ps migrate revision seed test lint fmt shell-backend psql \
        aws-whoami aws-deploy aws-deploy-auth aws-auth-env aws-ecr aws-push aws-deploy-backend \
        aws-deploy-backend-express aws-deploy-backend-vpc aws-migrate aws-url aws-status aws-logs \
        aws-frontend-cert aws-deploy-frontend aws-frontend-url aws-deploy-reports report-now report-logs aws-destroy

help:
	@grep -hE '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack
	$(COMPOSE) up

up-build: ## Rebuild images and start the whole stack
	$(COMPOSE) up --build

down: ## Stop the stack
	$(COMPOSE) down

down-v: ## Stop the stack and delete the database volume
	$(COMPOSE) down -v

logs: ## Follow logs from every service
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply database migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add column"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

seed: ## Insert demo meetings for today for one user: make seed owner=<cognito-sub>
	@test -n "$(owner)" || { echo "Usage: make seed owner=<cognito-sub> (the user's sub from the Cognito console)"; exit 1; }
	$(COMPOSE) exec backend python -m app.seed "$(owner)"

test: ## Run the backend test suite against a throwaway database
	$(COMPOSE) exec db psql -U app -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='meetings_test'" | grep -q 1 || \
		$(COMPOSE) exec db createdb -U app meetings_test
	$(COMPOSE) exec -e DATABASE_URL=postgresql+asyncpg://app:app@db:5432/meetings_test backend pytest -q

lint: ## Lint backend and frontend
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec frontend npm run lint

fmt: ## Format the backend code
	$(COMPOSE) exec backend ruff format .

shell-backend: ## Open a shell in the backend container
	$(COMPOSE) exec backend sh

psql: ## Open psql against the application database
	$(COMPOSE) exec db psql -U app -d meetings

aws-whoami: ## Verify the AWS credentials in .env
	$(require-aws-credentials)
	$(AWS) sts get-caller-identity

aws-deploy: ## Deploy everything: sign-in, then the backend, then the frontend built against both
	@$(MAKE) --no-print-directory aws-deploy-auth
	@$(MAKE) --no-print-directory aws-deploy-backend
	@$(MAKE) --no-print-directory aws-deploy-frontend

aws-deploy-auth: ## Create/update the Cognito user pool (email + password; Google when GOOGLE_CLIENT_ID is set)
	$(require-aws-credentials)
	@origins="http://localhost:$(or $(FRONTEND_PORT),3000)"; \
		site=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) 2>/dev/null | tr -d '[:space:]'); \
		case "$$site" in ""|None) ;; *) origins="$$origins,$$site" ;; esac; \
		callbacks=""; logouts=""; \
		oldifs="$$IFS"; IFS=','; \
		for origin in $$origins; do \
			origin="$${origin%/}"; \
			logouts="$${logouts:+$$logouts,}$$origin/"; \
			callbacks="$${callbacks:+$$callbacks,}$$origin/auth/callback/"; \
		done; \
		IFS="$$oldifs"; \
		echo "Callback URLs: $$callbacks"; \
		echo "Logout URLs: $$logouts"; \
		test -n "$(GOOGLE_CLIENT_ID)" || echo "GOOGLE_CLIENT_ID is empty — Continue with Google stays off until you set it and redeploy"; \
		$(call wait-stack-idle,$(AUTH_STACK)); \
		$(call clear-failed-create,$(AUTH_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(AUTH_STACK) \
			--template-file infra/auth.yml \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"CallbackUrls=$$callbacks" \
				"LogoutUrls=$$logouts" \
				"GoogleClientId=$(GOOGLE_CLIENT_ID)" \
				"GoogleClientSecret=$(GOOGLE_CLIENT_SECRET)"
	@echo "Google Cloud → OAuth client (Web application):"; \
		echo "  Authorised JavaScript origin: https://$$($(call stack-output,$(AUTH_STACK),HostedDomain) | tr -d '[:space:]')"; \
		echo "  Authorised redirect URI:      $$($(call stack-output,$(AUTH_STACK),GoogleRedirectUri) | tr -d '[:space:]')"
	@$(MAKE) --no-print-directory aws-auth-env

aws-auth-env: ## Print the Cognito settings to put in .env for local development
	@$(call stack-outputs,$(AUTH_STACK)) | awk -F '\t' ' \
		$$1 == "UserPoolId" { print "COGNITO_USER_POOL_ID=" $$2 } \
		$$1 == "UserPoolClientId" { print "COGNITO_CLIENT_ID=" $$2 } \
		$$1 == "Issuer" { print "COGNITO_ISSUER=" $$2 } \
		$$1 == "HostedDomain" { print "COGNITO_DOMAIN=" $$2 } \
		$$1 == "GoogleEnabled" { print "COGNITO_GOOGLE_ENABLED=" $$2 }' | tr -d '\r'

aws-ecr: ## Create the ECR repository for the backend image
	$(require-aws-credentials)
	$(AWS) cloudformation deploy \
		--stack-name $(ECR_STACK) \
		--template-file infra/ecr.yml \
		--no-fail-on-empty-changeset \
		$(STACK_TAGS) \
		--parameter-overrides "ProjectName=$(PROJECT_NAME)"

aws-push: aws-ecr ## Build the backend Lambda image and push it to ECR
	$(require-aws-credentials)
	@repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		echo "Pushing $$repo:$(IMAGE_TAG) ($(IMAGE_PLATFORM))"; \
		$(AWS) ecr get-login-password | docker login --username AWS --password-stdin "$${repo%%/*}"; \
		docker build --platform $(IMAGE_PLATFORM) --provenance=false \
			-f backend/Dockerfile.lambda -t "$$repo:$(IMAGE_TAG)" ./backend; \
		docker push "$$repo:$(IMAGE_TAG)"

aws-deploy-backend: aws-push ## Deploy the backend, then migrate. Keeps Aurora Express when that is what is already running.
	$(require-aws-credentials)
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) 2>/dev/null | tr -d '[:space:]'); \
		vpc=""; \
		if [ -n "$$fn" ] && [ "$$fn" != "None" ]; then \
			vpc=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
				--query 'VpcConfig.VpcId' --output text 2>/dev/null | tr -d '[:space:]'); \
		fi; \
		if [ -n "$$fn" ] && [ "$$fn" != "None" ] && { [ -z "$$vpc" ] || [ "$$vpc" = "None" ]; }; then \
			echo "The API is Aurora Express (no VPC). Updating that function. A second database is not created."; \
			$(MAKE) --no-print-directory aws-deploy-backend-express; \
		else \
			$(MAKE) --no-print-directory aws-deploy-backend-vpc; \
		fi

aws-deploy-backend-express: ## Update the Aurora Express API. Does not create or replace the database.
	$(require-aws-credentials)
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) | tr -d '[:space:]'); \
		test -n "$$fn" -a "$$fn" != "None" || { echo "No backend function to update"; exit 1; }; \
		url=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.DATABASE_URL' --output text | tr -d '[:space:]'); \
		user=$$(printf '%s' "$$url" | sed -E 's#^postgresql\+asyncpg://([^@]+)@.*#\1#'); \
		host=$$(printf '%s' "$$url" | sed -E 's#^postgresql\+asyncpg://[^@]+@([^:/]+):.*#\1#'); \
		name=$$(printf '%s' "$$url" | sed -E 's#^.*/([^/?]+).*#\1#'); \
		tz=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.APP_TIMEZONE' --output text | tr -d '[:space:]'); \
		cors=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.CORS_ORIGINS' --output text | tr -d '[:space:]'); \
		log=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.LOG_LEVEL' --output text | tr -d '[:space:]'); \
		pool=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.COGNITO_USER_POOL_ID' --output text | tr -d '[:space:]'); \
		client=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.COGNITO_CLIENT_ID' --output text | tr -d '[:space:]'); \
		repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		digest=$$($(AWS) ecr describe-images --repository-name "$${repo#*/}" \
			--image-ids imageTag=$(IMAGE_TAG) --query 'imageDetails[0].imageDigest' \
			--output text | tr -d '[:space:]'); \
		test -n "$$digest" -a "$$digest" != "None" || { echo "No image in ECR — run: make aws-push"; exit 1; }; \
		echo "express host=$$host db=$$name user=$$user image=$$repo@$$digest arch=$(AWS_LAMBDA_ARCH)"; \
		$(call wait-stack-idle,$(APP_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(APP_STACK) \
			--template-file infra/backend-express.yml \
			--capabilities CAPABILITY_IAM \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				ImageUri="$$repo@$$digest" \
				"Architecture=$(AWS_LAMBDA_ARCH)" \
				"DatabaseHost=$$host" \
				"DatabaseName=$$name" \
				"DatabaseUser=$$user" \
				"AppTimezone=$$tz" \
				"CorsOrigins=$$cors" \
				"LogLevel=$$log" \
				"CognitoUserPoolId=$$pool" \
				"CognitoClientId=$$client"
	@$(MAKE) --no-print-directory aws-migrate
	@$(MAKE) --no-print-directory aws-url

aws-deploy-backend-vpc: ## Create or update the private-VPC backend (Lambda + Aurora Serverless), then migrate
	$(require-aws-credentials)
	$(require-db-password)
	@pool=$$($(call stack-output,$(AUTH_STACK),UserPoolId) 2>/dev/null | tr -d '[:space:]'); \
		client=$$($(call stack-output,$(AUTH_STACK),UserPoolClientId) | tr -d '[:space:]'); \
		issuer=$$($(call stack-output,$(AUTH_STACK),Issuer) | tr -d '[:space:]'); \
		case "$$pool" in ""|None) echo "No user pool found — run: make aws-deploy-auth"; exit 1 ;; esac; \
		jwks=$$(curl -fsS "$$issuer/.well-known/jwks.json" | base64 | tr -d '\n'); \
		test -n "$$jwks" || { echo "Could not download $$issuer/.well-known/jwks.json"; exit 1; }; \
		vpc=$$($(AWS) ec2 describe-vpcs --filters Name=isDefault,Values=true \
		--query 'Vpcs[0].VpcId' --output text | tr -d '[:space:]'); \
		test "$$vpc" != "None" -a -n "$$vpc" || { \
			echo "No default VPC in $(AWS_REGION) — pass VpcId/SubnetIds yourself"; exit 1; }; \
		subnets=$$($(AWS) ec2 describe-subnets \
			--filters Name=vpc-id,Values=$$vpc Name=default-for-az,Values=true \
			--query 'Subnets[].SubnetId' --output text | tr '[:space:]' ',' | sed 's/,*$$//'); \
		repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		digest=$$($(AWS) ecr describe-images --repository-name "$${repo#*/}" \
			--image-ids imageTag=$(IMAGE_TAG) --query 'imageDetails[0].imageDigest' \
			--output text | tr -d '[:space:]'); \
		cors="$(AWS_CORS_ORIGINS)"; \
		if [ -z "$$cors" ]; then \
			cors=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) 2>/dev/null | tr -d '[:space:]'); \
			case "$$cors" in ""|None) cors='*' ;; esac; \
		fi; \
		echo "vpc=$$vpc subnets=$$subnets image=$$repo@$$digest cors=$$cors"; \
		echo "This takes ~15 minutes the first time (Aurora is the slow part)."; \
		$(call wait-stack-idle,$(APP_STACK)); \
		$(call clear-failed-create,$(APP_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(APP_STACK) \
			--template-file infra/backend.yml \
			--capabilities CAPABILITY_IAM \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"VpcId=$$vpc" \
				"SubnetIds=$$subnets" \
				ImageUri="$$repo@$$digest" \
				"Architecture=$(AWS_LAMBDA_ARCH)" \
				"DbPassword=$(AWS_DB_PASSWORD)" \
				"AppTimezone=$(APP_TIMEZONE)" \
				"CorsOrigins=$$cors" \
				"CognitoUserPoolId=$$pool" \
				"CognitoClientId=$$client" \
				"CognitoJwks=$$jwks"
	@$(MAKE) --no-print-directory aws-migrate
	@$(MAKE) --no-print-directory aws-url

aws-migrate: ## Apply database migrations (invokes the backend function directly)
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) | tr -d '[:space:]'); \
		echo "Migrating ($$fn)"; \
		err=$$($(AWS) lambda invoke --function-name "$$fn" \
			--cli-binary-format raw-in-base64-out --payload '{"action":"migrate"}' \
			--query FunctionError --output text /dev/null | tr -d '[:space:]'); \
		test "$$err" = "None" || { echo "Migration failed ($$err) — see make aws-logs"; exit 1; }

aws-url: ## Print the deployed API URL
	@$(call stack-output,$(APP_STACK),ApiUrl)

aws-status: ## Show the stack outputs and the API function's state
	@$(AWS) cloudformation describe-stacks --stack-name $(APP_STACK) \
		--query 'Stacks[0].Outputs' --output table
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) | tr -d '[:space:]'); \
		$(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query '{state:State,lastUpdate:LastUpdateStatus,arch:Architectures[0],memory:MemorySize}' \
			--output table

aws-logs: ## Follow the backend function logs
	$(AWS) logs tail /aws/lambda/$(PROJECT_NAME)-backend --follow

aws-frontend-cert: ## Request and validate the HTTPS certificate for AWS_FRONTEND_DOMAIN (in us-east-1)
	$(require-aws-credentials)
	@test -n "$(AWS_FRONTEND_DOMAIN)" || { \
		echo "AWS_FRONTEND_DOMAIN is empty — set it in .env (e.g. app.example.com)"; exit 1; }
	@$(CERT) ensure "$(AWS_FRONTEND_DOMAIN)"

aws-deploy-frontend: ## Deploy the frontend to S3 + CloudFront, built against the deployed backend URL
	$(require-aws-credentials)
	@api=$$($(call stack-output,$(APP_STACK),ApiUrl) 2>/dev/null | tr -d '[:space:]'); \
		test -n "$$api" -a "$$api" != "None" || { \
			echo "No backend API found — run: make aws-deploy-backend"; exit 1; }; \
		domain=""; \
		if [ -n "$(AWS_FRONTEND_DOMAIN)" ]; then \
			cert=$$($(CERT) find "$(AWS_FRONTEND_DOMAIN)"); \
			test -n "$$cert" || { \
				echo "No issued us-east-1 certificate for $(AWS_FRONTEND_DOMAIN) — run: make aws-frontend-cert"; \
				exit 1; }; \
			zone=$$($(CERT) zone "$(AWS_FRONTEND_DOMAIN)"); \
			domain="DomainName=$(AWS_FRONTEND_DOMAIN) CertificateArn=$$cert HostedZoneId=$$zone"; \
			echo "custom domain: $(AWS_FRONTEND_DOMAIN) (Route 53 zone: $${zone:-none})"; \
		fi; \
		$(call wait-stack-idle,$(FRONTEND_STACK)); \
		$(call clear-failed-create,$(FRONTEND_STACK)); \
		echo "A new CloudFront distribution takes ~5 minutes to come up."; \
		$(AWS) cloudformation deploy \
			--stack-name $(FRONTEND_STACK) \
			--template-file infra/frontend.yml \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"PricingPlan=$(or $(AWS_CLOUDFRONT_PLAN),FREE)" \
				$$domain
	@# Now that the site's URL exists, let Cognito redirect back to it.
	@$(MAKE) --no-print-directory aws-deploy-auth
	@api=$$($(call stack-output,$(APP_STACK),ApiUrl) | tr -d '[:space:]'); \
		auth=$$($(call stack-outputs,$(AUTH_STACK)) | tr -d '\r'); \
		auth_out() { printf '%s\n' "$$auth" | awk -F '\t' -v k="$$1" '$$1 == k { print $$2 }'; }; \
		bucket=$$($(call stack-output,$(FRONTEND_STACK),BucketName) | tr -d '[:space:]'); \
		dist=$$($(call stack-output,$(FRONTEND_STACK),DistributionId) | tr -d '[:space:]'); \
		site=$$($(call stack-output,$(FRONTEND_STACK),SiteUrl) | tr -d '[:space:]'); \
		site="$${site%/}"; \
		echo "Building the static export against $$api (sign-in returns to $$site/auth/callback/)"; \
		rm -rf frontend/out; \
		docker build --target export --output type=local,dest=frontend/out \
			--build-arg NEXT_PUBLIC_API_BASE_URL="$$api" \
			--build-arg NEXT_PUBLIC_COGNITO_AUTHORITY="$$(auth_out Issuer)" \
			--build-arg NEXT_PUBLIC_COGNITO_CLIENT_ID="$$(auth_out UserPoolClientId)" \
			--build-arg NEXT_PUBLIC_COGNITO_DOMAIN="$$(auth_out HostedDomain)" \
			--build-arg NEXT_PUBLIC_COGNITO_REDIRECT_URI="$$site/auth/callback/" \
			--build-arg NEXT_PUBLIC_COGNITO_LOGOUT_URI="$$site/" \
			./frontend || exit 1; \
		echo "Uploading to s3://$$bucket"; \
		$(AWS) s3 sync frontend/out "s3://$$bucket" --delete --exclude "*.html" \
			--cache-control "public,max-age=31536000,immutable" --only-show-errors || exit 1; \
		$(AWS) s3 sync frontend/out "s3://$$bucket" --delete --exclude "*" --include "*.html" \
			--cache-control "no-cache" --only-show-errors || exit 1; \
		$(AWS) cloudfront create-invalidation --distribution-id "$$dist" --paths "/*" \
			--query 'Invalidation.Status' --output text
	@$(MAKE) --no-print-directory aws-frontend-url
	@if [ -z "$(AWS_CORS_ORIGINS)" ]; then \
		allowed=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) | tr -d '[:space:]'); \
		fn=$$($(call stack-output,$(APP_STACK),FunctionName) | tr -d '[:space:]'); \
		current=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.CORS_ORIGINS' --output text | tr -d '[:space:]'); \
		test "$$current" = "$$allowed" || echo "The API still allows CORS_ORIGINS=$$current — run make aws-deploy-backend to limit it to $$allowed"; \
	fi
	@if [ -n "$(AWS_FRONTEND_DOMAIN)" ] && [ -z "$$($(CERT) zone "$(AWS_FRONTEND_DOMAIN)")" ]; then \
		echo "Point $(AWS_FRONTEND_DOMAIN) at the distribution: CNAME $$($(call stack-output,$(FRONTEND_STACK),DistributionDomain) | tr -d '[:space:]')"; \
	fi

aws-frontend-url: ## Print the deployed site URL
	@$(call stack-output,$(FRONTEND_STACK),SiteUrl)

aws-deploy-reports: ## Deploy the weekly report (queue, schedule, builder, mailer, SES)
	$(require-aws-credentials)
	@test -n "$(REPORT_RECIPIENT)" || { \
		echo "REPORT_RECIPIENT is empty — set it in .env (the inbox that receives the report)"; exit 1; }
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) 2>/dev/null | tr -d '[:space:]'); \
		test -n "$$fn" -a "$$fn" != "None" || { echo "No backend function — run: make aws-deploy-backend"; exit 1; }; \
		vpc=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'VpcConfig.VpcId' --output text | tr -d '[:space:]'); \
		net=""; \
		if [ -z "$$vpc" ] || [ "$$vpc" = "None" ]; then \
			echo "Aurora Express: the builder stays outside a VPC, same as the API."; \
		else \
			subnets=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
				--query 'VpcConfig.SubnetIds' --output text | tr '[:space:]' ',' | sed 's/,*$$//'); \
			sg=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
				--query 'VpcConfig.SecurityGroupIds[0]' --output text | tr -d '[:space:]'); \
			tables=$$($(AWS) ec2 describe-route-tables --filters Name=vpc-id,Values=$$vpc \
				--query 'RouteTables[].RouteTableId' --output text | tr '[:space:]' ',' | sed 's/,*$$//'); \
			endpoint=$$($(AWS) ec2 describe-vpc-endpoints \
				--filters Name=vpc-id,Values=$$vpc Name=service-name,Values=com.amazonaws.$(AWS_REGION).s3 \
				Name=vpc-endpoint-type,Values=Gateway \
				--query 'VpcEndpoints[?State==`available` || State==`pending`].VpcEndpointId | [0]' \
				--output text | tr -d '[:space:]'); \
			create_endpoint=true; \
			if [ -n "$$endpoint" ] && [ "$$endpoint" != "None" ]; then \
				create_endpoint=false; \
				echo "S3 gateway endpoint already exists ($$endpoint) — not creating another"; \
			fi; \
			net="VpcId=$$vpc SubnetIds=$$subnets SecurityGroupId=$$sg RouteTableIds=$$tables CreateS3Endpoint=$$create_endpoint"; \
			echo "vpc=$$vpc subnets=$$subnets sg=$$sg"; \
		fi; \
		dburl=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.DATABASE_URL' --output text | tr -d '[:space:]'); \
		iam=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.DATABASE_IAM_AUTH' --output text | tr -d '[:space:]'); \
		case "$$iam" in true|True|TRUE) iam=true ;; *) iam=false ;; esac; \
		tz=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.APP_TIMEZONE' --output text | tr -d '[:space:]'); \
		case "$$tz" in ""|None) tz="$(or $(APP_TIMEZONE),Europe/Kyiv)" ;; esac; \
		repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		digest=$$($(AWS) ecr describe-images --repository-name "$${repo#*/}" \
			--image-ids imageTag=$(IMAGE_TAG) --query 'imageDetails[0].imageDigest' \
			--output text | tr -d '[:space:]'); \
		test -n "$$digest" -a "$$digest" != "None" || { echo "No image in ECR — run: make aws-push"; exit 1; }; \
		echo "image=$$repo@$$digest arch=$(AWS_LAMBDA_ARCH)"; \
		echo "If you changed Python since the last push, run make aws-push first. This target does not rebuild the image."; \
		$(call wait-stack-idle,$(REPORTS_STACK)); \
		$(call clear-failed-create,$(REPORTS_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(REPORTS_STACK) \
			--template-file infra/reports.yml \
			--capabilities CAPABILITY_IAM \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				$$net \
				"ImageUri=$$repo@$$digest" \
				"Architecture=$(AWS_LAMBDA_ARCH)" \
				"DatabaseUrl=$$dburl" \
				"DatabaseIamAuth=$$iam" \
				"AppTimezone=$$tz" \
				"SenderDomain=$(REPORT_SENDER_DOMAIN)" \
				"RecipientEmail=$(REPORT_RECIPIENT)" \
				"ReportFailWeek=$(REPORT_FAIL_WEEK)" \
				"ScheduleExpression=$(or $(SCHEDULE_EXPRESSION),cron(0 7 ? * MON *))"
	@echo ""; \
		if [ -n "$(REPORT_SENDER_DOMAIN)" ]; then \
			echo "Add these three CNAME records at the DNS host for $(REPORT_SENDER_DOMAIN)."; \
			echo "SES becomes Verified a few minutes after they resolve."; \
			$(call stack-outputs,$(REPORTS_STACK)) | awk -F '\t' ' \
				$$1 ~ /^DkimName/ { name[substr($$1, 9)] = $$2 } \
				$$1 ~ /^DkimValue/ { value[substr($$1, 10)] = $$2 } \
				END { for (i = 1; i <= 3; i++) if (name[i] != "") print "  " name[i] "  ->  " value[i] }'; \
			echo "The report is sent from reports@$(REPORT_SENDER_DOMAIN)."; \
		else \
			echo "No domain is set. The report is sent from $(REPORT_RECIPIENT)."; \
			echo "There are no DKIM records to add."; \
		fi; \
		echo ""; \
		echo "Two messages arrive at $(REPORT_RECIPIENT). Open both and confirm:"; \
		echo "  1. Amazon SES — verify this address (the sandbox can only send to verified recipients)."; \
		echo "  2. AWS Notification — confirm the dead-letter alarm. Until you do, a failed report emails nobody."; \
		bucket=$$($(call stack-output,$(REPORTS_STACK),ReportsBucketName) | tr -d '[:space:]'); \
		echo "After a report: aws s3 ls s3://$$bucket/reports/ --recursive"

report-now: ## Queue one report: make report-now WEEK=2026-W41
	$(require-aws-credentials)
	@printf '%s\n' "$(WEEK)" | grep -Eq '^[0-9]{4}-W[0-9]{1,2}$$' || { \
		echo "Usage: make report-now WEEK=2026-W41"; exit 1; }
	@url=$$($(call stack-output,$(REPORTS_STACK),ReportQueueUrl) | tr -d '[:space:]'); \
		echo "Queueing week $(WEEK)"; \
		$(AWS) sqs send-message --queue-url "$$url" \
			--message-body '{"week":"$(WEEK)","source":"manual"}' \
			--query MessageId --output text

report-logs: ## Show recent builder and mailer log lines
	$(require-aws-credentials)
	@$(AWS) logs tail /aws/lambda/$(PROJECT_NAME)-report-builder --since 30m --format short
	@$(AWS) logs tail /aws/lambda/$(PROJECT_NAME)-report-mailer --since 30m --format short

aws-destroy: ## Delete every stack, including the database and its data
	$(require-aws-credentials)
	@printf 'Delete %s, %s, %s, %s and %s? The Aurora cluster and all its data, and every user account, go with them (no snapshot). Type yes: ' \
		"$(REPORTS_STACK)" "$(FRONTEND_STACK)" "$(APP_STACK)" "$(AUTH_STACK)" "$(ECR_STACK)"; \
		read answer; test "$$answer" = "yes" || { echo "Aborted."; exit 1; }
	@bucket=$$($(call stack-output,$(FRONTEND_STACK),BucketName) 2>/dev/null | tr -d '[:space:]'); \
		if [ -n "$$bucket" ] && [ "$$bucket" != "None" ]; then \
			echo "Emptying s3://$$bucket"; \
			$(AWS) s3 rm "s3://$$bucket" --recursive --only-show-errors || true; \
		fi
	-$(AWS) cloudformation delete-stack --stack-name $(FRONTEND_STACK)
	-$(AWS) cloudformation wait stack-delete-complete --stack-name $(FRONTEND_STACK)
	@if $(AWS) cloudformation describe-stacks --stack-name $(REPORTS_STACK) >/dev/null 2>&1; then \
		reports_bucket=$$($(call stack-output,$(REPORTS_STACK),ReportsBucketName) | tr -d '[:space:]'); \
		if [ -n "$$reports_bucket" ] && [ "$$reports_bucket" != "None" ]; then \
			echo "Emptying s3://$$reports_bucket"; \
			$(AWS) s3 rm "s3://$$reports_bucket" --recursive --only-show-errors || true; \
		fi; \
		echo "Deleting $(REPORTS_STACK)"; \
		$(AWS) cloudformation delete-stack --stack-name $(REPORTS_STACK); \
		$(AWS) cloudformation wait stack-delete-complete --stack-name $(REPORTS_STACK); \
	fi
	@echo "Deleting $(APP_STACK) — Lambda releases its VPC network interfaces slowly, allow ~20 minutes."
	$(AWS) cloudformation delete-stack --stack-name $(APP_STACK)
	$(AWS) cloudformation wait stack-delete-complete --stack-name $(APP_STACK)
	$(AWS) cloudformation delete-stack --stack-name $(AUTH_STACK)
	$(AWS) cloudformation wait stack-delete-complete --stack-name $(AUTH_STACK)
	$(AWS) cloudformation delete-stack --stack-name $(ECR_STACK)
	$(AWS) cloudformation wait stack-delete-complete --stack-name $(ECR_STACK)
	@echo "All stacks deleted."
