"""Application settings, loaded from the environment."""

from functools import lru_cache
from zoneinfo import ZoneInfo

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://app:app@db:5432/meetings"
    # When true (Aurora Express on the AWS free plan), connections use an IAM
    # auth token as the password. Host/user/db still come from database_url.
    database_iam_auth: bool = False
    aws_region: str = "eu-north-1"
    app_timezone: str = "Europe/Kyiv"
    cors_origins: str = "http://localhost:3000"
    log_level: str = "INFO"
    # Weekly-report button writes requests/<id>.json here. Empty locally, so
    # the button answers 503 until the reports stack is deployed.
    reports_bucket: str = ""
    run_migrations_on_start: bool = True
    version: str = Field(default="1.0.0")

    # Cognito user pool whose access tokens the API accepts. Empty pool id means
    # authentication is not configured, and every meetings request is refused.
    cognito_region: str = "eu-north-1"
    cognito_user_pool_id: str = ""
    cognito_client_id: str = ""
    # The pool's signing keys (JSON, or that JSON base64-encoded). The Lambda
    # runs in a VPC without internet access, so the deploy passes them in; when
    # empty they are fetched from Cognito on first use.
    cognito_jwks: str = ""
    # Claude inference-profile id for the agenda parser (Bedrock Converse).
    # Opus/Haiku 5.5 are listed but not invokable on this Free project; Sonnet 4.6 works.
    # Override with PARSER_MODEL=... to compare models when access opens.
    parser_model: str = "eu.anthropic.claude-sonnet-4-6"

    @field_validator("app_timezone")
    @classmethod
    def _validate_timezone(cls, value: str) -> str:
        ZoneInfo(value)  # raises for an unknown timezone
        return value

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.app_timezone)

    @property
    def cognito_issuer(self) -> str:
        return (
            f"https://cognito-idp.{self.cognito_region}.amazonaws.com/{self.cognito_user_pool_id}"
        )

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
