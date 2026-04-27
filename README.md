# 🚨 Incident-to-Runbook Automation for SOC Teams

> **Take a new incident, pull the right context from old tickets and playbooks, and generate a useful runbook fast enough to cut MTTR.**

[![GitHub Stars](https://img.shields.io/github/stars/deployedengineer/incident-response?style=social)](https://github.com/deployedengineer/incident-response)
[![n8n](https://img.shields.io/badge/Built%20with-n8n-orange?logo=n8n)](https://n8n.io)
[![Supabase](https://img.shields.io/badge/Vector%20DB-Supabase-green?logo=supabase)](https://supabase.com)

**[📥 Import n8n Workflow](https://github.com/deployedengineer/incident-response/blob/main/Incident%20Management.json)** · **[📖 Deep Dive Docs](./docs/)**

---

## 📋 Table of Contents

- [🔥 The Problem](#-the-problem)
- [💡 The Solution](#-the-solution)
- [🧠 What This Is (and Isn't)](#-what-this-is-and-isnt)
- [🏗️ Architecture](#%EF%B8%8F-how-it-works)
- [🛠️ Tech Stack](#%EF%B8%8F-tech-stack)
- [📁 What's in This Repo](#-whats-in-this-repo)
- [🚀 Quickstart](#-quickstart)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

---

## 🔥 The Problem

When an incident fires at 3 AM, SOC teams face a critical bottleneck: **finding context fast**.

- **Context-switching overhead**: Manually searching Slack, Confluence, JIRA, and past incident docs takes 15–30 minutes before any real analysis begins.
- **Tribal knowledge loss**: The engineer who resolved a similar incident 6 months ago may be gone. Resolution strategies live in scattered notes, not in a searchable system.
- **Cognitive load at peak stress**: High-pressure triage leads to missed signals from past incidents that match the current pattern.
- **60% of incidents are repeats**: Industry data consistently shows the majority of incidents are variations of previously resolved issues — yet most teams solve them from scratch each time.

**The result:** Mean time to resolution (MTTR) averages 3–4 hours per incident without good tooling. With relevant context surfaced instantly, that drops to 45 minutes – 1.5 hours.

---

## 💡 The Solution

This system **automatically enriches every incident** with three parallel intelligence streams — within minutes of an alert firing:

1. **Historical intelligence** — retrieves the most similar past resolved incidents from your vector store and extracts proven remediation steps.
2. **Playbook routing** — semantically matches an appropriate reference playbook and surfaces its trigger conditions and immediate actions.
3. **Live threat intel** — uses Tavily to search for active CVEs, threat actor campaigns, and vendor advisories relevant to this specific incident.

The three streams are merged and synthesized by a final LLM into a single, structured triage report — written directly back to your database or SIEM.

**The generated output strictly includes:**
1. Executive Summary
2. Alert Analysis & Affected Systems
3. Root Cause Hypothesis & MITRE ATT&CK Assessment
4. Indicators of Compromise (IOCs)
5. Immediate Response Checklist (Next 30 Minutes)
6. Escalation Decision
7. Eradication & Recovery Plan
8. Historical Context & Pattern Intelligence
9. Threat Intelligence Briefing
10. Long-term Hardening Recommendations
11. Documentation Requirements

---

## 🧠 What This Is (and Isn't)

This repository is designed to do exactly one thing well. Setting the right expectations is critical.

### ✅ What this is:
**An advisory intelligence layer.** It automatically drafts a heavily-contextualized runbook for a human analyst to review. It brings the data to the analyst, saving them 30 minutes of searching.

### ❌ What this is NOT:
- **It is not a SOAR platform:** It does not actively isolate endpoints, ban hashes, or block IPs out of the box. Every action requires human execution.
- **It is not a BAS (Breach & Attack Simulation) tool:** It does not simulate attacks.
- **It is not a Detection Engineering platform:** It does not write YARA or Sigma rules (though that is on our [roadmap](./docs/roadmap.md)).
- **It does not make autonomous decisions:** Severity calibration and containment steps are surfaced as *recommendations*, not automated actions.

---

## 🏗️ How It Works

The system operates in a 6-step pipeline orchestrated entirely within [n8n](https://n8n.io):

1. **Fetch:** Receive the incident alert (via Webhook or Database fetch).
2. **Retrieve (Parallel):**
   - Branch A: Fetch historical resolved incidents via Vector Search.
   - Branch B: Route to the exact Playbook via Vector Search.
   - Branch C: Fetch real-world Threat Intel via Tavily web search.
3. **Merge:** Combine all three data streams.
4. **Synthesize:** An LLM (`claude-opus-4.5`) drafts the runbook following a strict trust hierarchy (Playbook > History > Threat Intel > LLM Reasoning).
5. **Validate:** A Structured Output Parser guarantees the shape of the runbook, and a logic gate ensures required fields (like Immediate Actions) are present.
6. **Write:** Output the validated runbook to the destination.

👉 **[Read the full Architecture breakdown](./docs/architecture.md)**

---

## 🛠️ Tech Stack

| Layer                 | Tool                                                                                  | Detail                                                  |
| --------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Orchestration         | [n8n](https://n8n.io)                                                                 | Self-hostable, visual workflow logic                    |
| Vector DB             | [Supabase](https://supabase.com) + pgvector                                           | 3 tables: playbooks, resolved incidents, test incidents |
| Embeddings            | [Google AI Studio](https://aistudio.google.com) `models/gemini-embedding-001`         | High fidelity vectors for maximum retrieval accuracy            |
| Retrieval agents      | [OpenRouter](https://openrouter.ai) (`anthropic/claude-opus-4.5`)                     | Playbook selection + historical similarity extraction   |
| Synthesizer LLM       | [OpenRouter](https://openrouter.ai) (`anthropic/claude-opus-4.5`)                     | Final structured report generation                      |
| Playbook Summarizer   | [Google AI Studio](https://aistudio.google.com) (`gemini-3.1-pro-preview`)            | Summarizing markdown playbooks during ingestion         |
| External threat intel | [Tavily Search](https://tavily.com)                                                   | Real-time CVE / threat actor / advisory lookup          |

---

## 📁 What's in This Repo

```text
Incident Management/
├── README.md                      # This file
├── docs/                          # Deep-dive documentation:
│   ├── quickstart.md              # Setup and execution guide
│   ├── architecture.md            # Data flow and schema contracts
│   ├── research.md                # Rationale for AI choices
│   └── roadmap.md                 # Future planned extensions
├── Incident Management.json       # The core n8n workflow to import
├── supabase_schema_v1.sql         # DB setup — run once in Supabase SQL editor
├── Reference Playbooks/           # Pre-written markdown playbooks
├── Resolved Incidents/            # Synthetic historical SOC tickets
└── Test Incidents/                # Synthetic incoming alerts to test the pipeline
```

---

## 🚀 Quickstart

You can have this pipeline running in under 10 minutes. 

We support a frictionless execution path to test the pipeline directly from your database:
1. **The 5-Minute Demo Path:** Click "Test workflow" and watch the workflow generate a runbook for a pre-loaded test incident.

👉 **[Go to the Quickstart Guide](./docs/quickstart.md)** to configure your database, import the workflow, and run your first incident.

---

## 🤝 Contributing

Contributions are welcome from the SOC and Detection Engineering communities. The most valuable things to contribute:

- **Reference playbooks** — add a Markdown playbook for an attack type not currently covered
- **Resolved incident schemas** — share anonymised incident templates to improve the sample dataset

**To contribute:**
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature-name`)
3. Make your changes and test them
4. Open a pull request with a description of what you changed and why

---

## 📄 License

MIT License — see `LICENSE` for full terms.

You are free to use, modify, and distribute this project for commercial or non-commercial purposes. Attribution appreciated but not required.
