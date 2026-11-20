# JWT Bearer Flow Authentication Setup

> **日本語版**: [jwt-auth-setup.ja.md](jwt-auth-setup.ja.md)

Step-by-step guide to configure JWT Bearer Flow for CI/CD deployment to Salesforce orgs.

## Overview

```
GitHub Actions → JWT authentication (as a dedicated CI user) → Deploy to Salesforce org
```

Requirements:

- Admin access to Salesforce org
- OpenSSL (for key generation)
- Access to GitHub repository Settings

## 1. Generate Private Key and Certificate

Run locally:

```bash
mkdir -p ~/.config/salesforce-ci && cd ~/.config/salesforce-ci

# Generate private key
openssl genrsa -out server.key 2048 && chmod 600 server.key

# Generate certificate (valid for 365 days)
openssl req -new -x509 -key server.key -out server.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"
```

`server.key` is used in CI. `server.crt` is uploaded to Salesforce. Keep both outside the repository.

## 2. Create a Dedicated CI User

Deploys run as a dedicated integration user, not a personal account, so the pipeline is unaffected by staff changes and password policies. Salesforce has no user-less service principal — a dedicated integration user is the Salesforce equivalent of a service account.

You can create it from an admin-authenticated sf CLI:

```bash
# Get the System Administrator profile ID
pnpm exec sf data query --target-org sandbox \
  --query "SELECT Id FROM Profile WHERE Name = 'System Administrator'"

# Create the CI user (replace ProfileId with the result above)
pnpm exec sf data create record --target-org sandbox --sobject User --values \
  "Username='github-ci@company.com.sandboxname' LastName='GitHub CI' Alias='ghci' Email='<admin email>' TimeZoneSidKey='Asia/Tokyo' LocaleSidKey='ja_JP' EmailEncodingKey='UTF-8' LanguageLocaleKey='ja' ProfileId='<ProfileId>'"
```

Do not set a password. The user stays password-less and authenticates only via the JWT certificate.

> **License note**: the free "Salesforce Integration" (API-only) license is hard to combine with the permissions metadata deploys need (per-type permissions, plus Modify All Data for some types). A full license with the System Administrator profile is recommended.

## 3. Create an External Client App in Salesforce

> **Note**: orgs provisioned since 2025 disable creation of new Connected Apps by default
> (even via the Metadata API the deploy fails with "Cannot create connected apps").
> Use the successor, an **External Client App**: it officially supports the JWT Bearer Flow and works with `sf org login jwt` as-is.
> The app configuration is not included in this repository and is managed manually in the org — when you change it, update this document to keep a record in Git.

### Configure in the Sandbox org

1. **Setup** → Quick Find: type "App" → **App Manager**
2. **New App ▼** → **New External Client App**
3. Basic information:
   - External Client App Name: `CI Deploy` / API Name: `CI_Deploy`
   - Contact Email: admin email / Distribution State: **Local**
4. Check **Enable OAuth Settings**:
   - Callback URL: `https://login.salesforce.com/services/oauth2/callback` (unused by this flow but required)
   - OAuth Scopes: `api` / `web` / `refresh_token, offline_access`
   - Check **Enable JWT Bearer Flow** → upload `server.crt`
     (if the macOS file dialog hides `~/.config`, press Cmd+Shift+. to show hidden files)
5. **Save**

### Configure Access Policy

1. Open the app's **Policies** tab → **Edit**
2. In App Policies, under **Select Profiles**, move "System Administrator" to selected
3. In OAuth Policies, set **Permitted Users** to **Admin approved users are pre-authorized**
4. **Save**

### Get the Consumer Key

1. **Settings** tab → **OAuth Settings** → reveal consumer key and secret (identity verification may be required)
2. Copy the **Consumer Key** (this is `SF_CLIENT_ID`; the consumer secret is not used by the JWT flow)

## 4. Repeat for the Production Org

Create the same CI user (`github-ci@company.com`) and External Client App in Production. Using the same `server.crt` allows the same private key to authenticate to both orgs.

## 5. Configure GitHub Secrets

Create the environments under repository **Settings** → **Environments**. With the gh CLI:

```bash
gh api -X PUT repos/OWNER/REPO/environments/sandbox > /dev/null
gh secret set SF_CLIENT_ID --env sandbox --body '<consumer key>'
gh secret set SF_JWT_KEY --env sandbox < ~/.config/salesforce-ci/server.key
gh secret set SF_USERNAME --env sandbox --body 'github-ci@company.com.sandboxname'
gh secret set SF_INSTANCE_URL --env sandbox --body 'https://mycompany--dev.sandbox.my.salesforce.com'
```

### `sandbox` environment

| Secret            | Value                                              |
| ----------------- | -------------------------------------------------- |
| `SF_CLIENT_ID`    | External Client App consumer key                   |
| `SF_JWT_KEY`      | Contents of `server.key` (full PEM text)           |
| `SF_USERNAME`     | `github-ci@company.com.sandboxname`                |
| `SF_INSTANCE_URL` | `https://mycompany--dev.sandbox.my.salesforce.com` |

### `production` environment

| Secret            | Value                                 |
| ----------------- | ------------------------------------- |
| `SF_CLIENT_ID`    | Production app consumer key           |
| `SF_JWT_KEY`      | Same `server.key` contents            |
| `SF_USERNAME`     | `github-ci@company.com`               |
| `SF_INSTANCE_URL` | `https://mycompany.my.salesforce.com` |

### Repository-level Secrets (for CI validation)

The PR validate job runs outside environments, so Sandbox secrets are also needed at the repository level:

| Secret                    | Value                    |
| ------------------------- | ------------------------ |
| `SF_CLIENT_ID`            | Sandbox app consumer key |
| `SF_JWT_KEY`              | Contents of `server.key` |
| `SF_SANDBOX_USERNAME`     | CI username (Sandbox)    |
| `SF_SANDBOX_INSTANCE_URL` | Sandbox URL              |

## 6. Test Authentication Locally

```bash
pnpm exec sf org login jwt \
  --client-id <consumer key> \
  --jwt-key-file ~/.config/salesforce-ci/server.key \
  --username github-ci@company.com.sandboxname \
  --instance-url https://mycompany--dev.sandbox.my.salesforce.com \
  --alias ci-sandbox
```

On success:

```
Successfully authorized github-ci@company.com.sandboxname with org ID 00D...
```

## 7. Verify

```bash
# Dry-run deploy to Sandbox as the CI user
pnpm exec sf project deploy start --dry-run --target-org ci-sandbox --wait 30
```

## Troubleshooting

### "Cannot create connected apps. To enable creation of connected apps, contact Salesforce Customer Support"

Newer orgs disable creation of new Connected Apps. Create an External Client App instead, as described in this document.

### `INVALID_LOGIN: Invalid login credentials`

- Verify the app's access policy pre-authorizes the user's profile
- Confirm the consumer key is correct
- Confirm the username is correct (Sandbox requires the `.sandboxname` suffix)

### `JWT_INVALID_GRANT: user hasn't approved this consumer`

- Verify "Admin approved users are pre-authorized" is set
- Verify the profile is in the selected list

### `INVALID_CLIENT_ID`

- App creation can take up to 10 minutes to propagate
- Re-copy the consumer key

### Certificate expiration

```bash
# Generate a new certificate (the private key stays the same)
openssl req -new -x509 -key ~/.config/salesforce-ci/server.key \
  -out ~/.config/salesforce-ci/server.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"

# Replace the certificate in the External Client App's JWT Bearer Flow settings
```

The private key (`server.key`) remains unchanged, so no GitHub Secrets update is needed.

## Security Notes

- Never commit `server.key` to the repository (keep it outside the repo, e.g. `~/.config/salesforce-ci/`)
- After registering it in GitHub Secrets, you may delete the local `server.key` (keep it in a safe place if you plan to reissue certificates)
- Set a calendar reminder for certificate expiration
- Add **Required reviewers** and a **deployment branch policy (main only)** to the `production` environment
