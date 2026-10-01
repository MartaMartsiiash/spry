# PROJECT.md — Spry (SuccessfulSuccess)

This file is the structure-and-contract specification for this monorepo.
It contains no implementation code. `SPEC.md` is the longer product
spec this tree was built from; if the two disagree, the running code
and this file must be brought back in line.

The product name in Lab 1 was Spry. This repository was cloned from the
course template `SuccessfulSuccess` and published as our own GitHub
remote. Folder names and image names still use SuccessfulSuccess.

Local development starts with one command after Docker Desktop is
installed: copy `.env.example` to `.env`, then `docker compose up --build`.
Sign-in still needs a Cognito user pool (`make aws-deploy-auth` and
`make aws-auth-env`); without those values every `/api/v1` request is
refused.

## Repository layout

```
SuccessfulSuccess/
├── PROJECT.md              this file: structure and contracts
├── DECISIONS.md            why this is one repository, not three
├── SPEC.md                 full product spec (behaviour, UI, tests)
├── README.md               how to run, seed, lint, and deploy
├── Makefile                local and AWS targets; CI should call the same recipes
├── make.cmd                Windows wrapper so `make` works without GNU make first
├── docker-compose.yml      db + backend + frontend for the laptop
├── .env.example            every variable, with safe local defaults; never commit `.env`
├── .gitignore
├── .gitattributes          LF checkouts (CRLF would break `entrypoint.sh`)
├── .dockerignore
├── .github/workflows/
│   └── style.yml           ruff + ESLint on every push to main
├── infra/                  CloudFormation; not used by `docker compose up`
│   ├── auth.yml            Cognito user pool
│   ├── ecr.yml             container registry for the backend image
│   ├── backend.yml         API + database on AWS
│   ├── frontend.yml        S3 + CloudFront
│   └── certificate.sh      ACM certificate for a custom frontend domain
├── backend/                FastAPI service
│   ├── Dockerfile          python:3.12-slim image; uv installs from the lockfile
│   ├── pyproject.toml      runtime and dev dependencies
│   ├── uv.lock             exact Python versions
│   ├── alembic.ini
│   ├── entrypoint.sh       `alembic upgrade head`, then the container CMD
│   ├── alembic/
│   │   ├── env.py          Alembic ↔ DATABASE_URL and the ORM metadata
│   │   └── versions/       0001 meetings; 0002 users + meeting.owner_id
│   ├── tests/              pytest against a real Postgres
│   └── app/
│       ├── main.py         FastAPI app, CORS, routers, GET /health
│       ├── config.py       settings from the environment
│       ├── db.py           async engine, session, pool_pre_ping
│       ├── auth.py         Cognito JWT; CurrentUser for /api/v1
│       ├── errors.py       one error envelope for every non-2xx
│       ├── lambda_handler.py  AWS Lambda adapter (Mangum); unused locally
│       ├── seed.py         `python -m app.seed <cognito-sub>`
│       ├── models/         SQLAlchemy tables (Meeting, Participant, User)
│       ├── schemas/        Pydantic request/response shapes
│       ├── repositories/   SQL only
│       ├── services/       business rules (day window, ownership)
│       └── api/
│           ├── deps.py     session + current user → services
│           └── v1/         HTTP: /api/v1/meetings, /api/v1/me
└── frontend/               Next.js app
    ├── Dockerfile          node:22-alpine; compose uses the `dev` target
    ├── package.json
    ├── package-lock.json   exact JS versions (`npm ci`)
    ├── next.config.ts
    ├── tsconfig.json
    ├── components.json     shadcn/ui
    ├── postcss.config.mjs
    ├── app/
    │   ├── layout.tsx      root shell
    │   ├── page.tsx        `/` — sign-in
    │   ├── globals.css     Tailwind v4 + Canva tokens
    │   └── (app)/          signed-in routes (RequireAuth)
    │       ├── layout.tsx
    │       ├── today/page.tsx          today's meetings
    │       └── meetings/new/page.tsx   create dialog already open
    ├── components/         pages, dialogs, shadcn `ui/`
    ├── hooks/              TanStack Query wrappers
    └── lib/                api.ts (the only HTTP client), types, auth, datetime
```

Uncommitted trees (`node_modules/`, `.venv/`, `.env`, `.next/`) belong in
`.gitignore`, not in this layout.

### Why the backend is split this way

HTTP lives in `api/`, persistence in `models/` + `repositories/`, rules in
`services/`. Putting them in one file would mix request parsing with SQL
and with “what is today”, so a contract change would not have an obvious
home. `schemas/` is the JSON contract; ORM types stay separate.

## Versions (pinned)

| Component | Version |
|---|---|
| Backend base image | `python:3.12-slim` |
| Frontend base image | `node:22-alpine` |
| Database image | `postgres:17-alpine` |
| Python | 3.12 (requires-python `>=3.12`) |
| FastAPI | `>=0.115.0` (locked in `uv.lock`) |
| SQLAlchemy | 2.x async (`sqlalchemy[asyncio]>=2.0.30`) |
| DB driver | asyncpg |
| Alembic | `>=1.13.0` |
| Uvicorn | `>=0.30.0` |
| Pydantic | v2 |
| pytest / ruff | pytest `>=8.2`; CI runs `ruff@0.16.6` |
| Next.js | 16.3.4 |
| React | 19.2.8 |
| TypeScript | 5.x (`strict`) |
| Tailwind CSS | 4.x (`@tailwindcss/postcss`) |
| shadcn/ui | Radix + `components/ui/*` |

Compose and Dockerfiles do not use `python:latest` or `postgres:latest`.
Python and JS exact versions are the lockfiles, not floating tags on
images. The backend Dockerfile currently copies `ghcr.io/astral-sh/uv:latest`
to install the package manager; that tag is the one `latest` still in
the tree and should be pinned when we next touch the image.

## Services in docker-compose.yml

| Service | Image / build | Host port (default) | Depends on | Ready when |
|---|---|---|---|---|
| `db` | `image: postgres:17-alpine` | 5432 (`POSTGRES_PORT`) | none | healthcheck `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB` succeeds |
| `backend` | `build: ./backend` (`INSTALL_DEV=true`) | 8000 (`BACKEND_PORT`) | `db`, `condition: service_healthy` | healthcheck: `GET /health` returns 200 (`curl` in the image) |
| `frontend` | `build: ./frontend`, target `dev` | 3000 (`FRONTEND_PORT`) | `backend`, `condition: service_started` | Next.js answers on 3000 |

- Container ports are fixed (5432, 8000, 3000). Only the host mapping is
  configurable. If `BACKEND_PORT` or `FRONTEND_PORT` change,
  `NEXT_PUBLIC_API_BASE_URL` and `CORS_ORIGINS` must change with them.
- `db` keeps data in the named volume `pgdata`.
- `depends_on` without a health condition only orders process start.
  Postgres is not ready when its process exists; the backend waits for
  `service_healthy`. The frontend waits only until the backend
  *process* has started (`service_started`), not until `/health` is 200 —
  the first page load can still race a slow migration.
- Migrations run in `entrypoint.sh` at **container start**
  (`alembic upgrade head`), then the CMD (uvicorn). They never run at
  **build** time: the build has no database. Compose overrides the CMD
  with `--reload` for local development.
- `RUN_MIGRATIONS_ON_START` (default `true`) can skip the upgrade.
- Bind mounts (`./backend:/app`, `./frontend:/app`) and `--reload` /
  `next dev` are **development only**. Production would drop the mounts
  and serve a built artefact (frontend `production` / `export` Docker
  targets; backend image without `--reload`).
- Frontend anonymous volumes keep `node_modules` and `.next` from being
  hidden by the bind mount.
- The browser calls `NEXT_PUBLIC_API_BASE_URL` (default
  `http://localhost:8000`), a host address, not the compose service
  name `backend`. CORS on the API must list the frontend origin
  (`CORS_ORIGINS`, default `http://localhost:3000`).
- `DATABASE_URL` uses driver `postgresql+asyncpg` and hostname `db`.
- If Postgres disappears after startup, the backend process stays up.
  `pool_pre_ping` checks connections before use; `GET /health` returns
  503 until the database answers again. Compose cannot help after boot.

## Data model

PostgreSQL 17. Schema only via Alembic (never `Base.metadata.create_all`
on a database that already has rows).

**users** — one row per Cognito account (`id` = Cognito `sub`).

**meetings**

| Column | Type | Rules |
|---|---|---|
| id | UUID | PK, server-generated |
| owner_id | string, FK → users.id | from the access token, never from the body; `ON DELETE CASCADE` |
| name | varchar(200) | required, trimmed, non-blank |
| description | text | optional, ≤ 2000 |
| location | varchar(200) | optional |
| starts_at | timestamptz | required, stored UTC |
| ends_at | timestamptz | required, `CHECK (ends_at > starts_at)` |
| created_at / updated_at | timestamptz | server-generated |

**participants** — composition: they do not exist outside a meeting.

| Column | Type | Rules |
|---|---|---|
| id | UUID | PK |
| meeting_id | UUID | FK, `ON DELETE CASCADE` |
| name | varchar(120) | required, trimmed |
| email | varchar(255) | optional, valid email |
| position | int | 0-based order |

Invariants: 0–50 participants; no duplicate (name, email) in one meeting.

## API contract

Base path `/api/v1`. Content-Type `application/json`.

Timestamps in requests must include a timezone (`Z` or an offset);
naive datetimes are `422`. Responses re-serialize every datetime into
`APP_TIMEZONE` (default `Europe/Kyiv`) so every client shows the same
wall clock as the “today” window.

### Auth

Every `/api/v1` route needs `Authorization: Bearer <Cognito access token>`.
Missing/invalid token → `401` with the error envelope below.
Empty `COGNITO_USER_POOL_ID` / `COGNITO_CLIENT_ID` → `503` (sign-in not
configured). A user never sees, edits or deletes another user’s meeting
(`404`). `GET /health` is public.

### Error envelope (every non-2xx)

```json
{
  "error": {
    "code": "validation_error",
    "message": "must be later than starts_at",
    "details": [{ "field": "ends_at", "message": "must be later than starts_at" }]
  }
}
```

Codes: `unauthorized` (401), `not_found` (404), `validation_error` (422),
`service_unavailable` (503), `internal_error` (500). FastAPI’s default
`{"detail": ...}` must not leak.

### Meeting object (`MeetingRead`)

```json
{
  "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "name": "Sprint planning",
  "description": "Plan the next two weeks",
  "location": "Room 3",
  "starts_at": "2026-09-10T10:00:00+03:00",
  "ends_at": "2026-09-10T11:00:00+03:00",
  "participants": [
    { "id": "…", "name": "Ostap", "email": "ostap@example.com", "position": 0 }
  ],
  "created_at": "2026-09-09T18:20:11+03:00",
  "updated_at": "2026-09-09T18:20:11+03:00"
}
```

Create/replace body: `name`, `starts_at`, `ends_at` required;
`description`, `location`, `participants` optional (`id` is not accepted).
`participants[]` is `{ "name": "…", "email": "…" }` (email optional).

### `GET /health`

- `200`: `{"status": "ok", "database": "ok", "version": "1.0.0"}` after `SELECT 1`.
- `503`: database unreachable (same envelope as other errors).
- Used by the compose healthcheck; later by a load balancer.

### `GET /api/v1/meetings`

Query: `date` (`YYYY-MM-DD`, default today in `APP_TIMEZONE`), `q`
(substring on name/description), `limit` (1–500, default 100), `offset` (≥ 0).

A meeting **overlaps** day D when `starts_at < end_of_D` and
`ends_at > start_of_D` in `APP_TIMEZONE` (then converted to UTC). A
meeting that crosses midnight appears on both days.

Order: `starts_at ASC`, then `name ASC`.

`200`:

```json
{
  "items": [ "…MeetingRead…" ],
  "total": 1,
  "limit": 100,
  "offset": 0,
  "date": "2026-09-10"
}
```

An empty day is `"items": []`, `"total": 0`.

### `GET /api/v1/meetings/{id}`

`200` `MeetingRead`; `404` if missing or not owned by the caller.

### `POST /api/v1/meetings`

`201` `MeetingRead` plus `Location: /api/v1/meetings/{id}`.
`422` for blank/too-long name, datetime without offset, `ends_at` not
after `starts_at`, too many or duplicate participants.

### `PUT /api/v1/meetings/{id}`

Same body as POST; replaces fields and the whole participant list.
`200` `MeetingRead`; `404` / `422` as above.

### `DELETE /api/v1/meetings/{id}`

`204` empty body; participants cascade. `404` if missing or not owned.

### `GET /api/v1/me`

`200` profile (`UserRead`: `id`, `email`, names, `picture_url`,
`auth_provider`, timestamps).

### `POST /api/v1/me/sync`

Body: `{ "id_token": "…" }` (Cognito ID token, same user as the access
token). Upserts `users`. `401` if the ID token is invalid or for another `sub`.

## Frontend behaviour

- `/` is sign-in (Cognito email/password; Google when configured).
- `/today` is the list the lab screenshot needs: meetings overlapping
  today (name, description, participants) and a form/dialog to add one.
- `/meetings/new` is the same screen with the create dialog open.
- `lib/api.ts` is the only module that calls the backend; it sends the
  access token and maps the error envelope to `ApiError`.
- After a successful create the list and the header nav refresh from the
  same TanStack Query cache (no optimistic insert).
- Reloading the page keeps meetings: they live in Postgres, keyed by user.

## Tests and CI

Backend tests (`make test`) hit a real Postgres and cover create/list/
update/delete, the today window, the error envelope, 401 without a
token, and isolation between users. Frontend has no automated tests;
`npm run lint` and `npm run build` must pass.

`.github/workflows/style.yml` runs on push to `main`: ruff in
`backend/`, ESLint in `frontend/` after `npm ci`. It is CI (check),
not yet CD (deploy).

## AWS (already in the tree; not started by compose)

`infra/` plus `make aws-*` is the deploy contract: Cognito, ECR, the
API, S3 + CloudFront. Access keys stay in `.env`, never in git.
OIDC for GitHub and a custom domain for both services are later lab
steps; this file does not invent extra services (no Redis, no queue,
no Kubernetes, no second database).

## Out of scope for the product

Recurring meetings, invitations, email, calendar sync, WebSockets,
per-user timezone, a dark-mode toggle. Other calendar days are in the
API (`?date=`) but not as first-class UI navigation.
