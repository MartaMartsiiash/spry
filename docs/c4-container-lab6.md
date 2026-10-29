# C4 container diagram (Lab 6) — Paste an agenda

Update of the Lab 1 container view: parser Lambda, Bedrock, and the two arrows
**parse** (browser → parser → Bedrock) and **save** (browser → API → Aurora).

```mermaid
C4Container
    title Spry — containers after Lab 6

    Person(user, "User", "Pastes an agenda, checks the form, saves")

    System_Boundary(spry, "Spry") {
        Container(web, "Web app", "Next.js static / CloudFront", "Paste an agenda UI + meeting forms")
        Container(api, "API", "Lambda + FastAPI", "Meetings CRUD; PUT …/agenda writes Aurora")
        Container(parser, "Agenda parser", "Lambda (no VPC)", "Validates Cognito token; calls Claude; returns JSON")
        ContainerDb(db, "Aurora PostgreSQL", "JSONB agenda + ai_suggestion")
    }

    System_Ext(cognito, "Amazon Cognito", "Access tokens")
    System_Ext(bedrock, "Amazon Bedrock", "Claude (Mantle Messages API)")

    Rel(user, web, "Uses")
    Rel(web, cognito, "Sign-in")
    Rel(web, parser, "1 · POST text, today, tz + Bearer", "HTTPS function URL")
    Rel(parser, bedrock, "messages + record_agenda tool")
    Rel(bedrock, parser, "tool_use → validated JSON")
    Rel(parser, web, "JSON → pre-filled form")
    Rel(web, api, "3 · Save checked form + ai_suggestion", "HTTPS")
    Rel(api, db, "INSERT/UPDATE agenda", "5432")
    Rel(api, cognito, "Verify JWT")
```

## Flow

1. **Parse** — Browser → agenda-parser Lambda (outside VPC) → Bedrock Claude → JSON.
2. **Review** — Pre-filled form with “suggested” badges; user may edit.
3. **Save** — Browser → API Lambda → Aurora. The model never writes.
