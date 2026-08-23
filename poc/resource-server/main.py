import os
import time

import httpx
from fastapi import FastAPI, HTTPException, Request
from jose import jwt
from jose.exceptions import JWTError

app = FastAPI()

ISSUER = os.environ.get("OIDC_ISSUER", "http://localhost:4000")

_jwks_cache = {"keys": None, "fetched_at": 0.0}
JWKS_TTL_SECONDS = 300


def get_jwks():
    now = time.time()
    if _jwks_cache["keys"] is None or now - _jwks_cache["fetched_at"] > JWKS_TTL_SECONDS:
        discovery = httpx.get(f"{ISSUER}/.well-known/openid-configuration", timeout=5).json()
        jwks = httpx.get(discovery["jwks_uri"], timeout=5).json()
        _jwks_cache["keys"] = jwks["keys"]
        _jwks_cache["fetched_at"] = now
    return _jwks_cache["keys"]


def verify_token(auth_header: str | None) -> dict:
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = auth_header.removeprefix("Bearer ")

    try:
        header = jwt.get_unverified_header(token)
        key = next(k for k in get_jwks() if k["kid"] == header["kid"])
        claims = jwt.decode(
            token,
            key,
            algorithms=[header["alg"]],
            issuer=ISSUER,
            options={"verify_aud": False},
        )
    except (JWTError, StopIteration, KeyError) as exc:
        raise HTTPException(status_code=401, detail=f"invalid token: {exc}") from exc

    return claims


@app.get("/health")
def health():
    return {"issuer": ISSUER}


@app.get("/fake-provider/meetings")
def list_meetings(request: Request):
    claims = verify_token(request.headers.get("authorization"))
    return {
        "user": claims.get("sub"),
        "meetings": [
            {"id": "1", "title": "Standup", "start": "2026-08-24T09:00:00Z"},
            {"id": "2", "title": "1:1 with manager", "start": "2026-08-24T14:00:00Z"},
        ],
    }
