#!/usr/bin/env bash
# Same walkthrough as test-keycloak-flow.sh, pointed at the node-oidc-provider
# fake IdP instead. Requires:
#   - `node server.js` already running in this directory (port 4000)
#   - the resource server running with OIDC_ISSUER=http://localhost:4000
set -euo pipefail

ISSUER="http://localhost:4000"
CLIENT_ID="poc-agent-client"
CLIENT_SECRET="poc-secret"
REDIRECT_URI="http://localhost:8090/callback"
RESOURCE_URL="http://localhost:9000/fake-provider/meetings"

VERIFIER=$(openssl rand -base64 48 | tr -d '=+/' | cut -c1-64)
CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')
STATE=$(openssl rand -hex 8)

AUTH_URL="${ISSUER}/auth?client_id=${CLIENT_ID}&redirect_uri=${REDIRECT_URI}&response_type=code&scope=openid%20offline_access%20read:meetings&state=${STATE}&code_challenge=${CHALLENGE}&code_challenge_method=S256"

echo "==> 1) Open this URL in a browser, log in as testuser / testpass:"
echo "$AUTH_URL"
echo
echo "==> Waiting for the redirect on ${REDIRECT_URI} ..."

RAW=$(printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nLogin complete, you can close this tab.' | nc -l 8090)
CODE=$(printf '%s' "$RAW" | head -1 | grep -oE 'code=[^& ]+' | cut -d= -f2)

if [ -z "${CODE:-}" ]; then
  echo "!! Did not capture an authorization code. First line received:"
  echo "$RAW" | head -1
  exit 1
fi
echo "==> Got code: ${CODE:0:12}..."

echo
echo "==> 3) Exchanging code for tokens:"
TOKEN_RESPONSE=$(curl -s -X POST "${ISSUER}/token" \
  -d "grant_type=authorization_code" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "redirect_uri=${REDIRECT_URI}" \
  -d "code=${CODE}" \
  -d "code_verifier=${VERIFIER}")
echo "$TOKEN_RESPONSE" | python3 -m json.tool

ACCESS_TOKEN=$(printf '%s' "$TOKEN_RESPONSE" | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')
REFRESH_TOKEN=$(printf '%s' "$TOKEN_RESPONSE" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("refresh_token",""))')

echo
echo "==> 4) Calling the resource server WITH the access token:"
curl -s "$RESOURCE_URL" -H "Authorization: Bearer ${ACCESS_TOKEN}" | python3 -m json.tool

echo
echo "==> 5) Calling the resource server with NO token (expect 401):"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "$RESOURCE_URL"

if [ -n "$REFRESH_TOKEN" ]; then
  echo
  echo "==> 6) Refreshing the access token:"
  curl -s -X POST "${ISSUER}/token" \
    -d "grant_type=refresh_token" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "refresh_token=${REFRESH_TOKEN}" | python3 -m json.tool
fi

echo
echo "==> Done."
