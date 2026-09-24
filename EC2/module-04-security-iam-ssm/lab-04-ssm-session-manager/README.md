<div align="center">

# 🔬 Lab 4.4: Zero-SSH Access via AWS Systems Manager (SSM) Session Manager

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 04](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-20_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate_to_Advanced-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-04_%E2%80%94_Security-fd8c73?style=flat-square)

**[⬅️ Previous Lab](../../module-04-security-iam-ssm/lab-03-imdsv2-hardening/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-05-ha-asg-alb/lab-01-launch-templates/README.md)**

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

# 1. Create Trust Policy
cat <<JSON > ssm-trust.json
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

aws iam create-role \
  --role-name "ec2-ssm-core-role" \
  --assume-role-policy-document file://ssm-trust.json 2>/dev/null || true

# 2. Attach AWS-managed policy
aws iam attach-role-policy \
  --role-name "ec2-ssm-core-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# 3. Create Instance Profile
aws iam create-instance-profile --instance-profile-name "ec2-ssm-core-profile" 2>/dev/null || true
aws iam add-role-to-instance-profile \
  --instance-profile-name "ec2-ssm-core-profile" \
  --role-name "ec2-ssm-core-role" 2>/dev/null || true

sleep 10
```

### Step 2: Create a Security Group with ZERO Inbound Rules
```bash
LOCKED_SG_ID=$(aws ec2 create-security-group \
  --group-name "sg-locked-down" \
  --description "Zero inbound ports allowed" \
  --vpc-id "${VPC_ID}" \
  --query "GroupId" --output text)

echo "Created locked Security Group: ${LOCKED_SG_ID}"
```

### Step 3: Launch Instance with SSM Profile and Locked SG
```bash
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

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

echo "Launched zero-SSH host: ${INSTANCE_ID}"
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"

echo "Waiting 60 seconds for SSM Agent to register with AWS..."
sleep 60
```

---

## 🔍 Verification & Testing

### 1. Start an Interactive Terminal Session
From your local terminal, initiate an interactive shell session:
```bash
aws ssm start-session --target "${INSTANCE_ID}"
```
You are immediately dropped into a bash prompt as `ssm-user`:
```bash
# sh-5.2$ whoami
# ssm-user
# sh-5.2$ sudo su -
# [root@ip-172-31-x-x ~]#
```
Exit the session by typing `exit`.

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
You can then run `ssh ec2-user@<instance-id>` transparently through the encrypted SSM tunnel!

---

## 📘 Deep-Dive Command & Flag Reference

> [!TIP]
> **Line-by-Line Production Analysis**: Every command executed in this lab is dissected below, explaining each CLI flag, JMESPath query, Linux kernel parameter, and why it is critical in production automation.

<details open>
<summary>📘 <b>Command 1: Attaching the `AmazonSSMManagedInstanceCore` Policy</b></summary>

```bash
aws iam attach-role-policy \
  --role-name "ec2-ssm-core-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
```

#### 🔍 Parameter & Component Breakdown

- **`AmazonSSMManagedInstanceCore`** — The foundational AWS-managed policy required for any EC2 instance to communicate with the AWS Systems Manager (SSM) control plane.

- Actions Granted:
  - **`ssm:UpdateInstanceInformation`** — Allows the local `amazon-ssm-agent` daemon to send heartbeats and register its OS platform and IP with the AWS SSM inventory.
  - `ssmmessages:CreateControlChannel` & `ssmmessages:OpenControlChannel`: Allows establishing real-time multiplexed WebSocket communication channels between AWS and the instance.
  - **`ec2messages:*`** — Enables secure command routing and logging.

> 🏭 **Why This Matters in Production Automation**
> Without this specific managed policy, the SSM Agent on the instance will launch, attempt to contact `ssm.<region>.amazonaws.com`, receive an `AccessDeniedException`, and fail to register, leaving the instance invisible in the AWS Systems Manager console.

</details>

<details open>
<summary>📘 <b>Command 2: Locking Down the Security Group (ZERO Inbound Rules)</b></summary>

```bash
LOCKED_SG_ID=$(aws ec2 create-security-group \
  --group-name "sg-locked-down" \
  --description "Zero inbound ports allowed" \
  --vpc-id "${VPC_ID}" \
  --query "GroupId" --output text)
```

#### 🔍 Parameter & Component Breakdown

- **The Zero-Inbound Architecture** — Notice that **no `authorize-security-group-ingress` command is executed**. The security group contains zero inbound rules. Port 22 (SSH), Port 3389 (RDP), and all other listening ports are 100% blocked from the network.

- **How Communication Succeeded** — The instance makes an **outbound HTTPS (port 443)** connection to the AWS SSM endpoint. Because AWS security groups are stateful, return communication over this outbound-initiated WebSocket is automatically permitted without opening any inbound ports.

> 🏭 **Why This Matters in Production Automation**
> This command realizes the "Zero-Trust Bastionless Architecture": 1. Completely eliminates costly Bastion/Jump hosts that need patching and maintenance. 2. Eliminates port 22 internet scans and brute-force SSH dictionary attacks. 3. Eliminates the operational nightmare of generating, distributing, and revoking private SSH key pairs (`.pem` files).

</details>

<details open>
<summary>📘 <b>Command 3: Starting an Interactive Shell Session via AWS CLI</b></summary>

```bash
aws ssm start-session --target "${INSTANCE_ID}"
```

#### 🔍 Parameter & Component Breakdown

- **`aws ssm start-session`** — Invokes the AWS Session Manager Plugin on your local workstation.

- **Technical Connection Workflow** — 1. Local AWS CLI authenticates against IAM using your local AWS credentials.
2. AWS Systems Manager creates an encrypted WebSocket tunnel between your machine and the SSM service.  
3. The instance's `amazon-ssm-agent` connects to the other end of the tunnel.  
4. The agent forks a pseudo-terminal (`pty`) running bash as the `ssm-user` operating system user.  
5. Interactive keystrokes and output stream across the encrypted tunnel with zero inbound ports open.

> 🏭 **Why This Matters in Production Automation**
> All session activity can be governed by IAM policies (e.g. enforcing Multi-Factor Authentication before accessing production instances). Furthermore, every command and terminal output can be logged and audited immutably to **AWS CloudWatch Logs** or **Amazon S3** for compliance audits.

</details>

<details open>
<summary>📘 <b>Command 4: Tunneling Private Web Traffic via SSM Port Forwarding</b></summary>

```bash
aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --document-name "AWS-StartPortForwardingSession" \
  --parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'
```

#### 🔍 Parameter & Component Breakdown

- **`--document-name "AWS-StartPortForwardingSession"`** — Executes a pre-defined AWS Systems Manager Document that configures local port forwarding.

- `--parameters '{"portNumber":["80"],"localPortNumber":["8080"]}'`:
  - **`localPortNumber: 8080`** — Binds a listening TCP socket on your local workstation's `localhost:8080`.
  - **`portNumber: 80`** — Target TCP port running inside the private EC2 instance.
Any packet sent to `http://localhost:8080` in your browser is encapsulated inside the encrypted SSM WebSocket tunnel and delivered to port 80 on the remote private instance.

> 🏭 **Why This Matters in Production Automation**
> Port forwarding eliminates the need for expensive VPNs, Direct Connects, or public load balancers when developers need to access internal administrative portals, microservice APIs, or private databases (PostgreSQL/MySQL on private port 5432/3306).

</details>

---

## 🧹 Teardown & Clean-up


> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

```bash
# 1. Terminate instance
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"

# 2. Delete locked security group
aws ec2 delete-security-group --group-id "${LOCKED_SG_ID}"

# 3. Clean up IAM roles
aws iam remove-role-from-instance-profile \
  --instance-profile-name "ec2-ssm-core-profile" \
  --role-name "ec2-ssm-core-role"
aws iam delete-instance-profile --instance-profile-name "ec2-ssm-core-profile"
aws iam detach-role-policy \
  --role-name "ec2-ssm-core-role" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
aws iam delete-role --role-name "ec2-ssm-core-role"
rm -f ssm-trust.json

echo "Lab 4.4 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-04-security-iam-ssm/lab-03-imdsv2-hardening/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 04](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-05-ha-asg-alb/lab-01-launch-templates/README.md)**

</div>
