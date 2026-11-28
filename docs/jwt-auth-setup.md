# JWT Bearer Flow Authentication Setup

> **日本語版**: [jwt-auth-setup.ja.md](jwt-auth-setup.ja.md)

Step-by-step guide to configure JWT Bearer Flow for CI/CD deployment to Salesforce orgs.

## Overview

```text
GitHub Actions → JWT authentication (as a dedicated CI user) → Deploy to Salesforce org
```

Requirements:

- Admin access to Salesforce org
- OpenSSL (for key generation)
- Access to GitHub repository Settings

## 1. Generate Private Keys and Certificates

Generate one key pair per trust tier — one for production, one shared by all sandboxes. A sandbox-only key cannot sign tokens that production accepts, so the unprotected sandbox environments never hold a key that works against production.

```bash
mkdir -p ~/.config/salesforce-ci && cd ~/.config/salesforce-ci

# Production key pair
openssl genrsa -out production.key 2048 && chmod 600 production.key
openssl req -new -x509 -key production.key -out production.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"

# Sandbox key pair
openssl genrsa -out sandbox.key 2048 && chmod 600 sandbox.key
openssl req -new -x509 -key sandbox.key -out sandbox.crt -days 365 \
  -subj "/CN=salesforce-ci-sandbox/O=YourCompany"
```

The `.key` files are used in CI. The `.crt` files are uploaded to Salesforce. Keep all of them outside the repository.

## 2. Create a Dedicated CI User

Deploys run as a dedicated integration user, not a personal account, so the pipeline is unaffected by staff changes and password policies. Salesforce has no user-less service principal — a dedicated integration user is the Salesforce equivalent of a service account.

You can create it from an admin-authenticated sf CLI:

```bash
# Get the System Administrator profile ID
pnpm exec sf data query --target-org production \
  --query "SELECT Id FROM Profile WHERE Name = 'System Administrator'"

# Create the CI user (replace ProfileId with the result above)
pnpm exec sf data create record --target-org production --sobject User --values \
  "Username='github-ci@company.com' LastName='GitHub CI' Alias='ghci' Email='<admin email>' TimeZoneSidKey='Asia/Tokyo' LocaleSidKey='ja_JP' EmailEncodingKey='UTF-8' LanguageLocaleKey='ja' ProfileId='<ProfileId>'"
```

Do not set a password. The user stays password-less and authenticates only via the JWT certificate.

> **License note**: the free "Salesforce Integration" (API-only) license is hard to combine with the permissions metadata deploys need (per-type permissions, plus Modify All Data for some types). A full license with the System Administrator profile is recommended.

## 3. Create an External Client App in Salesforce

> **Note**: orgs provisioned since 2025 disable creation of new Connected Apps by default
> (even via the Metadata API the deploy fails with "Cannot create connected apps").
> Use the successor, an **External Client App**: it officially supports the JWT Bearer Flow and works with `sf org login jwt` as-is.
> The app configuration is not included in this repository and is managed manually in the org — when you change it, update this document to keep a record in Git.

### Configure in the Production org

1. **Setup** → Quick Find: type "App" → **App Manager**
2. **New App ▼** → **New External Client App**
3. Basic information:
   - External Client App Name: `CI Deploy` / API Name: `CI_Deploy`
   - Contact Email: admin email / Distribution State: **Local**
4. Check **Enable OAuth Settings**:
   - Callback URL: `https://login.salesforce.com/services/oauth2/callback` (unused by this flow but required)
   - OAuth Scopes: `api` / `web` / `refresh_token, offline_access`
   - Check **Enable JWT Bearer Flow** → upload `production.crt`
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

## 4. Sandboxes Receive Copies on Refresh

Everything is created once, in Production; each sandbox receives a copy on refresh. The External Client App is cloned with the **same consumer key**, and the CI user is cloned with a `.{sandboxname}` username suffix. The refresh also appends `.invalid` to user emails, which is harmless for a CI user that receives no mail.

The clone carries the **production certificate**, so after each refresh, replace the certificate in the sandbox copy of the app with `sandbox.crt`. Until it is replaced, CI authentication against that sandbox fails with an explicit error — it never falls through to another org. For a sandbox you cannot refresh yet, create the same app (with `sandbox.crt`) and user there manually.

## 5. Configure GitHub

Only the private keys are secrets. Values shared by every org are repository **variables**; each environment holds only its tier's key and, for sandboxes, `SANDBOX_ID`. The workflows derive the username (`SF_CI_USERNAME` + `.SANDBOX_ID` suffix) and the instance URL (from `SF_MY_DOMAIN` / `SANDBOX_ID`), so adding an environment means registering just those two values.

```bash
# Repository variables (shared by all environments)
gh variable set SF_MY_DOMAIN --body 'mycompany'
gh variable set SF_CI_USERNAME --body 'github-ci@company.com'
gh variable set SF_CLIENT_ID --body '<consumer key>'

# Per environment
gh api -X PUT repos/OWNER/REPO/environments/sandbox > /dev/null
gh secret set SF_JWT_KEY --env sandbox < ~/.config/salesforce-ci/sandbox.key
gh variable set SANDBOX_ID --env sandbox --body '<sandbox name>'

gh api -X PUT repos/OWNER/REPO/environments/production > /dev/null
gh secret set SF_JWT_KEY --env production < ~/.config/salesforce-ci/production.key
```

### Repository variables

| Name             | Value                                                       |
| ---------------- | ----------------------------------------------------------- |
| `SF_MY_DOMAIN`   | My Domain name (`https://<SF_MY_DOMAIN>.my.salesforce.com`) |
| `SF_CI_USERNAME` | `github-ci@company.com`                                     |
| `SF_CLIENT_ID`   | External Client App consumer key                            |

### Each environment

| Kind     | Name         | Value                                                                                   |
| -------- | ------------ | --------------------------------------------------------------------------------------- |
| Secret   | `SF_JWT_KEY` | The tier's key: `sandbox.key` on sandbox environments, `production.key` on `production` |
| Variable | `SANDBOX_ID` | Sandbox name (**do not set** on `production`)                                           |

Each environment holds **its own tier's key**. The sandbox key cannot sign tokens production accepts (production only trusts `production.crt`), so even though sandbox environments have no protection rules, nothing they hold can bypass the `production` environment's required reviewers. Keep the keys as environment secrets, not repository secrets — a repository secret can be read by a workflow on any branch.

The PR validate job also runs against the `sandbox` environment
(`environment: sandbox` in ci.yml), so no repository-level copies of the key are needed.

## 6. Test Authentication Locally

```bash
pnpm exec sf org login jwt \
  --client-id <consumer key> \
  --jwt-key-file ~/.config/salesforce-ci/sandbox.key \
  --username github-ci@company.com.sandboxname \
  --instance-url https://mycompany--dev.sandbox.my.salesforce.com \
  --alias ci-sandbox
```

On success:

```text
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
# Generate a new certificate (the private key stays the same); repeat per key pair
openssl req -new -x509 -key ~/.config/salesforce-ci/production.key \
  -out ~/.config/salesforce-ci/production.crt -days 365 \
  -subj "/CN=salesforce-ci/O=YourCompany"

# Replace the certificate in the External Client App's JWT Bearer Flow settings
```

The private keys remain unchanged, so no GitHub Secrets update is needed.

## Security Notes

- Never commit the private keys to the repository (keep them outside the repo, e.g. `~/.config/salesforce-ci/`)
- After registering them in GitHub Secrets, you may delete the local keys (keep them in a safe place if you plan to reissue certificates)
- Set a calendar reminder for certificate expiration
- Add **Required reviewers** and a **deployment branch policy (main only)** to the `production` environment
