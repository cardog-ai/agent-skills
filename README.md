# Cardog Agent Skills

The `cardog` skill teaches any skills-compatible agent harness — Claude Code, Cursor, Codex, Copilot, Goose, and the rest — how to use the [Cardog](https://cardog.app) platform correctly: resolve free text once, hold permanent refs, read the response envelope, recover from errors in one turn.

## Install

From the platform (discovery via `.well-known`):

```bash
npx skills add https://cardog.app
```

From this repo:

```bash
npx skills add cardog-ai/agent-skills
```

Both resolve to the same artifact.

## One truth, three surfaces

The skill is generated inside the cardog.app application from `@cardog/contracts` (the OpenAPI source) and `@cardog/entities` (the ref grammar). It is served at [`cardog.app/skill.md`](https://cardog.app/skill.md), indexed with a sha256 digest at [`/.well-known/skills/index.json`](https://cardog.app/.well-known/skills/index.json), and mirrored here.

This repo cannot drift: CI verifies the repo copy byte-matches the digest-verified live artifact on every push and PR, and a daily job opens a sync PR when the platform ships a new skill. See [`scripts/sync.sh`](scripts/sync.sh).

## What the skill covers

- **Resolve-first** — free text enters the API at exactly one endpoint; everything else takes a ref or a VIN.
- **The ref grammar** — `{domain}:{key}`, permanent join keys, validated offline by [`@cardog/entities`](https://www.npmjs.com/package/@cardog/entities).
- **Job routing** — identity, inventory, market, recalls, resolution: which call answers which job.
- **Envelope self-correction** — read `code`, follow `hint`, apply `suggestions`.
- **One-fetch docs** — `curl cardog.app/docs.md` before asking anything.
- **Auth rails** — keys, the `X-Credits-*` headers, what a 402 means.

Full platform docs: [cardog.app/docs](https://cardog.app/docs) (agents: [`cardog.app/docs.md`](https://cardog.app/docs.md)).

## License

Apache-2.0
