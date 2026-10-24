# Ollama Cloud model review — 2026-10-17

Recommendation after production inspection and the small provider comparison:
keep DeepSeek-V4.1-Flash as the general default, including Truth Seeker,
Tutoring and Brainstorm. Prioritize a GLM-5.3-Flash trial for Concise. Mistral
Large 4 remains a writing candidate, and Beam an experimental text-coding
candidate. Clef is most promising for room auto-reply eligibility. There is
insufficient evidence for an immediate production model switch.

The initial review used official published evidence and production configuration.
A follow-up inspection and small synthetic provider comparison are recorded
below. No models were pulled and no application configuration or production
data changed. This is not a comprehensive inference benchmark.

## Current application configuration

Read-only production inspection confirmed five built-in styles in each of
English and Spanish, all using `deepseek-v4.1-flash:cloud`:

| Preset | Current thinking | Recommendation |
| --- | --- | --- |
| Concise / Conciso | Provider default | Compare GLM-5.3-Flash at low effort against DeepSeek at low/off; measure time to final answer and instruction adherence. |
| Truth Seeker / Buscador de la verdad | Medium | Keep DeepSeek; compare alternatives only with actual search, citation checking, and conflicting evidence. |
| Writing & Stories / Escritura e historias | Provider default | Compare Mistral Large 4 with DeepSeek on blinded English and Spanish edits/stories. |
| Tutoring / Tutoría | Medium | Keep DeepSeek; measure teaching behavior as well as correctness before changing. |
| Brainstorm / Lluvia de ideas | Provider default | Compare GLM-5.3-Flash at low effort; Mistral is a secondary creative candidate. |

The assignments live in `backend/app/services/style_service.py`. Personas live
in `backend/app/services/system_prompt_service.py`; having a Coding Assistant
persona does not mean there is a built-in coding style. Personal topic nodes
are distinct from these preset bundles.

Production Ollama already has DeepSeek-V4.1-Flash, GLM-5.3-Flash, GLM-5.3,
Kimi K3, DeepSeek V4 Pro/Flash, MiniMax M3, GLM-5.2, Kimi K2.7 Code, and Gemma 4
cloud tags installed. Beam, Muse Spark Open, and Mistral Large 4 are absent.
An installed tag or public listing does not prove an inference request will
succeed with the current account.

At this October 17 review, the live `llm_context_window` cap was **100,000
tokens**. The application uses the smaller of that cap and model metadata.
Advertised 1M windows therefore did not distinguish candidates in this review.
The current default is 300,000 tokens; see [environment.md](environment.md).

## Full catalog comparison

Scope: all **20 families** in the user-supplied
[Ollama Cloud catalog](https://ollama.com/search?c=cloud), checked October 17,
2026. Prices are USD per million uncached input/output tokens, excluding
promotions, cache discounts and off-peak rates. Context and vision refer to
the hosted variant, not every local variant in a family. Each model link is
the official capability source; rates are cross-checked against
[Ollama pricing](https://ollama.com/pricing).

| Model family | Cloud context | Images | Input / output | Assessment for our presets |
| --- | --- | --- | --- | --- |
| [Beam](https://ollama.com/library/beam) | 1M | No | Temporarily free; ongoing rate not published | Trial for coding, text research and reasoning; predominantly English training limits confidence for Spanish. |
| [Muse Spark Open](https://ollama.com/library/muse-spark-open) | 1M | Yes | $1.25 / $4.25 | New multimodal engineering candidate; no demonstrated advantage for our five presets. |
| [Mistral Large 4](https://ollama.com/library/mistral-large-4) | 1M | Yes | $0.68 / $2.09 | Priority writing/multilingual comparison; preview maturity and subjective writing quality need checking. |
| [Clef](https://ollama.com/library/clef) | 64K | Yes | $0.24 / n/a | Typed decision model, not a conversational replacement. Uses a different API. |
| [DeepSeek-V4.1-Flash](https://ollama.com/library/deepseek-v4.1-flash) | 1M | Yes | $0.30 / $1.20 | Strong existing general baseline; retain for research and tutoring. |
| [GLM-5.3-Flash](https://ollama.com/library/glm-5.3-flash) | 1M | Yes | $0.15 / $0.50 | Best first cost comparison for Concise/Brainstorm; lower price does not establish lower latency. |
| [GLM-5.3](https://ollama.com/library/glm-5.3) | 1M | No | $1.40 / $4.40 | Specialized difficult coding option; weak reason to replace our general default. |
| [Kimi K3](https://ollama.com/library/kimi-k3) | 1M | Yes | $3.00 / $15.00 | Premium reasoning/knowledge-work challenger; expensive for ordinary presets. |
| [GLM-5.2](https://ollama.com/library/glm-5.2) | 1M | No | $1.40 / $4.40 | Do not newly standardize on the older GLM generation. |
| [Kimi K2.7 Code](https://ollama.com/library/kimi-k2.7-code) | 256K | Yes | $0.95 / $4.00 | Coding-focused, not a priority for the existing five styles. |
| [Nemotron 3 Ultra](https://ollama.com/library/nemotron-3-ultra) | 256K | No | $0.10 / $3.00 | Interesting input-heavy agent workloads; output price unattractive for everyday replies. |
| [MiniMax M3](https://ollama.com/library/minimax-m3) | 500K | Yes | $0.60 / $2.40 | Agent/coding candidate, without enough evidence to displace DeepSeek here. |
| [DeepSeek V4 Pro](https://ollama.com/library/deepseek-v4-pro) | 1M | No | $1.32 / $3.96 | Hard reasoning comparison only; higher price and lacks baseline image support. |
| [Kimi K2.6](https://ollama.com/library/kimi-k2.6) | 256K | Yes | $0.95 / $4.00 | Lower priority than its successors for a new preset assignment. |
| [MiniMax M2.7](https://ollama.com/library/minimax-m2.7) | 192K | No | $0.30 / $1.20 | No obvious price advantage over our newer multimodal baseline. |
| [Gemma 4](https://ollama.com/library/gemma4) | 256K | Yes | $0.14 / $0.40 | Budget concise/chat challenger, already installed; check correctness and tools before promotion. |
| [Nemotron 3 Super](https://ollama.com/library/nemotron-3-super) | 256K | No | $0.015 / $0.60 | Attractive input-heavy economics; prioritize for background agents rather than writing presets. |
| [Nemotron 3 Nano](https://ollama.com/library/nemotron-3-nano) | 256K | No | $0.06 / $0.24 | Cheap lightweight candidate; quality evidence insufficient for automatic replacement. |
| [Mistral Large 3](https://ollama.com/library/mistral-large-3) | 256K | Yes | $0.50 / $1.50 | Lower priority than evaluating Large 4 for new assignments. |
| [gpt-oss](https://ollama.com/library/gpt-oss) | 128K | No | 20B: $0.07 / $0.30; 120B: $0.15 / $0.60 | Budget text reasoning; both cloud sizes considered, neither preserves image input. |

## Why these recommendations

**DeepSeek remains a credible baseline.** Its published comparison reports
74.2 on DeepSWE v1.1 and 63.9 on HLE with tools, versus 66.9/62.5 for GLM-5.3
and 67.5/59.8 for Kimi K3. Kimi is stronger on some unaided reasoning metrics.
These are vendor-reported results, not our evaluation; they argue against
assuming an older flagship is an upgrade merely because it costs more.
[DeepSeek model card](https://ollama.com/library/deepseek-v4.1-flash).

**GLM-5.3-Flash is the practical cost challenger.** It supports tools and
vision, with competitive published agent results. Its reasoning is always on,
so Concise should explicitly evaluate low effort. Our provider already maps
GLM's off setting to low effort with reasoning hidden; off does not remove the
computation. Existing styles leave Concise/Brainstorm effort unspecified.
[GLM-5.3-Flash model card](https://ollama.com/library/glm-5.3-flash).

For a hypothetical request with 10,000 uncached input and 2,000 output tokens,
DeepSeek costs $0.0054 at peak and GLM Flash $0.0025: approximately **54% less**.
DeepSeek's off-peak total is $0.0027, reducing that advantage to about **7%**.
DeepSeek also has cheaper cached input. Actual cost comparisons must include
reasoning tokens, cache hit rates, retries and completed-task quality.
[Pricing and off-peak schedule](https://ollama.com/pricing).

**Mistral Large 4 is a writing experiment, not a proven writing winner.**
Mistral reports broad multilingual training and strong document/knowledge work,
making it a sensible candidate for both app languages. Its October 6 release
is a public preview; the announcement says weights are due later in October.
Published enterprise and coding results do not establish better fiction,
editing, tone or voice preservation. Use blind examples to decide.
[Mistral announcement](https://mistral.ai/news/mistral-large-4/).

**Beam deserves a separate trial.** Released October 16, it targets text-based
coding, tool use and reasoning and is temporarily free on Ollama. Its published
DeepSWE result is 43.3 in BF16, so it is not an obvious coding upgrade over our
baseline even before considering harness differences. It is predominantly
English and accepts no images. Keep it experimental, especially for Spanish
or attachment-heavy chats. No permanent zero-price assumption is justified.
[Beam card](https://ollama.com/library/beam),
[Ollama launch announcement](https://ollama.com/blog/reflection-beam).

**Muse Spark Open is a watchlist candidate.** It launched October 15 and has
multimodal tool/reasoning support, but is substantially more expensive than
DeepSeek. The available evidence does not establish a benefit for our current
presets. Its release uses a custom model license rather than Apache/MIT.
[Model listing](https://ollama.com/library/muse-spark-open),
[publisher release/license](https://huggingface.co/meta-models/Muse-Spark-Open-816B-A42B/blob/main/LICENSE.md).

**Clef cannot be selected as a drop-in chat model.** It produces typed
decisions and probabilities through `/v1/systemone`, whereas Garbanzo's
provider uses chat generation. Potential routing/classification use would be
a separate feature, not a preset model update.
[Clef API and model card](https://ollama.com/library/clef).

## Evidence needed before changing defaults

Use synthetic, repeatable prompts in English and Spanish, through our actual
provider/tool loop. Keep the same evidence, tools, output limits and sampling
for each pair; record actual reasoning settings and endpoint metadata. Repeat
cases because one successful answer is not reliability evidence.

| Comparison | Required examples | Decision criteria |
| --- | --- | --- |
| Concise: DeepSeek vs GLM Flash, then Gemma | Short factual answer, strict word budget, clarification, multi-turn correction, image | Correctness and brevity, measured final-answer latency and total tokens. |
| Brainstorm: DeepSeek vs GLM Flash | Constrained ideas, non-repetition, revision after feedback | Useful diversity, instruction adherence, cost per acceptable answer. |
| Writing: DeepSeek vs Mistral Large 4 | Voice-preserving edit, nonfiction argument, dialogue/story, Spanish idiom | Blind preference across multiple samples; no factual additions during editing. |
| Truth Seeker: baseline plus challenger | Current claim, contradictory sources, insufficient evidence | Sources support the answer, uncertainty is honest, tool budget ends in a finished answer. |
| Tutoring: baseline plus challenger | Math misconception, guiding question, explicit request for full solution | Correct reasoning and appropriate teaching behavior, not merely final-answer accuracy. |
| Experimental coding: DeepSeek vs Beam | Bug fix, constrained tools, recovery from failure | Verifiable tests and artifacts; no fabricated completed actions. |

Do not replace research tool wiring, citation checks or context ownership with
a claim that a model is better at search. Those remain application behavior.
Validate streaming, thinking parsing, images and final synthesis before
promoting any new family. Do not assume every model accepts every effort value.

An eventual preset change needs both seed updates and an idempotent migration
for the existing shared built-in rows; seeding only inserts missing presets.
Scope it to the chosen built-in names/locales and leave saved user styles,
existing conversations, room agents and scheduled actions alone. Verify model
installation and capability discovery before rollout, since the picker hides
styles whose model is absent. Do not reuse migration 047's broad rewrite as
the template for this narrower change.

Migration 037 historically replaced several tags that the current public
catalog still lists (MiniMax M3, GLM-5.2, Kimi K2.7 Code). Treat that as a
historical application decision, not proof those families are globally
unavailable today. Recheck live account access before reintroducing any tag.


## Production follow-up — October 17

Checked the running backend settings, production database aggregates and local
Ollama metadata, rather than assuming repository defaults were deployed.
Production source is `e36789dba8e9f88fa75db962bbd5343faf9a79c3`; the local
review source is `1dbbf1ec3e580756575fa9c5bebebc955268ea63`. The model settings
below are the observed running values, not a proposed configuration.

| Production surface | Effective model / setting |
| --- | --- |
| All ten built-in style rows (five per language) | `deepseek-v4.1-flash:cloud` |
| General server default | `deepseek-v4.1-flash:cloud` |
| Daily memory extraction | `deepseek-v4.1-flash:cloud` |
| Topic semantic curator | `deepseek-v4.1-flash:cloud`, Medium thinking |
| Topic context privacy | `cloud_allowed` |
| Room auto-reply judge | `deepseek-v4.1-flash:cloud` |
| Agents in active rooms | `deepseek-v4.1-flash:cloud` |
| Scheduled action default | `deepseek-v4.1-flash:cloud`; active action has no override |
| Micro-apps / delegated workflow coding default | `ollama/deepseek-v4.1-flash:cloud` |
| Embeddings | `nomic-embed-text`, 768 dimensions |
| Production Ollama | **0.31.2** |
| Context ceiling | **100,000 tokens** |

Saved user styles also select GLM-5.3 and GLM-5.3-Flash; a global replacement
would override deliberate user choices. Recent persisted conversation traffic
uses those models as well as DeepSeek. Its latency figures do not establish
which model is faster: prompts, thinking settings, tools and output lengths
are not controlled, and joining current conversation.model does not prove the
historical model for every individual message. Raw aggregates remain private.

New-topic/startup composer initialization explicitly sets **Medium** thinking,
regardless of the saved preset effort. This is present in the deployed source
as well as current main (`StyleProvider.applyDefaultForNewTopic` and
`_seedPending`). Changing only Concise's stored effort to low would not change
that path. Any low-effort Concise proposal needs an explicit product decision
about this initialization behavior, with existing custom choices preserved.

The `topic_realtime_model` setting is empty in production and has no call site
beyond its declaration in the reviewed source. It is not evidence of a second
active real-time model route.

### Proposed changes after inspection

1. **First candidate: Concise on GLM-5.3-Flash.** Compare at the actual Medium
   startup setting as well as Low. Do not promise consistent speed from a few
   samples, and decide how a preset's effort interacts with new-topic defaults.
2. **Keep Brainstorm on DeepSeek for now.** A Low-effort Spanish GLM Flash
   sample added an explicitly forbidden closing paragraph. That narrows the
   earlier recommendation: price and speed do not justify promoting it yet.
3. **Keep research, tutoring and coding defaults on DeepSeek.** The production
   workload does not establish a benefit from changing them wholesale.
4. **Evaluate GLM Flash for structured topic/memory work separately.** They
   currently use the same general model, but require grounded extraction,
   schema validation and failure handling. A small conversational test cannot
   qualify them. Clef cannot generate their replacement assertions/memories.
5. **Clef: prioritize room auto-reply eligibility.** It can replace an existing
   generative binary judgment there. Topic drift, memory filtering and context
   ranking mostly add another inference step, so require a demonstrated quality
   benefit. The separate architecture report details the experiment and
   integration requirements.

No setting or preset has been changed or deployed as part of this follow-up.


### Synthetic provider comparison

Sixteen valid requests: four synthetic prompts, both models, Low and Medium
thinking. Used the deployed `OllamaProvider` and built-in persona prompts, no
user messages or database writes. Temperature 0.2, context 8192, output cap
1536, at most two concurrent calls. One sample per condition; not randomized
and not a representative reliability/latency benchmark. Request duration
includes metadata/network overhead and queueing, not merely generation.
An initial harness attempt used the wrong chunk field; its eight aborted
requests are excluded, and are not model failures. Raw reasoning was not saved.

| Case | Thinking | DeepSeek-V4.1-Flash | GLM-5.3-Flash |
| --- | --- | --- | --- |
| concise_en | Low | 0.57s; format pass | 0.28s; format pass |
| concise_en | Medium | 0.60s; format pass | 0.35s; format pass |
| concise_es | Low | 0.69s; format pass | 0.38s; format pass |
| concise_es | Medium | 0.68s; format pass | 0.90s; format pass |
| brainstorm_en | Low | 2.10s; format pass | 0.56s; format pass |
| brainstorm_en | Medium | 4.26s; empty at token cap | 7.10s; format pass |
| brainstorm_es | Low | 2.51s; format pass | 1.00s; format failure / truncated |
| brainstorm_es | Medium | 2.29s; format pass | 7.86s; format failure / truncated |

All Concise samples correctly preserved the supplied fact and declined to
invent PDF-export support, within 25 words. GLM was faster in both Low samples
and English Medium, but slower in Spanish Medium. Low-effort Spanish GLM
Brainstorm added a forbidden conclusion; Medium Spanish GLM and Medium English
DeepSeek hit the artificial output cap before completing their answers.
Those truncations do not establish model failure under production requests that do not set
this 1536-token cap. They do show why reasoning effort and token limits
must accompany a model recommendation. These probes do not qualify tools,
images, long context, extraction or full application turn behavior.

### Clef feasibility

Astra's independent code review ranks room auto-reply eligibility first, then
memory eligibility, advisory topic decisions and optional-context reranking.
The room case replaces an existing generative judgment. Other candidates mostly
add calls and could lose recall, so need a demonstrated benefit. Topic naming,
assertion extraction and memory text still require a generative model.

**Deployment prerequisite:** production Ollama is 0.31.2; the documented cloud
proxy requires >=0.40.5 for `/v1/systemone`. Clef is not installed or inference
verified. A direct authenticated cloud client is a separate integration option,
not a transparent chat-model setting change.
[System One API](https://docs.ollama.com/api/systemone),
[decision guide](https://docs.ollama.com/capabilities/decision).

Start with an offline, independently labeled room-routing comparison and a
separate typed decision client. Keep explicit mentions, active/self filtering,
turn limits, permissions, ownership and user topic choices deterministic.
Classification confidence is not proof of correctness. Errors must remain
visible, not become a false decision such as “do not reply.”

The full private review is at
`.ai/local/architecture-reviews/clef-use-cases-2026-10-17.md`.


## Implementation follow-up — October 18

The explicitly requested Ollama-only production upgrade is complete: 0.40.6,
with existing model/sign-in volume retained. Existing DeepSeek chat and Nomic
768-dimensional embedding smoke checks passed. Clef was provisioned and hidden
from the old application's chat picker because it is a decision-only model.

The preset-thinking fix and Clef application integrations are implemented and
reviewed locally. New-topic thinking honors saved effort, Medium otherwise.
Room judging uses a bounded latest-request gate followed by an agent suitability
check; topic decisions confirm drift advice and filter/rank already-selected
optional context, preserving required/pinned groups and revalidating freshness.
The live proxy reports canonical `clef` for requested `clef:cloud`; the client
accepts that exact alias normalization, not unrelated model names.

Eighteen distinct synthetic room/topic/relevance cases passed on the live
endpoint after correcting acknowledgment handling and adding one preceding
utterance for contextual English/Spanish acceptances. This is smoke evidence,
not a representative accuracy estimate. The application has not been released;
production backend source remains `e36789d` at this point.
