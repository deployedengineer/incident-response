# Incident Response Playbook: Phishing Campaign Targeting Employees

> **Document Version:** 1.0  
> **Date:** 2026-02-18  
> **Classification:** INTERNAL – SOC Operations  
> **Review Cycle:** Quarterly  

---

## Title & Use Case ID

| Field | Value |
|---|---|
| **Playbook Title** | Phishing Campaign Targeting Employees |
| **Use Case ID** | TTP-T1566 / TA0001-TA0006 |
| **MITRE Techniques** | T1566 – Phishing, T1078 – Valid Accounts |
| **MITRE Tactics** | TA0001 – Initial Access, TA0006 – Credential Access |
| **Version** | 1.0 |
| **Last Updated** | 2026-02-18 |
| **Owner** | SOC Manager / Incident Response Lead |

---

## MITRE ATT&CK Mapping

| ID | Name | Tactic | Description |
|---|---|---|---|
| T1566 | Phishing | Initial Access (TA0001) | Adversaries send phishing messages to gain access to victim systems via spearphishing attachments, links, or service-based phishing |
| T1566.001 | Spearphishing Attachment | Initial Access | Malicious files sent as email attachments |
| T1566.002 | Spearphishing Link | Initial Access | Emails containing malicious links to credential-harvesting or exploit sites |
| T1078 | Valid Accounts | Initial Access / Credential Access (TA0006) | Adversaries use compromised legitimate credentials obtained through phishing to access systems |

---

## Objective Statement

This playbook provides a structured, repeatable process for Security Operations Centre (SOC) analysts to **detect, analyse, contain, eradicate, and recover from phishing campaigns targeting organisational employees**. It covers scenarios ranging from a single reported suspicious email to a large-scale coordinated phishing campaign resulting in credential compromise or malware delivery. The goal is to minimise attacker dwell time, limit credential exposure, and prevent lateral movement following a successful phish.

---

## Alert Analysis

### Alert Triggers
- User reports a suspicious email via the "Report Phish" button or helpdesk
- Email gateway / Secure Email Gateway (SEG) flags a message (e.g., Proofpoint TAP, Microsoft Defender for Office 365, Mimecast)
- SIEM correlation rule fires on multiple users receiving emails with the same sender domain, subject line, or URL hash within a short window
- Threat intelligence feed matches a known phishing domain/IP to inbound email traffic
- Endpoint Detection and Response (EDR) alerts on a malicious attachment execution
- Impossible-travel or anomalous login detected shortly after email delivery (T1078 indicator)

### Detection Logic / Data Sources
| Data Source | What to Query |
|---|---|
| Email Gateway Logs | Sender address, SPF/DKIM/DMARC results, attachment hashes, embedded URLs |
| SIEM (e.g., Splunk, Sentinel) | Correlation of email delivery → URL click → credential entry within short time window |
| EDR (e.g., CrowdStrike, SentinelOne) | Process execution from email client, macro execution, PowerShell spawned from Office process |
| Identity Provider (IdP) Logs | Failed/successful authentications from unusual locations post-email-delivery |
| Web Proxy / DNS Logs | Connections to newly registered domains or known phishing infrastructure |
| Threat Intel Platform (TIP) | IOC enrichment against sender IPs, domains, file hashes |

---

## Initial Analyst Checklist

> **Note:** Steps marked with 🤖 are candidates for SOAR/workflow automation.

- [ ] 🤖 **Acknowledge alert** in SIEM/ticketing system within SLA (≤15 min for High, ≤30 min for Medium)
- [ ] 🤖 **Extract email artefacts**: Sender address, Reply-To, Return-Path, Subject, Message-ID, X-Originating-IP, embedded URLs, attachment file names and hashes (MD5, SHA-256)
- [ ] 🤖 **Validate email authentication**: Check SPF, DKIM, and DMARC pass/fail status in headers
- [ ] 🤖 **Enrich IOCs**: Submit URLs to VirusTotal, URLScan.io; submit attachments to sandbox (e.g., Hybrid Analysis, Joe Sandbox, ANY.RUN); check domain age via WHOIS
- [ ] **Analyse email content manually**: Identify social engineering lures, urgency cues, impersonation targets, grammatical anomalies
- [ ] 🤖 **Scope the campaign**: Search email gateway for all recipients of emails matching sender, subject, or URL pattern
- [ ] **Identify user actions**: Determine who opened, clicked, downloaded, or submitted credentials
- [ ] **Check IdP/SSO logs**: Look for successful authentications from unusual IPs/geolocations for users who interacted with the phish
- [ ] **Check EDR telemetry**: Look for suspicious child processes spawned from email clients or browsers on affected endpoints
- [ ] **Document all findings** in the incident ticket with timestamps

---

## Indicators of Compromise (IOC) Checklist

| IOC Type | Value | Source | Verified? |
|---|---|---|---|
| Sender Email | | Email header | ☐ |
| Sender IP | | X-Originating-IP / Received headers | ☐ |
| Reply-To Address | | Email header | ☐ |
| Malicious URL(s) | | Email body / attachment | ☐ |
| Domain(s) | | URL extraction, WHOIS | ☐ |
| Attachment Hash (SHA-256) | | File analysis | ☐ |
| Attachment Filename | | Email header | ☐ |
| Credential Harvesting Page URL | | URL analysis / sandbox | ☐ |
| C2 IP / Domain | | Sandbox detonation / EDR | ☐ |
| User-Agent String | | Web proxy logs | ☐ |

---

## Severity Classification Matrix

| Severity | Criteria | Response SLA |
|---|---|---|
| **Critical (P1)** | ≥10 users submitted credentials; executive/VIP targeted; confirmed malware execution; evidence of lateral movement or data exfiltration | Immediate escalation. War room within 30 min. |
| **High (P2)** | 1–9 users submitted credentials or clicked a confirmed malicious link; attachment detonated but contained by EDR | Escalate to Tier 2 within 15 min. Containment within 1 hour. |
| **Medium (P3)** | Multiple users received phishing email but no clicks/submissions confirmed; email blocked by gateway but some delivered | Triage within 30 min. Purge emails within 2 hours. |
| **Low (P4)** | Single user report; email blocked by SEG before delivery; known spam/marketing misclassified as phishing | Acknowledge within 1 hour. Verify and close. |

---

## Triage Steps

1. **Confirm the phish is malicious** (not a false positive / marketing email / internal test):
   - Check if the email matches an authorised phishing simulation (verify with Security Awareness team)
   - Analyse URL reputation, domain age (<30 days is suspicious), WHOIS data, and TLS certificate details
   - Sandbox any attachments; check for malicious macros, scripts, or exploit payloads

2. **Determine blast radius**:
   - Query email gateway: How many mailboxes received the email?
   - Query email gateway: How many users clicked the link or opened the attachment (via URL rewriting / click tracking)?
   - Cross-reference clicked users against IdP logs for post-click authentication events

3. **Classify user interaction level**:
   - **Level 0** – Email received, not opened → Low risk
   - **Level 1** – Email opened, no link click / attachment open → Low risk
   - **Level 2** – Link clicked, credential page visited but no submission → Medium risk
   - **Level 3** – Credentials submitted or attachment executed → High/Critical risk

4. **Assign severity** per the Severity Classification Matrix above

5. **Initiate containment** for Level 2+ interactions (see Containment Actions)

---

## De-escalated and Expected Benign Events

The following scenarios should be classified as **false positive / benign** and de-escalated:

- **Authorised phishing simulation**: Email matches a scheduled campaign from the Security Awareness platform (e.g., KnowBe4, Proofpoint PSAT). Verify campaign ID with the Security Awareness team before closing.
- **Marketing / newsletter misclassification**: Sender is a legitimate marketing platform (e.g., Mailchimp, HubSpot) and the link resolves to a known SaaS domain. User may need to unsubscribe.
- **Internal email misconfigured**: SPF/DKIM failure due to a misconfigured internal sending system (e.g., SaaS application sending on behalf of the org). Escalate to Email/IT Admin for SPF record correction.
- **Spam / unsolicited but non-malicious**: No malicious payload, credential harvesting, or impersonation. Standard spam. Mark as spam and adjust filters.
- **Duplicate / previously remediated report**: User reported an email already addressed in an existing incident. Link to existing ticket and close.

**Action on de-escalation**: Update the ticket with the reason for de-escalation, analyst name, and timestamp. No further response actions required.

---

## Escalation of Incident

### Tier 1 → Tier 2 Escalation (Severity: Medium or above)
**Trigger**: Confirmed malicious phishing email delivered to ≥1 user with evidence of interaction (click or credential submission).

**Actions**:
- Assign ticket to Tier 2 Incident Response analyst
- Include all extracted IOCs, scope data, and user interaction levels in the handoff
- Begin containment actions (do not wait for Tier 2 acknowledgement)

### Tier 2 → Tier 3 / IR Lead Escalation (Severity: High or Critical)
**Trigger**: Confirmed credential compromise (successful login from attacker infrastructure), malware execution on endpoint, or ≥10 affected users.

**Actions**:
- Page the Incident Response Lead and CSIRT
- Initiate incident bridge/war room
- Begin broad containment: forced password resets, MFA re-enrollment, endpoint isolation
- Engage Threat Intelligence team for campaign attribution and wider IOC hunting

### Tier 3 → Executive / Legal / Regulatory Escalation (Severity: Critical with data impact)
**Trigger**: Evidence of data exfiltration, PII/PHI exposure, executive account compromise, or business email compromise (BEC) with financial fraud.

**Actions**:
- Notify CISO and CTO within 1 hour
- Engage Legal and Compliance for breach notification assessment (GDPR 72-hour window, etc.)
- Engage Public Relations if external-facing impact is likely
- Notify cyber insurance carrier
- Consider law enforcement notification

---

## Containment Actions

- **Email purge**: Remove all instances of the phishing email from all mailboxes (e.g., Exchange Online Content Search & Purge, Proofpoint TRAP auto-pull)
- **URL/domain block**: Add malicious URLs and domains to web proxy blocklist, DNS sinkhole, and email gateway block rules
- **Credential reset**: Force immediate password reset for any user who submitted credentials. Revoke all active sessions (Azure AD: `Revoke-AzureADUserAllRefreshToken`; Okta: Clear User Sessions API)
- **MFA enforcement**: Verify MFA is active on all compromised accounts. If not, enforce immediately. If MFA was bypassed (e.g., adversary-in-the-middle), revoke and re-enrol MFA tokens.
- **Endpoint isolation**: If malware was executed, isolate the endpoint via EDR (CrowdStrike: Network Containment; SentinelOne: Disconnect from Network)
- **Block sender infrastructure**: Block sender IP ranges and email addresses at the email gateway
- **Disable compromised accounts** temporarily if there is evidence of active abuse

---

## Eradication & Recovery

1. **Remove malicious artefacts**: Delete downloaded files, browser cache entries, and any persistence mechanisms identified by EDR/forensic analysis
2. **Re-image endpoints** if malware execution is confirmed and full remediation confidence is not achievable through artefact removal alone
3. **Credential rotation**: Ensure all compromised passwords are changed. If the user reused the compromised password on other corporate systems, rotate those as well.
4. **Review account activity**: Audit mailbox rules (look for attacker-created forwarding rules), OneDrive/SharePoint access, and any OAuth app consents granted during the compromise window
5. **Restore normal access**: Re-enable accounts and remove endpoint isolation once the all-clear is given by IR Lead
6. **Update detection rules**: Add new IOCs to SIEM watchlists, email gateway block rules, and TIP
7. **User notification**: Inform affected users about what happened, what was done, and any required actions on their part (see Email Notification Template)

---

## Email Notification Templates

### Template 1: Internal Alert to Affected Users

```
Subject: [ACTION REQUIRED] Security Incident – Phishing Email Detected

Dear [User / Team],

Our Security Operations team has identified a phishing campaign targeting 
[Organisation Name] employees. You have been identified as a recipient of 
this malicious email.

DETAILS:
- Subject Line of Phishing Email: [Subject]
- Sender: [Sender Address]
- Date/Time Received: [Timestamp]

WHAT WE HAVE DONE:
- The phishing email has been removed from your mailbox.
- Malicious URLs and sender addresses have been blocked.
- [If applicable] Your password has been reset as a precaution.

WHAT YOU NEED TO DO:
1. Do NOT click any links or open any attachments from this email if you 
   still see it in your Deleted Items or any other folder.
2. If you clicked a link or entered your credentials, please contact the 
   Security team immediately at [security@org.com / ext. XXXX].
3. [If password reset] Log in with your new temporary password and set a 
   new unique password. Do not reuse passwords from other accounts.
4. Enable MFA on your account if not already active.

If you have any questions, please contact the SOC at [contact details].

Regards,
Security Operations Centre
[Organisation Name]
Incident Reference: [TICKET-ID]
```

### Template 2: Escalation Notification to Management

```
Subject: [INCIDENT] Phishing Campaign – Severity [P1/P2] – Ref: [TICKET-ID]

INCIDENT SUMMARY:
- Incident Type: Phishing Campaign (MITRE T1566 / T1078)
- Severity: [Critical / High]
- Detection Time: [Timestamp]
- Affected Users: [Number]
- Credential Compromise Confirmed: [Yes / No]
- Malware Execution Confirmed: [Yes / No]
- Data Exfiltration Suspected: [Yes / No]

CURRENT STATUS: [Investigating / Containing / Eradicating / Recovered]

ACTIONS TAKEN:
- [Summary of containment and remediation steps]

NEXT STEPS:
- [Planned actions]

BUSINESS IMPACT:
- [Assessment of impact to operations, data, reputation]

Incident Commander: [Name]
Bridge/War Room: [Link / Dial-in]
Next Update: [Timestamp]
```

---

## Analyst Comments

> **Instructions**: Use this section to record free-form observations, decisions, and context during the investigation. Each entry must include a timestamp and analyst name/handle.

| Timestamp (UTC) | Analyst | Comment |
|---|---|---|
| YYYY-MM-DD HH:MM | | |
| | | |
| | | |

---

## Contacts for Subject Matter Experts

| Role | Name | Contact | Availability |
|---|---|---|---|
| SOC Manager | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Incident Response Lead | [Name] | [Email / Phone / Slack] | 24/7 on-call rotation |
| Email Security / SEG Admin | [Name] | [Email / Phone / Slack] | Business hours |
| Identity & Access Management (IAM) | [Name] | [Email / Phone / Slack] | Business hours |
| Threat Intelligence Analyst | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Endpoint Security / EDR Admin | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Legal / Data Protection Officer | [Name] | [Email / Phone / Slack] | Business hours |
| CISO | [Name] | [Email / Phone / Slack] | Escalation only |
| Public Relations / Comms | [Name] | [Email / Phone / Slack] | Escalation only |
| Cyber Insurance Broker | [Company / Name] | [Email / Phone] | Business hours |
| Law Enforcement Liaison | [Agency / Name] | [Phone] | As needed |
| Security Awareness Team | [Name] | [Email / Slack] | Business hours |

---

## Automation Opportunities

| Step | Automation Capability | Tool Example |
|---|---|---|
| Artefact extraction from email headers | Fully automatable | SOAR (e.g., Cortex XSOAR, Splunk SOAR, Tines) |
| IOC enrichment (VirusTotal, URLScan, WHOIS) | Fully automatable | SOAR + TIP |
| Campaign scoping (search for matching emails) | Fully automatable | Email gateway API + SOAR |
| Email purge across mailboxes | Fully automatable | Exchange Online / Google Workspace Admin API |
| URL/domain blocking | Fully automatable | Proxy/DNS/Firewall API via SOAR |
| Credential reset + session revocation | Semi-automatable (may require approval) | IdP API via SOAR with approval workflow |
| Endpoint isolation | Semi-automatable (may require approval) | EDR API via SOAR |
| Ticket creation and enrichment | Fully automatable | ITSM API (ServiceNow, Jira) |
| Notification emails | Fully automatable | SOAR email action |

---

## Lessons Learned / Post-Incident Review

After incident closure, the IR Lead should schedule a post-incident review within **5 business days**. Address:

- What was the initial attack vector and why did it bypass controls?
- How quickly was the phishing email detected and reported?
- Were email gateway rules effective? What tuning is needed?
- Did affected users have MFA enabled? If not, why?
- Were containment actions timely and effective?
- What process improvements are needed?
- Are there training gaps to address with a targeted awareness campaign?

Document findings in the incident ticket and update this playbook if process changes are agreed.

---

## Related Playbooks & References

- Business Email Compromise (BEC) Playbook
- Malware Infection Playbook
- Credential Compromise / Account Takeover Playbook
- NIST SP 800-61r2 – Computer Security Incident Handling Guide
- MITRE ATT&CK: [T1566](https://attack.mitre.org/techniques/T1566/), [T1078](https://attack.mitre.org/techniques/T1078/)
- Counteractive IR Phishing Playbook Template

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-02-18 | [Author] | Initial release |
