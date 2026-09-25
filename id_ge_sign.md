# Sign with Georgian ID Card (QES) (`id_ge_sign`)

> **Module:** `id_ge_sign` 20.0.3.1.0 | **Path:** [`custom_addons/gec_odoo_modules/id_ge_sign/`](../custom_addons/gec_odoo_modules/id_ge_sign/)
> Verified against Odoo 20 source on 2026-09-24.

## Odoo 20 Status: The Module Does Not Load Yet

Enterprise Sign 20.0 rebuilt how the completed document is produced, and three parts of this module still target the old design. [Certain] from source; the module is not installed on `gec20_prod1` (checked 2026-09-24).

| Break | What 20.0 does | Effect |
|---|---|---|
| [`sign_completed_document.py`](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_completed_document.py) extends `sign.completed.document` | That model does not exist in 20.0; the working copy of each document is `sign.request.document` ([sign_request_document.py:19](../enterprise/sign/models/sign_request_document.py#L19), enterprise commit `d542cb352d8`) | Registry load fails with "Model 'sign.completed.document' does not exist in registry" ([model_classes.py:188](../odoo/orm/model_classes.py#L188)), so the module cannot be installed |
| `_geoeid_render_document()` calls `.getvalue()` on the result of `render_document_with_items()` | That method returns `(overlay, regions)`: the field values only, to be merged into the original as an incremental update ([sign_document.py:594](../enterprise/sign/models/sign_document.py#L594)) | The first launch would fail; the overlay alone has no page content |
| The completed file is the card-signed PDF | `_generate_completed_documents()` calls `sign.request.document._finalize_documents()`, which stamps the values onto the original bytes and seals them with the company certificate when one is set ([sign_request.py:1070](../enterprise/sign/models/sign_request.py#L1070), [sign_request_document.py:151](../enterprise/sign/models/sign_request_document.py#L151)) | Without a new hook, the card signatures would not reach the completed document |

What still matches 20.0: `sign(..., validation_required=True)` fills values without completing the signer ([sign_request_item.py:338](../enterprise/sign/models/sign_request_item.py#L338)); `_post_fill_request_item()` completes the signer and the request ([sign_request_item.py:424](../enterprise/sign/models/sign_request_item.py#L424)); the patched JS classes and methods exist; the templates the reports extend keep their xpath targets; `/sign/send_public` still exists ([main.py:609](../enterprise/sign/controllers/main.py#L609)).

**Where a port would plug in.** Sign 20.0 has its own flow for signers who sign the document themselves: a role with `requires_external_signature` ([sign_item_role.py:44](../enterprise/sign/models/sign_item_role.py#L44); `sign_itsme` sets it for *Qualified Signature via itsme®*, [sign_item_role.py:23](../enterprise/sign_itsme/models/sign_item_role.py#L23)). The working copy is frozen before the signer signs ([sign_request_document.py:106](../enterprise/sign/models/sign_request_document.py#L106)) and the returned signature increment is appended to it ([sign_request_document.py:126](../enterprise/sign/models/sign_request_document.py#L126)). The card app already returns an incremental update of the exact bytes it received (the module checks this), so its tail is such an increment. [Likely] that is the seam; the core flow reaches the signer through an Odoo-hosted QES service, which the desktop-app hand-off would have to replace.

The rest of this document describes the module as written.

---

## What It Does & Why It Exists

Stock Odoo Sign produces a *simple electronic signature*: a drawn or typed mark with an audit trail, but no certificate and no cryptographic binding. For documents where Georgian law expects a signature equal to a handwritten one (labour contracts, commercial agreements), that is not enough.

This module lets a signer sign an Odoo Sign document with their **Georgian ID Card**, producing a **Qualified Electronic Signature (QES)** embedded in the PDF as a PAdES signature. It adds "Georgian ID Card" to the **Authentication** field of a Sign role, the slot SMS uses ([sign_item_role.py:7](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_item_role.py#L7)), so templates, roles, the signer list and the portal stay standard.

The signing itself happens in the desktop **Georgian ID Card Universal Program** (the `geoeid-unitool://` app from id.ge), launched from the browser. Odoo hands the app the **whole PDF**; the app downloads it, lets the signer place a visible signature block, signs it with the card, and uploads the finished PDF back. Odoo verifies the embedded signature, records the cardholder's identity from the certificate, and stores the signed PDF.

It supports **any mix of signers and several Georgian ID signers on one document**: each adds their own card signature on top of the previous one. Verification uses `cryptography` and `asn1crypto`, which Odoo already requires ([requirements.txt:3](../requirements.txt#L3), [requirements.txt:8](../requirements.txt#L8)), so there is no new Python dependency.

---

## The Big Picture — How It Works

```
Signer fills fields, clicks "Validate"        (role Authentication = Georgian ID Card)
        |
        v
GeoeidSignerDialog --> POST /sign/geoeid/launch --> Odoo renders the PDF (or takes the
        |                                            previous card signer's signed PDF),
        |                                            stores it, mints a one-time token,
        |                                            returns a geoeid-unitool:// URL
        v
Dialog opens geoeid-unitool://.../init/<token>  -->  Universal Program (desktop)
        |                                            GET  /sign/geoeid/init/<token>     -> JSON {dataType:"document", dataUrl, submitUrl, ...}
        |  (browser idle, dialog polls status)       GET  /sign/geoeid/document/<token> -> downloads the PDF
        v                                            signer places the block, enters PIN, card signs the PDF
Dialog polls /sign/geoeid/status                     POST /sign/geoeid/submit/<token>   -> uploads the signed PDF (multipart "signedFile")
        |                                                       |
        |                                            Odoo verifies the embedded PAdES signature,
        |                                            captures the cardholder identity from the certificate,
        v                                            stores the signed PDF, completes the signer.
"Thank you" page
```

The browser is only the trigger. After it opens the `geoeid-unitool://` link, the desktop app talks to Odoo directly (init, document, submit), and the dialog polls until the signature lands.

### Key Decision Points
- **Role Authentication = `geoeid`** turns a normal Sign role into a card-signing role. It is the single integration seam; everything else keys off it.
- **One card signer or several?** Card signers are notified together but sign **one at a time**, each stacking a new PAdES signature on the previous signed PDF. The completed document is the last card signer's file, which carries every signature.
- **Trust anchor configured?** With the PSDA issuing certificates set as anchor, the signing certificate is checked against them and the result counts as a QES. Without an anchor the signature is still fully verified (digest, signature, validity) but marked "chain not verified".
- **Partner personal number set?** If set, the certificate's personal number must match. If not, the certificate identity is recorded and accepted: the signer already proved control through their unique link and their card.

---

## When to Use It (and When Not To)

### This module is for:
- Georgian employees or counterparties signing contracts that need QES-level legal weight, on a **desktop** with a card reader and the Universal Program installed.
- Documents with one **or several** Georgian ID signers, optionally mixed with ordinary Odoo Sign signers.

### Use something else when:
- **Mobile signers**: the `geoeid-unitool://` scheme has no mobile build; use standard Odoo Sign or a cloud QES.
- **Several PDFs in one request**: not supported; creating or launching such a request raises a clear error.
- **Long-term archive (LT/LTA)**: needs live timestamp and revocation services; out of scope.

---

## Real-World Scenarios

### Scenario 1: One internal employee signs (Sign Now)
**Situation:** An employee signs their employment contract from the backend Sign app.
**What they do:** Click the signature field; it is **auto-filled**, so no "Adopt Your Signature" dialog appears. Click **Validate**. The Georgian ID dialog launches the app; they draw the block and enter the card PIN.
**What happens:** The app returns the signed PDF, Odoo verifies it and completes the request. The sign log report gains a "Georgian ID Card Signatures" table with the certificate subject, personal number, serial, expiry and whether the chain was verified ([sign_completion_report.xml:17](../custom_addons/gec_odoo_modules/id_ge_sign/report/sign_completion_report.xml#L17)).

### Scenario 2: Two counterparties both sign with their cards
**Situation:** A two-party agreement; both parties must sign with their Georgian ID cards.
**What they do:** **Send** the request to both emails. Both receive the link. Each opens it; the field is auto-filled; they validate and sign with their card.
**What happens:** The first to sign produces a signed PDF; the second one's app receives **that** PDF and adds a second signature. The final document carries **both** signatures and both identities are recorded. If both launch at the same moment, one sees "Another Georgian ID Card signer is signing right now", a guard that prevents a lost signature.

### Scenario 3: Anonymous public link, zero typing
**Situation:** You publish a self-service link for someone who is not an Odoo contact.
**What they do:** Open the link and sign with the card. **No name or email is asked**; the card is the identity.
**What happens:** Odoo creates a placeholder contact with a unique, non-routable `@id-card.invalid` email, turns the shared link into a real sent request, the app signs, and the contact is **renamed to the cardholder's name** from the certificate ([geoeid.py:69](../custom_addons/gec_odoo_modules/id_ge_sign/controllers/geoeid.py#L69)).

---

## How Things Work Under the Hood

### The endpoints ([`controllers/geoeid.py`](../custom_addons/gec_odoo_modules/id_ge_sign/controllers/geoeid.py))

| Endpoint | Caller | Purpose |
|---|---|---|
| `POST /sign/geoeid/launch/<req>/<token>` | signing page | refuses a signer that is not in *sent* state, not a card role, or an expired request; then persists the filled values, prepares the PDF, mints a one-time token and returns the `geoeid-unitool://` URL ([geoeid.py:33](../custom_addons/gec_odoo_modules/id_ge_sign/controllers/geoeid.py#L33)) |
| `POST /sign/geoeid/cancel/<req>/<token>` | signing page | puts a launched or failed attempt back to idle and drops the prepared PDF ([geoeid.py:54](../custom_addons/gec_odoo_modules/id_ge_sign/controllers/geoeid.py#L54)) |
| `POST /sign/geoeid/status/<req>/<token>` | signing page (polling) | reports `idle / launched / signed / failed` |
| `POST /sign/geoeid/public/<req>/<token>` | signing page (public link only) | creates the signer with **no name/email**; only for a shared request with exactly one card role and no partner |
| `GET /sign/geoeid/init/<token>` | desktop app | returns the document-mode JSON |
| `GET /sign/geoeid/document/<token>` | desktop app | serves the exact PDF the app must sign |
| `POST /sign/geoeid/submit/<token>` | desktop app | receives the signed PDF (multipart field `signedFile`), verifies and finalizes; answers 409 on a concurrent submit and 400 on a rejected signature ([geoeid.py:130](../custom_addons/gec_odoo_modules/id_ge_sign/controllers/geoeid.py#L130)) |

`init`, `document` and `submit` are plain HTTP scoped by the unguessable one-time token, valid 10 minutes ([sign_request_item.py:15](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L15)) and burned on success. The caller is the desktop app, not a browser, so CSRF does not apply.

### Core model logic ([`models/sign_request_item.py`](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py))

- **`create()`** ([sign_request_item.py:59](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L59)) — the card seals the document, so card signers must come last. Regular signers keep their signing orders; **all** card signers get the next order after the highest regular one, so they are notified together. A request with a card signer must have exactly one document.
- **`_geoeid_launch()`** ([sign_request_item.py:83](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L83)) — locks the request, reuses a still-valid token of the same signer, refuses while an earlier-ordered signer is pending or another card signer is mid-signing. It then persists the field values with `sign(..., validation_required=True)` (filled, not completed), prepares the PDF and mints the token.
- **`_geoeid_prepared_pdf()`** ([sign_request_item.py:206](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L206)) — the key to several card signers: if an earlier card signer already produced a signed PDF, hand over **that** file so the app stacks a new signature on it; otherwise render the document.
- **`_geoeid_render_document()`** ([sign_request_item.py:135](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L135)) — renders every field value plus a generated name image in each card signer's signature field ([sign_request_item.py:155](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L155)). The guides go into the first prepared PDF, before the first seal, so later card signers still see their field position. This is the method that breaks on 20.0 (see the status section).
- **`_geoeid_submit_document()`** ([sign_request_item.py:226](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L226)) — locks the request and the signer, treats a repeated submit after success as a no-op, verifies the **latest** embedded signature against the prepared bytes, enforces the trust policy and the identity match, and stores the signed PDF with the certificate data. It renames a placeholder contact to the cardholder's name, posts the audit message, then calls `_post_fill_request_item()` as the signer's own user when they have one.

### Verification ([`tools/cms.py`](../custom_addons/gec_odoo_modules/id_ge_sign/tools/cms.py))

`verify_pdf_signature()` ([cms.py:53](../custom_addons/gec_odoo_modules/id_ge_sign/tools/cms.py#L53)) accepts the returned PDF only when:

- it starts with the exact bytes Odoo prepared, so it is an incremental update of them;
- the **last** `/ByteRange` covers the whole file, with nothing unsigned after it except whitespace ([cms.py:73](../custom_addons/gec_odoo_modules/id_ge_sign/tools/cms.py#L73));
- the CMS has exactly one signer, signed attributes, content type *data* and a `messageDigest` equal to the digest of the signed bytes;
- the signature verifies with the certificate key; only RSA PKCS#1 v1.5 is accepted ([cms.py:26](../custom_addons/gec_odoo_modules/id_ge_sign/tools/cms.py#L26));
- the certificate is valid at submit time and its key usage allows signing ([cms.py:187](../custom_addons/gec_odoo_modules/id_ge_sign/tools/cms.py#L187));
- if an anchor is set: the certificate's issuer equals an anchor's subject, that anchor is a valid CA, and its key verifies the certificate. That makes it trusted ([cms.py:202](../custom_addons/gec_odoo_modules/id_ge_sign/tools/cms.py#L202)). The check is single-level, not full path building.

The identity comes from the certificate subject: common name and `serialNumber` (the personal number) ([cms.py:251](../custom_addons/gec_odoo_modules/id_ge_sign/tools/cms.py#L251)).

### Completed document ([`models/sign_completed_document.py`](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_completed_document.py))

`_generate_completed_document()` is overridden so the completed file of a card-signed document **is** the signed PDF of the last card signer, picked by signing time. This is the file that stops the module from loading on 20.0.

### The init JSON ([`tools/protocol.py`](../custom_addons/gec_odoo_modules/id_ge_sign/tools/protocol.py))

`build_init_document_json()` ([protocol.py:26](../custom_addons/gec_odoo_modules/id_ge_sign/tools/protocol.py#L26)) returns `dataType:"document"`, `docType:"PDF"`, `dataUrl`, `submitUrl`, `signAlg:"sha256withRSA"`, `padesUsage:true`, `description` (the request reference), `language`, `keyId:"sign"` and `signatureProfile`. These map 1:1 onto the app's own message class (see the desktop app facts below).

### Front-end ([`static/src/`](../custom_addons/gec_odoo_modules/id_ge_sign/static/src/))

- **`document_signable_geoeid.js`** — patches the signing page: routes `geoeid` roles to `GeoeidSignerDialog` (`getAuthDialog`) and, for **public links**, overrides `_signDocuments` to skip the name/email dialog by calling `/sign/geoeid/public` ([document_signable_geoeid.js:33](../custom_addons/gec_odoo_modules/id_ge_sign/static/src/components/sign_request/document_signable_geoeid.js#L33)). On any failure it falls back to the standard dialog.
- **`signable_PDF_iframe_geoeid.js`** — auto-fills a card signer's signature field on render ([signable_PDF_iframe_geoeid.js:10](../custom_addons/gec_odoo_modules/id_ge_sign/static/src/components/sign_request/signable_PDF_iframe_geoeid.js#L10)).
- **`geoeid_signer_dialog.js` / `.xml`** — the launcher dialog (OWL 3): opens the `geoeid-unitool://` URL, polls the status, offers "Open the application again" and "Try again".

### Important fields (only the ones that matter)
- `geoeid_state` — `idle`, `launched`, `signed` or `failed`; the dialog polls it.
- `geoeid_prepared_document` — the PDF handed to the app (fresh render, or the previous card signer's signed PDF); cleared after a successful submit.
- `geoeid_signed_document` — the signed PDF the app returned; the next card signer stacks on it.
- `geoeid_cert_common_name`, `geoeid_cert_personal_number`, `geoeid_cert_serial`, `geoeid_cert_not_after` — the cardholder identity captured at submit. This is where "full name + personal number" comes from.
- `geoeid_cert_trusted` — true only when the certificate chained to an anchor; only then is the signature called a QES.

---

## Configuration & Settings

**Turning it on for a role:** the module adds **Sign > Configuration > Roles** for Sign managers ([sign_item_role_views.xml:21](../custom_addons/gec_odoo_modules/id_ge_sign/views/sign_item_role_views.xml#L21)); Sign 20.0 has no roles menu of its own. Set the role's **Authentication** to "Georgian ID Card".

**Sign settings, "Sign with Georgian ID Card"** ([res_config_settings.py:7](../custom_addons/gec_odoo_modules/id_ge_sign/models/res_config_settings.py#L7)). Each is a system parameter, read with the same defaults the settings fields use ([sign_request_item.py:331](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request_item.py#L331)):

- **Signature profile** (`id_ge_sign.signature_profile`, default `B`) — sent to the app. `B` is Baseline-B; `BT` asks the app to add a timestamp, which Odoo does not check.
- **Application language** (`id_ge_sign.language`, default `ka`) — UI language of the desktop app (`ka` or `en`).
- **Require trusted certificate chain** (`id_ge_sign.require_trusted_chain`, default off) — rejects a signature that does not chain to the anchor. **Leave it off until the anchor is set**, or every signature is rejected.

**System parameter** `id_ge_sign.trust_anchor` — PEM text with the PSDA issuing **intermediate and root** certificates. Only the immediate issuer is checked, so the intermediate must be included. Set it, then turn on *Require trusted certificate chain*, for real QES.

**Contact field** `geoeid_personal_number` — shown after the VAT field on the contact form to Sign managers only, 11 digits ([res_partner.py:10](../custom_addons/gec_odoo_modules/id_ge_sign/models/res_partner.py#L10)). When set, a card with another personal number is rejected at submit.

---

## Dependencies

| Requires | Why |
|---|---|
| `sign` (Enterprise) | Templates, roles, signing flow, completion pipeline |

| Python | Why |
|---|---|
| `cryptography`, `asn1crypto` | Parse and verify the embedded PAdES signature; both are in Odoo's requirements |

No new models, so no `ir.access.csv`. All fields are added to existing Sign models and `res.partner`.

---

## Gotchas & Non-Obvious Behavior

- **Card signers sign last; content locks after the first card signature.** PAdES forbids changing content once a document is signed. All regular signers and field values must come first, and **a card signer should have only signature fields**: a card signer's text or date fields would not reach the final PDF.
- **One visible block per card signer, placed by hand.** The signer draws the block; there is no way to pass a position. A second signature field for the same signer stays blank.
- **The card stamps the certificate identity, not the Odoo name.** The app's block shows the cardholder's name and personal number from the certificate; Odoo cannot change that text. The Odoo name image stays on the page as a placement guide and remains in the final PDF.
- **"QES" is conditional on trust.** A signature is reported as QES only when `geoeid_cert_trusted` is true. With no anchor it is verified but marked "chain not verified".
- **Certificate validity is checked at submit time**, not at a signing time inside the signature. A card that expires between signing and upload is rejected.
- **Public-link signers get a synthetic email.** Sign requires an email for every signer, so a public card signer gets a unique `@id-card.invalid` address. Completion mails to such contacts are skipped ([sign_request.py:9](../custom_addons/gec_odoo_modules/id_ge_sign/models/sign_request.py#L9)) and the address is hidden in the completion mail and the sign log ([sign_completion_report.xml:4](../custom_addons/gec_odoo_modules/id_ge_sign/report/sign_completion_report.xml#L4)). Expect one contact per public signing; nothing deduplicates them.
- **Name/email step only on public links.** For Sign Now and Send-to-contact the signer is already known, so the dialog never appears; the module bypasses it on public links too.
- **`documents_sign` access.** `documents_sign` gives the signer view access to the completed documents in `sign.request.item._sign()` ([sign_request.py:75](../enterprise/documents_sign/models/sign_request.py#L75)). The card signer is completed through `_post_fill_request_item()` instead, so [Likely] that grant does not run when a card signer finishes the request. The completed file is still attached.
- **Asset bundles.** The signing-page patches load in both `web.assets_backend` and `sign.assets_public_sign`; the public signing page does not use `web.assets_frontend`.
- **Out of scope:** LT/LTA profiles, the PSDA qualified document timestamp and server-side OCSP/CRL checks.

---

## Desktop App Facts the Design Rests On

Checked against the installed app (`/Applications/Georgian ID Card.app`) on 2026-09-24:

- **The init message has no position and no certificate-read step.** The app's `JsonMessage` class (`web-signer.jar`) has exactly these fields: `dataType`, `dataHex`, `dataUrl`, `hash`, `signAlg`, `submitUrl`, `description`, `docType`, `language`, `keyId`, `signatureProfile`, `padesUsage`.
- **Two data types.** `hash`: the app signs a hash and returns a CMS, with no visible block. `document`: the app downloads the PDF, opens a placement dialog, draws its **own** visible block from the card certificate, signs, and uploads the PDF. The module uses `document`, because only that mode produces the id.ge visible block.
- **The visible block is built by the app.** `visual-signer.jar` holds the stamp generator (`SignatureImageGeneratorService`) and the PSDA watermark image. The block geometry (`VisualSignatureParameters` in `cmssigner.jar`: `originX`, `originY`, `width`, `height`, `page`) comes from the app itself, since the init message cannot carry it.
- **The upload uses an unparseable multipart boundary.** The app sends an unquoted boundary containing `=` (for example `boundary====1780578020325===`). Werkzeug 3.0.1, pinned for Python 3.12+ ([requirements.txt:58](../requirements.txt#L58)), returns no files for it without reading the body. `_read_signed_file()` takes the boundary from the header and re-parses the raw body with Werkzeug's own parser ([geoeid.py:153](../custom_addons/gec_odoo_modules/id_ge_sign/controllers/geoeid.py#L153)).

---

## Testing Without a Card

[`dev/mock_universal_program.py`](../custom_addons/gec_odoo_modules/id_ge_sign/dev/mock_universal_program.py) is a standalone fake Universal Program for **hash mode**. It does not exercise document mode (download the PDF, return a signed file), so testing the current flow needs a real card.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- Module README (developer reference): [`custom_addons/gec_odoo_modules/id_ge_sign/README.md`](../custom_addons/gec_odoo_modules/id_ge_sign/README.md)
