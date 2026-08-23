# POC: build the fake OAuth server first (Phase 0)

Companion to
[2026-08-23-agent-oauth-connector-architecture.md](2026-08-23-agent-oauth-connector-architecture.md).
This is the very first milestone — build and validate a fake OAuth provider (authorization server +
resource server) **before** touching Next.js, the ADK agent, or any real vendor (Microsoft/Google/
Atlassian). Goal: prove the raw OAuth mechanics work, entirely via curl/browser, with zero product
code in the loop yet.

Code for this milestone lives under `poc/` in this repo:

```
poc/
  resource-server/     # shared FastAPI resource server — reused by both phases below
    main.py
    requirements.txt
  keycloak/             # Phase 1
    docker-compose.yml
    realm-export.json
    test-keycloak-flow.sh
  node-oidc/             # Phase 2
    server.js
    package.json
    test-node-oidc-flow.sh
```

## Why this comes first

Real providers add friction that's unrelated to whether your own architecture is correct (Google's
CASA, Microsoft's admin consent, Atlassian's cloudId resolution). Building your own fake provider
isolates that variable — when something breaks here, it's your code, not a vendor console setting.
It also proves the resource server is provider-agnostic: the same `poc/resource-server/main.py`
validates tokens from *either* fake IdP just by changing `OIDC_ISSUER` — no code changes. That's
the actual property your real Graph/Gmail/Jira connectors will need later too.

## Definition of done (per phase)

Without any Next.js UI or ADK agent involved — pure curl/browser, run by the test scripts:
1. Hit the fake authorization server's `/authorize`, log in as the test user, get redirected back
   with `?code=...`.
2. Exchange the code (+ PKCE verifier) for an access token (and refresh token).
3. Call the resource server with `Authorization: Bearer <access_token>` — get real fake data back.
4. Call the resource server with no token — get a 401.
5. Use the refresh token to get a new access token without repeating step 1.

## Phase 1 — Keycloak

1. **Build the Keycloak server.**
   ```bash
   cd poc/keycloak
   docker compose up
   ```
   `--import-realm` auto-provisions everything from `realm-export.json` on first boot — a realm
   `poc-realm`, a confidential client `poc-agent-client` (PKCE required, redirect URI
   `http://localhost:8090/*`), and a test user `testuser` / `testpass`. No manual admin-console
   clicking needed.

   ⚠️ Caveat: Keycloak's realm-import JSON schema is version-sensitive and this file is a
   best-effort minimal shape, not something I could run and verify end-to-end. If it fails to
   import cleanly on `docker compose up`, fall back to the manual admin-console steps (create
   realm → client → user by hand, same field values as in `realm-export.json`) — once it's
   configured correctly through the UI you can re-export it (Realm settings → Action → Partial
   export) and replace this file with a known-good version.

2. **Build the resource server, pointed at Keycloak.**
   ```bash
   cd poc/resource-server
   pip install -r requirements.txt
   OIDC_ISSUER=http://localhost:8080/realms/poc-realm uvicorn main:app --port 9000
   ```

3. **Run the test script** (in a third terminal — it needs both of the above running):
   ```bash
   ./poc/keycloak/test-keycloak-flow.sh
   ```
   It generates the PKCE pair, prints the authorize URL for you to open and log in (the one
   interactive step that can't be scripted), captures the redirect with a local `nc` listener on
   `:8090`, exchanges the code, calls the resource server with and without the token, and exercises
   the refresh token — steps 1–5 of the Definition of Done, automatically.

## Phase 2 — node-oidc-provider

1. **Build the node-oidc server, with `devInteractions` disabled and a real (in-memory) credential
   check.**
   ```bash
   cd poc/node-oidc
   npm install
   node server.js
   ```
   `server.js` deliberately does *not* use `devInteractions` (the auto-approve stub) — it wires a
   custom `/interaction/:uid` login route that checks the submitted username/password against an
   in-memory `USERS` map before calling `interactionFinished()`. Swap that map for a real SQLite
   lookup later if you want persistence or more than a couple of test users; the interaction
   handler shape stays the same either way.

2. **Connect the resource server to node-oidc instead** (stop the Phase 1 instance, restart with a
   different issuer — this is the whole point, same code, no changes):
   ```bash
   cd poc/resource-server
   OIDC_ISSUER=http://localhost:4000 uvicorn main:app --port 9000
   ```

3. **Run the test script:**
   ```bash
   ./poc/node-oidc/test-node-oidc-flow.sh
   ```
   Same shape as the Keycloak script — PKCE, capture-redirect-with-`nc`, exchange, call resource
   server with/without token, refresh.

## Explicitly out of scope for this milestone

No Next.js UI, no `ConnectCard`, no ADK agent, no vault, no `auth_required` SSE event. Those come
after both phases above are green — see the phased plan in the companion doc, where this becomes
Phase 0, preceding "Foundations."
