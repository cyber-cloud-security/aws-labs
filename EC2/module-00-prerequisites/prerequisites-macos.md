<div align="center">

# 🍎 macOS: AWS CLI v2 & Environment Setup

![OS](https://img.shields.io/badge/🍎_OS-macOS_Sequoia%20%7C%20Sonoma%20%7C%20Ventura-000000?style=flat-square)
![Arch](https://img.shields.io/badge/⚙️_Chip-Apple_Silicon_(M1--M4)_%26_Intel-0969da?style=flat-square)
![CLI](https://img.shields.io/badge/💻_CLI-AWS_CLI_v2-FF9900?style=flat-square)
![Pkg](https://img.shields.io/badge/📦_Manager-Homebrew%20%7C%20Official_PKG-2da44e?style=flat-square)

[⬅️ Back to Module 00 Hub](./README.md) &nbsp;•&nbsp; [🐧 Ubuntu Setup Guide](./prerequisites-ubuntu.md) &nbsp;•&nbsp; [🚀 Start Module 01](../module-01-fundamentals-and-lifecycle/README.md)

</div>

---

## 📌 Overview

This guide provides step-by-step instructions to configure **macOS** (both Apple Silicon `M1`/`M2`/`M3`/`M4` and Intel Macs) for executing all 28 labs in the AWS EC2 hands-on curriculum.

---

## 🛠️ Step 1: Install AWS CLI v2 & Helper Tools

Choose either **Homebrew (Recommended)** or the **Official Apple PKG Installer**:

### Option A: Install via Homebrew (Recommended)
```bash
# 1. Install AWS CLI v2 and jq via Homebrew
brew install awscli jq

# 2. Verify installation
aws --version
```

### Option B: Install via Official macOS PKG Installer
```bash
# 1. Download official AWS installer package
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

# 2. Install to system
sudo installer -pkg AWSCLIV2.pkg -target /
rm -f AWSCLIV2.pkg

# 3. Verify installation
aws --version
```

---

## ⚙️ Step 2: Configure Terminal Optimization & AWS Credentials

### 1. Disable AWS CLI Terminal Paging
By default, AWS CLI v2 pipes output into `less`. In macOS Terminal/iTerm2 zsh sessions, this causes commands to hang waiting for user keypresses (`q` or `Return`).

```bash
# Disable pager for current and future zsh / bash sessions
export AWS_PAGER=""
echo 'export AWS_PAGER=""' >> ~/.zshrc 2>/dev/null || true
echo 'export AWS_PAGER=""' >> ~/.bashrc 2>/dev/null || true
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

Run this automated validation script in your macOS terminal to verify that your AWS CLI, authentication, region connectivity, and Default VPC are functioning properly:

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
  echo "✅ Pre-flight checks passed! Default VPC verified: ${VPC_CHECK}"
else
  echo "⚠️ Warning: No default VPC found in us-east-1. Please ensure you have a VPC available before launching instances."
fi
```

### Expected Output:
```text
=== 1. Checking AWS CLI Version ===
aws-cli/2.x.x Python/3.x.x Darwin/...
=== 2. Verifying Authenticated IAM Identity ===
------------------------------------------------------------------
|                       GetCallerIdentity                        |
+--------------+----------------------------------+--------------+
|   Account    |               Arn                |    UserId    |
+--------------+----------------------------------+--------------+
| 123456789012 | arn:aws:iam::123456789012:user/... | AIDA...      |
+--------------+----------------------------------+--------------+
=== 3. Verifying EC2 Regional Connectivity (us-east-1) ===
✅ Pre-flight checks passed! Default VPC verified: vpc-0a1b2c3d4e5f
```

---

## 🚀 Next Steps

Your macOS environment is now configured and verified!
👉 **[Proceed to Module 01: EC2 Fundamentals & Lifecycle](../module-01-fundamentals-and-lifecycle/README.md)**
