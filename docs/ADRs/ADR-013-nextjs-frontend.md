# ADR-013: Minimal Next.js 14 Frontend — Submit, Poll, See the Result

## Status

Accepted

## Context

BUILD_PLAN's Phase 12 is deliberately small: submit a request, poll/see
the result, no polish. Unlike every phase before it, there's no Terraform
bullet attached - confirmed before starting rather than assumed, and the
scope stayed exactly that: app code, verified locally, no new hosting
infrastructure.

## Decision

### One page, one component, no framework beyond Next.js itself

A form, a poll loop, a result display - `app/page.tsx` as a single
client component. No state management library, no component library, no
routing beyond the one page. Matches "no need for polish" literally
rather than building scaffolding for pages that don't exist yet.

### Poll, don't stream

`setInterval` re-fetching `GET /generations/{id}` every 2 seconds until
`completed`/`failed`, not WebSockets or server-sent events. The backend
has neither, and adding either would be new backend scope smuggled into
a frontend phase - polling is the honest match for what Phase 10 already
built.

### Best-effort inline result, always-working fallback link

`result_url` points at a different origin than wherever this frontend
runs (the live site, or MinIO locally) - a `fetch()` of it from the
browser has no CORS guarantee either way, unlike `curl`, which never
enforces CORS at all and would have hidden this entirely. The page tries
the fetch and renders the message inline when it works, and always shows
the raw link regardless - a real request never dead-ends into nothing to
show.

## Three real bugs, all found by actually using the thing - none catchable by curl

**TypeScript's actual latest release doesn't work with Next.js 14.**
Verified `typescript@7.0.2` live against the registry (this project's
standing habit) and pinned it - and `next dev` crashed outright
(`TypeError: Cannot read properties of undefined (reading 'endsWith')`
inside Next's own TypeScript-setup verification). Next 14.2.35 predates
TypeScript's 6.x/7.x line entirely; "verified against the live registry"
isn't the same claim as "verified compatible with what it's paired with."
Fixed by pinning to the latest 5.x release (5.9.3) instead - the cohort
Next 14 was actually built and tested against, not just "whatever's
newest this week."

**FastAPI never needed CORS before, and it showed the moment a browser
was the client instead of curl.** Phase 10/11 verification was
exclusively `curl` - which doesn't enforce CORS, so this gap sat
invisible through two full phases of "verified live" testing. The instant
a real browser on `localhost:3000` tried to call the API on a different
origin, it would have been silently blocked. Added `CORSMiddleware`,
permissive (`allow_origins=["*"]`) deliberately, not by default - this API
has no cookies/session auth for permissive CORS to expose, and every
field it returns is already meant to be readable by anyone holding the
generation's UUID.

**Local MinIO needed a public-read bucket policy that the real S3 bucket
must never have.** Confirmed in an actual browser: `AccessDenied` on the
result URL, screenshotted directly from MinIO's raw S3 API. Real S3
(Phase 6) stays fully private - `block_public_acls` and friends - and is
only ever readable through CloudFront's OAC, a server-side grant that a
browser's anonymous `fetch()` never has to satisfy itself. Locally there's
no CloudFront standing in front of MinIO, so the browser hits MinIO's raw
API directly and needs the bucket itself to allow anonymous reads. Fixed
inside the same `S3_ENDPOINT_URL`-gated local-only branch that already
creates the bucket (Phase 11) - this policy call never executes against
the real bucket, which stays exactly as private as Phase 6 built it.

## Consequences

- `npm install` inside this repo's own directory fails outright
  (`EBADF`/`TAR_ENTRY_ERROR`) - the project lives in a Google-Drive-synced
  folder, and npm's native-binary extraction doesn't tolerate the live
  sync watching the same files mid-write. Worked around by installing in
  an unsynced scratch location and copying `package-lock.json` back for
  commit - the actual source files were always written directly into the
  repo, unaffected either way. Worth remembering for any future `npm
  install` in this repo, not just this phase.
- Two known, unpatched CVEs remain on `next@14.2.35` (the latest
  available 14.x release) - the real fixes only land in Next 15/16.
  Deliberately not upgraded past the pinned major version CLAUDE.md's
  stack section calls for; none of the affected surfaces
  (`next/image`, middleware, i18n) are used by this two-page app anyway.
  Worth a second look if this project's Next.js version ever gets
  revisited on its own terms, not silently bundled into a later phase.
- Verified live in an actual browser, not just curl - a real prompt went
  in, a real status transition and a real generated message came back,
  confirmed on screen.
- No hosting infrastructure exists for this yet, on purpose - a natural
  next addition (S3+CloudFront static export, or another approach) is a
  future decision with its own tradeoffs, not something this phase's
  "app code only" scope quietly forecloses.
