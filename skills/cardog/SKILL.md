---
name: cardog
description: "Canadian vehicle data: VIN identity, canonical specs, live market pricing, and Transport Canada + NHTSA recalls behind one typed ref graph. Use whenever a task needs to identify a vehicle from a VIN or free text, price a used vehicle, check for open recalls, or search live Canadian listings."
license: Apache-2.0
metadata:
  homepage: https://cardog.app
  docs: https://cardog.app/docs.md
  api: https://api.cardog.app
---

# Cardog

Cardog is the system of record for the Canadian vehicle: VIN → identity,
canonical specs, live market pricing, and recalls (Transport Canada + NHTSA)
— all addressed through one permanent ref grammar, `{domain}:{key}`. This
skill is the decision tree; the full contract is one fetch away
(`https://cardog.app/docs.md`).

## The one rule: resolve first, then hold refs

Free text enters this API in exactly **one** place:

```bash
curl "https://api.cardog.app/v2/entities/resolve?q=2021%20civic" \
  -H "x-api-key: $CARDOG_API_KEY"
```

It returns candidates ordered best-first with a confidence score. `best` is
`null` when nothing clears the floor — **the API will not guess for you, so
do not guess either.** Take the ref from the response and hold it; every
other call in this platform takes a **ref** or a **VIN**, never a free-text
name. Never construct a ref by guessing a make/model spelling — resolve it,
or decode a VIN.

## The ref grammar

A ref is `{domain}:{key}`, lowercase, `/`-separated for composite keys.
Refs are permanent join keys — store them in memory, config, database
columns; `make:honda` means Honda for the life of the platform.

| Domain | Shape | Example |
| --- | --- | --- |
| `make` | `make:{slug}` | `make:tesla` |
| `model` | `model:{make}/{model}` | `model:honda/civic` |
| `model-year` | `model-year:{make}/{model}/{year}` | `model-year:honda/cr-v/2026` |
| `squish` | `squish:{9-char VIN grain}` | `squish:5TDGSKFCR` |
| `recall` | `recall:{authority}/{campaign}` | `recall:tc/2024-123` |
| attribute domains | `{domain}:{slug}` | `fuel-type:electric`, `body-style:pickup` |

Grammar version `1` (`npm install @cardog/entities` holds
and validates this grammar offline — zero network, zero key — see
[the ref grammar guide](https://cardog.app/docs/ref-grammar)).

**Two encodings, depending on position:**

- In a URL **path**, encode the ref's slashes as `%2F`:
  `https://api.cardog.app/v2/entities/model-year:honda%2Fcr-v%2F2026`
- In a **query string**, pass the ref raw: `?make=make:tesla`

Every response carries a `links` block (rel → server-relative path) —
follow it instead of building URLs by hand; the paths it emits are already
correctly encoded.

## VIN-first entry

If the task already has a VIN, skip resolve — decode it directly. The
identity comes back **as refs**, plus links to the instrument, recalls, and
listings for that vehicle:

```bash
curl "https://api.cardog.app/v2/vin/1HGCM82633A123456" -H "x-api-key: $CARDOG_API_KEY"
```

Batch decode up to 1,000 VINs in one call
(`POST /v2/vin/batch`) — all-accepted, per-item-resolved: one malformed VIN
fails its own row, never the batch.

## Route the job

Five jobs, same shape as the MCP tools below — pick the row that matches the
task:

| Job | REST call | MCP tool |
| --- | --- | --- |
| Resolve free text → refs | `GET /v2/entities/resolve?q=` | `resolve_entity` |
| Identify a vehicle from a VIN | `GET /v2/vin/{vin}` | `identify_vehicle` |
| Search live Canadian listings | `GET /v2/listings/search` | `search_inventory` |
| Price a vehicle (market instrument) | `GET /v2/quotes/{ref}` (or `?refs=a,b,c`, up to 20) | `market_quote` |
| Check recalls | `GET /v2/recalls/vin/{vin}` or `/v2/recalls/entity/{ref}` | `check_recalls` |

One call that answers the question beats four correct ones: quote up to
20 instruments in a single `/v2/quotes` call, and a
VIN decode's `links` put every adjacent answer one traversal away.

## Errors are instructions — act on the envelope

Every non-2xx response from `/v2/*` is one shape. Read it in order and
self-correct in the same turn instead of retrying blind:

1. **`code`** — dispatch on it (`unknown_entity_refs`, `invalid_vin`,
   `insufficient_credits`, … an open, additive set).
2. **`message`** — names the exact offending input.
3. **`hint`** — says what to DO next, usually the endpoint to call.
4. **`suggestions`** — for a near-miss ref, the nearest valid refs plus a
   ready-to-call `resolve` URL. Advisory only — never apply it silently;
   confirm or re-call.
5. **`docs_url`** — a fetchable deep link into the errors guide for this
   exact code. When the hint alone doesn't unblock you, fetch it (append
   `.md` for the markdown twin) instead of guessing.

```json
{
  "code": "unknown_entity_refs",
  "message": "Unknown entity refs: make:teslla",
  "hint": "Resolve free text to refs at GET /v2/entities/resolve?q=teslla",
  "docs_url": "https://cardog.app/docs/errors#unknown_entity_refs",
  "refs": ["make:teslla"],
  "suggestions": [
    {
      "invalid": "make:teslla",
      "nearest": [{ "ref": "make:tesla", "name": "Tesla" }],
      "resolve": "/v2/entities/resolve?domain=make&q=teslla"
    }
  ]
}
```

The corollary you can rely on: **an unknown-but-well-formed ref is always a
named 400, never a silent fuzzy match or an empty result.** Full code list
and every HTTP status: [Errors guide](https://cardog.app/docs/errors).

## Auth and credits

Every `/v2/*` call needs an API key (create one at
https://cardog.app/account/api), sent as `x-api-key` or
`Authorization: Bearer` — both accepted, equivalent. Read the key from an
environment variable (`CARDOG_API_KEY` in every example on this page);
never hardcode it.

Everything commercial is denominated in **credits**, one currency across
REST and MCP alike. Every metered response carries the live state of your
budget — read these instead of hardcoding a rate:

- `X-Credits-Rate` — what this response cost (0 on errors)
- `X-Credits-Remaining` / `X-Credits-Allowance` — budget left this cycle
- `X-Credits-Reset` — when the allowance rolls over

Past the free tier's allowance, metered requests return
`402 insufficient_credits` (the standard envelope above) until reset or
upgrade — an evaluation-tier stop, not a production one; paid tiers bill
overage instead of blocking. The rate card itself is machine-readable and
needs no auth:

```bash
curl https://api.cardog.app/v2/pricing
```

Compute the cost of a proposed integration, or budget mid-task ("spend at
most 20 credits answering this"), from that response — never from a
hardcoded number. Details: [Credits & limits](https://cardog.app/docs/credits).

## Everything else, one fetch

This skill stays thin on purpose — the full platform (auth, every operation
with request/response shapes, the complete ref grammar, MCP, compliance) is
one fetch away, generated from the same contract this page is:

```bash
curl https://cardog.app/docs.md
```

The machine-readable OpenAPI 3.1 spec is `GET https://api.cardog.app/v2/openapi.json`.
Every docs page also has a markdown twin (append `.md`, or send
`Accept: text/markdown`).

## MCP: the tool-shaped channel

If the runtime speaks [MCP](https://modelcontextprotocol.io), the same five
jobs are tools — same refs, same credit rates, same links:

| Transport | URL |
| --- | --- |
| Streamable HTTP (preferred) | `https://mcp.cardog.io/mcp` |
| SSE | `https://mcp.cardog.io/sse` |

```bash
claude mcp add --transport http cardog "https://mcp.cardog.io/mcp?api_key=$CARDOG_API_KEY"
```

Any MCP client: pass the key as `?api_key=`, `Authorization: Bearer`, or
`x-api-key`. Full connection details: [MCP Server](https://cardog.app/docs/mcp).
