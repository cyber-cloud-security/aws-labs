<div align="center">

# 🔬 Lab 1.1: Launching & Bootstrapping EC2 (x86_64 vs Graviton ARM64)

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 01](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-15_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Beginner_to_Intermediate-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-01_%E2%80%94_Foundations-fd8c73?style=flat-square)

<br/>

<a href="https://cyber-cloud-security.github.io/aws-labs/?lab=lab-01-launch-and-bootstrap" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/🎮_Live_Simulation-Launch_Interactive_Lab-2563eb?style=for-the-badge" alt="Interactive Simulation"></a>

**⬅️ Previous Lab (Start)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-01-fundamentals-and-lifecycle/lab-02-lifecycle-and-hibernation/README.md)**

</div>

---

## 📌 Lab Objectives

- [x] Understand the difference between x86_64 (`Intel/AMD`) and ARM64 (`AWS Graviton`) EC2 architectures.
- [x] Launch an EC2 instance programmatically using the AWS CLI.
- [x] Bootstrap the instance with automated **User Data** (`cloud-init`) to install Nginx and query instance metadata.
- [x] Configure Security Groups with least-privilege ingress (HTTP port 80).
- [x] Query instance metadata using **IMDSv2** (Instance Metadata Service Version 2).

---

## 🏗️ Architecture Diagram

![Architecture Diagram](./images/architecture-lab-01.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart LR
    User["DevOps Engineer (Local / CLI)"]
    subgraph VPC["Default VPC"]
        subgraph PublicSubnet["Public Subnet"]
            IGW["Internet Gateway"]
            SG["Security Group (Port 80 Allowed)"]
            EC2["EC2 Instance (t4g.micro or t3.micro)\nNginx Web Server"]
            IMDS["IMDSv2 (169.254.169.254)"]
        end
    end

    User -->|HTTP GET :80| IGW
    IGW -->|Route| SG
    SG -->|Forward| EC2
    EC2 -->|Bootstrap: Query Token & Metadata| IMDS
```

</details>

---

## 💡 Key Architectural Concepts

1. **Instance Families & Generations**:
   - `t3.micro`: 2 vCPUs (Intel Xeon / AMD EPYC), x86_64, Burstable compute credits.
   - `t4g.micro`: 2 vCPUs (AWS Graviton2), ARM64 architecture, up to 40% better price/performance. Requires ARM64-compiled AMIs and binaries.
2. **User Data & cloud-init**:
   - Executes as `root` once during the first boot lifecycle of an EC2 instance.
   - Output logged to `/var/log/cloud-init-output.log` and `/var/log/user-data.log`.
3. **IMDSv2 (Session-Oriented Metadata)**:
   - Uses HTTP PUT requests with a TTL header to acquire a signed token, preventing Server-Side Request Forgery (SSRF) vulnerabilities found in legacy IMDSv1.

---

## ⏱️ Prerequisites & Cost

> [!TIP]
> **AWS Free Tier & Cost Guardrail**
> - **AWS Free Tier Eligible**: Yes (`t2.micro`, `t3.micro`, or `t4g.micro` free tier allocations).
> - **Estimated Duration**: 15 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Discover Available Default VPC & Subnet

1. Resolve the default region and query VPC and subnet identifiers:
```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)
export SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[0].SubnetId" \
  --output text)
```

2. Confirm resolved network identifiers:
```bash
echo "Target VPC: ${VPC_ID}"
echo "Target Subnet: ${SUBNET_ID}"
```

---

### Step 2: Create a Security Group for HTTP Access

1. Create the security group:
```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name "ec2-master-lab-web-sg" \
  --description "Allow inbound HTTP traffic for Lab 1.1" \
  --vpc-id "${VPC_ID}" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=web-sg}]" \
  --query "GroupId" --output text)
```

2. Authorize inbound HTTP traffic on Port 80:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id "${SG_ID}" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

3. Confirm created security group:
```bash
echo "Created Security Group: ${SG_ID}"
```

---

### Step 3: Fetch the Latest Amazon Linux 2023 AMI

Choose either **ARM64 (Graviton)** or **x86_64**:

#### Option A: AWS Graviton (ARM64 - Recommended)
1. Query the latest official ARM64 AMI parameter:
```bash
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64" \
  --query "Parameter.Value" --output text)
export INSTANCE_TYPE="t4g.micro"
```

2. Confirm resolved ARM64 AMI:
```bash
echo "Resolved ARM64 AMI: ${AMI_ID}"
```

#### Option B: Intel/AMD (x86_64)
1. Query the latest official x86_64 AMI parameter:
```bash
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)
export INSTANCE_TYPE="t3.micro"
```

2. Confirm resolved x86_64 AMI:
```bash
echo "Resolved x86_64 AMI: ${AMI_ID}"
```

---

### Step 4: Create User Data Bootstrap Script & Launch Instance

1. Create the `userdata.sh` script to install Nginx and query IMDSv2 metadata:
```bash
cat << 'EOF' > userdata.sh
#!/bin/bash
dnf update -y
dnf install -y nginx

# Query IMDSv2 metadata
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
ARCH=$(uname -m)

cat <<HTML > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html>
<head><title>AWS EC2 Master Labs - Lab 1.1</title></head>
<body style="font-family: Arial; padding: 30px; background: #0f172a; color: #f8fafc;">
  <h1>AWS EC2 Bootstrap Verified</h1>
  <p><b>Instance ID:</b> ${INSTANCE_ID}</p>
  <p><b>Availability Zone:</b> ${AZ}</p>
  <p><b>Architecture:</b> ${ARCH}</p>
</body>
</html>
HTML

systemctl enable --now nginx
EOF
```

2. Launch the EC2 instance with user data and enforced IMDSv2:
```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --subnet-id "${SUBNET_ID}" \
  --security-group-ids "${SG_ID}" \
  --user-data file://userdata.sh \
  --metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=1" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=ec2-lab-01-web}]" \
  --query "Instances[0].InstanceId" --output text)
```

3. Confirm launched instance ID:
```bash
echo "Launched Instance ID: ${INSTANCE_ID}"
```

4. Wait for the instance to reach `running` state:
```bash
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
echo "[SUCCESS] Instance ${INSTANCE_ID} is now RUNNING."
```

---

## 🔍 Verification & Testing

### 1. Fetch Public IP
```bash
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
```

Verify the retrieved IP address:
```bash
echo "Instance Public IP: ${PUBLIC_IP}"
```

### 2. Query the Web Server
Wait 30–60 seconds for `cloud-init` to finish package installation, then run:
```bash
curl -i "http://${PUBLIC_IP}"
```
You should receive an HTTP `200 OK` response with an HTML document displaying your instance ID, availability zone, and CPU architecture.

### 3. Inspect the System Log (Console Output)
To see the bootstrap logs directly from AWS without SSH:
```bash
aws ec2 get-console-output --instance-id "${INSTANCE_ID}" --query "Output" --output text | tail -n 30
```

---

## 🧹 Teardown & Clean-up

> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

1. Terminate the EC2 instance and wait for termination:
```bash
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
```

2. Delete the Security Group:
```bash
aws ec2 delete-security-group --group-id "${SG_ID}"
```

3. Clean up local temporary files:
```bash
rm -f userdata.sh
```

4. Confirm cleanup:
```bash
echo "[SUCCESS] Lab 1.1 clean-up completed successfully."
```

---

<div align="center">

**⬅️ Previous Lab (Start)** &nbsp;•&nbsp; **[⬆️ Back to Module 01](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-01-fundamentals-and-lifecycle/lab-02-lifecycle-and-hibernation/README.md)**

</div>
