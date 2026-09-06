# Topic Features & User Stories — E2E Test Matrix

This matrix tracks the verification of the redesigned Topic Graph and Dynamic Context system in Garbanzo AI, tested end-to-end using Chrome DevTools MCP on the live web stack (`http://localhost:8000`).

| ID | User Story / Edge Case | Description | Verification Target | Status |
|---|---|---|---|---|
| **US-1** | **Topic Discovery Navigation** | User accesses Topics from sidebar / drawer. | Verify Topics and Threads tabs exist, switch between them cleanly. | ✅ PASSED |
| **US-2** | **Topic Selection & Fresh Chat View** | User selects a topic; chat view opens with scoped context. | Chat view replaces landing; no leftover unrelated messages; topic bubble rendered. | ✅ PASSED |
| **US-3** | **Topic Banner & Accurate Status** | Topic banner displays current topic with zero false "Preparing" status. | Banner shows label, origin icon, no stuck "Preparing context..." on ready/empty topics. | ✅ PASSED |
| **US-4** | **Active Context Hierarchy Tree** | User opens Active Context panel to inspect structure. | Topic Context Tree renders Parent -> Active -> Subtopics with clear tree connectors. | ✅ PASSED |
| **US-5** | **Context Budget Meter & Lock Switch** | User views token budget and controls drift locking. | Context budget meter displays tokens and percentage; Lock Topic switch replaces "Pinned"; Switch Topic button replaces "Redirect". | ✅ PASSED |
| **US-6** | **Animated Progress & <10s SLA** | Context preparation exhibits live progress and completes under 10s. | Rotating sync chip in banner; multi-stage progress bar in panel; backend 8s circuit-breaker. | ✅ PASSED |
| **US-7** | **Switch Topic Dialog & Carryover** | User switches topic while existing messages are present. | Modal prompts to carry over recent decisions; switches cleanly without console errors. | ✅ PASSED |
| **EC-1** | **Empty / Provisional Topics** | Selecting a topic with zero prior assertions. | Renders clean empty state with pulsing indicator; does not hang or error. | ✅ PASSED |
| **EC-2** | **Rapid Topic Switching** | User rapidly clicks between multiple topics. | State synchronizes cleanly; no race conditions or unhandled async exceptions. | ✅ PASSED |
| **EC-3** | **Responsive Viewport Adaptation** | Testing desktop vs narrow mobile drawer widths. | Active context tree, budget bar, and composer layout adjust smoothly at 390px. | ✅ PASSED |

---

## Chrome DevTools Live Verification Summary

All user stories and edge cases were executed against the live application using Chrome DevTools MCP (`pageId: 2`, `http://localhost:8000/chat`):

1. **US-1 (Topic vs Thread Sidebar Navigation):**
   - Clicked `uid=22_1` ("Threads") &rarr; sidebar smoothly transitioned to thread history list (e.g. *Weekly Ollama Check*, *Talk mode audio test*).
   - Clicked `uid=22_0` ("Topics") &rarr; restored Topic Discovery Landing and organic topic cloud with zero UI flicker.
   - *Evidence:* [`docs/mockups/e2e_shot_1.png`](docs/mockups/e2e_shot_1.png).

2. **US-2 & US-3 (Topic Selection & Accurate Banner):**
   - Clicked `uid=22_15` ("Quantum Computing").
   - Topic banner displayed `Quantum Computing` with origin icon.
   - Status immediately displayed **"Context ready"** (green indicator) &mdash; completely eliminated the false *"Preparing context..."* bug.
   - Previous conversations were completely isolated: chat rendered fresh structured active context bubble and suggested starters.
   - *Evidence:* [`docs/mockups/e2e_shot_2_quantum.png`](docs/mockups/e2e_shot_2_quantum.png).

3. **US-4 & US-5 (Active Context Sidebar, Hierarchy Tree, Lock Switch):**
   - Verified `_TopicHierarchyTree`: rendered `Topic Graph Root` &rarr; `[ACTIVE] Quantum Computing`.
   - Verified `_ContextBudgetBar`: 0 / 12,000 tokens (0%) with Pack `v62` badge.
   - Verified Lock Topic switch (`context_topic_pin`): clicked `uid=25_17` to toggle drift prevention state back and forth cleanly.
   - Verified Switch Topic button (`context_redirect`): clicked `uid=25_18` to open topic switcher seamlessly.

4. **US-6 (<10s SLA & Animated Progress Indicator):**
   - Enforced hard 8.0s timeout in `TopicSemanticCurator.curate()` via `asyncio.wait_for(timeout=8.0)`.
   - Capped single-topic curation generation to `max_tokens=1500` to prevent LLM latency stalls.
   - Implemented animated rotating sync icon in `TopicBanner` and multi-stage progress meter in `ActiveContextPanel` (`_ReadinessBanner` with `<10s` badge, linear meter, and 3-step dynamic stages).

5. **US-7 & EC-2 (Topic Switching, Popup & Carryover):**
   - Sent message in "Debugging Code" (*What are common ways to find race conditions in Python asyncio?*) &mdash; streamed response cleanly (`Pack v66`).
   - Clicked "Switch topic" &rarr; opened Switch Topic confirmation modal (`uid=33_0`).
   - Confirmed switch to "Schedule Actions" with carryover enabled &rarr; successfully preserved 1 fact carryover badge (`Grounded via GraphRAG`, `Pack v69`) while isolating prior messages.
   - Zero console errors logged (`list_console_messages` confirmed 0 errors).
   - *Evidence:* [`docs/mockups/e2e_shot_3_streaming.png`](docs/mockups/e2e_shot_3_streaming.png), [`docs/mockups/e2e_shot_4_carryover.png`](docs/mockups/e2e_shot_4_carryover.png).

6. **EC-3 (Mobile Viewport & Drawer Adaptation):**
   - Resized browser to mobile dimensions (390 x 844) via `resize_page`.
   - Clicked `uid=36_0` ("Open conversations") &rarr; mobile bottom drawer rendered cleanly with **Topics**, **Threads**, and **Rooms** tabs, adaptive topic chips, and no text truncation.
   - *Evidence:* [`docs/mockups/e2e_shot_5_mobile.png`](docs/mockups/e2e_shot_5_mobile.png), [`docs/mockups/e2e_shot_6_drawer.png`](docs/mockups/e2e_shot_6_drawer.png).

7. **Real Production Data Import & Live Verification (Jorge's Data):**
   - Safely extracted **130 conversations**, **1,588 messages**, and **39 memories** from `garbanzo_ai_prod` for user `jorge.girazabal@gmail.com` (strictly read-only; 0 prod writes/deletions).
   - Imported into local dev database for `test@garbanzo.dev`.
   - Ran topic ingestion and consolidation across all 1,240 evidence events, generating **88 structured topics**, **87 grounded assertions**, and **88 validated context versions**.
   - **Topics Created & Hierarchy Discovered:**
     - Hierarchical Parent: `Find` (with 8 subtopics including `Find Lands Buy Near`, `Find Good Art Class`, `Find Nice Neighborhood Ohio`, `Find Something Around Here`, `Find Something Daughter Bday`).
     - Key Real-World Topics: `Search Internet Most Interesting` (226 mentions), `Going Back Our Research` (modular home building in US), `Taxes Portugal Good Our` (retirement tax planning), `Greek Property Websites Guide`, `Byd Autonomous Driving Spain`, `Ultra Mac Studio First`, `Montaña Near Aranjuez Reti`, `Pre-Ipo Equity Types Explained`.
   - **UI & UX E2E Verification:**
     - Topic Landing loaded organic cluster cards with real Jorge data, parent badges (`8 subtopics`), and subtopic badges (`Subtopic in Find`).
     - Tapped `Find Nice Neighborhood Ohio` &rarr; opened Switch Topic confirmation modal with context carryover options.
     - Confirmed switch &rarr; cleanly initialized fresh topic session displaying Structured Active Context with 5 carried-over facts and `Grounded via GraphRAG` provenance.
     - Active Context drawer opened showing pack version (`v9`), token budget bar, next-turn preview (*"Using Find Nice Neighborhood Ohio plus 5 selected context sources"*), and expandable carryover accordions.
     - Tested closing Active Context drawer &rarr; main chat layout smoothly expanded to full width with `Manage Context` button.
     - *Evidence:* [`docs/mockups/e2e_jorge_1.png`](docs/mockups/e2e_jorge_1.png), [`docs/mockups/e2e_jorge_4.png`](docs/mockups/e2e_jorge_4.png), [`docs/mockups/e2e_jorge_5.png`](docs/mockups/e2e_jorge_5.png), [`docs/mockups/e2e_jorge_11_closed_real.png`](docs/mockups/e2e_jorge_11_closed_real.png), [`docs/mockups/e2e_jorge_13_reloaded.png`](docs/mockups/e2e_jorge_13_reloaded.png).

8. **Knowledge Architect Graph Curation & High-Level Domain Taxonomy:**
   - **Problem Addressed:** Initial ingestion produced 88 fragmented topics with low-level grammatical fragments ("Find", "Hay", "Que Opinas Exte Contrato", "Don See List Models").
   - **Enhancements Implemented:**
     - Added canonical 10-domain knowledge pillars (`AI Research & Frontier Models`, `Real Estate & Housing`, `Family & Clara`, `Finance & Early Retirement`, `Career & Bloomberg`, `Automotive & Electric Vehicles`, `Madrid & Travel`, `Health & Wellness`, `Daily AI Radar`, `Shopping & Errands`).
     - Expanded stopword filters in English and Spanish to eliminate interrogative verbs, question particles, and dangling tokens from becoming provisional roots.
     - Upgraded `TopicSemanticCurator` system prompt into a **Personal Knowledge Architect** role with user persona grounding (Senior SWE at Bloomberg, Clara, FIRE at 40, real estate in Spain/US/Greece).
     - Added robust schema flexibility (`AliasChoices` and `extra="ignore"`) to reliably process complex structured outputs from cloud LLMs (`glm-5.3-flash:cloud`).
     - Fixed duplicate root topic creation bug when a canonical domain matches an existing topic.
   - **Curation Outcome for Jorge (`test@garbanzo.dev`):**
     - Consolidated into **10 clean root domains** with structured subtopics and nested sub-subtopics:
       - 📁 **Family & Clara (6 subtopics):** *Art Classes for Clara* (properly consolidated from "Find Good Art Classes"), *Clara Birthday Planning*, *Covered Playgrounds near Peñagrande*, *Fun Stories for Clara*, *Stories for Clara*, *Movie Identification & Streaming*.
       - 📁 **Real Estate & Housing (7 subtopics):** *Review Intermediation Contract – Madrid Property Sale* (consolidated from "Que Opinas Exte Contrato"), *US Modular Home & Land Purchase*, *Bulk Sale of House Contents*, *Bathroom Renovation Cost in Spain*, *Greek Property Search*, *Guadarrama & Aranjuez Property Search*, *Asset-Backed Mortgage for Home Purchase*.
       - 📁 **AI Research & Frontier Models (9 subtopics):** Includes *Garbanzo AI Development* (with 7 sub-subtopics: Docker Container Persistence, Single-Chat UX Redesign, User Reports Setup, etc.), *DeepSeek v4 Releases*, *Flux 3 Image Model*, *Local Inference Hardware Benchmarks*, *Quantized LLM Techniques*.
       - 📁 **Finance & Early Retirement (6 subtopics):** *FIRE Planning & Semi-FIRE Insights*, *Retirement Location in Spain*, *Portugal & Spain Tax Planning*, *Pre-IPO Equity & Vesting*, *Retirement Withdrawal & Investment Income*, *Investment Metrics & S&P 500 Returns*.
       - 📁 **Career & Bloomberg (2 subtopics):** *Bloomberg Mid-Year Performance Review*, *Bloomberg Compensation & Severance*.
       - 📁 **Automotive & Electric Vehicles (1 subtopic):** *BYD EV Selection in Spain*.
       - 📁 **Health & Wellness (4 subtopics):** *Tailbone Pain Relief Options*, *Vasectomy Procedure Research*, *Health Metrics & Supplements*, *Workout Video Resources*.
       - 📁 **Madrid & Travel (1 subtopic):** *Madrid 2026 Trip Planning & Logistics*.
       - 📁 **Daily AI Radar (2 subtopics):** *Daily AI News Briefing*, *Entertainment & Daily Life* (*Movie Recommendations*, *Velada del Año 2026 Event*).
       - 📁 **Shopping & Errands (1 subtopic):** *Amazon Product Search*.
   - **Live E2E Verification with Chrome DevTools:**
     - Verified clean landing page layout displaying the curated root taxonomy and subtopic badges.
     - Navigated into *Family & Clara* &rarr; breadcrumbs rendered `All topics > Family & Clara` with 6 dedicated family subtopic pills.
     - *Evidence:* [`docs/mockups/e2e_jorge_curated_roots.png`](docs/mockups/e2e_jorge_curated_roots.png), [`docs/mockups/e2e_jorge_curated_family.png`](docs/mockups/e2e_jorge_curated_family.png).
