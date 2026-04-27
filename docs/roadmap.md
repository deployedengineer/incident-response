# 🗺️ Roadmap & Future Extensions

The current V1 release focuses purely on **Incident-to-Runbook Automation**. It operates strictly as an advisory layer to reduce MTTR by surfacing context.

However, the architecture is designed to be highly extensible. Below are the planned future extensions for this repository. 

*(Note: These are future ideas, they are not implemented in the current workflow).*

---

## 1. Detection Engineering Pipeline

**The Concept:** Threat Intel → Extract TTPs → Generate Sigma Rule

Currently, the workflow uses threat intel (via Tavily) to provide context for an active incident. The next logical step is proactive defense. 
We plan to build a secondary n8n workflow that ingests threat intelligence feeds (e.g., CISA alerts, vendor blogs), extracts the MITRE ATT&CK TTPs, and automatically generates a draft Sigma or YARA rule for the Detection Engineering team to review and deploy.

---

## 2. Detection Validation via Atomic Red Team

**The Concept:** Execute Simulation → Verify Detection → Report Coverage

Once a rule is written, it must be tested. We intend to add an integration where n8n can trigger an [Atomic Red Team](https://atomicredteam.io/) test on a safe, isolated host. The workflow will then query the SIEM to verify if the alert fired successfully, automatically mapping the SOC's true detection coverage over time.

---

## 3. Human-in-the-Loop Remediation Skills

**The Concept:** Analyst Approves → n8n Executes Action

While this repository is not a SOAR platform, n8n is highly capable of executing API actions. In future iterations, we plan to add discrete, isolated "Remediation Sub-workflows" (e.g., `isolate-endpoint`, `block-ip-on-firewall`). 

The generated runbook will include a webhook link next to the "Immediate Response Checklist" section. If the human analyst agrees with the assessment, they click the link, and n8n executes the specific containment action. This maintains a strict Human-in-the-Loop boundary while accelerating the actual remediation phase.
