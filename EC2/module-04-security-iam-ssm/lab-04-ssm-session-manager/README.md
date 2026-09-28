<div align="center">

# 🔬 Lab 4.4: Zero-SSH Access via AWS Systems Manager (SSM) Session Manager

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 04](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-20_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate_to_Advanced-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-04_%E2%80%94_Security-fd8c73?style=flat-square) ![Theme](https://img.shields.io/badge/🎨_Theme-GitHub_Dark_Dimmed-22272e?style=flat-square)

**[⬅️ Previous Lab](../../module-04-security-iam-ssm/lab-03-imdsv2-hardening/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-05-ha-asg-alb/lab-01-launch-templates/README.md)**


[![Interactive Simulator](https://img.shields.io/badge/🎮_Live_Simulation-Launch_Interactive_Lab-2563eb?style=for-the-badge)](https://cyber-cloud-security.github.io/aws-labs/?lab=lab-04-ssm-session-manager)

</div>

---

## 📌 Lab Objectives

- [x] Implement the modern **"Zero-SSH / Bastion-less" Enterprise Architecture**:
  - Close Inbound Port 22 in all Security Groups.
  - Terminate costly Bastion Jump Hosts.
  - Eliminate SSH key generation, distribution, and key-rotation overhead.
- [x] Attach the `AmazonSSMManagedInstanceCore` managed policy to an EC2 instance profile.
- [x] Establish encrypted interactive terminal sessions directly through the AWS CLI using `aws ssm start-session`.
- [x] Configure **SSM Port Forwarding** to tunnel local workstation ports securely to private EC2 instances.

---

## 🏗️ Architecture Diagram

![Architecture Diagram](./images/architecture-lab-04.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart LR
    subgraph AdminWorkstation["Developer / Admin Workstation"]
        LocalCLI["AWS CLI (aws ssm start-session)"]
        LocalBrowser["Local Browser (http://localhost:8080)"]
    end

    subgraph AWSControlPlane["AWS Systems Manager Service"]
        SSMEndpoint["SSM Cloud Endpoints\n(Encrypted HTTPS / TLS 1.3)"]
    end

    subgraph PrivateVPC["Private Subnet (No Public IP / Port 22 CLOSED)"]
        SG["Security Group\nInbound: ZERO OPEN PORTS\nOutbound: HTTPS 443"]
        EC2["Private EC2 Instance\n(SSM Agent Running)"]
        App["Internal Web Service\n(:80)"]

        SG --- EC2
        EC2 --- App
    end

    LocalCLI <-->|TLS Websocket Tunnel| SSMEndpoint
    LocalBrowser <-->|Tunnel via LocalCLI| LocalCLI
    EC2 -->|Outbound HTTPS Long-Poll Connection| SSMEndpoint
```

</details>

---

## 💡 Key Architectural Concepts

1. **How Session Manager Works**:
   - The instance's open-source `amazon-ssm-agent` establishes an **outbound HTTPS (port 443)** connection to AWS Systems Manager.
   - **No inbound ports need to be open in your Security Group!** You can completely lock down ingress (`0` inbound rules).
2. **Enterprise Audit & Compliance**:
   - Every keystroke, terminal session, and command executed can be automatically encrypted and streamed to **Amazon CloudWatch Logs** or **AWS S3** for audit compliance.
   - Access control is governed by AWS IAM rather than Linux POSIX user accounts.

---

## ⏱️ Prerequisites & Cost

> [!TIP]
> **AWS Free Tier & Cost Guardrail**
> - **AWS Free Tier Eligible**: Yes (`t3.micro`). Session Manager itself is completely free of charge.
> - **Estimated Duration**: 20 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Create IAM Role for SSM Session Manager

1. Set environment variables:
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

2. Create the EC2 assume role trust policy:
```bash
cat << 'JSON' > ssm-trust.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
```

3. Create the IAM role:
```bash
aws iam create-role \
  --role-name "ec2-ssm-core-role" \
  --assume-role-policy-document file://ssm-trust.json 2>/dev/null || true
```

4. Attach the AWS-managed SSM policy:
```bash
aws iam attach-role-policy \
  --role-name "ec2-ssm-core-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
```

5. Create the instance profile and associate the role:
```bash
aws iam create-instance-profile --instance-profile-name "ec2-ssm-core-profile" 2>/dev/null || true
aws iam add-role-to-instance-profile \
  --instance-profile-name "ec2-ssm-core-profile" \
  --role-name "ec2-ssm-core-role" 2>/dev/null || true
sleep 10
```

### Step 2: Create a Security Group with ZERO Inbound Rules

1. Create a fully locked-down security group:
```bash
LOCKED_SG_ID=$(aws ec2 create-security-group \
  --group-name "sg-locked-down" \
  --description "Zero inbound ports allowed" \
  --vpc-id "${VPC_ID}" \
  --query "GroupId" --output text)
```

2. Confirm creation:
```bash
echo "[SUCCESS] Created locked Security Group: ${LOCKED_SG_ID}"
```

### Step 3: Launch Instance with SSM Profile and Locked SG

1. Fetch latest Amazon Linux 2023 AMI:
```bash
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)
```

2. Launch the zero-SSH instance with Nginx via User Data:
```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_ID}" \
  --security-group-ids "${LOCKED_SG_ID}" \
  --iam-instance-profile "Name=ec2-ssm-core-profile" \
  --user-data "#!/bin/bash
dnf install -y nginx
echo 'Private internal portal reachable only via SSM Port Forwarding' > /usr/share/nginx/html/index.html
systemctl start nginx" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=zero-ssh-host}]" \
  --query "Instances[0].InstanceId" --output text)
```

3. Wait for instance to enter running state:
```bash
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
echo "[INFO] Waiting 60 seconds for SSM Agent to register with AWS..."
sleep 60
```

---

## 🔍 Verification & Testing

### 1. Start an Interactive Terminal Session
From your local terminal, initiate an interactive shell session:
```bash
aws ssm start-session --target "${INSTANCE_ID}"
```
You are immediately dropped into a bash prompt as `ssm-user`. Exit the session by typing `exit`.

### 2. Tunnel Private Web Traffic via SSM Port Forwarding
Without opening any firewall ports or assigning a public IP, tunnel the instance's private port 80 to your local workstation port 8080:
```bash
aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --document-name "AWS-StartPortForwardingSession" \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'
```

In another terminal window or your browser, test the tunnel:
```bash
curl http://localhost:8080
```
**Output**: `Private internal portal reachable only via SSM Port Forwarding`

### 3. SSH Over SSM Proxy (Optional)
If your legacy tooling requires native SSH/SCP/rsync, configure `~/.ssh/config`:
```text
host i-* mi-*
    ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
```
You can then run `ssh ec2-user@<instance-id>` transparently through the encrypted SSM tunnel.

---

## 🧹 Teardown & Clean-up

> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

1. Terminate the instance:
```bash
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
```

2. Delete the locked security group:
```bash
aws ec2 delete-security-group --group-id "${LOCKED_SG_ID}"
```

3. Detach policies and delete IAM instance profile and role:
```bash
aws iam remove-role-from-instance-profile \
  --instance-profile-name "ec2-ssm-core-profile" \
  --role-name "ec2-ssm-core-role"
aws iam delete-instance-profile --instance-profile-name "ec2-ssm-core-profile"
aws iam detach-role-policy \
  --role-name "ec2-ssm-core-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
aws iam delete-role --role-name "ec2-ssm-core-role"
rm -f ssm-trust.json
```

4. Confirm clean-up completion:
```bash
echo "[SUCCESS] Lab 4.4 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-04-security-iam-ssm/lab-03-imdsv2-hardening/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 04](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-05-ha-asg-alb/lab-01-launch-templates/README.md)**

</div>
