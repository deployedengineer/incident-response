# Incident Response Playbook: Multiple Failed Login Attempts (Brute Force)

---

## Title & Use Case ID

| Field | Value |
|---|---|
| **Playbook Title** | Multiple Failed Login Attempts Detected (Brute Force / Password Spray) |
| **Use Case ID** | TTP-T1110 / T1078 |
| **MITRE Techniques** | T1110 – Brute Force, T1078 – Valid Accounts |
| **MITRE Mitigations** | M1036 – Account Use Policies, M1032 – Multi-factor Authentication, M1027 – Password Policies |
| **Version** | 1.0 |
| **Last Updated** | 2026-02-18 |
| **Owner** | SOC Manager / Incident Response Lead |

---

## MITRE ATT&CK Mapping

| ID | Name | Type | Description |
|---|---|---|---|
| T1110 | Brute Force | Technique (Credential Access) | Adversaries systematically guess passwords using repetitive/iterative mechanisms when credentials are unknown |
| T1110.001 | Password Guessing | Sub-technique | Guessing passwords for user accounts using common password lists |
| T1110.002 | Password Cracking | Sub-technique | Offline cracking of obtained password hashes |
| T1110.003 | Password Spraying | Sub-technique | Using one password against many accounts before moving to the next password |
| T1110.004 | Credential Stuffing | Sub-technique | Using breached credentials from other services |
| T1078 | Valid Accounts | Technique | Use of compromised legitimate credentials to access systems |
| M1036 | Account Use Policies | Mitigation | Account lockout policies, conditional access, and usage restrictions |
| M1032 | Multi-factor Authentication | Mitigation | MFA enforcement on all accounts, especially externally accessible services |
| M1027 | Password Policies | Mitigation | Password complexity, length, rotation, and breach-checking policies |

---

## Objective Statement

This playbook provides a structured process for SOC analysts to **detect, investigate, and respond to brute force login attempts, password spraying, and credential stuffing attacks** against organisational authentication systems. It covers scenarios ranging from a single source IP conducting high-volume login attempts to distributed password spraying campaigns across the entire user base. The goal is to identify whether any credentials have been compromised, contain the attack, lock down affected accounts, and strengthen authentication controls to prevent recurrence.

---

## Alert Analysis

### Alert Triggers
- SIEM correlation rule: ≥N failed login attempts from a single source IP within M minutes (configurable; recommended threshold: ≥10 failures in 10 min)
- SIEM correlation rule: ≥N failed login attempts against a single account within M minutes
- SIEM correlation rule: Failed logins across ≥N distinct accounts from a single IP (password spraying indicator; recommended: ≥5 accounts in 10 min)
- SIEM correlation rule: Multiple failed logins followed by a successful login from the same source (brute force success indicator)
- IdP/Azure AD Identity Protection: Risk detection – "Password Spray", "Brute Force", or "Unfamiliar sign-in properties"
- Cloud platform alerts: AWS GuardDuty `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration`, Azure AD Sign-in Risk
- Account lockout events firing in bulk across multiple accounts
- Threat intel match: Source IP is on a known brute force / botnet IP list

### Detection Logic / Data Sources

| Data Source | What to Query |
|---|---|
| Active Directory / Domain Controller Logs | Event IDs 4625 (failed logon), 4624 (successful logon), 4740 (account lockout), 4776 (credential validation) |
| Azure AD / Entra ID Sign-in Logs | `ResultType` codes for failures (50126, 50053, 50057), `RiskState`, `RiskLevel`, `IPAddress`, `UserAgent` |
| VPN / Remote Access Logs | Failed authentications, source IPs, geo-location |
| Web Application Logs | HTTP 401/403 responses, login endpoint access frequency |
| AWS CloudTrail | `ConsoleLogin` events with `errorMessage: "Failed authentication"` |
| Firewall / WAF Logs | Repeated connections to authentication endpoints from single IPs |
| SIEM | Correlated views across all the above |

---

## Initial Analyst Checklist

> **Note:** Steps marked with 🤖 are candidates for SOAR/workflow automation.

- [ ] 🤖 **Acknowledge alert** within SLA
- [ ] 🤖 **Identify the source IP(s)**: Extract all source IPs generating failed logins. Check geo-location, ASN, and whether they originate from known VPN/proxy/Tor exit nodes.
- [ ] 🤖 **Enrich source IP(s)**: Query threat intelligence (AbuseIPDB, GreyNoise, VirusTotal, Shodan) for reputation, known scanning/brute-force activity, and whether the IP is a known "benign scanner" (GreyNoise RIOT dataset)
- [ ] 🤖 **Identify targeted accounts**: List all accounts that received failed login attempts from the source IP(s)
- [ ] **Determine attack type**:
  - Single account targeted with many passwords → **Brute Force (T1110.001)**
  - Many accounts targeted with few passwords → **Password Spray (T1110.003)**
  - Known breached credential pairs used → **Credential Stuffing (T1110.004)**
- [ ] 🤖 **Check for successful authentication**: For each targeted account, check if any successful login occurred from the source IP(s) or from a different IP shortly after the failures (attacker may switch IPs)
- [ ] **Assess account sensitivity**: Are any targeted accounts privileged (admin, service account, executive)?
- [ ] **Check MFA status**: Verify whether targeted/compromised accounts have MFA enabled
- [ ] **Check for lockouts**: Determine if accounts were locked out and whether this is causing business disruption (potential DoS via lockout)
- [ ] **Review baseline**: Is this IP or user-agent pattern seen in normal operations? (e.g., misconfigured service account, password manager sync issue)
- [ ] **Document findings** in the incident ticket

---

## Indicators of Compromise (IOC) Checklist

| IOC Type | Value | Source | Verified? |
|---|---|---|---|
| Source IP(s) | | SIEM / Auth Logs | ☐ |
| Geo-location of Source IP | | GeoIP lookup | ☐ |
| ASN / ISP | | WHOIS / BGP | ☐ |
| User-Agent String | | Auth / Web logs | ☐ |
| Targeted Usernames | | Auth logs | ☐ |
| Compromised Accounts (successful auth) | | Auth logs | ☐ |
| Timestamp Range of Attack | | SIEM | ☐ |
| Authentication Endpoint Targeted | | Web / VPN logs | ☐ |

---

## Severity Classification Matrix

| Severity | Criteria | Response SLA |
|---|---|---|
| **Critical (P1)** | Brute force succeeded on privileged/admin account; evidence of post-compromise activity (lateral movement, data access); distributed attack causing widespread account lockouts (DoS) | Immediate escalation. War room within 30 min. |
| **High (P2)** | Brute force succeeded on ≥1 standard account; MFA not enabled on compromised account; targeted accounts include VIPs or service accounts | Escalate to Tier 2 within 15 min. Containment within 1 hour. |
| **Medium (P3)** | High-volume failed attempts detected but no successful authentication; MFA blocked a successful password guess; source IP is a known scanner | Triage within 30 min. Block IP. Monitor. |
| **Low (P4)** | Low-volume failed attempts from a single IP; likely automated scanner or misconfigured application; no account lockouts | Acknowledge within 1 hour. Verify and close or tune detection. |

---

## Triage Steps

1. **Validate the alert is not a false positive**:
   - Check if the source IP belongs to a corporate office, VPN gateway, or known partner
   - Check if a service account or automated process is misconfigured (expired credentials generating repeated failures)
   - Check if a user simply forgot their password or is entering the wrong credentials
   - Cross-reference GreyNoise: Is this a known benign internet scanner?

2. **Characterise the attack pattern**:
   - **Volume**: How many failed attempts? Over what time period?
   - **Breadth**: How many unique accounts targeted?
   - **Velocity**: Attempts per second/minute (automated vs. manual)
   - **Progression**: Did failures eventually lead to a success?

3. **Determine if any accounts are compromised**:
   - Search for successful logins from the attacker IP(s) across all authentication logs
   - Search for successful logins from *any* unusual IP for the targeted accounts within 24 hours (attacker may pivot)
   - Check for MFA challenge outcomes – was MFA prompted and bypassed?

4. **Assess post-compromise activity** (if successful login detected):
   - Mailbox rule changes, email forwarding additions
   - File access / download from SharePoint, OneDrive, or other data repositories
   - New OAuth app consents
   - Privilege escalation attempts
   - New MFA device registration by an attacker

5. **Assign severity** per the matrix above

---

## De-escalated and Expected Benign Events

The following should be classified as **false positive / benign**:

- **Misconfigured service account or application**: Automated system using expired/incorrect credentials. Action: notify application owner; update credentials; tune alert to exclude known service account + IP pair after remediation.
- **User password confusion**: Single user generating multiple failures on their own account from their known device/IP. Action: assist user with password reset if needed; close ticket.
- **Known benign scanner (GreyNoise RIOT)**: Source IP confirmed as a benign internet scanner (e.g., Shodan, Censys, security research). Action: add to allowlist if recurring; close ticket.
- **Penetration test / Red team activity**: Pre-authorised security testing. Action: verify authorisation with Red Team lead / change management; close ticket with reference to test ID.
- **Account lockout from password manager sync**: User's password manager has a stale password and is retrying. Action: advise user to update stored credentials; close ticket.

---

## Escalation of Incident

### Tier 1 → Tier 2 Escalation
**Trigger**: Confirmed brute force attack (not benign) with any of: successful authentication detected, targeted accounts include privileged/VIP users, or attack is large-scale (≥50 accounts targeted).

**Actions**:
- Assign to Tier 2 with full IOC and scope documentation
- Block source IP(s) at firewall/WAF immediately
- If successful auth detected, initiate credential reset for affected account(s)

### Tier 2 → Tier 3 / IR Lead Escalation
**Trigger**: Confirmed account compromise with post-login activity, privilege escalation, lateral movement, or MFA bypass.

**Actions**:
- Page IR Lead and CSIRT
- Initiate incident bridge
- Conduct comprehensive account audit for all compromised users
- Engage Identity & Access Management team
- Begin forensic preservation of relevant logs

### Tier 3 → Executive / Legal Escalation
**Trigger**: Compromise of privileged admin accounts, evidence of data exfiltration, widespread business disruption from account lockouts, or suspected state-sponsored actor.

**Actions**:
- Notify CISO within 1 hour
- Engage Legal if data exposure is suspected
- Assess regulatory notification requirements
- Consider engaging external forensic support

---

## Containment Actions

- **Block source IP(s)**: Add attacker IPs to firewall, WAF, and IdP conditional access deny-lists
- **Lock compromised accounts**: Temporarily disable any accounts where successful attacker login is confirmed
- **Force password reset**: Reset credentials for all compromised accounts and any accounts where the password was guessed (even if MFA blocked access)
- **Revoke sessions**: Terminate all active sessions for compromised accounts
- **Enforce MFA**: If compromised accounts did not have MFA, enable immediately. If MFA was bypassed, revoke and re-enrol MFA tokens.
- **Conditional access hardening**: Temporarily restrict sign-ins to trusted locations / compliant devices for targeted accounts or the entire organisation if the attack is widespread
- **Rate-limit authentication endpoint**: If not already in place, implement rate limiting on login endpoints (WAF rules, API gateway throttling)
- **Account lockout tuning**: If lockouts are causing DoS, consider temporarily adjusting lockout thresholds (balance security vs. availability)

---

## Eradication & Recovery

1. **Confirm no persistence**: Check for attacker-created backdoors – new user accounts, OAuth apps, forwarding rules, registered MFA devices, API keys, or service principals created during the compromise window
2. **Remove any attacker artefacts**: Delete unauthorized mailbox rules, OAuth consents, MFA registrations, and API keys
3. **Password rotation**: Enforce password change for all compromised and targeted accounts. If credential stuffing is suspected, advise all users to update passwords if they reuse corporate credentials on external services.
4. **Review and harden policies**:
   - Verify account lockout policies are aligned with M1036 recommendations
   - Verify MFA is enforced on all externally accessible services (M1032)
   - Verify password policies meet NIST SP 800-63B guidelines (M1027): minimum 12 characters, check against breached password databases, no forced periodic rotation unless compromise is detected
5. **Unblock legitimate users**: Re-enable locked-out accounts after password reset
6. **Update detection**: Add attacker IPs/user-agents to SIEM watchlists; tune correlation rules if thresholds were too high/low

---

## Email Notification Templates

### Template 1: Alert to Targeted Users (No Compromise Confirmed)

```
Subject: [INFO] Security Notice – Unusual Login Activity on Your Account

Dear [User],

Our Security Operations team detected unusual login activity targeting 
your account on [Date/Time]. Multiple failed login attempts were made 
from an unrecognised source.

WHAT HAPPENED:
- We detected [Number] failed login attempts against your account from 
  an external IP address.
- No successful unauthorised access was detected.
- Your account is secure.

WHAT WE HAVE DONE:
- The source IP address has been blocked.
- Your account has been monitored for any further suspicious activity.

RECOMMENDED ACTIONS:
1. If you did not attempt to log in at the time mentioned, no action is 
   required from you.
2. As a precaution, consider changing your password to a strong, unique 
   passphrase (≥12 characters).
3. Ensure Multi-Factor Authentication (MFA) is enabled on your account.
4. Do not reuse your corporate password on external websites or services.

If you notice any unusual activity on your account, please contact the 
SOC immediately at [contact details].

Regards,
Security Operations Centre
[Organisation Name]
Incident Reference: [TICKET-ID]
```

### Template 2: Alert to Users with Confirmed Compromise

```
Subject: [ACTION REQUIRED] Your Account Has Been Secured Following 
         Unauthorised Access

Dear [User],

Our Security Operations team identified that your account was accessed 
by an unauthorised party on [Date/Time]. We have taken immediate steps 
to secure your account.

WHAT HAPPENED:
- An attacker successfully guessed your password following a brute 
  force attack.
- [If applicable] The unauthorised party accessed [describe scope: 
  email, files, etc.].

WHAT WE HAVE DONE:
- Your password has been reset. You will need to create a new password 
  at your next login.
- All active sessions have been revoked.
- The source IP address has been blocked.
- [If applicable] MFA has been enforced on your account.

WHAT YOU NEED TO DO:
1. Log in using the temporary password sent to your [recovery method] 
   and immediately set a new, unique password.
2. Review your account for any changes you did not make (e.g., 
   forwarding rules, connected apps, recent file activity).
3. Report any anomalies to the SOC at [contact details].
4. Change your password on any personal accounts where you used the 
   same password.

Regards,
Security Operations Centre
[Organisation Name]
Incident Reference: [TICKET-ID]
```

### Template 3: Escalation to Management

```
Subject: [INCIDENT] Brute Force / Credential Attack – Severity [P1/P2] – 
         Ref: [TICKET-ID]

INCIDENT SUMMARY:
- Incident Type: Brute Force / Password Spray (MITRE T1110)
- Severity: [Critical / High]
- Detection Time: [Timestamp]
- Attack Type: [Brute Force / Password Spray / Credential Stuffing]
- Source IPs: [Count] unique IPs from [Geography]
- Targeted Accounts: [Number]
- Compromised Accounts: [Number]
- Post-Compromise Activity Detected: [Yes / No]
- MFA Status of Compromised Accounts: [Enabled / Not Enabled]

CURRENT STATUS: [Investigating / Containing / Eradicating / Recovered]

ACTIONS TAKEN:
- [Summary]

BUSINESS IMPACT:
- [Assessment – e.g., account lockouts affecting N users, 
  data access by attacker, etc.]

Incident Commander: [Name]
Next Update: [Timestamp]
```

---

## Analyst Comments

| Timestamp (UTC) | Analyst | Comment |
|---|---|---|
| YYYY-MM-DD HH:MM | | |
| | | |

---

## Contacts for Subject Matter Experts

| Role | Name | Contact | Availability |
|---|---|---|---|
| SOC Manager | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Incident Response Lead | [Name] | [Email / Phone / Slack] | 24/7 on-call rotation |
| Identity & Access Management (IAM) | [Name] | [Email / Phone / Slack] | Business hours |
| Active Directory / Entra ID Admin | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Network / Firewall Team | [Name] | [Email / Phone / Slack] | 24/7 on-call rotation |
| VPN / Remote Access Admin | [Name] | [Email / Phone / Slack] | Business hours |
| Threat Intelligence Analyst | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Application Security Team | [Name] | [Email / Phone / Slack] | Business hours |
| CISO | [Name] | [Email / Phone / Slack] | Escalation only |
| Legal / DPO | [Name] | [Email / Phone / Slack] | Business hours |
| Red Team / Pentest Lead | [Name] | [Email / Phone / Slack] | Business hours |

---

## Automation Opportunities

| Step | Automation Capability | Tool Example |
|---|---|---|
| Source IP enrichment (reputation, geo, ASN) | Fully automatable | SOAR + TIP (GreyNoise, AbuseIPDB, VirusTotal) |
| Identify targeted accounts | Fully automatable | SIEM query via SOAR |
| Check for successful auth post-failure | Fully automatable | SIEM query via SOAR |
| Block source IP at firewall/WAF | Fully automatable | Firewall API via SOAR |
| Account lockout / disable | Semi-automatable (approval) | IdP API via SOAR |
| Forced password reset | Semi-automatable (approval) | IdP API via SOAR |
| Session revocation | Fully automatable | IdP API via SOAR |
| Notification emails | Fully automatable | SOAR email action |
| Ticket enrichment | Fully automatable | SOAR + ITSM API |

---

## Lessons Learned / Post-Incident Review

- Were account lockout policies (M1036) effective, or did they create a denial-of-service condition?
- Was MFA (M1032) enforced on all targeted accounts? What percentage of accounts lacked MFA?
- Did password policies (M1027) allow weak/breached passwords?
- Were detection thresholds appropriately tuned (too many false positives? too few true positives)?
- How quickly was the attack detected and contained?
- Was the source IP already on known threat intelligence lists? If so, could proactive blocking have prevented the attack?

---

## Related Playbooks & References

- Credential Compromise / Account Takeover Playbook
- Phishing Campaign Playbook (may chain together – phishing leads to credential stuffing)
- Lateral Movement Playbook
- NIST SP 800-61r2 – Computer Security Incident Handling Guide
- NIST SP 800-63B – Digital Identity Guidelines (password policy)
- MITRE ATT&CK: [T1110](https://attack.mitre.org/techniques/T1110/), [T1078](https://attack.mitre.org/techniques/T1078/)
- SANS Brute Force Investigation Playbook

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-02-18 | [Author] | Initial release |
