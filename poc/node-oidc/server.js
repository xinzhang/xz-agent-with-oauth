// Fake identity/authorization server for the POC.
// devInteractions is disabled on purpose: it auto-approves anyone, which proves
// nothing. This server checks credentials against an in-memory user list instead,
// via a hand-written /interaction/:uid login route.

import express from 'express';
import { Provider } from 'oidc-provider';

const PORT = 4000;
const ISSUER = `http://localhost:${PORT}`;

// In-memory "user database" for the POC. Swap for a real lookup (SQLite, etc.)
// if you want persistence across restarts or more than a couple of test users.
const USERS = {
  'user-1': { username: 'testuser', password: 'testpass', email: 'test@example.com' },
};

function findAccountIdByCredentials(username, password) {
  const match = Object.entries(USERS).find(
    ([, u]) => u.username === username && u.password === password,
  );
  return match ? match[0] : undefined;
}

const configuration = {
  clients: [
    {
      client_id: 'poc-agent-client',
      client_secret: 'poc-secret',
      redirect_uris: ['http://localhost:8090/callback'],
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      scope: 'openid offline_access read:meetings',
    },
  ],
  scopes: ['openid', 'offline_access', 'read:meetings'],
  claims: { openid: ['sub'] },
  formats: { AccessToken: 'jwt' },
  features: {
    devInteractions: { enabled: false }, // <- the whole point of this file
    revocation: { enabled: true },
  },
  pkce: { required: () => true },
  async findAccount(ctx, id) {
    const user = USERS[id];
    if (!user) return undefined;
    return {
      accountId: id,
      async claims() {
        return { sub: id, email: user.email };
      },
    };
  },
};

const oidc = new Provider(ISSUER, configuration);

const app = express();
app.use(express.urlencoded({ extended: false }));

// GET /interaction/:uid — oidc-provider's default interaction URL. This is the
// real login form, replacing devInteractions' auto-approve stub.
app.get('/interaction/:uid', async (req, res, next) => {
  try {
    const { uid } = await oidc.interactionDetails(req, res);
    res.send(`
      <h3>Fake IdP login (interaction ${uid})</h3>
      <form method="POST" action="/interaction/${uid}/login">
        <input name="username" placeholder="username" value="testuser" /><br/>
        <input name="password" type="password" placeholder="password" value="testpass" /><br/>
        <button type="submit">Login</button>
      </form>
    `);
  } catch (err) {
    next(err);
  }
});

// POST /interaction/:uid/login — the actual credential check.
app.post('/interaction/:uid/login', async (req, res, next) => {
  try {
    const accountId = findAccountIdByCredentials(req.body.username, req.body.password);
    if (!accountId) {
      res.status(401).send('Invalid credentials. Go back and try again.');
      return;
    }
    await oidc.interactionFinished(
      req,
      res,
      { login: { accountId } },
      { mergeWithLastSubmission: false },
    );
  } catch (err) {
    next(err);
  }
});

app.use(oidc.callback());

app.listen(PORT, () => {
  console.log(`Fake IdP (node-oidc-provider) listening on ${ISSUER}`);
});
