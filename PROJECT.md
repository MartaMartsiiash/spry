# PROJECT.md — Spry

Spry is a monorepo. This file describes its structure and the contracts
between parts. It contains no implementation code. Everything in the
repository is generated from this file, so an error here is an error
everywhere.

## Repository layout

```
spry/
├── PROJECT.md            this file: the specification
├── DECISIONS.md          why the repo is a monorepo
├── make.cmd              Windows wrapper for GNU make (inherited from the course template)
├── docker-compose.yml    postgres + backend + frontend for local development
├── .env.example          every environment variable, with safe local values
├── .gitignore
├── .dockerignore         keeps node_modules, .venv, .git and .env out of build contexts
├── backend/              FastAPI service
│   ├── Dockerfile        image for the backend
│   ├── requirements.txt  pinned Python dependencies (runtime and pytest)
│   ├── alembic.ini       Alembic configuration
│   ├── alembic/          migrations: versioned changes to the schema
│   │   ├── env.py        connects Alembic to DATABASE_URL and the models
│   │   └── versions/     one file per migration
│   ├── tests/
│   │   └── test_schemas.py   unit tests of the validation rules; need no database
│   └── app/
│       ├── main.py       creates the FastAPI app, CORS, mounts routers
│       ├── config.py     reads settings from environment variables
│       ├── database.py   SQLAlchemy engine and session
│       ├── models.py     SQLAlchemy models (table definitions)
│       ├── schemas.py    Pydantic models: request/response shapes and validation
│       └── api/
│           ├── health.py     GET /api/health
│           └── meetings.py   HTTP layer: the meetings endpoints
└── frontend/             React single-page app
    ├── Dockerfile        image for the frontend
    ├── package.json      JS dependencies (exact versions locked in package-lock.json)
    ├── vite.config.ts    Vite configuration
    ├── tsconfig.json     TypeScript configuration
    ├── tailwind.config.ts  Tailwind v3 configuration
    ├── postcss.config.js   PostCSS plugins required by Tailwind v3
    ├── components.json   shadcn/ui configuration
    ├── index.html
    └── src/
        ├── main.tsx          entry point
        ├── index.css         Tailwind directives and shadcn theme variables
        ├── App.tsx           the one page: list + form
        ├── lib/
        │   ├── api.ts        the only place that calls the backend
        │   └── utils.ts      shadcn helper for class names
        └── components/
            ├── MeetingList.tsx   renders the list of meetings
            ├── MeetingForm.tsx   form that creates a meeting
            └── ui/               shadcn/ui components (button, input, card, label)
```

The backend has no separate business-logic layer in this slice:
validation lives in `schemas.py`, persistence in `models.py`, HTTP in
`api/`. A `services/` folder is added only when logic exists that is not
validation or persistence.

Folders and files that appear in the working tree but are not committed
(`node_modules/`, `.venv/`, `.env`) are listed in `.gitignore`.

## Versions (pinned)

| Component | Version |
|---|---|
| Backend base image | python:3.12-slim |
| Database image | postgres:16 |
| Frontend base image | node:22-slim |
| FastAPI | 0.115.x |
| SQLAlchemy | 2.0.x (sync engine) |
| Alembic | 1.13.x |
| psycopg | 3.2.x (`psycopg[binary]`) |
| Uvicorn | 0.30.x |
| pytest | 8.x |
| React | 18.3.x |
| Vite | 5.4.x |
| TypeScript | 5.5.x |
| Tailwind CSS | 3.4.x (v3 on purpose: shadcn/ui and `tailwind.config.ts` assume it) |

`requirements.txt` pins every Python package to an exact version
(`==`). `package.json` uses the lines above and `package-lock.json` fixes
exact versions; the frontend image installs with `npm ci`.
No `latest` tags anywhere.

## Services in docker-compose.yml

| Service | Image / build | Host port (default) | Depends on | Ready when |
|---|---|---|---|---|
| postgres | image: postgres:16 | 5432 (`POSTGRES_PORT`) | none | healthcheck `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB` succeeds |
| backend | build: ./backend | 8000 (`BACKEND_PORT`) | postgres, condition `service_healthy` | healthcheck: `GET /api/health` returns 200 |
| frontend | build: ./frontend | 5173 (`FRONTEND_PORT`) | backend, condition `service_healthy` | Vite dev server answers on 5173 |

- Container ports are fixed (5432, 8000, 5173). Only the host side of each
  mapping is configurable, so a port already used on the developer's
  machine can be changed in `.env` without touching the compose file.
  If `BACKEND_PORT` or `FRONTEND_PORT` change, `VITE_API_BASE_URL` and
  `CORS_ORIGINS` must change with them.
- postgres keeps its data in a named volume `pgdata`.
- backend runs `alembic upgrade head` and then starts Uvicorn, in that
  order, as the compose `command` at container start. The API does not
  accept requests before the migration has finished. The migration is
  never run at build time, because the build has no database.
- The backend healthcheck is written with Python's standard library
  (`urllib.request`), because `python:3.12-slim` does not contain `curl`
  and no extra packages are installed just for the check.
- frontend starts Vite with `--host 0.0.0.0`, otherwise the dev server
  listens only inside the container and the browser cannot reach it.
- backend and frontend mount their source folders so edits reload live.
  The frontend also keeps `node_modules` in an anonymous volume so the
  mount does not hide the dependencies installed in the image.
  These mounts and the Vite dev server are development only; production
  would remove the mounts and serve the built static files instead.
- Configuration comes from environment variables listed in `.env.example`:
  `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`,
  `BACKEND_PORT`, `FRONTEND_PORT`,
  `DATABASE_URL` (driver `postgresql+psycopg`, host `postgres`),
  `CORS_ORIGINS` (default `http://localhost:5173`),
  `VITE_API_BASE_URL` (default `http://localhost:8000`).
- The browser calls the backend directly at `VITE_API_BASE_URL`, which is
  why it is a `localhost` address and not the compose service name, and
  why the backend allows the frontend origin through CORS.

Local development is started with one command: `docker compose up --build`.
Prerequisite: Docker Desktop. Copy `.env.example` to `.env` first.

## Data model

Table `meetings`:

| Column | Type | Rules |
|---|---|---|
| id | integer | primary key, auto-increment |
| title | varchar(200) | not null, at least 1 character |
| starts_at | timestamptz | not null, stored in UTC |
| ends_at | timestamptz | not null, strictly after starts_at |
| attendee_count | integer | not null, 0 or more |

Created by the first Alembic migration. The migration also adds database
`CHECK` constraints for `ends_at > starts_at` and `attendee_count >= 0`.

## API contract

Base path `/api`. Content type `application/json`. Authentication: none.

### Meeting object

```json
{
  "id": 1,
  "title": "Sprint planning",
  "starts_at": "2026-10-01T09:30:00Z",
  "ends_at": "2026-10-01T10:30:00Z",
  "attendee_count": 4
}
```

| Field | JSON type | Format |
|---|---|---|
| id | integer | |
| title | string | 1–200 characters |
| starts_at | string | ISO 8601, UTC, with `Z` suffix |
| ends_at | string | ISO 8601, UTC, with `Z` suffix |
| attendee_count | integer | 0 or more |

Responses always use UTC with the `Z` suffix, whatever offset the client
sent.

### GET /api/meetings

- Request: no body.
- Response `200`: a JSON array of Meeting objects ordered by `starts_at`
  ascending, then `id`. An empty database returns `[]`.

### POST /api/meetings

- Request body: `title`, `starts_at`, `ends_at`, `attendee_count`
  (all required; `id` is not accepted). Datetimes must include a timezone
  (`Z` or an offset); the server converts them to UTC.
- Response `201`: the created Meeting object, including `id`.
- Response `422`: validation failed. Body is FastAPI's default shape:
  `{"detail": [{"loc": [...], "msg": "...", "type": "...", "input": ..., "ctx": {...}}]}`
  (`input` and `ctx` may be absent). Causes: missing field, empty or too
  long title, datetime without timezone, `ends_at` not after `starts_at`,
  negative or non-integer `attendee_count`.

### GET /api/health

- Response `200`: `{"status": "ok"}` after a successful trivial query to
  the database (`SELECT 1`).
- Response `503`: the database did not answer.
- Used by the compose healthcheck (and later by the load balancer).
- If the database disappears after startup, the backend keeps running,
  `/api/health` returns `503`, and requests recover on their own when the
  database returns (the connection pool checks connections before use,
  `pool_pre_ping`).

## Tests

`backend/tests/test_schemas.py` checks the validation rules of
`schemas.py` (empty title, title longer than 200, datetime without
timezone, `ends_at` not after `starts_at`, negative `attendee_count`, UTC
normalisation). They run with `pytest` and need no database, so they can
run in CI without extra services. There are no frontend tests.

## Frontend behaviour

- One page, `App.tsx`, shows the meeting list and the creation form.
- On load it calls `GET /api/meetings`. After a successful
  `POST /api/meetings` it reloads the list.
- Times are shown in the browser's local timezone.
- The form shows the `422` messages next to the failing fields.
- Reloading the page keeps the meetings (they live in Postgres).

## Out of scope

No authentication, no update or delete endpoints, no Redis, no queue, no
reverse proxy, no second database, no Kubernetes, no frontend tests.
No linters, CI, Makefile or AWS files in this slice: they are added in
the next stage, driven by the same repository.