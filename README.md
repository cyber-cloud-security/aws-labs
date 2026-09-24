<div align="center">

# ☁️ AWS Hands-On Labs 🚀

![AWS](https://img.shields.io/badge/☁️_Platform-Amazon_Web_Services-FF9900?style=flat-square)
![EC2 Labs](https://img.shields.io/badge/🖥️_EC2_Curriculum-28_Labs_Live-2da44e?style=flat-square)
![CLI](https://img.shields.io/badge/💻_Execution-AWS_CLI_v2-0969da?style=flat-square)
![License](https://img.shields.io/badge/📖_Format-Step--by--Step_Annotated-8250df?style=flat-square)

*Hands-on laboratories, step-by-step CLI execution guides, pre-rendered architectural diagrams, and deep-dive technical command explanations for Amazon Web Services (AWS).*

</div>

---

## 🧭 Services and Domain

| Service / Domain | Path | Labs Count | Key Focus Areas |
| :--- | :---: | :---: | :--- |
| 🖥️ **[Amazon EC2 (Elastic Compute Cloud)](./EC2/README.md)** | **[`/EC2`](./EC2/README.md)** | **28 Labs** (8 Modules) | Compute Architectures, Graviton ARM64, EBS Elastic Volumes, NVMe Instance Store, EFS, Dual-ENI Routing, ENA Express (SRD), IMDSv2 Hardening, SSM Session Manager, Launch Templates, ALB & Target Tracking ASG, Spot Fleets & Interruption Watchdogs, FinOps gp3 Modernization, Disaster Recovery (EBS Root Rescue & Serial Console), VPC Flow Logs, and AWS Nitro System & Enclaves. |

---

## ✨ Designed for an Enjoyable Reading & Learning Experience

> [!TIP]
> **Built Like an Interactive Engineering Textbook**: Every lab in this repository is formatted so that reading both **code** and **architectural prose** is effortless on GitHub.

1. **📐 Visual Architecture First**: Every lab begins with a high-resolution architecture diagram PNG alongside a collapsible Mermaid source drawer.
2. **💻 Readable, Multi-Line Annotated Code**: Commands are cleanly wrapped across lines with `\` continuations and inline `# comments` — **zero horizontal scrolling** required.
3. **📘 Inline Deep-Dive Command Breakdowns**: Every lab includes a **Deep-Dive Command & Flag Reference** section explaining every flag, JMESPath `--query` filter, Linux kernel setting, and **why it matters in production automation**.
4. **🧭 Seamless Navigation**: Breadcrumb headers and `⬅️ Previous Lab` / `➡️ Next Lab` links let you move through the curriculum like a book.
5. **🛡️ Built-In Cost & Security Guardrails**: Native callout alerts (`[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`) highlight Free Tier eligibility, security pitfalls, and mandatory teardown steps.

---

## 🗂️ Quick Jump: Amazon EC2 Master Curriculum (28 Labs)

| Module | Topic Area | Labs Included |
| :---: | :--- | :--- |
| **[Module 01](./EC2/module-01-fundamentals-and-lifecycle/README.md)** | **🧱 Foundations & Lifecycle** | [1.1 Launch & Bootstrap](./EC2/module-01-fundamentals-and-lifecycle/lab-01-launch-and-bootstrap/README.md) • [1.2 Lifecycle & Hibernation](./EC2/module-01-fundamentals-and-lifecycle/lab-02-lifecycle-and-hibernation/README.md) • [1.3 Custom AMIs](./EC2/module-01-fundamentals-and-lifecycle/lab-03-amis-and-image-builder/README.md) |
| **[Module 02](./EC2/module-02-storage-ebs-ephemeral-efs/README.md)** | **💾 Storage Architecture** | [2.1 EBS Elastic Volumes](./EC2/module-02-storage-ebs-ephemeral-efs/lab-01-ebs-elastic-volumes/README.md) • [2.2 Snapshots & Multi-Attach](./EC2/module-02-storage-ebs-ephemeral-efs/lab-02-snapshots-dlm-multiattach/README.md) • [2.3 NVMe Instance Store](./EC2/module-02-storage-ebs-ephemeral-efs/lab-03-instance-store-ephemeral/README.md) • [2.4 Amazon EFS](./EC2/module-02-storage-ebs-ephemeral-efs/lab-04-efs-shared-filesystem/README.md) |
| **[Module 03](./EC2/module-03-networking-eni-placement/README.md)** | **🌐 Networking & Placement** | [3.1 Dual-ENI Routing](./EC2/module-03-networking-eni-placement/lab-01-dual-eni-routing/README.md) • [3.2 Elastic IP Failover](./EC2/module-03-networking-eni-placement/lab-02-elastic-ips-ha/README.md) • [3.3 ENA Express (SRD)](./EC2/module-03-networking-eni-placement/lab-03-enhanced-networking-ena/README.md) • [3.4 Placement Groups](./EC2/module-03-networking-eni-placement/lab-04-placement-groups/README.md) |
| **[Module 04](./EC2/module-04-security-iam-ssm/README.md)** | **🛡️ Security & Zero-Trust** | [4.1 SGs vs NACLs](./EC2/module-04-security-iam-ssm/lab-01-security-groups-nacls/README.md) • [4.2 IAM Instance Profiles](./EC2/module-04-security-iam-ssm/lab-02-iam-roles-instance-profiles/README.md) • [4.3 IMDSv2 Hardening](./EC2/module-04-security-iam-ssm/lab-03-imdsv2-hardening/README.md) • [4.4 SSM Session Manager](./EC2/module-04-security-iam-ssm/lab-04-ssm-session-manager/README.md) |
| **[Module 05](./EC2/module-05-ha-asg-alb/README.md)** | **⚖️ HA, Scaling & ALB** | [5.1 Launch Templates](./EC2/module-05-ha-asg-alb/lab-01-launch-templates/README.md) • [5.2 ALB & Target Groups](./EC2/module-05-ha-asg-alb/lab-02-alb-and-target-groups/README.md) • [5.3 ASG Dynamic Scaling](./EC2/module-05-ha-asg-alb/lab-03-asg-dynamic-scaling/README.md) • [5.4 ASG Lifecycle Hooks](./EC2/module-05-ha-asg-alb/lab-04-asg-lifecycle-hooks/README.md) |
| **[Module 06](./EC2/module-06-purchasing-cost-optimization/README.md)** | **💰 Purchasing & FinOps** | [6.1 Spot Interruption Watchdog](./EC2/module-06-purchasing-cost-optimization/lab-01-spot-interruption-handling/README.md) • [6.2 Mixed-Instance ASG](./EC2/module-06-purchasing-cost-optimization/lab-02-asg-mixed-instances/README.md) • [6.3 FinOps & gp3 Migration](./EC2/module-06-purchasing-cost-optimization/lab-03-cost-optimization-rightsizing/README.md) |
| **[Module 07](./EC2/module-07-monitoring-and-troubleshooting/README.md)** | **🩺 Monitoring & Recovery** | [7.1 Auto-Recovery Alarms](./EC2/module-07-monitoring-and-troubleshooting/lab-01-status-checks-autorecovery/README.md) • [7.2 Unified CW Agent](./EC2/module-07-monitoring-and-troubleshooting/lab-02-cloudwatch-agent-metrics-logs/README.md) • [7.3 Serial Console & EBS Rescue](./EC2/module-07-monitoring-and-troubleshooting/lab-03-serial-console-ebs-rescue/README.md) • [7.4 VPC Flow Logs](./EC2/module-07-monitoring-and-troubleshooting/lab-04-vpc-flow-logs/README.md) |
| **[Module 08](./EC2/module-08-advanced-nitro/README.md)** | **⚡ AWS Nitro System** | [8.1 Nitro Hardware Offloading](./EC2/module-08-advanced-nitro/lab-01-nitro-architecture/README.md) • [8.2 Nitro Enclaves Confidential Compute](./EC2/module-08-advanced-nitro/lab-02-nitro-enclaves/README.md) |

---

## 🚀 Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/cyber-cloud-security/aws-labs.git
cd aws-labs/EC2

# 2. Validate local AWS CLI v2 & default VPC prerequisites
chmod +x ./scripts/setup_prereqs.sh
./scripts/setup_prereqs.sh

# 3. Audit & clean up any active lab resources when finished
chmod +x ./scripts/cleanup_all.sh
./scripts/cleanup_all.sh
```
