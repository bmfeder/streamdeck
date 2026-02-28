# Supabase + PowerSync Setup Guide

## Prerequisites
- Apple Developer account (Team ID: 674CG3Y6T4)
- Supabase account (free tier)
- PowerSync Cloud account (free tier)

---

## Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Choose a region close to your users
3. Set a strong database password (save it — you'll need it for PowerSync)
4. Wait for the project to finish provisioning (~2 minutes)
5. Note down from Settings > API:
   - **Project URL**: `https://<project-id>.supabase.co`
   - **Anon public key**: `eyJ...`
   - **Service role key**: `eyJ...` (keep secret, never expose in frontend)

## Step 2: Run SQL Schema

In the Supabase Dashboard, go to **SQL Editor** and run these files **in order**:

1. `schema.sql` — Creates all 5 tables
2. `indexes.sql` — Performance indexes
3. `rls.sql` — Row Level Security policies
4. `triggers.sql` — Auto-update timestamps, PowerSync publication, user signup handler

Verify: Go to **Table Editor** and confirm all 5 tables appear:
`playlists`, `channels`, `vod_items`, `watch_progress`, `user_preferences`

## Step 3: Configure Apple Sign In

### Apple Developer Console

1. Go to [developer.apple.com](https://developer.apple.com) > Certificates, Identifiers & Profiles

2. **Create a Services ID** (for web OAuth):
   - Identifiers > Services IDs > Register
   - Description: "StreamDeck Web"
   - Identifier: `net.lctechnology.StreamDeck.web`
   - Enable "Sign in with Apple"
   - Configure Website URLs:
     - **Domain**: `<project-id>.supabase.co`
     - **Return URL**: `https://<project-id>.supabase.co/auth/v1/callback`

3. **Create a Signing Key**:
   - Keys > Create a new key
   - Name: "StreamDeck Supabase"
   - Enable "Sign in with Apple", select primary App ID
   - Download the `.p8` file (one-time download!)
   - Note the **Key ID**

### Generate the Apple Client Secret JWT

Apple Sign In for web requires a **JWT client secret** signed with your `.p8` key.
Supabase expects this JWT — **not** the raw `.p8` file contents.

```bash
# Install jsonwebtoken if needed
npm install jsonwebtoken

# Generate the secret (valid for 180 days)
node -e "
const jwt = require('jsonwebtoken');
const fs = require('fs');
const key = fs.readFileSync('./AuthKey_<KEY_ID>.p8');
const secret = jwt.sign({}, key, {
  algorithm: 'ES256',
  expiresIn: '180d',
  audience: 'https://appleid.apple.com',
  issuer: '674CG3Y6T4',
  subject: 'net.lctechnology.StreamDeck.web',
  keyid: '<KEY_ID>',
});
console.log(secret);
"
```

Replace `<KEY_ID>` with your Apple Key ID. The output starts with `eyJ...`.

### Supabase Dashboard

1. Go to **Authentication > Providers > Apple**
2. Enable the Apple provider
3. Fill in:
   - **Client ID**: `net.lctechnology.StreamDeck.web` (the Services ID)
   - **Secret Key**: The JWT output from above (starts with `eyJ...`)
   - **Key ID**: From Apple Developer Console
   - **Team ID**: `674CG3Y6T4`
4. Save

> **Note**: The client secret JWT expires after 180 days. Re-run the generation
> script with your `.p8` key to get a new one. Keep the `.p8` file safe — it
> cannot be re-downloaded from Apple.
> Native iOS/tvOS apps using ASAuthorizationAppleIDProvider do NOT need this
> secret and are not affected by rotation.

## Step 4: Set Up PowerSync Cloud

1. Go to [powersync.com](https://www.powersync.com) and create an account
2. Create a new PowerSync instance
3. Connect to your Supabase database:
   - **Host**: `db.<project-id>.supabase.co`
   - **Port**: `5432`
   - **Database**: `postgres`
   - **User**: `postgres`
   - **Password**: Your Supabase database password
4. Upload the sync rules from `powersync/sync-rules.yaml`
5. Click **Validate** — ensure all tables resolve correctly
6. Click **Deploy sync rules**
7. Note down the **PowerSync instance URL**: `https://<instance-id>.powersync.journeyapps.com`

## Step 5: Configure PowerSync JWT

PowerSync needs to verify Supabase JWTs:

1. In the PowerSync dashboard, go to **Instance > Auth**
2. Set the JWT issuer to: `https://<project-id>.supabase.co/auth/v1`
3. Set the JWKS URI to: `https://<project-id>.supabase.co/auth/v1/.well-known/jwks.json`
4. Alternatively, paste your Supabase JWT secret (found in Settings > API > JWT Secret)

## Step 6: Verify

1. Create a test user via Supabase Auth Dashboard
2. Use the Supabase client to sign in and insert a test playlist:

```sql
-- In Supabase SQL Editor (bypasses RLS for testing)
INSERT INTO playlists (user_id, name, type, url)
VALUES (
    '<your-test-user-uuid>',
    'Test Playlist',
    'm3u',
    'https://example.com/playlist.m3u'
);
```

3. Check PowerSync dashboard — the record should appear in the sync log

---

## Environment Variables (for Phase 2)

Save these for the React Router 7 web dashboard:

```env
SUPABASE_URL=https://<project-id>.supabase.co
SUPABASE_ANON_KEY=eyJ...
POWERSYNC_URL=https://<instance-id>.powersync.journeyapps.com
```

## Password Encryption

Xtream and Emby playlists store credentials. Passwords are encrypted in the
`encrypted_password` column using PostgreSQL's pgcrypto extension:

```sql
-- Encrypt (on insert/update)
INSERT INTO playlists (user_id, name, type, url, username, encrypted_password)
VALUES (
    auth.uid(),
    'My Xtream',
    'xtream',
    'https://provider.example.com',
    'myuser',
    pgp_sym_encrypt('mypassword', auth.uid()::text)
);

-- Decrypt (on read)
SELECT id, name, type, url, username,
       pgp_sym_decrypt(encrypted_password::bytea, auth.uid()::text) AS password
FROM playlists
WHERE user_id = auth.uid();
```

The encryption key is the user's UUID (from `auth.uid()`), which is only
available to the authenticated user via RLS. This ensures passwords are
encrypted at rest and only decryptable by the owning user.
