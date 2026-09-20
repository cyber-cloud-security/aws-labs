# Step-by-Step Technical Command Explanations: Lab 5.1

This guide breaks down every single command, parameter, and versioning mechanism used in **Lab 5.1: EC2 Launch Templates & Multi-Version Management**.

---

### Command 1: Creating Launch Template Version 1 (x86_64 Baseline)

```bash
TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name "web-app-template" \
  --version-description "Version 1 - x86_64 Baseline" \
  --launch-template-data file://template-v1.json \
  --query "LaunchTemplate.LaunchTemplateId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 create-launch-template`  
Creates an immutable specification template that defines all configuration parameters required to launch an instance (AMI, instance type, storage, user data, network interfaces, tags, IAM profiles).

• `--version-description "Version 1 - x86_64 Baseline"`  
Provides descriptive commit-like metadata explaining what changes or baseline configurations are captured in this revision.

• `--launch-template-data file://template-v1.json`  
Passes the declarative JSON payload containing configuration attributes.  
- Launch Templates completely replace legacy **Launch Configurations**. Unlike Launch Configurations (which were unversioned, requiring you to delete and recreate a new resource for every single change), Launch Templates support unlimited revisions under a single template ID.

──────
#### 2. Why This is Critical in Production Automation

Launch Templates provide the single source of truth for instance definitions across teams. Instead of passing dozens of CLI flags to `run-instances`, automation tools only need to reference the template ID.

---

### Command 2: Creating Launch Template Version 2 (Upgrading to Graviton ARM64)

```bash
aws ec2 create-launch-template-version \
  --launch-template-id "${TEMPLATE_ID}" \
  --version-description "Version 2 - Graviton2 ARM64" \
  --launch-template-data file://template-v2.json
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 create-launch-template-version`  
Appends a new incremented version number (Version 2) to the existing Launch Template container.

• What Changed in Version 2:  
- Replaced `t3.micro` (Intel x86_64) with `t4g.micro` (AWS Graviton2 ARM64).  
- Swapped x86 AMI with the certified ARM64 Amazon Linux 2023 AMI.  
- Injected optimized Graviton User Data.

──────
#### 2. Why This is Critical in Production Automation

Versioning enables GitOps-style infrastructure management. If Version 2 introduces a bad kernel patch or misconfigured user data, engineers can roll back the fleet to Version 1 instantaneously by changing a single pointer.

---

### Command 3: Promoting Version 2 as the Active Default

```bash
aws ec2 modify-launch-template \
  --launch-template-id "${TEMPLATE_ID}" \
  --default-version 2
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 modify-launch-template`  
Updates the top-level pointer metadata of the Launch Template.

• `--default-version 2`  
Every Launch Template maintains a designated `$Default` version and a `$Latest` version:  
- `$Latest`: Automatically matches the highest numbered revision created.  
- `$Default`: The certified, production-ready version used by Auto Scaling Groups unless explicitly overridden. This command promotes Version 2 to `$Default`.

──────
#### 2. Why This is Critical in Production Automation

This allows testing new revisions as canary versions (launching test instances explicitly against `$Latest` or Version 3) without impacting production Auto Scaling Groups tracking `$Default`. Once canary testing passes, a single `modify-launch-template` call updates production.

---

### Command 4: Launching an Instance Using the Default Template Pointer

```bash
TEST_INSTANCE_ID=$(aws ec2 run-instances \
  --launch-template "LaunchTemplateId=${TEMPLATE_ID},Version=\$Default" \
  --subnet-id "${SUBNET_ID}" \
  --query "Instances[0].InstanceId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `--launch-template "LaunchTemplateId=${TEMPLATE_ID},Version=\$Default"`  
- `LaunchTemplateId=...`: References the template container.  
- `Version=\$Default`: **Bash Escaping Rule**: Notice the backslash before `$Default` (`\$Default`). If omitted, bash treats `$Default` as an empty local shell variable, causing the CLI parameter to evaluate to `Version=`, which results in a syntax validation error!

──────
#### 2. Why This is Critical in Production Automation

Decoupling instance deployment commands from specific AMI IDs or instance sizes ensures that CI/CD deployment scripts never need to be rewritten when application architectures or instance generations evolve.
