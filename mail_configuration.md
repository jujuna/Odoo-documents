# Mail Configuration — Servers, Alias Domains, Aliases, Bounces & Notifications

> **Modules:** `base` (`ir.mail_server`) + `mail` (`mail.alias.domain`, `mail.alias`, `fetchmail.server`, `mail.mail`, `mail.thread`, `mail.blacklist`)
> **Primary paths:** [`odoo/addons/base/models/ir_mail_server.py`](../odoo/addons/base/models/ir_mail_server.py), [`addons/mail/models/`](../addons/mail/models/)

## What It Does & Why It Exists

This is the subsystem that lets Odoo **send** email (notifications, invoices, mailings) and **receive** it (replies that thread onto records, new leads/tasks created from an inbox). It exists to make Odoo a participant in normal email conversations: a customer replies to a quotation email and the reply lands on the sales order chatter; a delivery failure (bounce) is detected and the address is flagged; a message to `jobs@company.com` creates a recruitment applicant.

Three things make this more involved than "set an SMTP server and go":

1. **Deliverability** — modern mail (SPF/DKIM/DMARC) rejects a server sending "as" an address it isn't authorized for. Odoo rewrites the visible `From` to protect against this.
2. **Threading** — replies must find their way back to the right record. Odoo uses a `catchall` address as `Reply-To` plus message-id matching.
3. **Bounces** — failed deliveries must be attributed and acted on. Odoo uses a `bounce` address as the envelope sender.

The single object that ties deliverability, threading, and bounces together is the **Alias Domain** — start there.

---

## The Big Picture — Two Flows

```
OUTGOING                                        INCOMING
--------                                        --------
message_post / notification                     mail provider (IMAP/POP) or MTA
   |                                                |
   v                                                v
mail.mail (queue, state=outgoing)               fetchmail.server._fetch_mail()  (cron, 5 min)
   |  grouped by (server, alias_domain, from)       |   object_id -> fallback model
   v                                                v
_find_mail_server -> pick ir.mail_server        MailThread.message_process()
   |  rewrite From (encapsulate)                     |
   v                                                v
ir.mail_server.send_email -> SMTP relay         message_route()  (precedence: reply -> alias -> fallback -> bounce)
   |  relay may rewrite From again                   |
   v                                                v
recipient                                        message_new (create) / message_update (append)
```

- **Outgoing** path: [mail_mail.py](../addons/mail/models/mail_mail.py) → [ir_mail_server.py](../odoo/addons/base/models/ir_mail_server.py).
- **Incoming** path: [fetchmail.py](../addons/mail/models/fetchmail.py) → [mail_thread.py `message_process`](../addons/mail/models/mail_thread.py#L1422).

---

## 1. The Central Config Object — Alias Domain (`mail.alias.domain`)

Defined in [mail_alias_domain.py](../addons/mail/models/mail_alias_domain.py). It replaced the pre-v16 config-parameter approach and is now the source of truth for the three special addresses. One record per email domain; companies point at it via `res.company.alias_domain_id`.

| Field | Default | What it is FOR |
|---|---|---|
| `name` | — | The bare domain, e.g. `example.com` |
| `bounce_alias` → `bounce_email` | `bounce` → `bounce@domain` | **Envelope sender / Return-Path.** Delivery failures come back here so Odoo can detect bounces ([:53](../addons/mail/models/mail_alias_domain.py#L53)) |
| `catchall_alias` → `catchall_email` | `catchall` → `catchall@domain` | **Reply-To.** Human replies route here so the gateway threads them onto the record ([:59](../addons/mail/models/mail_alias_domain.py#L59)) |
| `default_from` → `default_from_email` | `notifications` → `notifications@domain` | **From-override / notifications address.** The visible sender when the real author isn't authorized on the relay ([:65](../addons/mail/models/mail_alias_domain.py#L65)) |
| `company_ids` | — | Companies pinned to this domain (multi-company restriction) |

Note the asymmetry: `default_from` may be a bare local-part **or** a full email (`x@other.com`); if it already contains `@` it is used verbatim ([:72](../addons/mail/models/mail_alias_domain.py#L72)). Bounce/catchall are always `alias@name`.

**Company derivation.** `res.company` does **not** store these addresses — it stores only `alias_domain_id` and computes `bounce_email`, `catchall_email`, `default_from_email` from it ([res_company.py:35-53](../addons/mail/models/res_company.py#L35)). So all three addresses for a company come from **one** alias-domain record.

**Multi-company.** When `alias_domain.company_ids` is non-empty, aliases on that domain are company-restricted — [_check_alias_domain_id_mc](../addons/mail/models/mail_alias.py#L98) raises if an alias's record belongs to a different company. Per-record resolution walks: record's company `alias_domain_id` → env company's → first found ([models.py `_mail_get_alias_domains`](../addons/mail/models/models.py#L101)).

**Seeding.** There is no XML seed. The first alias-domain ever created auto-attaches to every company and alias that lacked one ([create, :148-160](../addons/mail/models/mail_alias_domain.py#L148)); on upgrade, [_migrate_icp_to_domain](../addons/mail/models/mail_alias_domain.py#L237) converts the legacy `mail.catchall.domain` / `mail.bounce.alias` / `mail.default.from` ICPs into a record (defaulting to `bounce`/`catchall`/`notifications`).

---

## 2. Outgoing Mail Servers (`ir.mail_server`)

Defined in [ir_mail_server.py](../odoo/addons/base/models/ir_mail_server.py) (base), extended by [mail/.../ir_mail_server.py](../addons/mail/models/ir_mail_server.py). `_order = 'sequence, id'`.

### Configuration fields that are decision points

| Field | Default | Notes |
|---|---|---|
| `smtp_host` / `smtp_port` | — / `25` | 465 for SSL, 587 for STARTTLS by convention |
| `smtp_encryption` | `none` | `none`, `starttls` / `starttls_strict`, `ssl` / `ssl_strict`. `*_strict` validates the server cert against the OS trust store; non-strict encrypts only ([:462](../odoo/addons/base/models/ir_mail_server.py#L462)) |
| `smtp_authentication` | `login` | `login` (user/pass), `certificate` (client SSL cert — requires encryption ≠ none), `cli` (use `odoo.conf` SMTP params) |
| `from_filter` | empty | Comma-separated addresses **or** domains this server may send "From". **The deliverability gate** — see §3 |
| `sequence` | `10` | Labeled "Priority"; lower wins when no specific server is requested |

`_onchange_encryption` flips the port to 465 on `ssl`, else 25 ([:973](../odoo/addons/base/models/ir_mail_server.py#L973)). `max_email_size` falls back to ICP `base.default_max_email_size` (10 MB).

### CLI / `odoo.conf` alternative

If no DB `ir.mail_server` matches, Odoo falls back to config params: `--smtp`, `--smtp-port`, `--smtp-user`, `--smtp-password`, `--smtp-ssl` (maps to STARTTLS), `--email-from`, `--from-filter` ([config.py:345](../odoo/tools/config.py#L345); consumed at [ir_mail_server.py:472](../odoo/addons/base/models/ir_mail_server.py#L472)). `--email-from` is what `_get_default_from_address` returns when there's no alias domain.

### Personal (per-user) outgoing servers

A user can have their own outgoing server (`owner_user_id` set). These are **excluded from normal selection** ([_find_mail_server_allowed_domain restricts to `owner_user_id = False`](../addons/mail/models/ir_mail_server.py#L84)) and only the creator's own mail may use them. They are **throttled** to avoid spam-flagging — default 30 emails/minute (ICP `mail.server.personal.limit.minutes`), enforced by [_split_by_delayed_batch](../addons/mail/models/mail_mail.py#L580), which splits and reschedules overflow via `scheduled_date`. Created with port 587 + STARTTLS + `from_filter = user's email` ([res_users.py:618](../addons/mail/models/res_users.py#L618)).

---

## 3. How the Visible `From` Is Resolved (the part that surprises people)

Every email has **two** sender addresses and either can be rewritten:

| | Header `From:` | Envelope sender (`MAIL FROM` → `Return-Path`) |
|---|---|---|
| Purpose | What the recipient sees | Authentication + bounce routing |
| Set from | message author, then rewritten | the alias-domain **bounce** address |

### Server selection — `_find_mail_server`

[_find_mail_server(email_from)](../odoo/addons/base/models/ir_mail_server.py#L868) tries, in order:

1. A server whose `from_filter` matches the **exact author email**, then one matching the **author's domain** → keep the author as `From`.
2. A server matching the **notifications address** (alias-domain `default_from_email`) → send as notifications.
3. First server with **no** `from_filter` → use notifications address if available, else the author (spoof).
4. Any server, with a warning.
5. No DB servers → CLI `--from-filter` fallback.

**`from_filter` matching** ([_match_from_filter](../odoo/addons/base/models/ir_mail_server.py#L950)): empty = matches everything; an entry **with `@`** matches that **exact email only** (never the domain — `email_domain_normalize` returns `False` for anything containing `@`, [mail.py:932](../odoo/tools/mail.py#L932)); an entry **without `@`** matches the **whole domain**. So `test1@gmail.com` in `from_filter` authorizes only that address; `gmail.com` authorizes all of `@gmail.com`.

### Encapsulation — keeping the name, swapping the address

At send time, [_prepare_email_message__](../odoo/addons/base/models/ir_mail_server.py#L673) checks: if the chosen sender equals the notifications address but the header `From` doesn't, it **encapsulates** ([:704](../odoo/addons/base/models/ir_mail_server.py#L704)):

```
encapsulate_email("Dato" <dato@gmail.com>, notifications@your-domain)
   ->  "Dato" <notifications@your-domain>
```

It keeps the **display name**, swaps the **address** to the authorized one ([encapsulate_email, mail.py:1002](../odoo/tools/mail.py#L1002)). The envelope `Return-Path` is set to the bounce address. The notifications/bounce values reach the SMTP layer via the `domain_notifications_email` / `domain_bounce_address` context set in [mail_mail.py:564](../addons/mail/models/mail_mail.py#L564).

### The relay has the final say

After Odoo builds the headers, the SMTP relay enforces its own policy. **Gmail / Google Workspace rewrites `From:` to the authenticated account** unless the address is a verified "Send mail as" alias — Odoo cannot override this.

#### Worked example: server logs in as `test1@gmail.com`, author is `dato@gmail.com`

| Config | Visible `From:` to recipient |
|---|---|
| Gmail relay, `dato@gmail.com` not a verified Gmail alias | **`test1@gmail.com`** (display name "Dato" usually survives) — Gmail forces it |
| Own domain + SPF/DKIM, `from_filter` not matching author + notifications set | `"Dato" <notifications@your-domain>` (encapsulated) |
| Server + relay authorized for `gmail.com` (`from_filter = gmail.com`) | `dato@gmail.com` |

This is exactly why a personal Gmail/Outlook mailbox makes a poor outgoing server: it masks the real author. Use a real domain with SPF/DKIM and a notifications address.

---

## 4. Reply-To vs Return-Path — the two round-trip addresses

These are deliberately different so human replies and delivery failures go to different places:

- **Reply-To = catchall** ([_notify_get_reply_to_batch](../addons/mail/models/models.py#L672)). Priority: a document-specific alias (e.g. a project's own alias) → else the company `catchall_email` → else the passed-in `email_from`. Replies land on the gateway and thread onto the record. A 68-char guard drops the display name if the formatted header would risk RFC folding / DKIM breakage ([:759](../addons/mail/models/models.py#L759)).
- **Return-Path = bounce** ([mail_thread.py:3837](../addons/mail/models/mail_thread.py#L3837)). Delivery failures go to `bounce@domain` for detection.

> **Owner vs target gotcha.** Reply-To resolution keys off the alias's **owner** (`alias_parent_model_id` / `alias_parent_thread_id`), while incoming record *creation* keys off the alias's **target** (`alias_model_id`). This split is the single most confusing part of the subsystem ([models.py:711](../addons/mail/models/models.py#L711)).

---

## 5. The Outgoing Queue (`mail.mail`)

[mail_mail.py](../addons/mail/models/mail_mail.py). States: `outgoing` (default) → `sent` / `exception` / `cancel` ([:69](../addons/mail/models/mail_mail.py#L69)).

- **Cron "Mail: Email Queue Manager"** runs `process_email_queue(batch_size=1000)` **hourly** ([ir_cron_data.xml:4](../addons/mail/data/ir_cron_data.xml#L4)). Picks `state=outgoing` mails whose `scheduled_date` is empty or past.
- **Grouping**: [_split_by_mail_configuration](../addons/mail/models/mail_mail.py#L529) groups mails by `(server, alias_domain, email_from)` so one SMTP session is reused per group, then batches by ICP `mail.session.batch.size` (1000).
- **Direct send**: if fewer than ICP `mail.mail.force.send.limit` (100) notifications, they send immediately instead of queuing ([mail_thread.py:3490](../addons/mail/models/mail_thread.py#L3490)). Set the limit to `0` to always queue.
- **Failures**: `failure_type` (`mail_smtp`, `mail_email_invalid`, `mail_from_invalid`, …) + `failure_reason` text. **No automatic retry** — a failed mail stays `exception` until `action_retry`/`mark_outgoing` resets it. Per-recipient invalid addresses are downgraded so other recipients still receive the mail ([_send, :868](../addons/mail/models/mail_mail.py#L868)).
- `auto_delete` mails are unlinked after a successful, unblocked send.

The Settings page shows `fail_counter` — the count of `mail.mail` in `exception` over the last 30 days ([res_config_settings.py:64](../addons/mail/models/res_config_settings.py#L64)).

---

## 6. Incoming Mail Servers (`fetchmail.server`)

[fetchmail.py](../addons/mail/models/fetchmail.py). (The standalone `fetchmail` addon was folded into `mail` in v19.)

- **Types** (`server_type`): `imap`, `pop`, `local` (an MTA pipes into `odoo-mailgate.py`). OAuth `gmail` / `outlook` are added by [google_gmail](../addons/google_gmail/models/fetchmail_server.py#L12) / [microsoft_outlook](../addons/microsoft_outlook/models/fetchmail_server.py#L16) via `selection_add` (XOAUTH2 IMAP login).
- **`object_id`** = the fallback model for records created from this server's mail; it is passed into the gateway as `default_fetchmail_server_id` + target model ([:278](../addons/mail/models/fetchmail.py#L278)).
- **Cron "Mail: Fetchmail Service"** runs `_fetch_mails()` every **5 minutes**, but is **auto-toggled** — active only when at least one confirmed non-`local` server exists ([_update_cron](../addons/mail/models/fetchmail.py#L159)).
- Fetch loop: IMAP pulls `UNSEEN` (marks `\Seen` after), POP pulls all (deletes after); batch limit 50; **commits after each message** so one bad email doesn't abort the batch ([:288](../addons/mail/models/fetchmail.py#L288)). A server failing for > 5 days is set back to draft and admin notified.

---

## 7. The Mail Gateway — How an Incoming Email Finds Its Record

[message_process](../addons/mail/models/mail_thread.py#L1422) parses the raw email, drops duplicates (same `Message-Id`), runs loop checks, then [message_route](../addons/mail/models/mail_thread.py#L1120) decides routing in **strict precedence**:

1. **Bounce** — if detected, hand to bounce handling and create **nothing** (§9).
2. **Reply** — match `References` / `In-Reply-To` (last 32) against existing `mail.message.message_id`. A hit appends to that record's `(model, res_id)` and **ignores alias defaults** (a reply never creates). A recipient that's an alias of a *different* model is treated as a forward, not a reply.
3. **Alias** — search `mail.alias` by full address (`alias_full_name`) or local-part (if `alias_incoming_local`). Each match → route `(alias_model, alias_force_thread_id, alias_defaults, …)`. `alias_force_thread_id` set → append to that fixed record; else **create** a new record of `alias_model_id`.
4. **Fallback model** — the `object_id` passed from the fetchmail server.
5. **Catchall + unroutable** → bounce; otherwise raise "No possible route found".

Then [_message_route_process](../addons/mail/models/mail_thread.py#L1331) calls `message_update` (append) or `message_new` (create), posting as `base.user_root`.

**Loop detection** ([_detect_loop_sender](../addons/mail/models/mail_thread.py#L1002)): if ≥ 20 records were created from the same sender (or ≥ 20 emails landed on one record) within 120 minutes, the mail is dropped with a single bounce (ICPs `mail.gateway.loop.threshold` / `.minutes`). Senders in `mail.gateway.allowed` are exempt.

---

## 8. Aliases (`mail.alias`)

[mail_alias.py](../addons/mail/models/mail_alias.py). An alias maps an inbound address to a model.

- **`alias_model_id`** — model to create/append (must be a `mail.thread`).
- **`alias_defaults`** — Python-dict literal of field values applied on creation (e.g. `{'project_id': 5}`).
- **`alias_force_thread_id`** — if set, every mail appends to this one record; no creation.
- **`alias_contact`** — the security policy ([:73](../addons/mail/models/mail_alias.py#L73)):
  - `everyone` (default) — anyone can post.
  - `partners` — only senders matching a known `res.partner`.
  - `followers` — only followers of the related record.
- **`alias_bounced_content`** — custom HTML returned to rejected senders.

**Contact-policy enforcement** ([_routing_check_route](../addons/mail/models/mail_thread.py#L909) → [_alias_get_error](../addons/mail/models/models.py#L783)): when the policy fails, the mail is **bounced back to the sender (DSN), not silently dropped**. A *config* error (e.g. `followers` policy on a model with no followers concept) also flips `alias_status='invalid'`.

**Attaching an alias to a model** — via `mail.alias.mixin` (`alias_id` required) or `mail.alias.mixin.optional` (created lazily when a name is set). Models override `_alias_get_creation_values` to set the target model + defaults. Examples:

- **project.project** → alias creates a `project.task` with `project_id` pre-filled ([project_project.py:751](../addons/project/models/project_project.py#L751)).
- **crm.team** → alias creates a `crm.lead` with `type` (lead/opportunity) + `team_id` ([crm_team.py:147](../addons/crm/models/crm_team.py#L147)).

**Name safety**: aliases can't collide with their domain's bounce/catchall names, are unique per `(alias_name, alias_domain_id)`, and are sanitized (lowercased, accent-stripped, disallowed chars → `-`).

---

## 9. Bounces & Blacklist

> **v19 note:** Odoo does **not** VERP-encode ids into the bounce address. The Return-Path is a static `bounce@domain`. The original message is recovered from the **embedded `message/rfc822` Message-Id** in the DSN, not from the address ([_get_bounced_message_data](../addons/mail/models/mail_thread.py#L1910)).

**Detection** ([_detect_is_bounce](../addons/mail/models/mail_thread.py#L957)): a `To` equal to a domain's `bounce_email`, OR a `mailer-daemon` From, OR a `multipart/report` (RFC 3462 DSN) content type.

**On bounce** ([_routing_handle_bounce](../addons/mail/models/mail_thread.py#L783)):
- Increments `message_bounce` on every blacklist-enabled record matching the bounced address ([+1 per bounce](../addons/mail/models/mail_thread_blacklist.py#L97)). The base mixin **only counts — it does not auto-blacklist.**
- Marks the linked `mail.notification` rows `failure_type='mail_bounce'`.
- Receiving a *normal* email from an address later **resets** its bounce counter to 0 ([_routing_reset_bounce](../addons/mail/models/mail_thread.py#L941)) — proof the address is alive.

**Auto-blacklist lives in `mass_mailing`**, not core: ≥ 5 bounces over 13 weeks (spread > 1 week, partner counter also ≥ 5) adds the address to `mail.blacklist` ([mass_mailing/mail_thread.py:47](../addons/mass_mailing/models/mail_thread.py#L47)).

**`mail.blacklist`** ([mail_blacklist.py](../addons/mail/models/mail_blacklist.py)): normalized-email + active flag. `_add` / `_remove` (archive) manage entries; the `mail.thread.blacklist` mixin computes `is_blacklisted`. **Enforcement is a mass-mailing concern** — recipients on blacklist-enabled models are filtered before a mailing sends. The transactional path (`message_post` → `mail.mail`) does **not** consult the blacklist.

---

## 10. Notifications — Who Gets an Email vs an In-App Message

- **`res.users.notification_type`** ([res_users.py:29](../addons/mail/models/res_users.py#L29)): `email` (default — chatter notifications go to the inbox of their email client) or `inbox` (in-app Discuss only). It is really a wrapper over membership in group `mail.group_mail_notification_type_inbox`. **Portal/shared users cannot be `inbox`** (DB constraint) — they're forced to `email`.
- **Recipient classification** ([mail_followers `_get_recipient_data`](../addons/mail/models/mail_followers.py#L356)): each recipient is `user` (internal), `portal` (shared user), or `customer` (partner, no user). Notification **groups** ([_notify_get_recipients_groups](../addons/mail/models/mail_thread.py#L4140)) then decide the email layout: **only internal `user` recipients get the document access button** by default; `portal` and `follower` buttons are off unless explicitly enabled; `customer` gets no button.
- **Email branding** ([mail_notification_layout](../addons/mail/data/mail_templates_email_layouts.xml#L4)): the access button uses `company.email_secondary_color` (default Odoo purple `#875A7B`) for background and `email_primary_color` (`#FFFFFF`) for text; the footer carries the company name/phone/email/website + "Powered by Odoo".

---

## 11. Where You Configure This in the UI

Settings → General Settings → **Discuss / Emails** section ([res_config_settings_views.xml:11](../addons/mail/views/res_config_settings_views.xml#L11)), shown only when **"Use Custom Email Servers"** (`external_email_server_default`) is on:

| Setting | Effect |
|---|---|
| Use Custom Email Servers | Reveals the server buttons + Gmail/Outlook module toggles |
| Outgoing Email Servers | Opens `ir.mail_server` list |
| Incoming Email Servers | Opens `fetchmail.server` list |
| Alias Domain (`company_dependent`) | Picks the company's `mail.alias.domain` — drives catchall/bounce/default-from |
| Email Button Text / Color | The two notification-email branding colors |

There is **no global "notifications" setting** — that is per-user (`notification_type`). DNS records are **not** generated in-product; the Alias Domain setting only links to the SPF docs ([:32](../addons/mail/views/res_config_settings_views.xml#L32)).

---

## 12. DNS / Deliverability (operational, not in-product)

For mail sent from your own domain to actually arrive, configure at the DNS level (Odoo does not do this for you):

- **SPF** — authorize the sending IP / relay for your domain.
- **DKIM** — sign outgoing mail; the Reply-To 68-char guard exists specifically so headers don't break DKIM ([models.py:741](../addons/mail/models/models.py#L741)).
- **DMARC** — policy tying SPF/DKIM together.

The reason encapsulation (§3) exists is to stay SPF/DKIM-aligned: Odoo sends *as* your authorized notifications address, not as the customer's address.

---

## 13. Key System Parameters

| ICP | Default | Effect |
|---|---|---|
| `mail.default.from` | `notifications` | Local-part of the default-from (legacy → migrated into alias domain) |
| `mail.default.from_filter` | CLI `--from-filter` | Default `from_filter` when no specific server matches |
| `mail.bounce.alias` / `mail.catchall.alias` / `mail.catchall.domain` | `bounce` / `catchall` / — | **Legacy** (pre-v16); read only to migrate into `mail.alias.domain` |
| `mail.mail.force.send.limit` | `100` | Below this, notifications send directly; `0` = always queue |
| `mail.mail.queue.batch.size` | `1000` | Mails per queue-cron run |
| `mail.session.batch.size` | `1000` | Mails per SMTP session batch |
| `mail.batch_size` | `50` | Mail *generation* batch size |
| `mail.server.personal.limit.minutes` | `30` | Emails/minute cap for personal servers |
| `mail.disable_personal_mail_servers` | unset | Force public servers only |
| `mail.gateway.loop.threshold` / `.minutes` | `20` / `120` | Inbound loop detection |
| `base.default_max_email_size` | `10` (MB) | Fallback max email size |

---

## 14. Common Scenarios & Troubleshooting

| Symptom | Likely cause |
|---|---|
| Recipients see `notifications@yourdomain`, not the author | Normal — author didn't match any server's `from_filter`, so Odoo encapsulated (§3) |
| Recipients see your Gmail login address regardless of config | Gmail relay rewrites `From` to the authenticated account; not an Odoo bug (§3) |
| Replies don't thread onto the record | `catchall` not configured / not receiving, or Reply-To overridden; check the alias domain + incoming server (§4, §7) |
| Inbound email to `jobs@…` does nothing | No matching `mail.alias`, or `alias_contact` policy rejected the sender (and bounced) (§8) |
| Address keeps getting blacklisted | ≥ 5 bounces over 13 weeks via mass mailing (§9) — verify the address is real |
| Emails stuck in "Outgoing" | Queue cron disabled, or all mails in `exception` (no auto-retry) — check `fail_counter` (§5) |
| A user gets no notification emails | Their `notification_type` is `inbox`, or they're the message author (authors aren't notified) (§10) |

---

## Dependencies & Gotchas

- **Alias domain is the hub** — catchall, bounce, and default-from all come from one record; companies only *point* at it.
- **`from_filter` with a full email matches only that email**, never its domain — use a bare domain for domain-wide authorization.
- **Reply-To = catchall, Return-Path = bounce** — two different addresses by design.
- **Owner vs target** — Reply-To keys off the alias owner; record creation keys off the alias target.
- **No VERP in v19** — bounces are matched via embedded Message-Id, not an encoded address.
- **Blacklist enforcement is mass-mailing only** — transactional mail ignores it.
- **Don't use a personal Gmail/Outlook mailbox as the main outgoing server** — it masks the author and is rate-limited.
