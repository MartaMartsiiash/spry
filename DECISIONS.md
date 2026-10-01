# Decision 001: One monorepo, not three repositories

## Decision
Spry lives in a single repository containing backend/, frontend/,
database configuration (migrations, compose) and CI (.github/workflows).

## Why
1. **Atomic changes.** One commit can change an API endpoint and the
   client that calls it, so the contract cannot drift between them.
2. **The repository is the context window.** With the whole pipeline in
   one tree, an AI agent can read the endpoint, the model, the migration
   and the component that renders it in a single pass. With three
   repositories it sees a third of the system and guesses the rest, and
   a guessed contract is a bug found at integration time.
3. **Team and stage fit.** We are a team of four building a product that
   does not exist yet. At this stage context is worth more than
   independence.

## What we give up
- Independent deploys and release cycles per component. Our CI has to
  deploy only the part that changed.
- Access control per component: everyone sees everything.
- Possible slowdown of CI as the repo grows.

## When we would revisit
Separate teams that release on different schedules, a need for
different access rights, or a build time that has become painful.