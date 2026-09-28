<div align="center">

# 🐧 Ubuntu Linux: AWS CLI v2 & Environment Setup

![OS](https://img.shields.io/badge/🐧_OS-Ubuntu_22.04%2F24.04_LTS-E95420?style=flat-square)
![Arch](https://img.shields.io/badge/⚙️_Arch-x86__64_%26_ARM64_(aarch64)-0969da?style=flat-square)
![CLI](https://img.shields.io/badge/💻_CLI-AWS_CLI_v2-FF9900?style=flat-square)
![Scope](https://img.shields.io/badge/📦_Environment-Multipass%20%7C%20WSL2%20%7C%20Native-8250df?style=flat-square)

[⬅️ Back to Module 00 Hub](./README.md) &nbsp;•&nbsp; [🍎 macOS Setup Guide](./prerequisites-macos.md) &nbsp;•&nbsp; [🚀 Start Module 01](../module-01-fundamentals-and-lifecycle/README.md)

</div>

---

## 📌 Overview

This guide provides step-by-step instructions to configure **Ubuntu Linux (22.04 LTS or 24.04 LTS)** for executing all 28 labs in the AWS EC2 hands-on curriculum. It applies equally to:
- Local native Ubuntu installations
- **Canonical Multipass VMs** on macOS or Windows
- **WSL2** (Windows Subsystem for Linux) on Windows 10/11
- Remote Ubuntu EC2 bastion hosts

---

## 🛠️ Step 1: Install AWS CLI v2 & Helper Tools

1. Update package lists and install required helper tools:
```bash
sudo apt update && sudo apt install -y curl unzip jq
```

2. Download and install AWS CLI v2 (auto-detects `x86_64` vs `aarch64` / ARM64):
```bash
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  echo "Detected ARM64 (aarch64) architecture..."
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
  echo "Detected x86_64 architecture..."
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip
sudo ./aws/install --update
rm -rf aws awscliv2.zip
```

3. Verify installation:
```bash
aws --version
```

---

## ⚙️ Step 2: Configure Terminal Optimization & AWS Credentials

### 1. Disable AWS CLI Terminal Paging
By default, AWS CLI v2 pipes output into `less`. In bash sessions and automated scripts, this causes commands to hang waiting for user keypresses (`q` or `Return`).

```bash
export AWS_PAGER=""
echo 'export AWS_PAGER=""' >> ~/.bashrc
```

### 2. Configure Your AWS Credentials
```bash
aws configure
```

When prompted, enter your IAM access details:
- **AWS Access Key ID**: `YOUR_ACCESS_KEY_ID`
- **AWS Secret Access Key**: `YOUR_SECRET_ACCESS_KEY`
- **Default region name**: `us-east-1`
- **Default output format**: `json`

> [!TIP]
> **IAM Permissions**: Ensure your IAM user or role has policies granting permissions for `ec2:*`, `ssm:GetParameter`, and `kms:*` to execute all curriculum labs without permission denials.

---

## 🔍 Step 3: Universal Pre-Flight Verification Check

Run this automated validation script in your Ubuntu terminal to verify that your AWS CLI, authentication, region connectivity, and Default VPC are functioning properly:

```bash
echo "=== 1. Checking AWS CLI Version ==="
aws --version

echo "=== 2. Verifying Authenticated IAM Identity ==="
aws sts get-caller-identity --output table

echo "=== 3. Verifying EC2 Regional Connectivity (us-east-1) ==="
VPC_CHECK=$(aws ec2 describe-vpcs \
  --region us-east-1 \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

if [ -n "$VPC_CHECK" ] && [ "$VPC_CHECK" != "None" ]; then
  echo "[SUCCESS] Pre-flight checks passed! Default VPC verified: ${VPC_CHECK}"
else
  echo "[WARNING] No default VPC found in us-east-1. Please ensure you have a VPC available before launching instances."
fi
```

### Expected Output:
```text
=== 1. Checking AWS CLI Version ===
aws-cli/2.x.x Python/3.x.x Linux/6.x...
=== 2. Verifying Authenticated IAM Identity ===
------------------------------------------------------------------
|                       GetCallerIdentity                        |
+--------------+----------------------------------+--------------+
|   Account    |               Arn                |    UserId    |
+--------------+----------------------------------+--------------+
| 123456789012 | arn:aws:iam::123456789012:user/... | AIDA...      |
+--------------+----------------------------------+--------------+
=== 3. Verifying EC2 Regional Connectivity (us-east-1) ===
[SUCCESS] Pre-flight checks passed! Default VPC verified: vpc-0a1b2c3d4e5f
```

---

## 🚀 Next Steps

Your Ubuntu environment is now configured and verified!
👉 **[Proceed to Module 01: EC2 Fundamentals & Lifecycle](../module-01-fundamentals-and-lifecycle/README.md)**
