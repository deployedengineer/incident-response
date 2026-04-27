# 🚀 Quickstart: Running Your First Incident

This guide covers how to set up the Incident-to-Runbook workflow, ingest the historical data, and run your first test incident.

---

## 📋 Prerequisites

Before importing the workflow, you will need active accounts and API keys for the following services. These must be added as Credentials in your n8n instance:

1. **Supabase:** For vector storage and relational data. You need your Project URL and Service Role Key.
2. **Google AI Studio:** `models/gemini-embedding-001` is used for high-fidelity vector embeddings during ingestion. You need an API key (a free-tier key works perfectly).
3. **OpenRouter:** Used to access `anthropic/claude-opus-4.5` for the retrieval agents and the final synthesizer.
4. **Tavily:** Used by the external threat intelligence agent.

> [!WARNING]  
> **Setup Friction Note:** Because this workflow relies on external databases and multiple AI models, the initial setup will take about 10–15 minutes. Once the credentials are in place and the data is ingested, the pipeline runs entirely autonomously.

---

## Step 1: Database Setup

You must create the tables and SQL functions in Supabase before running the workflow.

1. Open your Supabase project dashboard.
2. Navigate to the **SQL Editor**.
3. Copy the contents of [`supabase_schema_v1.sql`](../supabase_schema_v1.sql) from the root of this repository.
4. Paste it into the editor and hit **Run**.

This creates three tables (`reference_playbooks_v1`, `resolved_incidents_v1`, `test_incidents_v1`) and the exact `match_` functions required for vector similarity search.

---

## Step 2: Import the Workflow

1. Open your n8n instance.
2. Click **Add Workflow** > **Import from File**.
3. Select the `Incident Management.json` file from the root of this repository.
4. Go through the nodes and select your configured credentials (Supabase, Google Gemini, OpenRouter, Tavily).

---

## Step 3: Data Ingestion (Required)

Before the retrieval pipeline can work, it needs historical context to retrieve. The workflow includes three ingestion pipelines at the top of the canvas, which are chained together.

You must run this manually **once** to populate your Supabase database:

1. Locate the **"1 Ingest Resolved Incidents"** pipeline at the top of the canvas.
2. Click **Test workflow** on the first node (`Get Resolved Incidents from GitHub`).
3. The system will automatically download historical incidents, summarize them, embed them, and store them. Once finished, it will automatically trigger the Playbooks ingestion, and then finally the Test Incidents ingestion. You only need to click once!

> [!NOTE]  
> **Built-in Rate Limiting:** The ingestion pipeline uses a built-in `Wait` loop. This ensures that you will not hit `429 Too Many Requests` errors during vector embedding, even on a free-tier Google AI Studio key.

---

## Step 4: The 5-Minute Demo Path

Once ingestion is complete, you are ready to test the primary workflow.

This repository supports a frictionless demo path that does not require you to configure external webhooks or payload simulators. 

1. Locate the **"When clicking 'Test workflow'"** trigger node on the far left of the main retrieval workflow.
2. It triggers a **"Config"** node where all essential pipeline variables are set:
   - **GitHub details:** `github_repo`, `github_baseUrl`
   - **Models:** `model_chat`, `model_embedding`, `model_analysis`, `temperature`
   - **Chunking:** `chunk_size`, `chunk_overlap`
   - **Supabase RPC/Tables:** `query_playbooks`, `query_incidents`, `table_resolved`, `table_playbooks`, `table_test`
3. Next, the **"Set Incident ID"** node is configured to fetch `Test-ransomware_detection-001` (a sample ransomware alert) from the `test_incidents_v1` table.
4. Click **Test workflow** on the trigger node to start the run.

Watch as the workflow fans out to query the vector database, match playbooks, search Tavily for active CVEs, and synthesize the final Runbook. The output will be visible in the final **Write Runbook to DB** node, and directly inside your Supabase `test_incidents_v1` table in the `output_markdown` column!

### 📝 Required Incident Schema

For the workflow to process alerts correctly, the incoming incident payload stored in the database must follow this schema:

```json
{
  "@timestamp": "2025-10-04T09:45:07Z",
  "incident_id": "INC-2025-1004-014",
  "severity": "medium",
  "status": "resolved",
  "category": "infrastructure",
  "type": "configuration_drift",
  "title": "Production server configuration drift detected",
  "description": "AWS Config detected configuration drift on 6 of 14 production web and application servers (web-servers-prod, app-servers) after a routine infrastructure-as-code reconciliation run. The drift manifested as disabled SSLv3/TLS 1.0 deprecation settings on 3 web servers (the nginx ssl_protocols directive had reverted to include TLSv1 after an automated OS package update), an incorrect sysctl.conf setting for net.ipv4.tcp_syncookies=0 on 2 app servers (re-enabled SYN flood vulnerability), and an open administrative port 8443 on 1 app server that had been closed in the Terraform baseline. The drift was introduced by a third-party OS patch management tool that restores modified config files during patch runs without applying the security baseline overlay.",
  "affected_systems": [
    "web-servers-prod",
    "app-servers"
  ],
  "assigned_to": "infrastructure-team",
  "detection_method": "AWS Config managed rule 'restricted-common-ports' + Terraform state drift detection (terraform plan non-empty) identified 6-server configuration deviation from IaC baseline",
  "tags": [
    "configuration-drift",
    "infrastructure",
    "medium"
  ],
  "timeline": [
    {
      "timestamp": "2025-10-04T09:45:07Z",
      "event": "AWS Config rule 'restricted-common-ports' fired: port 8443 open on app-server-04 outside of approved security group; Terraform Cloud workspace 'prod-compute' showed 6-resource drift in state; PagerDuty P2 alert generated",
      "actor": "aws-config"
    },
    {
      "timestamp": "2025-10-04T09:49:18Z",
      "event": "On-call SRE v.patel@company.com acknowledged; confirmed AWS Config finding; ran terraform plan against all 14 prod servers to enumerate full drift scope — 6 servers affected, 3 categories of drift identified",
      "actor": "v.patel@company.com"
    },
    {
      "timestamp": "2025-10-04T10:37:05Z",
      "event": "Root cause identified: OS patch management tool (Chef infrastructure_packages cookbook v2.1.4) restores /etc/nginx/nginx.conf and /etc/sysctl.conf from its own template, overwriting security hardening applied by Terraform cloud-init and Ansible playbook; deployed 3 days prior during patch cycle",
      "actor": "engineering-team"
    },
    {
      "timestamp": "2025-10-04T12:00:05Z",
      "event": "Terraform apply executed to reconcile all 6 servers to IaC baseline; nginx ssl_protocols corrected to TLSv1.2 TLSv1.3 only; sysctl tcp_syncookies=1 re-applied; port 8443 closed via security group update; Ansible hardening playbook re-run on all 14 servers",
      "actor": "engineering-team"
    },
    {
      "timestamp": "2025-10-04T12:43:05Z",
      "event": "AWS Config rules re-evaluated — all 6 previously non-compliant resources now showing COMPLIANT; terraform plan returned no changes (clean state); incident closed",
      "actor": "v.patel@company.com"
    }
  ],
  "resolved_timestamp": "2025-10-04T12:43:05Z",
  "resolved_by": "v.patel@company.com",
  "resolution_time_minutes": 177,
  "resolution_summary": "Terraform apply reconciled all 6 drifted servers to IaC baseline within 141 minutes of detection. The root cause (Chef cookbook overwriting security hardening configs during patch run) was identified and mitigated by adding configuration file immutability exceptions for security-critical files. AWS Config re-evaluation confirmed all 14 servers returned to COMPLIANT state. No evidence of exploitation of the drift window was found in access logs or security group flow logs.",
  "root_cause_analysis": "The Chef infrastructure_packages cookbook (v2.1.4, deployed Oct 1) contained a template resource for nginx.conf and sysctl.conf that overwrote the existing files during every patch run without checking whether the destination files had been intentionally modified post-deployment. The Chef templates did not include the TLS version restrictions or tcp_syncookies hardening applied by the Terraform cloud-init script and Ansible playbook. This created a pattern where security hardening was applied at server launch time but stripped by the next patch run. The drift had existed for 3 days before AWS Config's nightly reconciliation run detected it; a more frequent Config evaluation schedule (hourly) would have caught this within hours.",
  "mitre": {
    "tactic": [],
    "technique": [],
    "prevention": []
  },
  "mitre_tactic_ids": [],
  "mitre_technique_ids": [],
  "mitre_prevention_ids": [],
  "affected_users_count": 350,
  "business_impact": "Infrastructure configuration deviation creating potential SSL/TLS downgrade and network attack surface exposure",
  "estimated_cost": 12500,
  "sla_met": true,
  "mttr": 177,
  "mtta": 4,
  "remediation_actions": [
    "Ran terraform plan across all 14 production servers to enumerate full drift scope: identified 6 non-compliant servers with 3 distinct drift categories (TLS settings, sysctl net.ipv4.tcp_syncookies, open security group port)",
    "Executed terraform apply to reconcile all 6 drifted servers: corrected nginx ssl_protocols to 'TLSv1.2 TLSv1.3', set sysctl net.ipv4.tcp_syncookies=1, removed security group inbound rule for port 8443",
    "Re-ran Ansible security hardening playbook (server-hardening.yml) against all 14 servers to validate full compliance with the CIS Benchmark Level 2 baseline",
    "Patched Chef infrastructure_packages cookbook v2.1.4: added 'not_if' guards on nginx.conf and sysctl.conf template resources to preserve files that match a security hardening checksum; deployed v2.1.5",
    "Reviewed VPC Flow Logs for port 8443 against app-server-04 during 3-day drift window: 0 inbound connections to port 8443 detected (port was accessible but no traffic observed)",
    "Validated TLS downgrade exposure window: access logs for the 3 affected web servers showed no TLS 1.0 negotiation attempts during the drift period — modern client pool did not downgrade"
  ],
  "systems_remediated": [
    "web-servers-prod",
    "app-servers"
  ],
  "preventive_measures": [
    "AWS Config evaluation frequency changed from daily to hourly for all EC2 and security group resources in production — drift detection window reduced from 24 hours to <1 hour",
    "Chef cookbook template resources updated: all security-critical configuration files now use 'verify' and 'not_if' guards to preserve intentional security hardening applied at launch time",
    "Terraform Sentinel policy added: any terraform plan showing deletion of TLS or security group rules in production requires out-of-band approval from Security Architect before apply",
    "Ansible hardening playbook added to post-patch-run pipeline: runs automatically within 15 minutes of any OS package update on production servers to re-apply security baseline"
  ],
  "security_controls_updated": [
    "AWS Config managed rules expanded: 'encrypted-volumes', 'restricted-ssh', 'restricted-common-ports', and 'cloud-trail-enabled' now run hourly (previously daily) on all production resources",
    "Chef cookbook v2.1.5 deployed: template resource guards prevent overwrite of security-critical files; SHA256 checksum comparison used to detect intentional vs unintentional config changes",
    "nginx security configuration baseline updated in Terraform cloud-init: ssl_protocols, ssl_ciphers, and HSTS header settings now pinned with a Terraform lifecycle ignore_changes block for Chef-managed files",
    "Security group change notification: any AWS Config 'restricted-common-ports' non-compliance now triggers immediate PagerDuty P2 alert (previously routed to daily digest)"
  ],
  "documentation_updated": [
    "Infrastructure Hardening Runbook updated: configuration drift detection procedure, terraform plan enumeration command, and Ansible hardening playbook re-run steps",
    "Chef Cookbook Security Standards updated: template resource guard patterns for security-critical files made mandatory in all future cookbook releases",
    "System Architecture Diagram updated: patch management workflow documented with security hardening overlay annotated to prevent future ambiguity about config ownership",
    "INFRA-2025-1014 Jira ticket closed with Chef cookbook v2.1.4 root cause documented and v2.1.5 fix confirmed"
  ],
  "lessons_learned": "Configuration drift from automated patch management is a predictable failure mode when multiple tools manage overlapping configuration files — tool ownership of each config file must be explicitly defined and enforced. The 3-day detection window (daily AWS Config evaluation) is unacceptable for security-relevant settings like TLS protocol versions and network stack parameters; hourly evaluation is the appropriate baseline. Terraform plan drift detection should be a continuous CI job, not a one-time action — any non-empty plan in a production workspace should trigger an immediate alert.",
  "follow_up_tasks": [
    "INFRA-1004-01: AWS Config hourly evaluation schedule deployed for all EC2, VPC, and security group rules — Owner: Cloud Infra, Due: 2025-10-11",
    "INFRA-1004-02: Ansible hardening playbook integrated into post-patch pipeline via Systems Manager State Manager — Owner: Platform, Due: 2025-10-11",
    "INFRA-1004-03: Terraform Sentinel policy for production security group changes requiring Security approval — Owner: Platform Security, Due: 2025-10-18",
    "INFRA-1004-04: Chef cookbook security review: audit all 34 production cookbooks for template resources that could overwrite security hardening — Owner: Platform, Due: 2025-10-25"
  ],
  "resolution": "All 6 drifted servers reconciled to IaC baseline; no exploitation of drift window confirmed; Chef cookbook patched to prevent recurrence",
  "action_taken": "Resolved by infrastructure-team within 141 minutes of AWS Config detection",
  "entities": {
    "users": [
      "v.patel@company.com"
    ],
    "ips": [],
    "hosts": [
      "web-servers-prod",
      "app-server-04"
    ],
    "domains": [],
    "hashes": []
  },
  "alert_source": "AWS Config",
  "detection_gap": "AWS Config evaluation was set to daily frequency, creating an up-to-24-hour detection window for configuration drift; no real-time guardrail existed to prevent the OS patch management tool (Chef) from overwriting security-critical nginx.conf and sysctl.conf files managed by Terraform and Ansible",
  "what_went_well": [
    "AWS Config detected all 6 non-compliant resources before any observed exploitation of the drift window",
    "VPC Flow Logs confirmed no inbound connections to the exposed port 8443 across the 3-day drift period",
    "terraform plan enumeration rapidly scoped the full extent of drift across all 14 production servers within 13 minutes of acknowledgment"
  ],
  "what_went_wrong": [
    "Chef cookbook v2.1.4 template resources overwrote security-hardened configuration files without checksum comparison or 'not_if' guards",
    "Daily AWS Config evaluation frequency created a ~24-hour blind spot for security-critical configuration changes",
    "No automated alert existed when the OS patch management tool modified files that were under Terraform and Ansible management"
  ]
}
```

> [!IMPORTANT]  
> The `description` and `entities` fields are explicitly required by the downstream AI agents to extract Threat Intel and match historical playbooks accurately. Do not omit them.
