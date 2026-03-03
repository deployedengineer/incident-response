# 🧠 AI Concepts Deep Dive

> **Audience:** Engineers and practitioners who want to understand the AI design decisions made in this system — which workflows were tested, what the results showed, and why the architecture is built the way it is.

This document covers:

- What the **non-RAG workflow testing** revealed — four workflow types (LLM-only, Google Grounding, Tavily, SerpAPI), 14 models, 10 test cases, and the search delta analysis
- What the **RAG configuration testing** revealed — four retrieval architectures (Configs A–D), 8 test cases, pass rates, and token economics
- Why this system uses **RAG + Search together** (the combined approach consistently outperforms either alone)
- **Failure Mode Taxonomy** — eight patterns observed across all configurations and how the system mitigates them
- **Model Recommendations** grounded in actual test data, not marketing claims
- **Embedding model tradeoffs** and when to upgrade

> **Testing status:** Both the non-RAG workflow comparison and the RAG configuration analysis are complete. The non-RAG study covered all four workflow types and 14 models across 10 test cases. The RAG study covered all four configurations (Configs A–D) across 8 test cases each, with detailed pass/fail verdicts and cross-config comparisons.

---

## 📋 Table of Contents

- [Non-RAG Workflow Analysis](#1-non-rag-workflow-analysis)
- [RAG Configuration Analysis](#2-rag-configuration-analysis)
- [Why RAG + Search Beats Either Alone](#3-why-rag--search-beats-either-alone)
- [Failure Mode Taxonomy](#4-failure-mode-taxonomy)
- [Model Recommendations](#5-model-recommendations)
- [Embedding Model Tradeoffs](#6-embedding-model-tradeoffs)
- [Open Source vs Closed Source](#7-open-source-vs-closed-source)
- [What to Test Next](#8-what-to-test-next)

---

## 1. Non-RAG Workflow Analysis

> **Test setup:** 10 test cases (TC1–TC10), spanning Easy → Medium → Hard → Edge difficulty tiers. Graded on: **Accuracy (primary) > Safety > Search Economy > Completeness > Format**. No RAG / vector retrieval involved — this study isolates the web search and model quality variables only.

### Overview

| Workflow | Description | Models Tested | TC Coverage |
| -------- | ----------- | ------------- | ----------- |
| **LLM-Only** | No search, no vector store — just the system prompt and incident data | 14 models | Full 10-TC run |
| **LLM + Basic Search** (Google Grounding) | Gemini "Message a Model" node with `builtInTools: { googleSearch: true }` | 2 models | TC5/TC6/TC7 only (structural finding clear from 3 TCs) |
| **LLM + Tavily Search** | Tavily as AI agent tool, auto-parameters | 7 models | Full 10-TC run |
| **LLM + SerpAPI Search** | SerpAPI as AI agent tool, auto-parameters | 7 models | Full 10-TC run; systematic parameter failures documented |

**Models tested for LLM-only:**
Claude Sonnet 4.5, Claude Opus 4.5, Gemini 3 Pro Preview, GPT-5.2, Grok-4, GLM-4.7, Kimi-K2.5, Llama-4-Maverick, Qwen3.5 Plus, DeepSeek-V3.2, Minimax-M2.5, GPT-OSS-120B, GPT-5.2-Codex, Gemma-3-27b-it

**Models tested for Basic & Advanced Search:**
Claude Sonnet 4.5, Claude Opus 4.5, Gemini 3 Pro Preview, GPT-5.2, GLM-4.7, Kimi-K2.5, Qwen3.5 Plus

---

### LLM-Only: What models know without searching

**Verdict:** Reliable for Easy and Medium incidents. Unreliable for anything requiring specific external knowledge (exact CVE scores, vendor error codes, version-specific bug attribution).

**Key finding — temperature:**

- `0.3` → structured, consistent runbooks; lower hallucination rate
- `0.7+` → more prose detail, noticeably more hallucination, particularly on hard test cases
- **Recommendation:** `0.3` for incident response. The stakes are too high for creative variance.

**Hard test case failure pattern:**

- TC7 (RDS-EVENT-0056): The alert message says "incompatible network state" but the correct AWS event definition is "number of databases exceeds best practices." **0 out of 14 LLM-only models** identified this — the correct answer required hitting AWS documentation directly.
- TC6 (Apache Tomcat CVE-2025-24813): Alert reported severity as "High." NVD records it as 9.8 Critical. Many models deferred to the alert's stated severity without questioning it.

---

### LLM + Basic Search (Google Grounding): The Dual-Model Problem

**Verdict:** Competitive output quality in the best configuration, but architectural fragility makes it ill-suited for production.

**The n8n architecture constraint:**
The "Message a Model in Google Gemini" node is _not_ the standard n8n Chat Model node. They are different. Only the "Message a Model" node supports `builtInTools: { googleSearch: true }`. This creates a **dual-model architecture**: Gemini handles search internally, while the main n8n agent runs a separate model (e.g. Opus). This dual-model setup adds complexity and fragility for no proportional gain over using Tavily.

**Critical failure: Gemini Tool Node 75% failure rate**
When using Gemini models for both search via Tool Node and as the main agent model, Gemini failed 75% of the time with:

```text
Cannot use 'in' operator to search for 'functionCall' in undefined
```

This is an n8n JavaScript parsing bug triggered by Gemini's function call response schema — not a model quality issue. Claude Opus 4.5 was unaffected because Anthropic models format tool call responses differently.

**Best configuration found:**

- Agent+Tool Node prompt placement (not Tool Node only or Agent Node only)
- Claude Opus 4.5 as the search model
- Explicitly use the parameter `max number of tokens` for the token budget

**Conclusion:** Google Grounding is best for Gemini-native products. For multi-model production incident response, Tavily is a simpler and more reliable architectural choice.

---

### LLM + Tavily Search: The Production Baseline

**Verdict:** The best-performing non-RAG workflow. Highest reliability, clearest search delta on hard test cases.

**Search delta — the key finding:**
Search adds value when it finds something the LLM cannot know from training data alone:

| Test Case | LLM-Only Pass Rate | Tavily Pass Rate | What Search Found |
| --------- | ------------------ | ---------------- | ----------------- |
| TC7 — AWS RDS-EVENT-0056 (alert message wrong) | 0 / 7 | 2 / 7 | AWS docs: real event definition = "database count warning", not "network state" |
| TC6 — Apache Tomcat CVE-2025-24813 | 0 / 7 | 3 / 7 | NVD: actual CVSS 9.8 Critical, not "High" as alert stated |
| TC5 — Node.js v22.5.0 regression | 0 / 7 | 4 / 7 | GitHub Issue #53902: `fs.closeSync` regression, fix = v22.5.1 |

**Failure modes with Tavily:**

- **Tool loop (Gemini):** On TC2 (IP WHOIS) and TC4 (recursive bibliography), Gemini with Tavily triggered 10–30 recursive searches consuming 146k–200k+ tokens with no improvement in output quality. A **max-iteration cap** (≤5 searches) is required before production deployment.
- **Over-triggering (Sonnet TC3):** One Tavily search on a deterministic nginx typo — a case where search added latency and cost with zero information gain.

**Guard rail required before production:**

```json
{
  "maxIterations": 5,
  "searchBudget": "Trigger search only when: CVE pattern, named threat actor, or specific error code is present. Not for pure availability or performance incidents."
}
```

---

### LLM + SerpAPI Search: Parameter Failures at Scale

**Verdict:** When it works, SerpAPI produces comparable output to Tavily for targeted technical searches. But systematic parameter failures make it unreliable without guard rails.

**Root cause of failures — not parameter volume, but incompatible parameters:**
SerpAPI's API rejected auto-generated calls that included:

- `output` parameter (not valid for SerpAPI REST calls)
- `uule` + `location` conflict (mutually exclusive in SerpAPI)
- `q` field missing (required)

These are not failures of the AI giving SerpAPI too much freedom — they are failures of specific auto-generated parameter names being invalid for the SerpAPI call signature. The fix is a **parameter exclusion guard rail** hardcoded in the tool config, not switching to manual parameters.

**Where SerpAPI won despite failures:**
On test cases requiring site-specific technical searches (GitHub issues, vendor KB articles), SerpAPI's response quality — when the call succeeded — matched or exceeded Tavily. For production use, SerpAPI is the better choice for `site:github.com` and `site:docs.vendor.com` targeted queries.

**Head-to-head: Tavily vs SerpAPI**

| Metric | Tavily | SerpAPI |
| ------ | ------ | ------- |
| Reliability | High | Medium (parameter guard rails needed) |
| Best for | General CVE/threat intel | Site-specific technical searches |
| Token efficiency | Medium | High (when working) |
| Setup effort | Minimal | Requires exclusion list configuration |
| Key failure | Tool loop (Gemini) | Parameter auto-generation errors |

---

### Non-RAG Cross-Workflow Summary

| Dimension | Winner | Notes |
| --------- | ------ | ----- |
| Highest overall reliability | **LLM + Tavily** | No architectural failure modes when guard rails are in place |
| Best search delta on hard TCs | **LLM + Tavily** | Only workflow to partially crack TC5, TC6, TC7 |
| Fastest / cheapest on Easy/Medium | **LLM-Only** | No tool overhead; strong enough for deterministic incidents |
| Best for targeted technical searches | **SerpAPI** (when working) | `site:github.com` / vendor KB targeted queries |
| Architecture most difficult to maintain | **Google Grounding** | Dual-model setup, n8n parsing bug, limited to Gemini products |
| Failure mode most dangerous | **LLM-Only on TC7** | Zero models corrected the misattributed alert — all triaged the wrong problem |

**Non-RAG recommendation:**

1. **Default workflow:** LLM + Tavily with `maxIterations: 5` and incident-type-based search trigger rules.
2. **Add SerpAPI** as a second tool for vendor KB and GitHub issue lookup — it is strictly better when the call succeeds.
3. **Avoid Google Grounding** for multi-model production setups unless the main agent is already Gemini.
4. **LLM-Only** is acceptable for Easy/Medium incident types (availability, config drift, certificate expiry) where the answer is deterministic.

---

## 2. RAG Configuration Analysis

> **Test setup:** All four RAG configs were evaluated against the **same 8 test cases** (TC1–TC8), covering a range of incident types and difficulty levels from easy direct matches to stress-test edge cases with deliberately misleading metadata. All numbers cited below are verified against the raw output files and `incidents.json`. These 8 TCs are separate from the 10 TCs used in the non-RAG study — they are purpose-designed to test retrieval characteristics specific to vector search, metadata filtering, and reranking. Graded on: **Retrieval Accuracy > Context Utilization > Accuracy and Legitimacy > Safety > Format**.

### Overview

| Config | Architecture | Total Tokens (8 TCs) | Pass Rate |
| ------ | ------------ | -------------------- | --------- |
| **A** | Base vector search (no reranker, no filter) | 23,535 | **7/8 (87.5%)** |
| **B** | Vector search + cross-encoder reranker | ~23,639 | **6/8 (75.0%)** |
| **C** | Vector search + metadata pre-filter (no reranker) | 62,164 | **3/8 (37.5%)** |
| **D** | Vector search + metadata pre-filter + reranker | ~59,517 | **3/8 full pass + 2/8 partial (37.5% full)** |

---

### Config A — Base Vector Search (Baseline)

**Architecture:** Raw semantic similarity. No metadata filtering. No reranking. Top 3 documents by cosine similarity passed directly to the LLM.

**Result: 7/8 pass rate — the most robust configuration tested.**

**Key findings:**

- **TC6 (Disguised Malware)** was the showcase pass: The alert said "PC acting weird" with no technical identifiers. Config A's semantic search correctly retrieved all three malware/ransomware precedents (INC-1022-011, INC-1031-023, INC-1202-009) by symptom pattern recognition alone. The LLM produced expert-level output mapping symptoms to likely ransomware.
- **TC3 (API Gateway Errors)** was the only notable miss: Ground truth was retrieved but at rank ~#2. The LLM's output was diluted by the competing incident at rank #1.
- **Context bleed pattern:** On TC5 (Network Anomaly), Config A correctly retrieved exfiltration context — but the LLM injected hostnames (`endpoint-145`, `customer-db-prod`) from those retrieved incidents into the current incident's resolution steps. The retrieval was right; the synthesis introduced noise.
- **Token efficiency:** ~2,942 tokens/TC average — the cheapest configuration by a 2.5× margin over C and D.

**When Config A is the right choice:** Default starting point for all use cases. Metadata-blind semantic search handles disguised alerts, mislabeled incidents, and synonym variance naturally. Use this unless you have a specific, measured retrieval problem it cannot solve.

---

### Config B — Vector Search + Reranker

**Architecture:** Same initial retrieval as Config A (top 5 candidates), but a cross-encoder reranker scores each candidate against the query and reorders them before the top 3 are passed to the LLM.

**Result: 6/8 pass rate — adds value in focused cases but introduces new failure modes.**

**Key findings:**

- **TC3 clear win:** Config A retrieved ground truth at rank ~#2 (diluted output). Config B's reranker pushed it to rank #1 with a score of 0.87 — the highest reranker confidence in the dataset. Output quality was noticeably better, with a clear root cause and specific resolution steps.
- **Reranker score clarity matters:** The reranker adds the most value when there is a large score gap between rank #1 and #2 (e.g., TC3: 0.87 vs 0.25). When scores are close (TC4: 0.41 vs 0.38), the reranker is operating near its uncertainty threshold and the output quality gain is minimal.
- **TC5 keyword bias failure:** Config B reranked a firewall configuration drift incident to rank #1 (ahead of the correct exfiltration incident) because both contained the word "firewall." The reranker prioritised token overlap over semantic meaning — a known weakness of cross-encoder models.
- **TC4 reranker regression:** Ground truth (INC-1222-019, rank #1 in Config A) was demoted to rank #3 by the reranker, with two less-relevant incidents promoted ahead of it. Net output quality degraded vs. Config A.

| TC | Config A | Config B | Verdict |
| -- | -------- | -------- | ------- |
| TC3 (API Gateway) | ⚠️ GT at rank ~2 | ✅ GT at rank 1 (0.87) | **B wins** |
| TC4 (S3 Exfil) | ✅ GT at rank 1 | ⚠️ GT demoted to rank 3 | **A wins** |
| TC5 (Network Anomaly) | ✅ Retrieval correct | ⚠️ Keyword bias error | **A wins** |

**When Config B is the right choice:** When you have a retrieval pool where the correct answer is consistently being buried and your reranker scores show clear separation (>2× gap between rank #1 and #2). Requires monitoring reranker score distributions — if most scores cluster in a narrow band (0.3–0.4), the reranker is adding noise, not signal.

---

### Config C — Metadata Pre-Filter (No Reranker)

**Architecture:** An LLM agent first reads the alert and extracts structured metadata fields (severity, category, affected_systems, tags). These are assembled into an exact-match AND filter applied to the vector store before retrieval. Only matching documents enter the candidate pool. Top 3 are passed to the LLM.

**Result: 3/8 pass rate — 50% zero-result trap rate. Not recommended for production without fallback.**

**Token cost: 62,164 total (~7,771/TC average) — 2.64× more expensive than A/B, with 4 of the highest-cost TCs producing zero useful output.**

**Key findings:**

| Trap Type | TCs Affected | Root Cause |
| --------- | ------------ | ---------- |
| Synonym mismatch | TC3 | `"application"` ≠ `"api"` in category field |
| Detection source vs. affected system | TC5 | "Source: Core Firewall" → `affected_systems: firewall-prod` — wrong field mapping |
| Alert severity ≠ incident severity | TC6 | Ticket severity=Low; real incidents stored as Critical/High |
| Mislabeled alert metadata | TC7, TC8 | Alert carries wrong severity/category; filter trusts it verbatim |

- **TC1 (Database Outage)** was Config C's best case: The tight `critical + infrastructure` filter produced a clean single-document context window. The LLM output was the best TC1 result across all four configs — split-brain diagnosis, replication-lag-specific action items. Proof that when the filter is perfectly specified, it outperforms semantic-only retrieval.
- **TC6 (Disguised Malware)** was Config C's most dangerous failure: Alert severity was "Low" (IT support ticket). All malware incidents are stored at Critical/High. The three-way compound filter (severity + category + tag — all wrong) produced zero results at 6,757 token cost. An on-call engineer received no guidance on what was likely a ransomware infection.
- **TC8 (Ransomware)** confirmed the category mislabeling risk: Alert contained `Category: infrastructure` (mislabeled). Ransomware incidents are stored as `category: endpoint`. Config A and B both ignored this label and retrieved correctly. Config C obeyed the wrong label and returned nothing.

**Bottom line:** Config C's fundamental assumption — that incoming alert metadata is semantically aligned with stored incident metadata — holds only ~37% of the time in this test set. The failure cases are not edge cases; they represent common real-world scenarios (synonyms, ticket severity vs. incident severity, detection source vs. affected system, mislabeled alert fields).

---

### Config D — Metadata Pre-Filter + Reranker

**Architecture:** Combines Config C's metadata pre-filtering with Config B's cross-encoder reranking. When the filter returns zero results, the reranker is skipped entirely — Config D inherits all of Config C's zero-result failure modes.

**Result: 3/8 full pass, 2/8 partial pass — same retrieval pass rate as C, but meaningfully better graceful degradation.**

**Token cost: ~59,517 total (~7,440/TC average) — marginally cheaper than C, still 2.53× more expensive than A/B.**

**Key findings vs. Config C:**

| TC | Config C | Config D | Net Verdict |
| -- | -------- | -------- | ----------- |
| TC1 | ✅ Best | ✅ Strong pass (reranker confirms at 0.51) | = Same |
| TC2 | Pass (comparable) | ✅ **Best across all configs** (email-gateway filter → 1 exact doc → 350-user count sourced) | **D better** |
| TC3 | ❌ Zero (synonym trap) | ✅ Fixed (D agent omitted category, used affected_systems only) | **D better** |
| TC4 | ✅ Best (broad `high` filter surfaced AWS creds incident) | ❌ Zero (over-specified `backup-system` — new trap) | **C better** |
| TC5 | ❌ Zero (graceful partial note) | ❌ Zero (complete blank) | **C slightly better** |
| TC6 | ❌ Zero | ❌ Zero (dual-tag AND logic made it worse) | Same (both fail) |
| TC7 | ❌ Wrong category | ⚠️ Wrong category + unique escalation advice ("'Low' may be a misclassification") | **D slightly better** |
| TC8 | ❌ Zero (complete blank) | ⚠️ Zero retrieval + domain-knowledge isolation advice (disconnect corp-fs-01, SOC escalation) | **D meaningfully better** |

**The Config D paradox:** D's filter intelligence is not deterministic — the agent sometimes specifies smarter filters (TC2, TC3) and sometimes over-specifies (TC4, TC6). The net pass rate is identical to Config C, but Config D's graceful degradation on trapped TCs is consistently better.

**The most important Config D insight:** TC2 (Phishing) represents Config D's ceiling. The `medium + security + email-gateway` filter produced perfect precision: exactly one document, the primary ground truth, which drove the most specific output in the entire dataset (macro GPO policy, ~350 user count correctly sourced from the incident record). When all three filter conditions align correctly, Config D outperforms every other configuration.

---

### RAG Cross-Config Summary

| Dimension | Winner | Notes |
| --------- | ------ | ----- |
| Highest pass rate | **Config A** (7/8) | Metadata-blind semantic search is most robust |
| Best on focused, well-labeled incident | **Config D** (TC2) | Perfect filter → perfect precision → best output |
| Best reranker application | **Config B** (TC3) | Adds real value when score gap is large |
| Most dangerous failure | **Config C/D** (TC6, TC8) | Zero output during active malware/ransomware events |
| Best token economy | **Config A/B** (~2,950/TC) | 2.5× cheaper than C/D |
| Best graceful degradation on zero-result TCs | **Config D** | Domain-knowledge recovery and escalation advice |

**Production recommendation:**

1. **Start with Config A.** It is the most robust, cheapest, and most forgiving of real-world metadata inconsistency.
2. **Add Config B's reranker selectively** once you have 100+ incidents and can measure whether reranker scores show meaningful separation (>2× gap between rank #1 and #2).
3. **Do not use Config C or D in production without a fallback mechanism** (if filter returns 0 → retry as Config A). Without the fallback, a 37.5% pass rate is unacceptable for on-call triage.
4. **The Config D fallback pattern (Config D → Config A on zero-result)** is the recommended path if you want precision filtering without the zero-result safety risk.

---

## 3. Why RAG + Search Beats Either Alone

### The three-way split

| What You Need | What Provides It |
| ------------- | ---------------- |
| "Have we seen this before?" — root cause and proven remediation | **RAG on past incidents** |
| "What playbook applies?" — trigger conditions and immediate steps | **RAG on reference playbooks** |
| "What does the external threat landscape say?" — CVEs, IOCs, campaigns | **External search (Tavily + APIs)** |
| Synthesizing all three into an actionable briefing | **LLM as synthesizer** |

No single layer can provide all three. LLM-only cannot recall _your_ specific past incidents or current live CVE data. RAG-only cannot access external threat intelligence. Search-only produces unstructured results without applying organisational memory.

### The trust hierarchy

The Final Synthesizer in this workflow enforces a content priority order:

```text
1. Reference Playbook        ← Highest trust. Human-authored, specifically designed for this attack type
2. Past Resolved Incidents   ← High trust. What actually worked in this environment before
3. External Threat Intel     ← Medium trust. Accurate but not environment-specific
4. General LLM Reasoning     ← Lowest trust. Used only when other layers have no answer
```

This hierarchy is why the system prompts are long and structured — they explicitly tell the LLM not to override playbook-sourced steps with its own reasoning, even if the reasoning sounds plausible.

---

## 4. Failure Mode Taxonomy

Eight failure patterns were observed across all non-RAG and RAG configurations. Understanding these helps with prompt engineering and system prompt design:

| Failure Mode | Description | Example | Occurs In |
| ------------ | ----------- | ------- | --------- |
| **Hard Hallucination** | Completely fabricated facts | Gemma-3 TC5: wrong Node.js version stated as confirmed fact; Opus TC10: invented IR emergency hotline numbers | LLM-Only, all configs |
| **Partial Hallucination** | Correct concept, wrong details | GLM mislabeling M1027 as "rate-limiting" when it means "Password Policies"; Qwen citing Mozi botnet (dismantled Aug 2023) as active | LLM-Only |
| **Tool Loop** | Agent recursively searches without exit | Gemini + Tavily TC2 (IP WHOIS): 200k+ tokens, 30+ searches | Tavily, SerpAPI |
| **Generation Failure** | Agent searched successfully but returned empty JSON | Kimi TC4 with Tavily: 3 successful searches, `{}` returned | Tavily |
| **Over-Triggering** | Search used when no search was needed | Sonnet TC3 + Tavily: 1 search on deterministic nginx typo, 3× token cost | Tavily |
| **Parameter Failure** | Invalid API parameters auto-generated | GLM + SerpAPI TC4: 7 complete failures (~188k tokens, zero output) | SerpAPI |
| **Safety Risk** | Suggested action could cause harm | Sonnet TC7: `rm` on binary logs without replica check; Qwen TC1: `rm -rf` without space verification | LLM-Only |
| **Severity Miscalibration** | Wrong severity for the actual risk level | Gemini rated nginx typo "High" across both Tavily and SerpAPI non-RAG runs | All configs |

**How the current system mitigates these:**

| Failure Mode | Mitigation in v0 |
| ------------ | ---------------- |
| Hard / Partial Hallucination | Trust hierarchy in Synthesizer; source attribution required; phase-labelled mitigations with `source_url` field mandatory |
| Tool Loop | `maxIterations` cap recommended (see Section 1); search trigger rules in Threat Intel Agent system prompt |
| Generation Failure | `retryOnFail: true` on all agent nodes in workflow |
| Over-Triggering | Incident type classification before search decision (AVAILABILITY / PERFORMANCE → don't search) |
| Safety Risk | Every remediation action carries a `phase` label; IMMEDIATE and CONTAINMENT actions surface first |
| Severity Miscalibration | NVD CVSS cross-check when CVE is present; explicit miscalibration warning in system prompt |

---

## 5. Model Recommendations

> **Testing context:** Model recommendations below are based on testing conducted in late February 2026. Model capabilities change with version updates — treat these as benchmarks from that point in time, not permanent rankings.

Based on actual test output data, not marketing claims:

### For the Threat Intel Agent (retrieval quality matters most)

| Recommendation | Model | Why |
| -------------- | ----- | --- |
| 🥇 Best overall | **Claude Opus 4.5** | Highest accuracy across hard TCs; handles tool output reliably; no Gemini Tool Node bug |
| 🥈 Strong alternative | **Kimi-K2.5** | Top open-source performer; correctly identified TC6 CVE trap; 10–20% of Gemini's token cost on structured incidents |
| 🥉 Efficient option | **Qwen3.5 Plus** | 2 searches on exactly the right TCs; 10–20% of Gemini's token cost |
| ⚠️ Use with caution | **Gemini 3 Pro Preview** | Highest accuracy ceiling but systematic tool loop risk; requires hard `maxIterations: 5` guard |
| ❌ Avoid for this use case | **GLM-4.7 with SerpAPI** | 7 complete call failures on TC4 (~188k tokens, zero output) |

### For the Final Synthesizer (structured output quality matters most)

| Recommendation | Model | Why |
| -------------- | ----- | --- |
| 🥇 Best | **Claude Opus 4.5** | Best structured JSON output; enforces format constraints reliably; handles long multi-source context |
| 🥈 Strong | **Claude Sonnet 4.5** | Faster and cheaper; slight over-triggering tendency on search but excellent synthesis quality |
| 🥉 Budget | **Kimi-K2.5** | Open source; strong structured output; confirmed correct on hard CVE traps |

### For ingestion pipelines (playbook summarisation)

The `Summarize Reference Playbooks for Embeddings` chain uses **Gemini 3 Pro Preview** in v0. Any strong 7B+ model works well here — the task is deterministic text summarisation, not adversarial fact-finding.

---

## 6. Embedding Model Tradeoffs

The choice of embedding model affects retrieval accuracy for the RAG branches. This is a higher-impact decision than most practitioners realise.

### Current: `gemini-embedding-001` (3072 dimensions)

This is a surprisingly strong choice. Despite being an older model, `gemini-embedding-001` outperforms Google's newer `text-embedding-004` on pure retrieval benchmarks (RTEB). The newer model was optimised for clustering and classification — not incident retrieval.

> **Note:** The embedding model recommendations below are based on RTEB leaderboard standings as of late February 2026. Rankings change as new models are released — verify against the current leaderboard at [huggingface.co/spaces/mteb/leaderboard](https://huggingface.co/spaces/mteb/leaderboard) before making a switch.

### When to consider upgrading

| Your Situation | Recommendation |
| -------------- | -------------- |
| Incidents contain lots of log payloads, stack traces, and JSON | Upgrade to **Voyage AI `voyage-code-2`** — trained on technical/code data |
| Maximum retrieval accuracy, willing to use a third-party API | Use **Octen-Embedding-8B** via Fireworks AI or DeepInfra — currently #1 on RTEB leaderboard |
| Self-hosted / data sovereignty requirement | **BGE-M3 (BAAI)** — requires ~16GB VRAM |
| Stay on Google, improve overall (not pure retrieval) | **`text-embedding-004`** — better at clustering but slightly worse at retrieval vs `001` |

### Dimension alignment rule

⚠️ **Critical:** If you change the embedding model, the vector column dimension in Supabase must match. `gemini-embedding-001` produces 3072-dimensional vectors. Voyage AI produces 1536-dimensional vectors. You cannot mix models in the same table — drop and recreate, then re-ingest.

---

## 7. Open Source vs Closed Source

Across the LLM-only tests (the widest model comparison set), open-source and closed-source models were competitive on Easy and Medium test cases. Divergence appeared on Hard and Edge cases.

**Where closed-source models struggled:**

- Gemini: Systematic tool loop failures across Tavily TCs (not a model quality failure — n8n + Gemini function call schema interaction)
- Claude Sonnet: Over-triggered search on deterministic incidents (TC3 nginx typo)

**Where open-source models excelled:**

- Kimi-K2.5: Correctly identified the TC6 RDS-EVENT-0056 CVE trap (`CVE-2025-24813`) — one of only 2 models to do so across all workflows
- GLM-4.7: Correct CVE-2025-32433 attribution on TC11 (Erlang/OTP) via Tavily — a hard find

**Where open-source models failed:**

- Gemma-3-27b-it TC5: Hallucinated Node.js version as confirmed fact (hard hallucination)
- Qwen3.5 Plus TC1: `rm -rf` without space verification before destructive action (safety risk)

**Cost efficiency finding:** Open-source models generally used fewer tokens for equivalent Easy/Medium outputs — Qwen3.5 Plus achieved 10–20% of Gemini's token usage. For bulk incident processing, open-source models are a viable cost optimisation.

---

## 8. What to Test Next

### Hybrid search evaluation

The hybrid search upgrade (vector 70% + keyword FTS 30%) is planned as a next evaluation. The expected benefit is in hard test cases with exact error codes and CVE IDs — the same cases where pure semantic search struggled most in the non-RAG tests. See [Production Deployment Guide](./Production_Deployment_Guide.md#3-moving-to-hybrid-search) for the implementation.

### Metadata filtering calibration at scale

The Config C/D failure mode analysis was conducted on a relatively small knowledge base. The hypothesis at 100+ incidents: filtering by metadata filters like `mitre_technique_id` should produce more reliable matches because the category field space shrinks (fewer synonym mismatches when every incident is consistently tagged with structured MITRE IDs). This requires real incident data with consistent MITRE tagging to validate.

### Similarity threshold calibration

The current minimum similarity threshold is `0.4`. This was not systematically tested — it was set conservatively to avoid irrelevant retrievals. A lower threshold (e.g., 0.3) might have improved Config A's TC3 result by allowing more candidates into the pool. A planned calibration test would sweep 0.25–0.50 and measure precision/recall on the same 8 TCs.
