# 🔬 Research & Design Rationale

This document explains the technical choices, model selection, and engineering constraints that shaped the Incident-to-Runbook workflow.

---

## 1. Why RAG + Web Search?

Most "AI in Cybersecurity" implementations attempt to use a single large language model to reason through an alert. This fails in production for two reasons:
1. **Hallucination:** LLMs invent containment steps that do not align with company policy.
2. **Stale Knowledge:** A model trained 6 months ago does not know about a zero-day vulnerability disclosed this morning.

To fix this, we decoupled the reasoning engine from the knowledge base using a multi-branch architecture:
- **Historical RAG (Supabase + pgvector):** Provides the "how we do things here" context.
- **Tavily Web Search:** Provides the "what is happening in the world today" context.

By forcing the final LLM to only synthesize data provided by these two pipelines, we effectively eliminate operational hallucination.

---

## 2. Model Selection

We evaluated several models for the pipeline and settled on a split-model architecture to balance cost, speed, and reasoning capability.

### Ingestion & Embeddings: `models/gemini-embedding-001`
We use Gemini Embeddings for generating the vector embeddings.
- **Why:** Its vector space is extremely dense, resulting in much higher accuracy when a sparse, 3-line SIEM alert needs to match against a 300-line markdown playbook. It is also highly cost-effective for bulk background ingestion.

### Playbook Summarization: `google/gemini-3.1-pro-preview`
We use Gemini 3.1 Pro Preview to summarize the raw markdown playbooks before they are embedded.
- **Why:** Full markdown playbooks are often too large or unstructured for dense vector retrieval. Summarizing the core actions creates a much cleaner semantic target for the embedding model.

### Retrieval & Synthesis: `anthropic/claude-opus-4.5`
We use Claude Opus 4.5 (via OpenRouter) for all active retrieval and the final runbook generation.
- **Why:** In cybersecurity, instruction-following is paramount. Claude Opus consistently demonstrated the highest adherence to our strict JSON schema requirements and the "Trust Hierarchy" instructions. It rarely hallucinates external facts when explicitly instructed to rely only on the provided context.

---

## 3. The Playbook Router Design

The Playbook retrieval branch does not use a simple semantic similarity search. Instead, it uses an **AI Agent Router**.

If an incident is vague (e.g., "High CPU on server"), a raw vector search might accidentally pull a "Ransomware Response" playbook simply because both texts mention "servers." This creates panic.

To solve this, the Playbook Matcher Agent evaluates the incident against the vector results and makes a definitive boolean choice: `match_found: true` or `false`. If `false`, the system falls back to a generic `GEN-UNIVERSAL-001` triage playbook, ensuring that analysts are never sent down the wrong operational path due to poor semantic overlap.

---

## 4. Threat Intel Suppression Logic

Not every incident is a cyberattack. A significant portion of SOC and NOC alerts are availability or performance issues (e.g., database instance rebooting, network latency).

The Threat Intel Agent (Tavily) is equipped with suppression logic:
- If the incident is classified as an availability issue (e.g., no active attacker, no CVE, no exploit mentioned), the agent skips the web search and returns a standard "No external threat intelligence required" message.
- This prevents the LLM from desperately searching the web and returning unrelated articles just to fill the payload, keeping the final runbook clean and focused.

---

## 5. The Synthesizer Trust Hierarchy

The most critical instruction given to the Claude 4.5 Opus synthesizer is the **Trust Hierarchy**. When the merged data stream contains conflicting information, the LLM must resolve it using this exact priority order:

1. **Playbooks (Ground Truth):** If a playbook dictates a specific containment step, it supersedes all other data.
2. **Historical Incidents (Evidence):** What actually worked last time. Used to augment the playbook.
3. **Threat Intel (Advisory):** External context (e.g., CVSS scores) used to enrich the summary.
4. **LLM Reasoning (Glue):** The LLM is strictly forbidden from inventing containment strategies. Its only job is to format the top 3 tiers into the final JSON structure.
