"""Database engine, session factory and the FastAPI session dependency."""

from collections.abc import AsyncIterator
from urllib.parse import urlparse

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


class Base(DeclarativeBase):
    """Declarative base for every ORM model."""


def _iam_token(hostname: str, port: int, username: str) -> str:
    import boto3

    return boto3.client("rds", region_name=settings.aws_region).generate_db_auth_token(
        DBHostname=hostname,
        Port=port,
        DBUsername=username,
        Region=settings.aws_region,
    )


def make_engine(url: str | None = None):
    """Build the async engine. Local compose uses a password URL; Aurora Express uses IAM."""
    url = url or settings.database_url
    connect_args: dict = {}
    if settings.database_iam_auth:
        connect_args["ssl"] = True
    engine = create_async_engine(
        url,
        echo=False,
        pool_pre_ping=True,
        connect_args=connect_args,
    )
    if settings.database_iam_auth:
        parsed = urlparse(url.replace("postgresql+asyncpg://", "postgresql://", 1))
        host = parsed.hostname or ""
        port = parsed.port or 5432
        user = parsed.username or "postgres"

        @event.listens_for(engine.sync_engine, "do_connect")
        def _set_iam_password(dialect, conn_rec, cargs, cparams):  # noqa: ARG001
            cparams["password"] = _iam_token(host, port, user)

    return engine


engine = make_engine()
SessionFactory = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """Yield a session and roll back if the request handler raises."""
    async with SessionFactory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
