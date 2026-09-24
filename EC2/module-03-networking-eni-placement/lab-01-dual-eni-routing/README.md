<div align="center">

# 🔬 Lab 3.1: Dual Elastic Network Interfaces (ENI) & Linux Policy Routing

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 03](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-20_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate_to_Advanced-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-03_%E2%80%94_Networking-fd8c73?style=flat-square)

**[⬅️ Previous Lab](../../module-02-storage-ebs-ephemeral-efs/lab-04-efs-shared-filesystem/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-03-networking-eni-placement/lab-02-elastic-ips-ha/README.md)**

</div>

---

## 📌 Lab Objectives

- [x] Provision and attach a secondary **Elastic Network Interface (ENI)** to an EC2 instance across two subnets.
- [x] Understand how primary (`eth0`) and secondary (`eth1`) interfaces interact.
- [x] Diagnose and resolve the classic Linux **asymmetric routing problem** (where return packets exit the wrong interface and get dropped).
- [x] Implement Linux policy-based routing (`ip rule`, `ip route`) to ensure traffic responding to `eth1` exits through `eth1`'s gateway.

---

## 🏗️ Architecture Diagram

![Architecture Diagram](./images/architecture-lab-01.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart TD
    Client["External Client / Admin"]

    subgraph VPC["AWS VPC (172.31.0.0/16)"]
        subgraph SubnetA["Public Subnet A (172.31.1.0/24)"]
            ENI0["Primary ENI (eth0)\nIP: 172.31.1.50\nDefault Gateway: 172.31.1.1"]
        end

        subgraph SubnetB["Management Subnet B (172.31.2.0/24)"]
            ENI1["Secondary ENI (eth1)\nIP: 172.31.2.99\nGateway: 172.31.2.1"]
        end

        subgraph Host["Dual-Homed EC2 Instance"]
            LinuxKernel["Linux Kernel Routing Engine"]
            ENI0 --- LinuxKernel
            ENI1 --- LinuxKernel
        end
    end

    Client -->|Inbound Request to eth1| ENI1
    ENI1 --> LinuxKernel
    LinuxKernel -.->|Broken: exits default gateway via eth0!| ENI0
    LinuxKernel ==>|Fixed with Policy Routing: exits via eth1| ENI1
```

</details>

---

## 💡 Key Architectural Concepts

1. **Why Multiple ENIs?**:
   - Creating dual-homed network security appliances (firewalls, reverse proxies, IDS/IPS).
   - Isolating management traffic (SSH, telemetry) from production data plane traffic.
2. **The Asymmetric Routing Problem**:
   - Linux by default maintains only **one default gateway** (bound to `eth0`).
   - When a packet arrives on `eth1`, the application receives it, but the OS routing table sends the response packet out through `eth0`'s gateway.
   - The client's firewall or intermediate stateful NAT drops this response because the SYN-ACK originates from an unexpected IP address (or Reverse Path Filtering `rp_filter` drops it).

---

## ⏱️ Prerequisites & Cost

> [!TIP]
> **AWS Free Tier & Cost Guardrail**
> - **AWS Free Tier Eligible**: Yes (`t3.micro`).
> - **Estimated Duration**: 20 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Launch EC2 Instance with Primary ENI
```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

SUBNET_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[0].SubnetId" \
  --output text)
SUBNET_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[1].SubnetId" \
  --output text)

AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_1}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=dual-eni-host}]" \
  --query "Instances[0].InstanceId" --output text)

echo "Waiting for instance ${INSTANCE_ID} to run..."
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
```

### Step 2: Create and Attach Secondary ENI
```bash
# Get Security Group
SG_ID=$(aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
  --output text)

# Create secondary ENI in Subnet 2
SECONDARY_ENI_ID=$(aws ec2 create-network-interface \
  --subnet-id "${SUBNET_2}" \
  --description "Secondary ENI for management traffic" \
  --groups "${SG_ID}" \
  --tag-specifications "ResourceType=network-interface,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=secondary-eni}]" \
  --query "NetworkInterface.NetworkInterfaceId" --output text)

echo "Created Secondary ENI: ${SECONDARY_ENI_ID}"

# Attach ENI to Device Index 1 (eth1)
ATTACHMENT_ID=$(aws ec2 attach-network-interface \
  --network-interface-id "${SECONDARY_ENI_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --device-index 1 \
  --query "AttachmentId" --output text)

echo "Attached ENI (Device Index 1): ${ATTACHMENT_ID}"
```

---

## 🔍 Verification & Configuring Policy Routing

### 1. Inspect Interfaces Inside the Guest OS
Connect to the instance via Session Manager or SSH:
```bash
# Inspect network links
ip link show
```
Notice both `eth0` and `eth1` are present, but `eth1` has no default route.

Fetch IP and gateway of `eth1`:
```bash
IP2=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
GATEWAY2=$(ip route | grep "default via" | awk '{print $3}' | sed 's/\.[0-9]*$/.1/')
```

### 2. Configure Custom Routing Table for `eth1`
Create table `100` and rule so all packets with source IP of `eth1` use table `100`:
```bash
# Add default route for eth1 in table 100
sudo ip route add default via ${GATEWAY2} dev eth1 table 100

# Add rule: any packet originating from IP2 must consult table 100
sudo ip rule add from ${IP2} lookup 100

# Verify rule
ip rule show
# Output shows:
# 32765: from 172.31.x.x lookup 100
```

### 3. Verify Ping / Curl Responses
Ping both interfaces from another host in the VPC or run test curl commands. Both interfaces now respond cleanly with zero dropped packets.

---

## 📘 Deep-Dive Command & Flag Reference

> [!TIP]
> **Line-by-Line Production Analysis**: Every command executed in this lab is dissected below, explaining each CLI flag, JMESPath query, Linux kernel parameter, and why it is critical in production automation.

<details open>
<summary>📘 <b>Command 1: Creating a Secondary Elastic Network Interface (ENI)</b></summary>

```bash
SECONDARY_ENI_ID=$(aws ec2 create-network-interface \
  --subnet-id "${SUBNET_2}" \
  --description "Secondary ENI for management traffic" \
  --groups "${SG_ID}" \
  --tag-specifications "ResourceType=network-interface,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=secondary-eni}]" \
  --query "NetworkInterface.NetworkInterfaceId" --output text)
```

#### 🔍 Parameter & Component Breakdown

- **`aws ec2 create-network-interface`** — Allocates an independent virtual network interface controller (ENI) in the target VPC.

- **`--subnet-id "${SUBNET_2}"`** — Binds the network interface to a completely separate subnet (e.g. Subnet 2 / Management Subnet). This gives the ENI a private IPv4 address natively allocated from Subnet 2's CIDR block.

- **`--groups "${SG_ID}"`** — Attaches a security group directly to the network interface. In AWS, **security groups attach to ENIs, not to instances directly**.

- **`--query "NetworkInterface.NetworkInterfaceId" --output text`** — Extracts the unique identifier (e.g. `eni-0123456789abcdef0`).

> 🏭 **Why This Matters in Production Automation**
> Multi-ENI architectures enable true network segmentation: creating dual-homed appliances (such as load balancers, reverse proxies, and Web Application Firewalls) where one interface (`eth0`) connects to an untrusted public DMZ subnet while the second interface (`eth1`) connects strictly to a protected internal database subnet.

</details>

<details open>
<summary>📘 <b>Command 2: Attaching the Secondary ENI to the Running Instance</b></summary>

```bash
ATTACHMENT_ID=$(aws ec2 attach-network-interface \
  --network-interface-id "${SECONDARY_ENI_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --device-index 1 \
  --query "AttachmentId" --output text)
```

#### 🔍 Parameter & Component Breakdown

- **`aws ec2 attach-network-interface`** — Hot-plugs the secondary network card into the virtual PCIe bus of the running EC2 instance.

- **`--device-index 1`** — **The Interface Enumeration Rule**:
Specifies the PCIe device index:  
  - **`device-index 0`** — Reserved for the primary interface (`eth0`), assigned at launch.
  - **`device-index 1`** — Maps to secondary interface (`eth1`).
Skipping indices (e.g. attaching directly to index 2 without an index 1) will trigger an `InvalidDeviceIndex` error.

- **`--query "AttachmentId" --output text`** — Extracts the attachment handle (e.g. `ela-attach-0abcdef1234567890`), required later for clean detachment.

> 🏭 **Why This Matters in Production Automation**
> Hot-attaching ENIs allows elastic network failover and live network reconfiguration without stopping or rebooting business-critical instances.

</details>

<details open>
<summary>📘 <b>Command 3: Configuring Linux Policy Routing to Fix Asymmetric Routing</b></summary>

```bash
# 1. Add default gateway for eth1 inside custom routing table 100
sudo ip route add default via ${GATEWAY2} dev eth1 table 100

# 2. Add rule routing all packets originating from IP2 via table 100
sudo ip rule add from ${IP2} lookup 100
```

#### 🔍 Parameter & Component Breakdown

- **The Problem (Asymmetric Routing)** — By default, the Linux kernel maintains a single global routing table with only **one default gateway** (pointing out `eth0`).
When an external client sends a request to `eth1` (`IP2`):  
1. The packet enters via `eth1`.  
2. The application receives and processes the request.  
3. When the kernel prepares the return SYN-ACK packet, it checks the default routing table and routes the response **out of `eth0`**!  
4. The client's firewall drops this packet because the connection was initiated with `eth1`'s IP, not `eth0`'s IP (or Linux Reverse Path Filtering `rp_filter` drops it internally).

- **`sudo ip route add default via ${GATEWAY2} dev eth1 table 100`** — Creates an isolated, secondary routing table named `100`. Inside table 100, the default gateway is set explicitly to `eth1`'s subnet router.

- **`sudo ip rule add from ${IP2} lookup 100`** — Instructs the Linux Policy Routing Engine: If any outgoing packet has a **source IP equal to `IP2`** (the secondary interface), force the kernel to evaluate routing table `100` instead of the global default table.

> 🏭 **Why This Matters in Production Automation**
> Failing to configure policy-based routing on dual-homed Linux instances causes secondary interfaces to silently drop incoming connections. This command establishes source-based policy routing, guaranteeing that all response traffic exits through the exact same network interface that received the inbound request.

</details>

---

## 🧹 Teardown & Clean-up


> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

```bash
# 1. Detach secondary ENI
aws ec2 detach-network-interface --attachment-id "${ATTACHMENT_ID}" --force
sleep 5

# 2. Delete secondary ENI
aws ec2 delete-network-interface --network-interface-id "${SECONDARY_ENI_ID}"

# 3. Terminate instance
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"

echo "Lab 3.1 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-02-storage-ebs-ephemeral-efs/lab-04-efs-shared-filesystem/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 03](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-03-networking-eni-placement/lab-02-elastic-ips-ha/README.md)**

</div>
