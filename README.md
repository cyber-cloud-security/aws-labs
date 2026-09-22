# AWS Hands-On Labs 🚀

Welcome to the **AWS Labs** repository — hands-on laboratories, step-by-step CLI execution guides, pre-rendered architectural diagrams, and deep-dive technical command explanations for Amazon Web Services (AWS).

This repository is organized by AWS service domains, providing practical, real-world implementations designed for Cloud Architects, DevOps/Platform Engineers, Security Specialists, and System Administrators.

---

## 🧭 Service Laboratories Catalog

| Service / Domain | Path | Labs Count | Key Focus Areas |
| :--- | :--- | :---: | :--- |
| 🖥️ **[Amazon EC2 (Elastic Compute Cloud)](./EC2)** | [`/EC2`](./EC2) | **28 Labs** (8 Modules) | Compute Architectures, Graviton ARM64, EBS Elastic Volumes, NVMe Instance Store, EFS, Dual-ENI Routing, ENA Express (SRD), IMDSv2 Hardening, SSM Session Manager, Launch Templates, ALB & Target Tracking ASG, Spot Fleets & Interruption Watchdogs, FinOps gp3 Modernization, Disaster Recovery (EBS Root Rescue & Serial Console), VPC Flow Logs, and AWS Nitro System & Enclaves. |

---

## 🌟 What Makes These Labs Unique?

Every single laboratory in this repository is built with production standards:

1. **Architecture First**: Each lab contains visual architecture diagrams (pre-rendered as high-resolution PNG images ready for documentation or Google Docs embedding, along with raw Mermaid source code).
2. **Production-Ready AWS CLI v2**: Fully automated, copy-paste-ready CLI commands utilizing modern features (IMDSv2 tokens, SSM Parameter Store references, IAM instance profiles, and least-privilege tags).
3. **Deep Architectural & Operational Concepts**: Every lab explains failure modes, security best practices (IMDSv2, least-privilege IAM, policy routing), idempotency, and operational standards directly within the lab workflow.
4. **Zero-Cost & Free-Tier Guardrails**: Designed to run within the AWS Free Tier wherever possible, including automated cleanup commands and auditing scripts to prevent unexpected cloud spend.

---

## 🚀 Quick Start: Exploring Amazon EC2 Labs

To get started with the complete 28-lab Amazon EC2 curriculum:

```bash
# 1. Clone the repository
git clone https://github.com/cyber-cloud-security/aws-labs.git
cd aws-labs/EC2

# 2. Verify your AWS CLI prerequisites
chmod +x ./scripts/setup_prereqs.sh
./scripts/setup_prereqs.sh

# 3. Explore the modules
ls -l
```

👉 **Head directly to the [Amazon EC2 Master Labs Curriculum](./EC2)** to begin Module 1!

---

## 🧹 Cost & Clean-Up Guardrails

Always remember to run the teardown steps at the conclusion of each laboratory. To run an automated audit of active lab instances or leftover resources in your AWS account:

```bash
chmod +x ./EC2/scripts/cleanup_all.sh
./EC2/scripts/cleanup_all.sh
```
