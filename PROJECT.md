# PROJECT.md — Spry

Spry is a monorepo. This file describes its structure and the contracts
between parts. It contains no implementation code.

## Repository layout

```
spry/
├── PROJECT.md            this file: the specification
├── DECISIONS.md          why the repo is a monorepo
├── docker-compose.yml    postgres + backend + frontend for local development
├── .env.example          every environment variable, with safe local values
├── .gitignore
├── backend/              FastAPI service
│   ├── Dockerfile        image for the backend
│   ├── requirements.txt  pinned Python dependencies
│   ├── alembic.ini       Alembic configuration
│   ├── alembic/          migrations: versioned changes to the schema
│   │   └── versions/     one file per migration
│   └── app/
│       ├── main.py       creates the FastAPI app, CORS, mounts routers
│       ├── config.py     reads settings from environment variables
│       ├── database.py   SQLAlchemy engine and session
│       ├── models.py     SQLAlchemy models (table definitions)
│       ├── schemas.py    Pydantic models: request/response shapes and validation
│       └── api/
│           └── meetings.py   HTTP layer: the meetings endpoints
└── frontend/             React single-page app
    ├── Dockerfile        image for the frontend
    ├── package.json      pinned JS dependencies
    ├── vite.config.ts    Vite configuration
    ├── tailwind.config.ts
    ├── index.html
    └── src/
        ├── main.tsx          entry point
        ├── App.tsx           the one page: list + form
        ├── lib/api.ts        the only place that calls the backend
        └── components/
            ├── MeetingList.tsx   renders the list of meetings
            ├── MeetingForm.tsx   form that creates a meeting
            └── ui/               shadcn/ui components (button, input, card, label)
```

The backend has no separate business-logic layer in this slice:
validation lives in `schemas.py`, persistence in `models.py`, HTTP in
`api/meetings.py`. A `services/` folder is added only when logic exists
that is not validation or persistence.

## Versions (pinned)

| Component | Version |
|---|---|
| Backend base image | python:3.12-slim |
| Database image | postgres:16 |
| Frontend base image | node:22-slim |
| FastAPI, SQLAlchemy 2.x, Alembic, psycopg 3, Uvicorn | exact versions in requirements.txt |
| React, Vite, Tailwind, TypeScript | exact versions in package.json |

No `latest` tags anywhere.

## Services in docker-compose.yml

| Service | Image / build | Host port | Depends on | Ready when |
|---|---|---|---|---|
| postgres | image: postgres:16 | 5432 | none | healthcheck `pg_isready` succeeds |
| backend | build: ./backend | 8000 | postgres, condition `service_healthy` | healthcheck: GET /api/health returns 200 |
| frontend | build: ./frontend | 5173 | backend, condition `service_healthy` | Vite dev server answers on 5173 |

- postgres keeps its data in a named volume `pgdata`.
- backend runs `alembic upgrade head` and then starts Uvicorn, in that
  order, at container start. The API does not accept requests before the
  migration has finished. The migration is never run at build time.
- backend and frontend mount their source folders so edits reload live
  (development only; this would be removed in production).
- Configuration comes from environment variables listed in `.env.example`:
  `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `DATABASE_URL`,
  `CORS_ORIGINS` (default `http://localhost:5173`),
  `VITE_API_BASE_URL` (default `http://localhost:8000`).
- The browser calls the backend directly at `VITE_API_BASE_URL`, so the
  backend allows the frontend origin through CORS.

Local development is started with one command: `docker compose up --build`.
Prerequisite: Docker Desktop.

## Data model

Table `meetings`:

| Column | Type | Rules |
|---|---|---|
| id | integer | primary key, auto-increment |
| title | varchar(200) | not null, at least 1 character |
| starts_at | timestamptz | not null, stored in UTC |
| ends_at | timestamptz | not null, strictly after starts_at |
| attendee_count | integer | not null, 0 or more |

Created by the first Alembic migration.

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
  `{"detail": [{"loc": [...], "msg": "...", "type": "..."}]}`. Causes:
  missing field, empty or too long title, datetime without timezone,
  `ends_at` not after `starts_at`, negative or non-integer
  `attendee_count`.

### GET /api/health

- Response `200`: `{"status": "ok"}` after a successful trivial query to
  the database. Used by the compose healthcheck (and later by the load
  balancer).

## Frontend behaviour

- One page, `App.tsx`, shows the meeting list and the creation form.
- On load it calls `GET /api/meetings`. After a successful
  `POST /api/meetings` it reloads the list.
- Times are shown in the browser's local timezone.
- The form shows the `422` messages next to the failing fields.
- Reloading the page keeps the meetings (they live in Postgres).

## Out of scope

No authentication, no update or delete endpoints, no Redis, no queue, no
reverse proxy, no second database, no Kubernetes, no tests in this slice.