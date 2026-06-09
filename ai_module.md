# AI Module — Odoo 19 Enterprise

> **Module:** `ai` (+ ~20 satellite modules) | **Path:** [`enterprise/ai/`](../enterprise/ai/)
> **License:** OEEL-1 (Enterprise only) | **pgvector required** (auto-detected by [`ai_auto_install`](../enterprise/ai_auto_install/))

## What It Does & Why It Exists

`ai` is the central LLM integration layer of Odoo Enterprise. It exposes three primary capabilities to every other module:

1. **Conversational agents** (`ai.agent`) — partners-with-a-prompt that users chat with in Discuss, in form-view side panels, or in livechat.
2. **AI server actions** (`ir.actions.server` with `state='ai'`) — automation steps that hand a record + a prompt to an LLM and let it call other server actions as "tools" (function-calling).
3. **AI computed fields** (via [`ai_fields`](../enterprise/ai_fields/)) — `compute=` style fields whose value is a single-shot LLM call against record context, used by Studio, Documents, ESG, Recruitment, etc.

The module is RAG-capable: each agent can have `ai.agent.source` records (attachments) that get chunked, embedded, and stored in pgvector. Retrieval is cosine similarity through `ai_embedding.embedding_vector` (1536 dims).

It is **strictly bring-your-own-key**: there is no Odoo IAP fallback. If `ai.openai_key` / `ai.google_key` (or `ODOO_AI_CHATGPT_TOKEN` / `ODOO_AI_GEMINI_TOKEN` env vars) are not set, every AI call raises `UserError`.

---

## The Big Picture — How It Works

```
User sends prompt in ai_chat channel
   │
   ▼
ai.agent._generate_response(prompt, history, ctx)
   │  builds system prompt + RAG context
   ▼
LLMApiService(provider=agent._get_provider()).request_llm(...)
   │  loops up to ai.max_successive_calls (default 20)
   │     ├─ provider-specific HTTP call (OpenAI Responses API or Gemini generateContent)
   │     ├─ if response contains tool calls → run them, append outputs as "inputs"
   │     └─ if pure text or __end_message → break
   ▼
Markdown sanitize → message_post on discuss.channel as agent partner
```

### Provider dispatch
The whole module routes through one class: `LLMApiService` ([`utils/llm_api_service.py:87`](../enterprise/ai/utils/llm_api_service.py#L87)). Its `__init__` only knows two providers (`'openai'`, `'google'`) and raises `NotImplementedError` for anything else. Provider is derived from the chosen `llm_model` via the hard-coded `PROVIDERS` list in [`utils/llm_providers.py:16`](../enterprise/ai/utils/llm_providers.py#L16).

### Agent vs. AI Action vs. AI Field — same pipe, different callers

| Caller | Provider/Model selection | Tools | History |
|---|---|---|---|
| `ai.agent` (chat) | User-selectable per agent (`llm_model` field) | `topic_ids.tool_ids` (`ir.actions.server use_in_ai=True`) | Yes (last N messages from channel) |
| AI server action | **Hard-coded** OpenAI + `gpt-4.1` ([`ir_actions_server.py:26-27`](../enterprise/ai/models/ir_actions_server.py#L26)) | `ai_tool_ids` of the action | No |
| AI computed field | **Hard-coded** `gpt-4.1` ([`ai_fields/tools.py:59`](../enterprise/ai_fields/tools.py#L59)) | None — schema-coerced output | No |

This is intentional: agents are user-tunable; deterministic automation paths are pinned to a known model so prompt regressions don't surprise users.

---

## The Provider System (the part that matters for Claude)

### `Provider` NamedTuple
```python
PROVIDERS = [
    Provider("openai", "OpenAI", "text-embedding-3-small", {...}, [llm tuples]),
    Provider("google", "Google", "gemini-embedding-001",   {...}, [llm tuples]),
]
```
([`llm_providers.py:16-52`](../enterprise/ai/utils/llm_providers.py#L16))

There is **no plugin/registry mechanism**. Adding a provider means editing this Python list. Other modules can monkey-patch it but nothing in core does.

### `LLMApiService` branch points
Every provider-aware method has an `if self.provider == 'openai': … elif 'google': … else raise NotImplementedError` switch:

| Method | Purpose |
|---|---|
| `__init__` ([line 88](../enterprise/ai/utils/llm_api_service.py#L88)) | Sets `base_url` |
| `_get_api_token` ([line 211](../enterprise/ai/utils/llm_api_service.py#L211)) | Looks up config_parameter + env var |
| `_request_llm` ([line 524](../enterprise/ai/utils/llm_api_service.py#L524)) | Dispatches to `_request_llm_openai` or `_request_llm_google` |
| `_to_open_ai_tool_schema` ([line 672](../enterprise/ai/utils/llm_api_service.py#L672)) | Schema mutation only for OpenAI |
| `_build_tool_call_response` ([line 692](../enterprise/ai/utils/llm_api_service.py#L692)) | Builds the per-provider tool-output object |

The OpenAI path uses the **Responses API** (`/responses`), not Chat Completions. Tool calls come back as `output[].type=='function_call'` items; tool results go back in as `function_call_output` items keyed by `call_id`.

The Google path uses Gemini's native API (not its OpenAI compatibility shim) because the shim doesn't handle `type: file`. Tool calls come back in `candidates[].content.parts[].functionCall`.

### Embeddings
`ai.embedding` ([`models/ai_embedding.py`](../enterprise/ai/models/ai_embedding.py)) stores 1536-dim vectors via the custom `Vector` ORM field ([`orm/field_vector`](../enterprise/ai/orm/)) and an `ivfflat` cosine-ops index. Each provider declares its own embedding model; switching an agent's LLM model also switches the embedding model and triggers re-embedding of all sources (`_sync_new_agent_provider`, [`ai_agent.py:343-346`](../enterprise/ai/models/ai_agent.py#L343)).

---

## Module Map (what depends on what)

```
ai (core)
├── ai_app          — packaging meta-module, depends on attachment_indexation
├── ai_auto_install — installs ai if pgvector is present
├── ai_fields       — AI computed fields (model.field with compute via LLM)
│   ├── ai_server_actions — server actions of state='ai'
│   ├── web_studio_ai_fields — Studio UI for creating AI fields
│   └── test_ai_fields
├── ai_knowledge    — Knowledge article AI text drafting
├── ai_account      — Invoice/SO line text drafting
├── ai_documents    — Auto-sort uploaded documents into folders
│   ├── ai_documents_account
│   └── ai_documents_source — index Documents as agent sources
├── ai_crm          — Auto-create leads from text
│   └── ai_crm_livechat
├── ai_livechat     — AI agents as livechat operators
│   └── ai_website_livechat
├── ai_website
├── voip_ai         — Whisper transcription of call recordings
├── sign_ai
├── hr_recruitment_ai
└── esg_csrd_ai
```

External integration points the AI module hooks into:
- **`mail`**: `mail.thread`, `mail.template`, `mail.render.mixin`, `mail.composer.mixin` — AI prompts in mail rendering.
- **`discuss.channel`**: new `channel_type='ai_chat'` ([`discuss_channel.py:30`](../enterprise/ai/models/discuss_channel.py#L30)).
- **`res.partner`**: every agent has a `partner_id` so it can be a chat author.
- **`ir.actions.server`**: extended with `state='ai'` and tool metadata.
- **`ir.attachment`**: file context source for prompts and embeddings.

---

## Configuration

Settings (Settings → General Settings → Integrations):

| Field | config_parameter | env var | Effect |
|---|---|---|---|
| OpenAI key | `ai.openai_key` | `ODOO_AI_CHATGPT_TOKEN` | Required for any OpenAI/`gpt-*` model usage |
| Google key | `ai.google_key` | `ODOO_AI_GEMINI_TOKEN` | Required for any Gemini model usage |
| — | `ai.max_successive_calls` | — | Tool-call loop ceiling, default 20 |
| — | `ai.max_tool_calls_per_call` | — | Parallel tool calls per turn, default 20 |

Defined in [`models/res_config_settings.py`](../enterprise/ai/models/res_config_settings.py) and [`views/res_config_settings_views.xml`](../enterprise/ai/views/res_config_settings_views.xml).

---

## Why There Is No Claude (Anthropic) Provider

There is no architectural reason — Anthropic was simply not added to the `PROVIDERS` list. The codebase has no anthropic SDK import, no `'anthropic'` branch, and no `anthropic_key` setting. Adding it requires touching every dispatch point listed above.

### Concrete differences vs. OpenAI / Gemini that complicate a port

| Concern | OpenAI (current) | Anthropic Messages API | Impact |
|---|---|---|---|
| Endpoint | `POST /v1/responses` | `POST /v1/messages` | New base URL + path |
| Auth | `Authorization: Bearer …` | `x-api-key: …` + `anthropic-version: 2023-06-01` header | New `_get_base_headers` branch |
| System prompt | First role in `input` array | Top-level `system` field (string or content blocks) | New body shape |
| User/assistant turns | `input: [{role, content:[...]}]` | `messages: [{role, content:[...]}]`, no system role allowed | Conversion of `inputs` and `chat_history` |
| Tool definitions | `tools: [{type:"function", name, parameters, strict}]` | `tools: [{name, input_schema, description}]` (no `strict`, no `additionalProperties` rewrite) | New `_to_anthropic_tool_schema` |
| Tool call in response | `output[].type=='function_call'` w/ `call_id` | `content[].type=='tool_use'` w/ `id` | Separate parser |
| Tool result back to model | `{type:'function_call_output', call_id, output}` as next `input` | `{role:'user', content:[{type:'tool_result', tool_use_id, content}]}` | New `_build_tool_call_response` branch |
| Files / PDFs | `{type:'input_file', file_data: data: URI}` | `{type:'document', source:{type:'base64', media_type, data}}` | New `_build_file` |
| Images | `{type:'input_image', image_url}` | `{type:'image', source:{...}}` | Same |
| Structured output | `text.format = json_schema (strict=true)` | Native `output_config.format` with `type: json_schema` (Opus 4.5+) | Reuse strict schema verbatim — no rewrite |
| Web grounding | `web_search_preview` tool | `web_search_20250305` server tool with different config | Easy rename, but feature parity differs |
| Embeddings | `text-embedding-3-small` (1536) | **None — Anthropic ships no embedding endpoint** | Hard problem (see below) |
| Token usage shape | `usage.input_tokens / output_tokens / input_tokens_details.cached_tokens` | `usage.input_tokens / output_tokens / cache_read_input_tokens / cache_creation_input_tokens` | Adapt logging |

### The embedding problem

`ai.agent` couples chat model and embedding model through `_get_provider()` → `provider.embedding_model`. If Claude is the chat model, there is no Anthropic embedding to pair with it. Three honest options:

1. **Decouple** — add `embedding_provider` separately on `ai.agent` so a Claude agent can use OpenAI/Google embeddings. Requires editing the `Provider` schema and the re-sync logic in [`ai_agent.py:333-347`](../enterprise/ai/models/ai_agent.py#L333).
2. **Borrow** — give the Anthropic provider entry an `embedding_model` that points at OpenAI's `text-embedding-3-small`; route embedding calls to `LLMApiService(provider='openai')` regardless. Cheapest change, but requires the user to also configure an OpenAI key.
3. **Voyage AI** — Anthropic's recommended embedding partner. Means another provider with its own auth and API. Most work, most consistent UX.

### Hard-coded surfaces that won't pick up Claude automatically

Even after adding the provider, these stay on OpenAI unless explicitly changed:

- [`ir_actions_server.py:26-27`](../enterprise/ai/models/ir_actions_server.py#L26) — `AI_PROVIDER='openai'`, `AI_MODEL='gpt-4.1'`
- [`ai_fields/tools.py:59`](../enterprise/ai_fields/tools.py#L59) — `OPENAI_MODEL='gpt-4.1'`
- [`voip_ai/models/voip_call.py:63`](../enterprise/voip_ai/models/voip_call.py#L63) — `LLMApiService(self.env)` defaults to `provider='openai'` for Whisper transcription. Anthropic has no transcription endpoint, so this stays OpenAI regardless.

---

## What It Would Take — Minimum Viable Anthropic Provider

A custom addon `custom_addons/ai_anthropic/` that:

1. **Extends `PROVIDERS`** by monkey-patching `odoo.addons.ai.utils.llm_providers.PROVIDERS.append(Provider('anthropic', 'Anthropic', borrowed_embedding_model, {...}, [('claude-opus-4-7','Claude Opus 4.7'), …]))` in `__init__.py` at import time. `post_init_hook` does not work here — it only fires on install, so patches would be lost on the next process restart (see [`ai_anthropic_integration_plan.md`](ai_anthropic_integration_plan.md) §8.2).
2. **Patches `LLMApiService`** with `monkey_patch` or method override to add:
   - `'anthropic'` branch in `__init__`, `_get_api_token`, `_request_llm`, `_build_tool_call_response`
   - new `_request_llm_anthropic(...)` method translating system_prompts/user_prompts/tools/files/inputs → Messages API body and parsing `content[]` for `tool_use` / `text` blocks
3. **Inherits `res.config.settings`** to add `anthropic_key` field + view extension.
4. **Inherits `ai.agent`** only if you want the embedding decoupling (option 1 above) — otherwise nothing to change here, the new models will appear in the existing `llm_model` selection automatically because `_get_llm_model_selection` rebuilds from the patched `PROVIDERS`.

### Realistic effort
- ~400 LOC for the provider port itself
- ~50 LOC for settings
- Tests (mock the Messages API like [`test_gemini_integration.py`](../enterprise/ai/tests/test_gemini_integration.py) does for Gemini)
- Decision point on embeddings before any of the above — that's the architectural choice, not the code.

### Caveats Odoo-side
- Hard-coded `AI_MODEL='gpt-4.1'` paths (server actions, ai_fields) will keep using OpenAI. To switch them to Claude you'd need to either fork those modules or add a config_parameter override and patch them too — that's a separate piece of work.
- No fallback / retry across providers exists. If the chosen agent model fails, the call fails.
- The tool-loop assumes the OpenAI semantics around `__end_message`. Claude's tool loop terminates differently — Claude returns `stop_reason='end_turn'` vs `'tool_use'`. The loop in `_request_llm_silent` ([line 608-660](../enterprise/ai/utils/llm_api_service.py#L608)) needs to respect that signal instead of just "no `next_actions`".

---

## Edge Cases & Gotchas

- **No `ai.composer` for tool action**: AI server actions don't go through `ai.composer`, so the user can't pick the model — it's always GPT-4.1.
- **Channel garbage collection**: AI chat channels are auto-deleted after 1 day of inactivity ([`discuss_channel.py:108-115`](../enterprise/ai/models/discuss_channel.py#L108)).
- **Provider switch re-embeds everything**: changing `llm_model` to a model from a different provider triggers re-embedding of all sources — costly on large source sets.
- **Tool call cap**: `ai.max_tool_calls_per_call` (default 20) silently truncates parallel tool batches. If Claude's parallel-tool behavior differs, this limit may bite earlier.
- **`is_system_agent` agents cannot be deleted** ([`ai_agent.py:356-361`](../enterprise/ai/models/ai_agent.py#L356)).
- **`ai_agent_id` is `groups=fields.NO_ACCESS`** on `discuss.channel` — only sudo flows can write it.
