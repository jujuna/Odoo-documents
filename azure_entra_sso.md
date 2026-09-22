# Azure / Microsoft Entra ID ↔ Odoo 19

> **Modules:** `auth_oauth`, `auth_signup`, `auth_ldap`, `auth_timeout`, `microsoft_account`, `microsoft_outlook`, `microsoft_calendar`
> **Paths:** [`addons/auth_oauth/`](../addons/auth_oauth/), [`addons/auth_ldap/`](../addons/auth_ldap/), [`addons/auth_signup/`](../addons/auth_signup/)

## What It Does & Why It Exists

Odoo has **no Azure/Entra connector**. What it has is a generic OAuth2 login module (`auth_oauth`) and a generic LDAP module (`auth_ldap`). Entra ID is integrated by hand-configuring an `auth.oauth.provider` record with Microsoft's identity-platform endpoints. There is no shipped Microsoft provider record — [`auth_oauth_data.xml`](../addons/auth_oauth/data/auth_oauth_data.xml) seeds only Odoo.com, Google and Facebook.

The practical consequence: **Entra becomes an authentication source, not a user-management source.** Odoo has no SCIM endpoint, no group-claim mapping, and no deprovisioning hook. Access rights, activation and archiving of Odoo users stay in Odoo.

Separately, `microsoft_outlook` / `microsoft_calendar` use Microsoft Graph OAuth for mail and calendar. These are unrelated to login and are covered at the bottom.

---

## The Big Picture — SSO Login Flow

```
User clicks "Sign in with Microsoft"
   -> /auth_oauth/signin builds authorize URL with response_type=token   (implicit flow)
   -> Entra authenticates (password + MFA + Conditional Access)
   -> redirect back with #access_token=... in the URL fragment
   -> Odoo converts fragment to query string, calls the UserInfo URL with the token
   -> extracts `sub` -> looks up res.users by (oauth_provider_id, oauth_uid)
        MATCH    -> log in, store the access token
        NO MATCH -> fall through to auth_signup -> almost always AccessDenied
```

The flow type matters. [`controllers/main.py:64`](../addons/auth_oauth/controllers/main.py#L64) hardcodes `response_type='token'` — **implicit flow**, not authorization-code + PKCE. Odoo never validates an `id_token` JWT; it takes the opaque access token and calls the provider's UserInfo endpoint ([`_auth_oauth_validate`](../addons/auth_oauth/models/res_users.py#L64)). Entra still allows this, but implicit-flow access tokens must be explicitly enabled on the app registration, and modern Entra guidance discourages the pattern.

The identity anchor is the `sub` claim, stored on `res.users.oauth_uid` with a uniqueness constraint per provider. Not the email. Change a user's UPN in Entra and the link survives; delete and recreate the Entra account and it breaks.

---

## Entra-Side Configuration

App registration in the Azure portal:

| Setting | Value |
|---|---|
| Redirect URI (platform: Web) | `https://<your-odoo>/auth_oauth/signin` |
| Authentication → Implicit grant | **Access tokens** checked |
| Supported account types | Single tenant (unless you genuinely need guests/multi-tenant) |
| API permissions | `openid`, `profile`, `email`, `User.Read` (delegated) |

Odoo-side provider record (Settings → Users & Companies → OAuth Providers, `auth.oauth.provider`):

| Field | Value |
|---|---|
| Provider name | `Microsoft Entra ID` |
| Client ID | Application (client) ID from the app registration |
| Authorization URL | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize` |
| Scope | `openid profile email` |
| UserInfo URL | `https://graph.microsoft.com/oidc/userinfo` |
| Allowed | ✅ |

**Required system parameter:** set `auth_oauth.authorization_header` = `True`. Without it, [`_auth_oauth_rpc`](../addons/auth_oauth/models/res_users.py#L45) sends the token as an `access_token` **query parameter**, which Microsoft Graph rejects. This is the single most common cause of a silently failing Entra login in Odoo.

No client secret is used or stored — implicit flow has no token exchange.

---

## What You Can and Cannot Control From Entra

### You genuinely control

| Capability | Where |
|---|---|
| Who may obtain a token at all | Enterprise application → Properties → **Assignment required = Yes**, then assign specific users/groups |
| MFA, device compliance, IP/location, risk | Conditional Access policies on that enterprise app |
| Password policy, rotation, self-service reset | Entra |
| Sign-in audit trail | Entra sign-in logs |
| Revoking future token issuance | Disable/delete the Entra account — blocks new SSO logins immediately |

### You do **not** control

| Gap | Reality |
|---|---|
| **Provisioning** | No SCIM. Odoo exposes no provisioning endpoint; Entra's "Automatic provisioning" cannot target it. |
| **Group / role mapping** | Odoo access groups are set only inside Odoo. No claim is read into groups. |
| **Deprovisioning** | Disabling the Entra account does not archive the Odoo user. The `res.users` record stays active. |
| **Password fallback** | Odoo's local password login stays enabled. A user disabled in Entra can still log in with their Odoo password if one is set. There is no built-in "SSO only" toggle. |
| **Session revocation** | Revoking sessions in Entra does not kill an existing Odoo session. Odoo sessions expire on their own schedule (`auth_timeout` for idle logout). |

**That last pair is the security-relevant one.** SSO without removing local passwords gives you the appearance of centralised control, not the substance.

---

## User Linking — the part that surprises people

`_auth_oauth_signin` ([res_users.py:105](../addons/auth_oauth/models/res_users.py#L105)) matches **only** on `(oauth_provider_id, oauth_uid)`. It does not match on login or email. An existing Odoo internal user with no `oauth_uid` will not be recognised on first Microsoft login.

On no-match, Odoo falls into `auth_signup.signup()` ([auth_signup/models/res_users.py:38](../addons/auth_signup/models/res_users.py#L38)):

- **With a signup token** (from an Odoo invitation link) and a user already on that partner → writes `oauth_provider_id` + `oauth_uid` onto the existing user. **This is the supported linking path.**
- **Without a token**, `_signup_create_user` raises `SignupError` unless `auth_signup.invitation_scope` = `b2c`; with `b2c`, it copies `base.template_portal_user_id` and creates a **portal** user — never an internal one.

So there are exactly two ways to get an internal Odoo user onto Entra SSO:

1. Create the user in Odoo, use **Invite / Send Password Reset** so the partner gets a signup token, and have the user complete it by clicking "Sign in with Microsoft".
2. Set `OAuth Provider` and `OAuth User ID` (the Entra object `sub`) directly on the `res.users` record from the developer view.

There is no self-service path where an Entra employee logs in and becomes an internal Odoo user.

---

## The LDAP Alternative — and why it usually isn't one

`auth_ldap` has what OAuth lacks: a **Template User** plus `create_user` ([res_company_ldap.py:65](../addons/auth_ldap/models/res_company_ldap.py#L65)), so a first successful LDAP bind auto-creates an internal Odoo user copied from a template — real auto-provisioning with real groups.

The blocker: **Entra ID exposes no LDAP interface.** You would need either

- **Entra Domain Services** — a separate paid managed-domain resource offering LDAPS, or
- on-premises AD reachable from the Odoo host over VPN/private link.

If either already exists in the estate, LDAP is the better fit for onboarding and worth evaluating against OAuth. Otherwise it is a new paid dependency added purely for authentication, and Conditional Access/MFA do not apply to LDAP binds.

---

## Getting Real Control — what a custom module would need

Everything below is missing from stock Odoo. If "control Odoo users from Azure" is a hard requirement, this is the scope:

| Need | Implementation |
|---|---|
| Deprovisioning | Scheduled action calling Graph `/users?$filter=accountEnabled eq false` (or delta query), archiving matched `res.users` by `oauth_uid` |
| Group → Odoo-group mapping | On login, read Graph `/me/memberOf`, map to `res.groups` via a config model, write `groups_id` |
| Auto-provision internal users | Override `_generate_signup_values` / `_auth_oauth_signin` to create from an internal template user instead of falling into `auth_signup` |
| SSO-only enforcement | Blank the password on SSO-linked users; keep one break-glass local admin |
| Authorization-code + PKCE | Substantial override of `auth_oauth`'s controller and `auth_oauth` model method — the whole flow is implicit-only today |

The pragmatic middle ground for most deployments: OAuth login + Entra assignment-required + Conditional Access, passwords cleared on all SSO users, one break-glass admin, and a documented manual offboarding step (archive the Odoo user) in the HR leaver checklist.

---

## Unrelated Microsoft Integrations

| Module | What it does |
|---|---|
| `microsoft_account` | Shared OAuth token plumbing for the Graph-based modules |
| `microsoft_outlook` | OAuth authentication for outgoing/incoming mail servers (replaces SMTP passwords). See [`mail_configuration.md`](mail_configuration.md) |
| `microsoft_calendar` | Two-way calendar sync with Outlook/M365 |
| `appointment_microsoft_calendar` (enterprise) | Availability lookup for the Appointments app |

None of these affect who can log into Odoo. They use their own app registration and their own consent.

Azure as **infrastructure** (VMs, PostgreSQL Flexible Server, Blob Storage for filestore) is orthogonal — Odoo runs there like any Linux host, with no Odoo-side module involved.

---

## Edge Cases & Gotchas

- **`auth_oauth.authorization_header` unset → login silently fails.** Graph will not accept a query-string token. Symptom: bounced back to the login screen with "Access Denied".
- **Implicit access tokens not enabled** on the app registration → Entra returns an error in the fragment; Odoo shows a generic failure.
- **The `sub` from Graph userinfo is pairwise per application.** Re-creating the app registration issues new `sub` values and orphans every `oauth_uid` in `res.users`.
- **Deleting an Entra user does not stop an active Odoo session** and does not touch the Odoo record.
- **`b2c` invitation scope is a real exposure.** Combined with a multi-tenant app registration, any Microsoft account could self-create an Odoo portal user. Keep `invitation_scope` = `b2b` unless the portal is deliberately public.
- **Odoo stores the access token** in `res.users.oauth_access_token` (`groups=NO_ACCESS`, `prefetch=False`) and includes it in the session-token hash ([`_get_session_token_fields`](../addons/auth_oauth/models/res_users.py#L153)) — clearing it invalidates that user's sessions.
- **Guest (B2B) accounts** authenticate fine but often have no `email` claim shape you expect; check what UserInfo actually returns before relying on it for `login`.
