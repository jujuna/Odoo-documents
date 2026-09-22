# Recruitment — Where an Applicant's Source Comes From

> **Modules:** `hr_recruitment`, `website_hr_recruitment`, `utm` | **Path:** [`addons/hr_recruitment/`](../addons/hr_recruitment/), [`addons/utm/`](../addons/utm/)
> Focused doc: only the Source / Medium / Campaign ("Sourcing") side of Recruitment.

## What This Answers

"Where did this applicant come from?" is answered by three UTM fields on the applicant —
**Source** (`source_id`), **Medium** (`medium_id`), **Campaign** (`campaign_id`) — shown in the
*Sourcing* group of the applicant form ([hr_applicant_views.xml:204](../addons/hr_recruitment/views/hr_applicant_views.xml#L204)).

There is **no inference logic**. Odoo never looks at the applicant's email domain, the job board
that forwarded the mail, or the referrer header to guess a source. The field is filled only if one
of two mechanisms hands a value to `create()`. Everything else leaves it empty.

---

## The Two Mechanisms

```
Visitor clicks tracker URL  -->  ?utm_source=LinkedIn in URL
                            -->  ir_http._post_dispatch sets cookie odoo_utm_source
                            -->  visitor applies (any page, up to 31 days later)
                            -->  create() -> default_get() reads cookie -> source_id

Candidate emails job+linkedin@company.com
                            -->  mail.alias with alias_defaults {'source_id': ...}
                            -->  message_new(custom_values=alias_defaults) -> source_id
```

### 1. Website apply — the UTM cookie

`hr.applicant` inherits `utm.mixin` ([utm_mixin.py:15](../addons/utm/models/utm_mixin.py#L15)), which
carries `source_id` / `medium_id` / `campaign_id` and, crucially, a `default_get` override
([utm_mixin.py:26](../addons/utm/models/utm_mixin.py#L26)).

The chain:

| Step | Code |
|---|---|
| Any HTTP response, if the request URL had `utm_source=X`, writes cookie `odoo_utm_source=X`, `max_age` 31 days, host-scoped | [ir_http.py:15](../addons/utm/models/ir_http.py#L15) |
| The website form controller creates the applicant as SUPERUSER with only the submitted fields | [form.py:263](../addons/website/controllers/form.py#L263) |
| ORM `create()` fills every field absent from `vals` via `default_get` | [models.py:1546](../odoo/orm/models.py#L1546), called at [models.py:4794](../odoo/orm/models.py#L4794) |
| `utm.mixin.default_get` reads the three cookies; a string value is resolved to a `utm.source` record | [utm_mixin.py:33](../addons/utm/models/utm_mixin.py#L33) |
| No matching `utm.source` (case-insensitive `name =ilike`) → **a new one is created** | `_find_or_create_record`, [utm_mixin.py:88](../addons/utm/models/utm_mixin.py#L88) |

So the source is dynamic, but it is dynamic *at create time from a cookie*, not from anything about
the application itself.

**Non-obvious consequences:**

- The cookie is set by **any** page hit carrying `utm_source`, is host-wide, and lives 31 days. A
  visitor who once landed via a marketing link and applies three weeks later through a Google search
  still gets the old source. Last-touch it is not; it's *last URL parameter seen*.
- Unknown source strings silently create `utm.source` rows. A typo in a hand-shared tracker URL
  produces a new source in the catalog.
- `default_get` **skips UTM entirely** for a non-superuser in `sales_team.group_sale_salesman`
  ([utm_mixin.py:30](../addons/utm/models/utm_mixin.py#L30)). Irrelevant to the website flow (it runs
  as SUPERUSER) but it means a salesperson creating an applicant in the backend never gets defaults.
- Tracker URLs are generated per recruitment source by `_compute_url`
  ([website_hr_recruitment/models/hr_recruitment_source.py:14](../addons/website_hr_recruitment/models/hr_recruitment_source.py#L14)) —
  it appends `utm_campaign=Job`, `utm_medium` (default `website`), `utm_source=<source name>`.

### 2. Email alias per recruitment source

On a job position, *Recruitment Sources* (`hr.recruitment.source`, one row per job × source) can each
get their own catch-all address via `create_alias`
([hr_recruitment_source.py:30](../addons/hr_recruitment/models/hr_recruitment_source.py#L30)).
The alias is named `<job alias>+<source name>` and its `alias_defaults` hardcode:

| Key | Value |
|---|---|
| `job_id` | the job |
| `source_id` | the recruitment source's `utm.source` |
| `medium_id` | `email` |
| `campaign_id` | `hr_recruitment.utm_campaign_job` |

Mail arriving at that address goes through `hr.applicant.message_new`
([hr_applicant.py:935](../addons/hr_recruitment/models/hr_applicant.py#L935)), which merges
`custom_values` (= the alias defaults) into the vals — so the applicant is born with the source set.

This is the only path that is truly deterministic: address → source.

---

## Paths That Leave Source Empty

| Path | Why |
|---|---|
| Mail to the **job's own alias** (`job._alias_get_creation_values`, [hr_job.py:273](../addons/hr_recruitment/models/hr_job.py#L273)) | its `alias_defaults` set job / department / company / user only — no UTM |
| Mail from a **Job Platform** (`hr.job.platform` — Indeed, LinkedIn forwarders, [hr_job_platform.py](../addons/hr_recruitment/models/hr_job_platform.py)) | the model only strips the sender and regex-extracts the candidate name; it has no source field |
| Enterprise **job-board integrations** (`hr_recruitment_integration_base` / `_monster` / `_website`) | none of them write `source_id`; applications come back as ordinary alias mail |
| **Backend manual creation** | the field is plain editable input with a placeholder; whoever creates the record types it or leaves it blank |
| Website apply where the visitor never hit a `utm_source` URL | no cookie, no default |

If accurate source attribution matters, the practical lever is: create one `hr.recruitment.source` per
channel per job, and use **either** its tracker URL (website) **or** its generated alias (email). No
other configuration produces attribution.

---

## Source Records — Two Different Models

Don't confuse them:

| Model | Role |
|---|---|
| `utm.source` | the global catalog entry ("LinkedIn"). What `applicant.source_id` points to. |
| `hr.recruitment.source` | a per-job channel row: `job_id` + `source_id` + optional `alias_id` + tracker URL. Inherits `utm.source.mixin` ([utm_source.py:55](../addons/utm/models/utm_source.py#L55)), so creating one with just a name auto-creates the underlying `utm.source` ([utm_source.py:66](../addons/utm/models/utm_source.py#L66)). |

Deleting a `utm.source` still referenced by a `hr.recruitment.source` is blocked with a readable error
([hr_recruitment/models/utm_source.py:11](../addons/hr_recruitment/models/utm_source.py#L11)) on top of
the `ondelete='restrict'` on the link. On the applicant side the three UTM fields are re-declared with
`ondelete='set null'` ([hr_applicant.py:122-125](../addons/hr_recruitment/models/hr_applicant.py#L122)),
so removing a source blanks historical applicants rather than deleting them.

---

## Dependencies

- `hr_recruitment` depends on `utm` for the mixin and on `mail` for the alias gateway.
- `website_hr_recruitment` adds only the tracker `url` compute; the cookie plumbing lives in `utm`'s
  `ir.http` and applies site-wide.
