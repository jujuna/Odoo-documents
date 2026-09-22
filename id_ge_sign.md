# Sign with Georgian ID Card (QES)

> **Module:** `id_ge_sign` | **Path:** [`custom_addons/gec_id_sign/id_ge_sign/`](../custom_addons/gec_id_sign/id_ge_sign/)
> **Mode:** Document mode (v19.0.3.x) — the desktop app signs the whole PDF and returns it. (Earlier hash-mode design was replaced; see [Design Journey](#design-journey--why-the-module-looks-like-this-session-analysis).)

## What It Does & Why It Exists

Stock Odoo Sign produces a *simple electronic signature* — a drawn or typed mark with an audit trail, but no certificate and no cryptographic binding. For documents where Georgian law expects a signature equal to a handwritten one (labour contracts, commercial agreements), that is not enough.

This module lets a signer sign an Odoo Sign document with their **Georgian ID Card**, producing a **Qualified Electronic Signature (QES)** embedded in the PDF as a PAdES signature. It adds a "Georgian ID Card" option to the *Extra Authentication Step* of a Sign role — the same slot SMS uses — so templates, roles, the signer list and the portal are unchanged.

The signing itself happens in the desktop **Georgian ID Card Universal Program** (the `geoeid-unitool://` app from id.ge), launched from the browser. In the current design Odoo hands the app the **whole PDF**; the app downloads it, lets the signer place a visible signature block, signs it with the card, and uploads the finished PDF back. Odoo verifies the embedded signature, records the cardholder's identity from the certificate, and stores the signed PDF as the completed document.

It supports **any mix of signers and multiple Georgian-ID signers on one document** — each adds their own card signature, stacked on top of the previous one. Verification reuses `cryptography` + `asn1crypto` (already in Odoo), so there is **no new Python dependency**.

---

## The Big Picture — How It Works

```
Signer fills fields, clicks "Validate"        (role auth = Georgian ID Card)
        │
        ▼
GeoeidSignerDialog ──► POST /sign/geoeid/launch ──► Odoo renders the PDF (or takes the
        │                                            previous card signer's signed PDF),
        │                                            stores it, mints a one-time token,
        │                                            returns a geoeid-unitool:// URL
        ▼
Dialog opens geoeid-unitool://…/init/<token>  ──►  Universal Program (desktop)
        │                                            GET  /sign/geoeid/init/<token>     → JSON {dataType:"document", dataUrl, submitUrl, …}
        │  (browser idle, dialog polls status)       GET  /sign/geoeid/document/<token> → downloads the PDF
        ▼                                            user places the block, enters PIN3, card signs the PDF
Dialog polls /sign/geoeid/status                     POST /sign/geoeid/submit/<token>   → uploads the signed PDF (multipart "signedFile")
        │                                                       │
        │                                            Odoo verifies the embedded PAdES signature,
        │                                            captures the cardholder identity from the cert,
        ▼                                            stores the signed PDF, completes the signer.
"Thank you" page                                     Completed document = the signed PDF.
```

The browser is only the trigger. After it opens the `geoeid-unitool://` link, the desktop app talks to Odoo directly (init → document → submit), and the dialog just polls until the signature lands.

### Key Decision Points
- **Role auth method = `geoeid`** — turns a normal Sign role into a card-signing role. The single integration seam; everything else keys off it.
- **One signer or several?** A document can have several card signers. They are notified together but sign **one at a time**, each stacking a new PAdES signature on the previous signed PDF. The completed document is the last signer's file (it carries every signature).
- **Trust anchor configured?** With a PSDA root/intermediate PEM set, the signing certificate is validated against it and the result is a QES. Without one, the signature is still fully verified (digest + signature + validity) but marked "chain not verified".
- **Partner personal number set?** If set, the certificate's personal number must match (strict identity binding). If not, the certificate identity is recorded and accepted (the signer already proved control via their unique link / their card).

---

## When to Use It (and When Not To)

### This module is for:
- Georgian employees or counterparties signing contracts that need QES-level legal weight, on a **desktop** with a card reader and the Universal Program installed.
- Documents with one **or several** Georgian-ID signers, optionally mixed with ordinary Odoo Sign signers.

### Use something else when:
- **Mobile signers** — the `geoeid-unitool://` scheme has no mobile build; fall back to standard Odoo Sign or a cloud QES.
- **Multiple PDFs in one request** — not supported; launch raises a clear error. One document per request.
- **Long-term archive (LT/LTA)** — needs pyHanko + live TSA/OCSP; out of scope.

---

## Real-World Scenarios

### Scenario 1: One internal employee signs (Sign Now)
**Situation:** An employee signs their employment contract from the backend Sign app.
**What they do:** Click the signature field — it is **auto-filled** (no "Adopt Your Signature" dialog) — then Validate. The Georgian ID dialog launches the app; they place the block and enter PIN3.
**What happens:** The app returns the signed PDF, Odoo verifies it and completes the request. The completed document is a PAdES-signed PDF; the Certificate of Completion lists the cardholder's name, personal number, serial and expiry.

### Scenario 2: Two counterparties both sign with their cards
**Situation:** A two-party agreement; both parties must sign with their Georgian ID cards.
**What they do:** You **Send** the request to both emails (Signing Order off). Both receive the link. Each opens it, the field is auto-filled, they Validate and sign with their card.
**What happens:** The first to sign produces a signed PDF; the second's app receives **that** PDF and adds a second signature on top. The final document carries **both** signatures; both names are captured. If both click "sign" at the same moment, one briefly sees "another signer is signing, try again" — a guard that prevents a lost signature.

### Scenario 3: Anonymous public link, zero typing
**Situation:** You publish a self-service link for someone who is not an Odoo contact.
**What they do:** Open the link, sign with the card. **No name/email is asked** — the card is the identity.
**What happens:** Odoo silently creates a placeholder contact (a synthetic, non-routable `@id-card.invalid` email), the app signs, and after signing the contact is **renamed to the cardholder's real name** from the certificate.

---

## How Things Work Under the Hood

### The endpoints ([`controllers/geoeid.py`](../custom_addons/gec_id_sign/id_ge_sign/controllers/geoeid.py))

| Endpoint | Caller | Purpose |
|---|---|---|
| `POST /sign/geoeid/launch/<req>/<token>` | signing page (browser) | persist the filled values, prepare the PDF to sign, mint a one-time token, return the `geoeid-unitool://` URL |
| `POST /sign/geoeid/status/<req>/<token>` | signing page (polling) | report `idle / launched / signed / failed` |
| `POST /sign/geoeid/public/<req>/<token>` | signing page (public link only) | create the signer with **no name/email** (placeholder contact + synthetic email) and turn the shared link into a real sent request |
| `GET /sign/geoeid/init/<token>` | desktop app | return the document-mode JSON spec (`dataType:"document"`, `dataUrl`, `submitUrl`, `signatureProfile`, …) |
| `GET /sign/geoeid/document/<token>` | desktop app | serve the exact PDF the app must sign |
| `POST /sign/geoeid/submit/<token>` | desktop app | receive the finished signed PDF (multipart field `signedFile`), verify and finalize |

`init`/`document`/`submit` are plain HTTP scoped by the unguessable one-time token (10-min TTL); the caller is the desktop app, not a browser, so CSRF does not apply.

### Core model logic ([`models/sign_request_item.py`](../custom_addons/gec_id_sign/id_ge_sign/models/sign_request_item.py))

- **`create()`** — orders signers so the card seals the document last: regular signers get orders `1..n`; **all** card signers share order `n+1` (so they are notified together but still sign one at a time).
- **`_geoeid_launch()`** — validates (single document; all earlier-ordered signers completed; no other card signer mid-signing), persists the field values via `sign(..., validation_required=True)` (fills without completing), computes the PDF to sign via `_geoeid_prepared_pdf()`, stores it and mints the token.
- **`_geoeid_prepared_pdf()`** — the key to multi-signer: if an earlier card signer already produced a signed PDF, hand **that** over (so the app stacks a new signature on it); otherwise render the document fresh.
- **`_geoeid_render_document()`** — fresh render of **all** field values, plus generated guide marks for every Georgian ID Card signer. Those guide marks are baked into the first prepared PDF before the first PAdES seal, so later card signers still see their field position when they receive the previous signer's signed PDF. The card's visible block is added wherever the signer draws.
- **`_geoeid_submit_document(signed_pdf)`** — locks the row, verifies the **latest** embedded signature, enforces the trust-chain policy and identity match, stores the signed PDF + certificate metadata, renames a public placeholder contact to the cardholder's name, posts the audit message, then calls the stock `_post_fill_request_item()` so completion proceeds normally.

### Verification ([`tools/cms.py`](../custom_addons/gec_id_sign/id_ge_sign/tools/cms.py))

- **`verify_pdf_signature(pdf_bytes, anchors)`** — extracts the **last** PAdES signature in the PDF (the one just added), recomputes the ByteRange digest, and reuses `verify_card_signature()`.
- **`verify_card_signature()`** — checks the CMS is well-formed PAdES, that `messageDigest` equals the signed bytes, that the signature verifies against the certificate, that the certificate is valid and allows signing, and (if an anchor is set) that it chains to it; returns the signer identity.
- **`_extract_pdf_signature()`** — finds the last `/ByteRange` and decodes the `/Contents` CMS. A document may carry several stacked signatures; the last one belongs to the current signer.

### Completed document ([`models/sign_completed_document.py`](../custom_addons/gec_id_sign/id_ge_sign/models/sign_completed_document.py))

`_generate_completed_document()` is overridden so a geoeid document's completed file **is** the signed PDF returned by the app — specifically the **last** card signer's PDF (it carries every stacked signature). `_geoeid_item()` picks that signer by signing order.

### The init JSON ([`tools/protocol.py`](../custom_addons/gec_id_sign/id_ge_sign/tools/protocol.py))

`build_init_document_json()` returns keys that map 1:1 onto the desktop app's internal `JsonMessage` model (verified by decompiling the app — see [Design Journey](#design-journey--why-the-module-looks-like-this-session-analysis)): `dataType:"document"`, `docType:"PDF"`, `dataUrl`, `submitUrl`, `signAlg:"sha256withRSA"`, `padesUsage:true`, `description`, `language`, `keyId:"sign"`, `signatureProfile`.

### Front-end ([`static/src/`](../custom_addons/gec_id_sign/id_ge_sign/static/src/))

- **`document_signable_geoeid.js`** — patches the signing page: routes `geoeid` roles to `GeoeidSignerDialog`, and for **public links** overrides `_signDocuments` to skip the name/email "Final Validation" dialog (calls `/sign/geoeid/public`).
- **`signable_PDF_iframe_geoeid.js`** — auto-fills a geoeid signer's signature field on render, so "Adopt Your Signature" never appears.
- **`geoeid_signer_dialog.js` / `.xml`** — the launcher dialog: opens the `geoeid-unitool://` URL and polls status.

### Important fields (only the ones that matter)
- `geoeid_state` — `idle → launched → signed` (or `failed`); the dialog polls it.
- `geoeid_prepared_document` — the PDF handed to the app (fresh render, or the previous signer's signed PDF).
- `geoeid_signed_document` — the signed PDF the app returned (used to build the completed document and to stack the next signature).
- `geoeid_cert_common_name` / `geoeid_cert_personal_number` — the cardholder identity captured from the certificate at submit. **This is where "receive full name + passport ID" comes from.**
- `res.partner.geoeid_personal_number` — set it to enforce strict certificate-to-contact matching.

---

## Configuration & Settings

**Turning it on for a role:** the module restores a **Sign → Configuration → Roles** menu ([`sign_item_role_views.xml`](../custom_addons/gec_id_sign/id_ge_sign/views/sign_item_role_views.xml)); set a role's **Authentication** to "Georgian ID Card". (Also reachable in the template editor via a role's ⋮ → Edit → Signer Settings.)

Settings → Sign → "Sign with Georgian ID Card" ([`res_config_settings.py`](../custom_addons/gec_id_sign/id_ge_sign/models/res_config_settings.py)):

- **Signature profile** (`id_ge_sign.signature_profile`, default `B`) — value sent to the app. `B` = Baseline-B; `BT` asks the app to add a timestamp (not validated server-side).
- **Application language** (`id_ge_sign.language`, default `ka`) — UI language of the desktop app (`ka` / `en`).
- **Require trusted certificate chain** (`id_ge_sign.require_trusted_chain`, default off) — reject a signature that does not chain to the anchor. **Leave off until the anchor is set**, or every signature is rejected.

System Parameters (Settings → Technical → System Parameters):
- `id_ge_sign.trust_anchor` — the PSDA trust anchor, a PEM with the issuing **intermediate + root** certificate. Validation pins the immediate issuer, so the intermediate must be included. Set this (and turn on *Require trusted chain*) for real QES.

> Removed in document mode: the old **Stamp signature appearance** and **Read certificate before signing** settings, and the `id_ge_sign.appearance_font` parameter. The app now draws the visible block itself, and the cert-read step never existed in the real app (see Design Journey).

---

## Dependencies

| Requires | Why |
|---|---|
| `sign` (Enterprise) | Templates, roles, signing flow, completion pipeline |

| Python | Why |
|---|---|
| `cryptography`, `asn1crypto` | Parse and verify the embedded PAdES signature; both ship with Odoo |

No new database models, so no new ACL file. All fields are added to existing Sign models.

---

## Gotchas & Non-Obvious Behavior

- **The card signer signs last; content locks after the first card signature.** PAdES forbids changing content once a document is signed. So all regular signers and field values must come first, and **a card signer should have only signature field(s)** — a card signer's text/date fields would not reach the final PDF. `create()` enforces the order.
- **One visible block per card signer, placed by hand.** The app builds its visible signature from coordinates the signer **draws with the mouse**; there is no way to pass a position or auto-place it (proven from the app — see Design Journey). So a single signature field per geoeid signer is the supported shape; a second field for the same signer would stay blank.
- **The card stamps the certificate identity, not the Odoo name.** The app generates its own block showing the cardholder's real name + personal number + "Digitally signed by … / Date …" from the card certificate; Odoo cannot change that text. The auto-filled Odoo name mark (e.g. "zh") is kept on the page only as a **placement guide** and stays in the final output (see *Design Journey* §3).
- **Multiple card signatures stack.** The app signs incrementally (DSS PAdES), so each signer's app receives the previous signed PDF and adds a new signature; earlier signatures stay valid. The completed document is the last signer's PDF.
- **"QES" is conditional on trust.** A signature is reported as a QES only when its certificate chains to `id_ge_sign.trust_anchor` (`geoeid_cert_trusted`). With no anchor it is verified but marked "chain not verified".
- **Public-link signers get a synthetic email.** Sign requires every signer to have an email, but a card signer types none, so a public-link signer is created with a unique non-routable `@id-card.invalid` address (nothing is ever sent there). The contact is renamed to the cardholder's real name after signing. Expect one contact per public signing (no email-based dedup; clean up periodically).
- **Name/email step only on public links.** For **Sign Now** (internal) and **Send to a contact**, the signer is already known, so the "Final Validation" name/email dialog never appears. It is only the anonymous public link that needs it, and the module bypasses even that for geoeid (above).
- **Identity number.** `res.partner.geoeid_personal_number` is shown on the Contacts form and validated as 11 digits; when set, a mismatched card is rejected at submit.
- **`documents_sign` gap.** Like stock `sign_itsme`/`sign_emsigner`, geoeid finalizes via `_post_fill_request_item` (out-of-band), so the `documents` bridge's "grant the signer access" step doesn't run; the completed file is still attached normally.
- **Asset bundles.** The signing-page patches load in both `web.assets_backend` and `sign.assets_public_sign` (the portal page doesn't use `web.assets_frontend`).
- **Out of scope:** LT/LTA archive profiles, the PSDA qualified `DocTimeStamp` (needs a TSA endpoint), and server-side OCSP/CRL. The chain check is single-level (issuer == anchor), not full path building.

---

## Design Journey — Why the Module Looks Like This (session analysis)

This section records how the current design was reached, because almost none of it was obvious up front. The original module used **hash mode** (Odoo hashed the PDF, the card signed only the hash, Odoo embedded the CMS and drew its own visible block). That worked against a mock but **failed on the first real card**. The investigation that followed reshaped the module.

### 1. The first crash, and reverse-engineering the real app
The real desktop app threw `java.lang.NullPointerException` at `WebSignerWindow.initializeFromJson` the moment it read Odoo's init JSON. We decompiled the app (`/Applications/Georgian ID Card.app`, `plugins/web-signer.jar`, using the app's bundled `javap`) and found the ground truth:
- The init JSON is deserialized into a class `JsonMessage` whose only fields are `dataType, dataHex, dataUrl, hash, signAlg, submitUrl, description, docType, language, keyId, signatureProfile, padesUsage`. There is **no `action` and no `certUrl`**.
- The old module sent `{"action":"getCertificate", "certUrl":…}` for its "read certificate before signing" feature. The real app has **no such step** — that whole flow was fictional (it had only ever been tested against the project's own mock). The app saw no `dataType`, dereferenced null, and crashed.

**Lesson baked into the code:** the cert-read flow and its settings/fields were deleted. The init JSON now maps 1:1 onto `JsonMessage`.

### 2. Two real modes — and why we chose `document`
The app supports exactly two `dataType` values:
- **`hash`** — the app signs a hash and returns a CMS; it draws **no** visible block.
- **`document`** — the app downloads the whole PDF, opens a placement dialog, draws its **own** visible signature block from the card certificate, signs the PDF, and uploads it back.

The client wanted the signature to look the way the id.ge app renders it. That block exists **only in document mode**. So the module was rewritten from hash mode to document mode: Odoo serves the PDF at `dataUrl`, the app signs it, and `/submit` receives the finished file. The hash-mode plumbing (`tools/pades.py`) and Odoo's own appearance drawing (`tools/appearance.py`) were removed.

### 3. What document mode costs (verified from the app)
Decompiling further (`cmssigner.jar`, `visual-signer.jar`) showed the visible signature is built from `VisualSignatureParameters` (originX/Y, width, height, page) taken **only from the interactive mouse-draw dialog**. There is no init-JSON field for position and no detection of existing PDF signature fields. Consequences, now documented as limitations:
- The signer must **draw** the block; it cannot be auto-placed.
- The app places **one** block and signs once, so **one signature field per card signer**.

**What the visible stamp contains (verified from `visual-signer.jar`).** The app builds the block itself, at sign time, with JasperReports (`SignatureImageGeneratorService.generate`) — not from anything Odoo sends. On clicking *Sign* it reads the card's `CERT_ELECTRONIC_SIGNATURE` certificate and renders: the cardholder's **full name** and **personal number** (from the certificate subject / SubjectAlternativeNames), plus the lines `Digitally signed by <name>` and `Date: <app-local timestamp>`, over the PSDA watermark (`psda_transparent.png`). Odoo has **no control over this text** — the init JSON (`JsonMessage`) has no appearance field — so the stamp always shows the **certificate identity**, never the Odoo signer label. Odoo-generated guide marks are **kept** in the PDF handed to the app (`_geoeid_render_document`) as placement guides, so signers see their field positions and draw the card block over them; they stay in the final signed PDF alongside the card's own block. Apart from those guides, the placement dialog renders only the source PDF page plus a red draw-overlay, so any other text seen there before signing is content of the source PDF itself (e.g. a decorative "Signature" graphic). The only placement the signer controls is *where* the card block lands (the mouse-drawn rectangle).

### 4. The multipart upload that "arrived" but parsed to nothing
After signing, `/submit` returned 400 with "no signedFile", even though the app clearly POSTed a file. Logging the request showed the body was there but `request.httprequest.files` was empty. The cause: the app builds its multipart boundary as `===<timestamp>===`, so the header is `boundary====1780578020325===` — an **unquoted boundary containing `=`**, which **werkzeug 3.0.1 cannot parse** (`parse_options_header` returns no boundary). werkzeug then raises "Missing boundary" and silently returns empty form/files — **before reading the body**, so the raw body is still intact. The fix (`_read_signed_file` in the controller): when `files` is empty, take the boundary straight from the `Content-Type` header and re-run werkzeug's own `MultiPartParser` on the raw body. Verified against the app's exact wire format.

### 5. Trust chain — a setting, not a bug
Once uploads worked, a real signature was rejected with "A trusted certificate chain is required". That was correct: **Require Trusted Certificate Chain** was on, but no `id_ge_sign.trust_anchor` was configured, so nothing could be "trusted". For testing the setting is left off (the signature is still verified, just marked "chain not verified"); for production the PSDA intermediate + root PEM goes into the anchor and the setting is turned on.

### 6. Removing the typing steps (the card is the authentication)
The client's point: signing with the ID card *is* the authentication, so Odoo shouldn't ask the signer to type anything.
- **"Adopt Your Signature"** (draw a mark) — redundant, because the app draws the real block. The front-end now **auto-fills** a geoeid signer's signature field on render. The server still needs non-empty signature values, so generated name images are rendered into the first prepared PDF as placement guides for every card signer. They remain in the final output.
- **"Final Validation" (name + email)** — only appears for **anonymous public links** (Odoo must create a contact before the card step). For Sign Now and Send-to-contact it never appears. For public links, the module creates the contact silently with a synthetic `@id-card.invalid` email (Sign requires *some* valid-format email; `.invalid` is reserved and never routes) and **renames it from the certificate** after signing.

### 7. Multiple card signers — the email ordering subtlety
The goal: any number of card signers on one document, each validated by their card. The app uses DSS incremental signing, so signatures **stack** — each signer's app receives the previous signed PDF and adds another. Implementing this surfaced two traps:
- **Sequence vs. notification.** A first attempt gave each card signer a distinct signing order — which made Odoo send the link to **only the first signer**. The fix: card signers share **one** order, so they are all emailed together, but a launch-time guard lets only one sign at a time (and each picks up the latest signed PDF to stack on). Regular signers still take lower orders and sign first.
- **Verify the right signature.** With several stacked signatures, verification must check the **last** ByteRange (the one the current signer just added), and the completed document must be the **last** signer's file.

The net result is the behaviour documented above: send to everyone, everyone is notified, each signs with their card in turn, and the final PDF carries every signature.

---

## Testing Without a Card

[`dev/mock_universal_program.py`](../custom_addons/gec_id_sign/id_ge_sign/dev/mock_universal_program.py) is a standalone "fake Universal Program". **Note:** it was written for the old **hash mode** and is now out of date — it does not exercise document mode (download the PDF, return a fully signed file). Real verification of the current flow needs a real card. The mock is kept for reference and should be rewritten or removed before relying on it.

---

## Related Docs

- [`INDEX.md`](INDEX.md)
- Module README (developer reference): [`custom_addons/gec_id_sign/id_ge_sign/README.md`](../custom_addons/gec_id_sign/id_ge_sign/README.md)
