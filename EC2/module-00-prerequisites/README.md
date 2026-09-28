<div align="center">

# ⚙️ Module 00: Global Prerequisites & AWS CLI Environment Setup

![AWS](https://img.shields.io/badge/☁️_Platform-Amazon_Web_Services-FF9900?style=flat-square)
![OS](https://img.shields.io/badge/🐧_Linux-Ubuntu_22.04%2F24.04-E95420?style=flat-square)
![OS](https://img.shields.io/badge/🍎_macOS-Intel_%26_Apple_Silicon-000000?style=flat-square)
![CLI](https://img.shields.io/badge/💻_Execution-AWS_CLI_v2-0969da?style=flat-square)
![Curriculum](https://img.shields.io/badge/🖥️_EC2_Mastery-28_Labs_Baseline-2da44e?style=flat-square)

[🏠 EC2 Index](../README.md) &nbsp;•&nbsp; [🚀 Start Module 01: Foundations](../module-01-fundamentals-and-lifecycle/README.md) &nbsp;•&nbsp; [🎮 Live Interactive Simulator](https://cyber-cloud-security.github.io/aws-labs/)

</div>

---

## 📌 Overview & Purpose

This module establishes the **foundational workstation and cloud environment** required to successfully execute all 28 hands-on labs in the Amazon EC2 curriculum. 

By completing this one-time setup, you ensure:
1. The **official AWS CLI v2** is installed and optimized for your operating system (**Ubuntu** or **macOS**).
2. Terminal pagination issues (`AWS_PAGER=""`) are eliminated to prevent interactive commands and scripts from hanging.
3. Your IAM credentials, default region (`us-east-1`), and permissions are verified through an automated pre-flight health check.
4. *(Optional)* A clean, isolated local **Ubuntu 24.04 LTS VM** can be launched in seconds using Canonical Multipass.

---

## 🛠️ Step 0.1: Install AWS CLI v2 & Required Tools

Choose your operating system below:

<details open>
<summary>🐧 <b>Ubuntu / Debian (Multipass, WSL2, Local Workstation, or Cloud Bastion)</b></summary>

```bash
# 1. Update package repository and install essential utilities
sudo apt update && sudo apt install -y curl unzip jq

# 2. Download and install AWS CLI v2 (auto-detects x86_64 vs ARM64 / Apple Silicon VMs)
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi

unzip -q awscliv2.zip
sudo ./aws/install --update
rm -rf aws awscliv2.zip

# 3. Verify installation
aws --version
```
</details>

<details>
<summary>🍎 <b>macOS (Intel & Apple Silicon M1 / M2 / M3 / M4)</b></summary>

```bash
# Option A: Install via Homebrew (Recommended)
brew install awscli jq

# Option B: Install via Official macOS PKG Installer
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
rm -f AWSCLIV2.pkg

# Verify installation
aws --version
```
</details>

---

## 🔑 Step 0.2: Configure AWS Credentials & Terminal Optimization

### 1. Disable AWS CLI Terminal Paging
By default, AWS CLI v2 pipes output into `less`. In automated scripts or terminal sessions, this causes commands to hang waiting for user keypresses (`q` / `Return`).

```bash
export AWS_PAGER=""
echo 'export AWS_PAGER=""' >> ~/.bashrc 2>/dev/null || true
echo 'export AWS_PAGER=""' >> ~/.zshrc 2>/dev/null || true
```

### 2. Configure Your AWS Credentials
```bash
aws configure
```

When prompted, enter your IAM access credentials:
- **AWS Access Key ID**: `YOUR_ACCESS_KEY_ID`
- **AWS Secret Access Key**: `YOUR_SECRET_ACCESS_KEY`
- **Default region name**: `us-east-1`
- **Default output format**: `json`

> [!TIP]
> **IAM Permissions**: Ensure your IAM user or role has the `AdministratorAccess` policy or permissions for `ec2:*`, `ssm:GetParameter`, and `kms:*` to perform resource provisioning across the curriculum.

---

## 🔍 Step 0.3: Universal Pre-Flight Verification Check

Run this automated validation script in your terminal to verify that your AWS CLI, authentication, region connectivity, and Default VPC are functioning properly:

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
aws-cli/2.x.x Python/3.x.x Linux/Darwin...
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

## 💻 Step 0.4 (Optional): Launch an Isolated Ubuntu 24.04 VM via Multipass

If you are running on macOS or Windows and want a clean, dedicated Linux sandbox for all labs:

```bash
# 1. Install Multipass (macOS via Homebrew)
brew install --cask multipass

# 2. Launch a lightweight Ubuntu 24.04 LTS VM
multipass launch 24.04 --name dev-ubuntu --cpus 2 --memory 4G --disk 20G

# 3. Enter the VM shell
multipass shell dev-ubuntu
```

---

## 🚀 Next Steps

With your environment configured and verified:
👉 **[Proceed to Module 01: EC2 Fundamentals & Lifecycle](../module-01-fundamentals-and-lifecycle/README.md)**
