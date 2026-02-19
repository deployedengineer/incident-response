# Incident Response Playbook: Unusual S3 Bucket Access Patterns

> **Document Version:** 1.0
> **Date:** 2026-02-18
> **Classification:** INTERNAL – SOC Operations
> **Review Cycle:** Quarterly

---

## Title & Use Case ID

| Field | Value |
|---|---|
| **Playbook Title** | Unusual S3 Bucket Access Patterns Detected |
| **Use Case ID** | TTP-T1020 / T1039 |
| **MITRE Techniques** | T1020 – Automated Exfiltration, T1039 – Data from Network Shared Drive |
| **MITRE Mitigations** | M1057 – Data Loss Prevention, M1041 – Encrypt Sensitive Information |
| **Related Techniques** | T1530 – Data from Cloud Storage, T1537 – Transfer Data to Cloud Account |
| **Version** | 1.0 |
| **Last Updated** | 2026-02-18 |
| **Owner** | SOC Manager / Cloud Security Lead |

---

## MITRE ATT&CK Mapping

| ID | Name | Type | Description |
|---|---|---|---|
| T1020 | Automated Exfiltration | Technique (Exfiltration) | Adversaries use automated techniques (scripts, tools) to exfiltrate data after collection, potentially using S3 replication or bulk download |
| T1039 | Data from Network Shared Drive | Technique (Collection) | Adversaries access shared network drives (including cloud storage mapped as drives) to collect data for exfiltration |
| T1530 | Data from Cloud Storage | Technique (Collection) | Adversaries access data from cloud storage objects such as S3 buckets |
| T1537 | Transfer Data to Cloud Account | Technique (Exfiltration) | Adversaries transfer data to another cloud account they control |
| M1057 | Data Loss Prevention | Mitigation | DLP tools and policies to detect and prevent data exfiltration |
| M1041 | Encrypt Sensitive Information | Mitigation | Encryption of data at rest and in transit to protect against unauthorized access |

---

## Objective Statement

This playbook provides a structured process for SOC and Cloud Security analysts to **detect, investigate, and respond to anomalous access patterns on AWS S3 buckets** that may indicate unauthorized access, data exfiltration, or data destruction. It covers scenarios including bulk object downloads from unusual IPs or IAM principals, unauthorized bucket policy changes, public exposure of private buckets, cross-account replication, and ransomware-style deletion or encryption of S3 objects. The goal is to identify the scope of unauthorized access, contain the threat, prevent data loss, and restore any affected data.

---

## Alert Analysis

### Alert Triggers
- **AWS GuardDuty findings**:
  - `Exfiltration:S3/MaliciousIPCaller`
  - `Exfiltration:S3/AnomalousBehavior`
  - `Discovery:S3/MaliciousIPCaller`
  - `UnauthorizedAccess:S3/MaliciousIPCaller.Custom`
  - `Policy:S3/BucketPublicAccessGranted`
  - `Policy:S3/BucketAnonymousAccessGranted`
  - `Policy:S3/AccountBlockPublicAccessDisabled`
  - `Stealth:S3/ServerAccessLoggingDisabled`
- **AWS CloudTrail anomaly**:
  - Spike in `GetObject`, `PutObject`, `DeleteObject`, or `CopyObject` API calls
  - `PutBucketPolicy`, `PutBucketAcl`, `DeleteBucketPolicy` from unusual principal
  - `PutBucketReplication` to unknown destination account
  - `PutBucketVersioning` (disabling) followed by `DeleteObject` calls
  - API calls from IP addresses or regions not normally seen
- **SIEM correlation rules**:
  - Data volume anomaly: S3 egress exceeding N GB above baseline in M-hour window
  - Access time anomaly: S3 API calls during off-hours from human IAM users (not service roles)
  - Cross-account anomaly: `AssumeRole` to S3-access role from unknown account
- **S3 Server Access Logs**: High sequential `REST.COPY.OBJECT_GET` from same remote IP
- **AWS Macie alert**: Sensitive data (PII, PHI, credentials) detected in a publicly accessible or newly modified bucket
- **CloudWatch alarm**: S3 request metrics (`NumberOfObjects`, `BucketSizeBytes`) show sudden decrease (deletion) or spike (data staging)
- **Cost anomaly**: AWS Cost Anomaly Detection flags unexpected S3 data transfer charges

### Detection Logic / Data Sources

| Data Source | What to Query |
|---|---|
| AWS CloudTrail (Management Events) | `PutBucketPolicy`, `PutBucketAcl`, `DeleteBucketPolicy`, `PutBucketReplication`, `PutBucketVersioning`, `CreateAccessKey` |
| AWS CloudTrail (Data Events – S3) | `GetObject`, `PutObject`, `DeleteObject`, `CopyObject`, `HeadObject` – filter by volume, source IP, and IAM principal |
| AWS GuardDuty | S3-specific findings (see alert triggers above) |
| AWS Macie | Sensitive data discovery findings, public bucket alerts |
| S3 Server Access Logs | Requester IP, operation, key, HTTP status, bytes sent, time |
| AWS IAM Access Analyzer | External access findings for S3 buckets |
| VPC Flow Logs | If S3 VPC endpoint is used, flow logs show traffic volume |
| AWS Config | Configuration changes to bucket policies, ACLs, encryption settings |
| CloudWatch Metrics | `NumberOfObjects`, `BucketSizeBytes`, S3 request metrics |
| AWS Cost Explorer | Unexpected S3 data transfer out charges |

---

## Initial Analyst Checklist

> **Note:** Steps marked with 🤖 are candidates for SOAR/workflow automation.

- [ ] 🤖 **Acknowledge alert** within SLA
- [ ] 🤖 **Identify the affected S3 bucket(s)**: Bucket name, AWS account, region, data classification
- [ ] 🤖 **Identify the IAM principal**: Which user, role, or access key performed the anomalous actions? Extract the `userIdentity` block from CloudTrail.
- [ ] 🤖 **Identify the source IP**: Extract `sourceIPAddress` from CloudTrail. Determine if internal (VPC/NAT Gateway), AWS service IP, or external. Geo-locate and check threat intel.
- [ ] **Review CloudTrail events** for the affected bucket within the suspicious time window:
  - Filter for `GetObject`, `CopyObject`, `DeleteObject`, `PutObject`
  - Filter for `PutBucketPolicy`, `PutBucketAcl`, `PutBucketReplication`, `PutBucketVersioning`
  - Note error codes (`AccessDenied` vs. success)
- [ ] **Quantify data exposure**:
  - How many objects were accessed/downloaded/deleted?
  - What is the total data volume (bytes)?
  - What data classification do the affected objects carry?
- [ ] **Check bucket configuration**:
  - Is the bucket public? (Check `PublicAccessBlockConfiguration`, bucket policy, ACL)
  - Is server-side encryption enabled? (SSE-S3, SSE-KMS, or SSE-C)
  - Is versioning enabled?
  - Is object lock enabled?
  - Is S3 server access logging enabled?
- [ ] **Check IAM credentials**:
  - Is the access key active? When was it last rotated?
  - Has the IAM user/role been compromised? Check for other anomalous API calls from the same principal.
  - Was an `AssumeRole` used? From which source account/principal?
- [ ] **Check for bucket policy changes**: Compare current bucket policy against the last known-good configuration in AWS Config history
- [ ] 🤖 **Check for replication**: Was `PutBucketReplication` called? To what destination bucket/account?
- [ ] **Document all findings** in the incident ticket with timestamps and CloudTrail event IDs

---

## Indicators of Compromise (IOC) Checklist

| IOC Type | Value | Source | Verified? |
|---|---|---|---|
| S3 Bucket Name | | Alert / CloudTrail | ☐ |
| AWS Account ID | | CloudTrail | ☐ |
| IAM Principal (ARN) | | CloudTrail `userIdentity` | ☐ |
| Access Key ID | | CloudTrail `userIdentity` | ☐ |
| Source IP Address(es) | | CloudTrail `sourceIPAddress` | ☐ |
| User-Agent String | | CloudTrail `userAgent` | ☐ |
| Suspicious API Calls | | CloudTrail | ☐ |
| Destination Replication Bucket/Account | | CloudTrail (`PutBucketReplication`) | ☐ |
| Objects Accessed / Deleted (count) | | CloudTrail Data Events / S3 Access Logs | ☐ |
| Data Volume (bytes) | | S3 Access Logs / CloudWatch | ☐ |
| Timeframe of Anomalous Activity | | SIEM / CloudTrail | ☐ |
| KMS Key ARN (if attacker used own key) | | CloudTrail KMS events | ☐ |

---

## Severity Classification Matrix

| Severity | Criteria | Response SLA |
|---|---|---|
| **Critical (P1)** | Confirmed data exfiltration of sensitive/classified data; bucket containing PII/PHI made public; objects deleted/encrypted by attacker (ransom scenario); IAM credentials for broad S3 access compromised with evidence of misuse | Immediate escalation. War room within 30 min. |
| **High (P2)** | Bulk `GetObject` calls from unusual IP/principal on sensitive bucket; bucket policy changed to allow public or cross-account access without authorisation; bucket replication to unknown account detected | Escalate to Tier 2 within 15 min. Containment within 1 hour. |
| **Medium (P3)** | Anomalous access volume on non-sensitive bucket; `AccessDenied` errors suggesting reconnaissance; bucket policy change that is potentially unintentional (e.g., by an authorised admin) | Triage within 30 min. Investigate and verify. |
| **Low (P4)** | Minor access anomaly (slightly above baseline) from known internal IP/role; Macie alert on already-known data classification issue; test/dev bucket with no sensitive data | Acknowledge within 1 hour. Verify and close or create hardening ticket. |

---

## Triage Steps

1. **Validate the alert is not a false positive**:
   - Is the IAM principal a known service (e.g., ETL pipeline, backup job, analytics workload) that legitimately accesses this bucket?
   - Is the spike in access due to a scheduled job (e.g., monthly reporting, data migration)?
   - Was a bucket policy change authorised through a change management ticket?
   - Check AWS Config timeline for the bucket: does the change align with an approved deployment?

2. **Determine the nature of the anomaly**:
   - **Unauthorized read (exfiltration)**: Bulk `GetObject` / `CopyObject` calls from unusual source
   - **Unauthorized write**: `PutObject` of unknown files (potential malware staging or ransomware encryption)
   - **Unauthorized delete**: Bulk `DeleteObject` calls (potential data destruction / ransom)
   - **Unauthorized configuration change**: `PutBucketPolicy`, `PutBucketAcl`, `DeleteBucketEncryption`, `PutBucketPublicAccessBlock` (disabling)
   - **Unauthorized replication**: `PutBucketReplication` to external account

3. **Scope the impact**:
   - Which objects were affected? Query CloudTrail Data Events with the bucket ARN and time range.
   - What data classification do these objects carry? Cross-reference with data catalogue or Macie.
   - Are other buckets affected? Check the same IAM principal's activity across all S3 buckets.
   - Is there evidence of privilege escalation? (e.g., the principal created new access keys, assumed higher-privilege roles, or modified IAM policies before accessing S3)

4. **Determine root cause of credential / access compromise**:
   - Was an access key leaked? (Check GitHub, Pastebin, or other public code repos)
   - Was an IAM role assumed from an external account? (Check `AssumeRole` events)
   - Was the bucket misconfigured to allow public access? (Check bucket policy for `"Principal": "*"`)
   - Was there a prior phishing or brute-force incident that led to credential compromise?

5. **Assign severity** per the matrix above

---

## De-escalated and Expected Benign Events

The following should be classified as **false positive / benign**:

- **Scheduled data pipeline / ETL job**: High `GetObject` volume from a known IAM role (e.g., `role/data-pipeline-prod`) accessing expected buckets during scheduled windows. Action: document as baseline; tune alert threshold or add role to allowlist.
- **Authorised bucket policy change**: Infrastructure team updated bucket policy via Terraform/CloudFormation as part of an approved change request. Action: verify change request number; confirm policy is as intended; close ticket.
- **AWS service internal access**: Some AWS services (e.g., Athena, Redshift Spectrum, EMR) access S3 on behalf of the customer using service-linked roles. Check `userAgent` for `athena.amazonaws.com`, `redshift.amazonaws.com`, etc. Action: close if expected service access.
- **Backup / disaster recovery operations**: Legitimate cross-region or cross-account replication job. Action: verify with the infrastructure team; close.
- **Macie false positive**: Macie flagged non-sensitive data as PII (e.g., test data, sample names). Action: update Macie custom data identifiers or add suppression rule; close.
- **Cost anomaly from legitimate large upload/download**: A one-time data migration or large dataset upload. Action: confirm with data owner; close.

---

## Escalation of Incident

### Tier 1 → Tier 2 / Cloud Security Escalation
**Trigger**: Confirmed anomalous S3 access that is not attributable to a known process; any bucket policy change granting public or unknown external access; any evidence of data download from sensitive buckets by unknown principals.

**Actions**:
- Assign to Tier 2 / Cloud Security analyst with full CloudTrail evidence and IOC checklist
- Begin containment (do not wait for Tier 2 acknowledgement if severity is High+)
- Tag incident with affected AWS Account ID and bucket name

### Tier 2 → Tier 3 / IR Lead Escalation
**Trigger**: Confirmed data exfiltration (bulk download of sensitive data to external IP); confirmed credential compromise with evidence of attacker activity beyond S3; bucket replication to attacker-controlled account; data deletion/ransomware.

**Actions**:
- Page IR Lead and Cloud Security Lead
- Initiate incident bridge
- Engage AWS Security (open AWS Support case with severity "Critical / Business-critical system down" if applicable)
- Begin forensic preservation: snapshot relevant logs, enable additional CloudTrail data event logging if not already active
- Assess whether to contact AWS Security Incident Response service

### Tier 3 → Executive / Legal / Regulatory Escalation
**Trigger**: PII/PHI data confirmed exfiltrated or exposed publicly; ransom demand received; significant data destruction; regulatory reporting thresholds met.

**Actions**:
- Notify CISO and CTO within 1 hour
- Engage Legal / DPO for data breach assessment and notification obligations (GDPR, CCPA, HIPAA, etc.)
- Engage Cyber Insurance carrier
- Prepare external communication if public-facing impact
- Engage law enforcement if appropriate
- Engage AWS Premium Support / AWS Security Incident Response team

---

## Containment Actions

### Credential-Level Containment
- **Deactivate compromised IAM access keys**: `aws iam update-access-key --access-key-id AKIAXXXXXXXX --status Inactive --user-name [username]`
- **Revoke temporary credentials**: Attach an inline deny-all policy with a condition of `aws:TokenIssueTime` before the current time to the compromised role, forcing all existing temporary credentials to be invalid
- **Disable compromised IAM user**: `aws iam update-login-profile` (remove console access) + deactivate all access keys
- **Rotate all access keys** for the compromised principal

### Bucket-Level Containment
- **Restore bucket policy**: Revert the bucket policy to the last known-good configuration (from AWS Config history or version control)
- **Enable S3 Block Public Access** at account and bucket level if it was disabled: `aws s3api put-public-access-block`
- **Restrict bucket policy**: If immediate lockdown is needed, apply a restrictive bucket policy that only allows access from known IAM principals and VPC endpoints
- **Disable bucket replication** if unauthorized replication was configured: `aws s3api delete-bucket-replication --bucket [bucket-name]`
- **Enable versioning** (if not already enabled) to protect against further deletions
- **Enable MFA Delete** on the bucket if it contains critical data

### Network-Level Containment
- **Block attacker IP(s)** at WAF, security group, or NACL level
- **Restrict S3 access to VPC endpoint**: If the bucket should only be accessed from within the VPC, update the bucket policy to include a `aws:sourceVpce` condition

---

## Eradication & Recovery

1. **Verify containment is effective**: Confirm no further unauthorized API calls from the compromised principal or IP
2. **Delete unauthorized IAM resources**: Remove any access keys, IAM users, roles, or policies created by the attacker
3. **Restore deleted objects**: If versioning was enabled, restore objects from previous versions. If Object Lock was in place, verify objects are intact.
4. **Restore from backup**: If objects were encrypted by the attacker (ransomware) and versioning was not enabled, restore from S3 cross-region replicas, S3 Glacier backups, or AWS Backup vaults. **Do not pay ransom.**
5. **Re-enable encryption**: Ensure server-side encryption (SSE-KMS or SSE-S3) is enabled and that the attacker has not replaced the KMS key with their own
6. **Audit all S3 buckets in the account**: Use IAM Access Analyzer and S3 Block Public Access settings at the account level to identify any other buckets that may have been affected
7. **Review and harden IAM policies**:
   - Remove wildcard `s3:*` permissions
   - Implement least-privilege with specific actions (`s3:GetObject`, `s3:PutObject`) on specific resource ARNs
   - Add conditions (source VPC, source IP, MFA required) to sensitive bucket policies
8. **Enable additional monitoring**: Ensure CloudTrail Data Events for S3 are enabled on all sensitive buckets; enable S3 Server Access Logging; enable AWS Macie for continuous sensitive data discovery

---

## Email Notification Templates

### Template 1: Internal Alert to Data/Bucket Owners

```
Subject: [ACTION REQUIRED] Unusual Access Detected on S3 Bucket [Bucket Name]

Dear [Data Owner / Team],

Our Security Operations team has detected unusual access patterns on 
the S3 bucket [Bucket Name] in AWS Account [Account ID] ([Account Alias]).

DETAILS:
- Bucket: [Bucket Name]
- Region: [Region]
- Timeframe of Anomalous Activity: [Start Time] – [End Time] (UTC)
- Nature of Activity: [Bulk download / Unauthorized policy change /
  Object deletion / Replication to unknown account]
- IAM Principal Involved: [ARN]
- Source IP: [IP Address] ([Geo-location])
- Objects Affected: [Count / Description]
- Estimated Data Volume: [X GB]

WHAT WE HAVE DONE:
- The compromised credentials have been deactivated.
- The bucket policy has been restored to its last known-good state.
- Attacker IP(s) have been blocked.
- [If applicable] Deleted objects are being restored from versioned
  copies / backups.

WHAT WE NEED FROM YOU:
1. Confirm the data classification of the affected objects.
2. Identify any objects containing PII, PHI, or regulated data.
3. Confirm whether the restored data is complete and intact.
4. Report any additional anomalies you observe in the bucket.

Please respond to this email or contact the SOC at [contact details]
by [deadline].

Regards,
Security Operations Centre
[Organisation Name]
Incident Reference: [TICKET-ID]
```

### Template 2: Escalation to Management

```
Subject: [INCIDENT] S3 Data Exfiltration / Unauthorized Access –
         Severity [P1/P2] – Ref: [TICKET-ID]

INCIDENT SUMMARY:
- Incident Type: S3 Unauthorized Access / Data Exfiltration
  (MITRE T1020 / T1530)
- Severity: [Critical / High]
- Detection Time: [Timestamp]
- AWS Account: [Account ID] ([Account Alias])
- Affected Bucket(s): [Bucket Name(s)]
- Data Classification: [Confidential / Internal / Public]
- Data Volume Affected: [X GB, Y objects]
- Exfiltration Confirmed: [Yes / No / Under Investigation]
- Data Destruction Confirmed: [Yes / No]
- Compromised Credential: [IAM User / Role / Access Key ID]

CURRENT STATUS: [Investigating / Containing / Eradicating / Recovered]

ACTIONS TAKEN:
- [Summary of containment and remediation steps]

REGULATORY / LEGAL IMPLICATIONS:
- [PII/PHI involved: Yes/No]
- [Breach notification required: Under assessment / Yes / No]
- [Regulator(s) involved: GDPR / CCPA / HIPAA / Other]

BUSINESS IMPACT:
- [Assessment]

Incident Commander: [Name]
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
| Cloud Security Lead | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Incident Response Lead | [Name] | [Email / Phone / Slack] | 24/7 on-call rotation |
| AWS Account Owner / Admin | [Name] | [Email / Phone / Slack] | Business hours |
| Cloud Platform / DevOps Team | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Data Owner (per bucket) | [Refer to data catalogue] | [Varies] | Business hours |
| IAM / Identity Team | [Name] | [Email / Phone / Slack] | Business hours |
| Network Security Team | [Name] | [Email / Phone / Slack] | 24/7 on-call rotation |
| Threat Intelligence Analyst | [Name] | [Email / Phone / Slack] | Business hours + on-call |
| Legal / Data Protection Officer | [Name] | [Email / Phone / Slack] | Business hours |
| CISO | [Name] | [Email / Phone / Slack] | Escalation only |
| AWS Account Manager / TAM | [Company] | [Email / Phone] | Business hours |
| AWS Support (Premium) | N/A | AWS Support Console | 24/7 |
| Cyber Insurance Broker | [Company / Name] | [Email / Phone] | Business hours |
| Law Enforcement Liaison | [Agency / Name] | [Phone] | As needed |

---

## Automation Opportunities

| Step | Automation Capability | Tool Example |
|---|---|---|
| GuardDuty finding enrichment | Fully automatable | SOAR + GuardDuty API |
| CloudTrail event extraction for affected bucket | Fully automatable | SOAR + CloudTrail Lake / Athena |
| Source IP enrichment | Fully automatable | SOAR + TIP |
| IAM access key deactivation | Semi-automatable (approval) | SOAR + AWS IAM API |
| Bucket policy rollback (from Config) | Semi-automatable (approval) | SOAR + AWS Config + S3 API |
| S3 Block Public Access enforcement | Fully automatable | AWS Config auto-remediation rule / SOAR |
| Replication removal | Semi-automatable (approval) | SOAR + S3 API |
| Macie finding processing | Fully automatable | EventBridge → Lambda / SOAR |
| Ticket creation and enrichment | Fully automatable | SOAR + ITSM API |
| Notification emails | Fully automatable | SOAR email action / SNS |

---

## Lessons Learned / Post-Incident Review

After incident closure, the Cloud Security Lead / IR Lead should schedule a post-incident review within **5 business days**. Address:

- How was the S3 bucket initially compromised? (Credential leak, misconfiguration, over-permissive policy)
- Were CloudTrail Data Events for S3 enabled *before* the incident? If not, critical forensic data may have been lost.
- Was the bucket policy following least-privilege? Were wildcard principals (`"*"`) in use?
- Was encryption at rest (M1041) enforced? Was the KMS key policy appropriately scoped?
- Were DLP controls (M1057) in place to detect anomalous data movement?
- Were S3 Block Public Access settings enabled at the account level?
- How quickly was the anomaly detected? Could detection be improved with tighter CloudWatch alarms or GuardDuty custom threat lists?
- Was versioning and/or Object Lock enabled, and did it aid recovery?
- Are there other buckets with similar configurations that need hardening?

Document findings in the incident ticket and update this playbook if process changes are agreed.

---

## Related Playbooks & References

- Compromised IAM Credentials Playbook
- AWS Ransomware Response Playbook (S3)
- Data Breach Notification Playbook
- NIST SP 800-61r2 – Computer Security Incident Handling Guide
- AWS Security Incident Response Guide
- AWS Customer Playbook Framework (GitHub: aws-samples/aws-customer-playbook-framework)
- MITRE ATT&CK: [T1020](https://attack.mitre.org/techniques/T1020/), [T1039](https://attack.mitre.org/techniques/T1039/), [T1530](https://attack.mitre.org/techniques/T1530/)

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-02-18 | [Author] | Initial release |
