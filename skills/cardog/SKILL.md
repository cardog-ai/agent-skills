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
canonical specs, live market pricing, and recalls (Transport Canada + NHTSA),
all addressed through one permanent ref grammar, `{domain}:{key}`. This
skill is the decision tree. The full contract is at
`https://cardog.app/docs.md`.

## The one rule: resolve first, then hold refs

Only one endpoint accepts free text:

```bash
curl "https://api.cardog.app/v2/entities/resolve?q=2021%20civic" \
  -H "x-api-key: $CARDOG_API_KEY" \
  -H "Cardog-Version: 2026-10-26"
```

It returns candidates ordered best-first with a confidence score. `best` is
`null` when no candidate clears the confidence floor. In that case, do not
pick one yourself. Take the ref from the response and hold it. Every other
call takes a **ref** or a **VIN**, not a free-text name. Do not construct a
ref by guessing a make/model spelling; resolve it, or decode a VIN.

## Ref grammar

A ref is `{domain}:{key}`, lowercase, `/`-separated for composite keys.
Refs are permanent join keys. Store them in memory, config, or database
columns; `make:honda` means Honda for the life of the platform.

| Domain | Shape | Example |
| --- | --- | --- |
| `make` | `make:{slug}` | `make:tesla` |
| `model` | `model:{make}/{model}` | `model:honda/civic` |
| `model-year` | `model-year:{make}/{model}/{year}` | `model-year:honda/cr-v/2026` |
| `squish` | `squish:{9-char VIN grain}` | `squish:5TDGSKFCR` |
| `recall` | `recall:{authority}/{campaign}` | `recall:tc/2024-123` |
| attribute domains | `{domain}:{slug}` | `fuel-type:electric`, `body-style:pickup` |

Grammar version `1`. `npm install @cardog/entities`
builds and validates this grammar offline, with no network and no key; see
[Ref grammar](https://cardog.app/docs/ref-grammar).

**Encoding depends on position:**

- In a URL **path**, encode the ref's slashes as `%2F`:
  `https://api.cardog.app/v2/entities/model-year:honda%2Fcr-v%2F2026`
- In a **query string**, pass the ref raw: `?make=make:tesla`

Every response carries a `links` block (rel → server-relative path).
Follow it instead of building URLs by hand; the paths it emits are already
encoded.

## VIN-first entry

If the task already has a VIN, skip resolve and decode it directly. The
identity comes back **as refs**, plus links to the instrument, recalls, and
listings for that vehicle:

```bash
curl "https://api.cardog.app/v2/vin/2T3R1RFV7MW180266" -H "x-api-key: $CARDOG_API_KEY" -H "Cardog-Version: 2026-10-26"
```

Batch decode up to 1,000 VINs in one call
(`POST /v2/vin/batch`). The batch is accepted as a whole and resolved per
item: one malformed VIN fails its own row, not the batch.

If a decode returns `valid: false` and you know what the vehicle is, report
it at `POST /v2/feedback` (0 credits). The decode's `links.feedback` points
there, and the receipt's `id` reads back at `GET /v2/feedback/{id}`.

## Route the job

Five jobs, matching the MCP tools below. Pick the row that matches the
task:

| Job | REST call | MCP tool |
| --- | --- | --- |
| Resolve free text → refs | `GET /v2/entities/resolve?q=` | `resolve_entity` |
| Identify a vehicle from a VIN | `GET /v2/vin/{vin}` | `identify_vehicle` |
| Search live Canadian listings | `GET /v2/listings/search` | `search_inventory` |
| Price a vehicle (market instrument) | `GET /v2/quotes/{ref}` (or `?refs=a,b,c`, up to 20) | `market_quote` |
| Check recalls | `GET /v2/recalls/vin/{vin}` or `/v2/recalls/entity/{ref}` | `check_recalls` |

Prefer one call that answers the question over several: quote up to
20 instruments in a single `/v2/quotes` call, and
follow a VIN decode's `links` to reach each adjacent answer in one request.

## Reading an error envelope

Every non-2xx response from `/v2/*` has the same shape. Read the fields in
order and correct the request in the same turn instead of retrying blind:

1. **`code`**: dispatch on it (`unknown_entity_refs`, `invalid_vin`,
   `insufficient_credits`, and others; the set is open and additive).
2. **`message`**: names the offending input.
3. **`hint`**: says what to do next, usually the endpoint to call.
4. **`suggestions`**: for a near-miss ref, the nearest valid refs plus a
   ready-to-call `resolve` URL. Advisory only. Confirm a suggestion or
   re-call resolve before using it.
5. **`docs_url`**: a deep link into the errors guide for this code. If the
   hint alone does not unblock you, fetch it (append `.md` for the
   markdown twin).

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

**A well-formed but unknown ref always returns a 400 that names it.** It is
not fuzzy-matched and it does not return an empty result. Full code list
and every HTTP status: [Errors guide](https://cardog.app/docs/errors).

## Auth and credits

Every `/v2/*` call needs an API key (create one at
https://cardog.app/login?next=/account/api), sent as `x-api-key` or
`Authorization: Bearer`. The two headers are equivalent. Read the key from
an environment variable (`CARDOG_API_KEY` in every example on this page);
do not hardcode it.

All usage is metered in **credits**, and the same credits apply to REST and
MCP. Every metered response carries the current state of your budget in
headers. Read these instead of hardcoding a rate:

- `X-Credits-Rate`: what this response cost (0 on errors)
- `X-Credits-Remaining` / `X-Credits-Allowance`: budget left this cycle
- `X-Credits-Reset`: when the allowance rolls over

Past the free tier's allowance, metered requests return
`402 insufficient_credits` (the standard envelope above) until the
allowance resets or the account upgrades. Paid tiers bill overage instead
of blocking. The rate card is machine-readable and needs no auth:

```bash
curl https://api.cardog.app/v2/pricing
```

Compute the cost of a proposed integration, or a mid-task budget ("spend at
most 20 credits answering this"), from that response rather than from a
hardcoded number. Details: [Credits](https://cardog.app/docs/credits).

## The full docs in one fetch

This skill covers the decision tree only. The full platform documentation
(auth, every operation with request/response shapes, the complete ref
grammar, MCP, compliance) is generated from the same contract as this page
and available in one fetch:

```bash
curl https://cardog.app/docs.md
```

The machine-readable OpenAPI 3.1 spec is `GET https://api.cardog.app/v2/openapi.json`.
Every docs page also has a markdown twin (append `.md`, or send
`Accept: text/markdown`).

## MCP server

If the runtime supports [MCP](https://modelcontextprotocol.io), the same
five jobs are available as tools, with the same refs, credit rates, and
links:

| Transport | URL |
| --- | --- |
| Streamable HTTP (preferred) | `https://mcp.cardog.io/mcp` |
| SSE | `https://mcp.cardog.io/sse` |

```bash
claude mcp add --transport http cardog "https://mcp.cardog.io/mcp?api_key=$CARDOG_API_KEY"
```

Any MCP client: pass the key as `?api_key=`, `Authorization: Bearer`, or
`x-api-key`. Full connection details: [MCP server](https://cardog.app/docs/mcp).
