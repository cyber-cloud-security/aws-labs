<div align="center">

# 🔬 Lab 3.4: EC2 Placement Groups (Cluster, Spread & Partition)

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 03](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-15_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate_to_Advanced-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-03_%E2%80%94_Networking-fd8c73?style=flat-square)

**[⬅️ Previous Lab](../../module-03-networking-eni-placement/lab-03-enhanced-networking-ena/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-04-security-iam-ssm/lab-01-security-groups-nacls/README.md)**


[![Interactive Simulator](https://img.shields.io/badge/🎮_Live_Simulation-Launch_Interactive_Lab-2563eb?style=for-the-badge)](https://cyber-cloud-security.github.io/aws-labs/?lab=lab-04-placement-groups)

</div>

---

## 📌 Lab Objectives

- [x] Understand the physical hardware layout and architectural differences between **Cluster**, **Spread**, and **Partition** Placement Groups.
- [x] Create each placement group type using the AWS CLI.
- [x] Launch instances directly into placement groups and verify their physical rack and partition distribution.
- [x] Know the limitations, quotas, and rules (e.g., max 7 instances per AZ for Spread).

---

## 🏗️ Architecture Diagrams

### 1. Cluster Placement Group (Low Latency / High Throughput)
![Architecture Diagram](./images/architecture-lab-04-1.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart TD
    subgraph Rack["Single Datacenter Rack / High-Speed Spine"]
        I1["EC2 Node 1"]
        I2["EC2 Node 2"]
        I3["EC2 Node 3"]
        I1 <===>|10/25/100 Gbps Sub-ms Latency| I2
        I2 <===>|10/25/100 Gbps Sub-ms Latency| I3
    end
```

</details>

### 2. Spread Placement Group (Strict Hardware Isolation)
![Architecture Diagram](./images/architecture-lab-04-2.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart LR
    subgraph HardwareRack1["Rack 1 (Switch A / Power A)"]
        N1["EC2 Primary DB"]
    end
    subgraph HardwareRack2["Rack 2 (Switch B / Power B)"]
        N2["EC2 Replica DB"]
    end
    subgraph HardwareRack3["Rack 3 (Switch C / Power C)"]
        N3["EC2 Quorum Witness"]
    end
```

</details>

### 3. Partition Placement Group (Distributed Topologies)
![Architecture Diagram](./images/architecture-lab-04-3.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart TD
    subgraph Partition1["Partition 1 (Racks 1-3)"]
        K1["Kafka Broker 1"]
        H1["HDFS DataNode 1"]
    end
    subgraph Partition2["Partition 2 (Racks 4-6)"]
        K2["Kafka Broker 2"]
        H2["HDFS DataNode 2"]
    end
```

</details>

---

## 💡 Strategy Comparison Matrix

| Strategy | Scope | Primary Use Case | Hardware Separation Guarantee | Limits / Caveats |
| :--- | :--- | :--- | :--- | :--- |
| **`cluster`** | Single AZ | HPC, MPI, low-latency microservices, high-bandwidth workloads | None (instances are clustered tightly on same spine) | If launched gradually over time, may fail with `InsufficientInstanceCapacity` |
| **`spread`** | Multi-AZ or Single AZ | High-availability database clusters, quorum arbiters | Guaranteed distinct underlying rack, power, and switch | **Strict limit of 7 running instances per AZ** per group |
| **`partition`** | Multi-AZ or Single AZ | Kafka, Cassandra, Hadoop HDFS, distributed datastores | Partitions do not share racks with each other | Up to 7 partitions per AZ; partitions expose partition number to OS |

---

## ⏱️ Prerequisites & Cost

> [!TIP]
> **AWS Free Tier & Cost Guardrail**
> - **AWS Free Tier Eligible**: Yes (`t3.micro`).
> - **Estimated Duration**: 15 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Create Placement Groups for Each Strategy
```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")

# 1. Cluster Placement Group
aws ec2 create-placement-group \
  --group-name "pg-hpc-cluster" \
  --strategy "cluster" \
  --tag-specifications "ResourceType=placement-group,Tags=[{Key=Project,Value=ec2-master-labs}]"

# 2. Spread Placement Group
aws ec2 create-placement-group \
  --group-name "pg-ha-spread" \
  --strategy "spread" \
  --spread-level "rack" \
  --tag-specifications "ResourceType=placement-group,Tags=[{Key=Project,Value=ec2-master-labs}]"

# 3. Partition Placement Group (3 partitions)
aws ec2 create-placement-group \
  --group-name "pg-kafka-partition" \
  --strategy "partition" \
  --partition-count 3 \
  --tag-specifications "ResourceType=placement-group,Tags=[{Key=Project,Value=ec2-master-labs}]"

echo "Created Cluster, Spread, and Partition placement groups."
```

### Step 2: Launch Instances into the Spread Placement Group
```bash
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[0].SubnetId" \
  --output text)

# Launch 2 instances guaranteed to sit on separate physical server racks
INSTANCE_IDS=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_ID}" \
  --count 2 \
  --placement "GroupName=pg-ha-spread" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=spread-node}]" \
  --query "Instances[*].InstanceId" --output text)

echo "Launched instances in Spread Placement Group: ${INSTANCE_IDS}"
```

---

## 🔍 Verification & Inspection

Inspect the placement details of the running instances:
```bash
aws ec2 describe-instances \
  --instance-ids ${INSTANCE_IDS} \
  --query "Reservations[*].Instances[*].[InstanceId,Placement.GroupName,Placement.AvailabilityZone]" \
  --output table
```
Both instances run in the same AZ under `pg-ha-spread`, but AWS guarantees they are hosted on physically separate server racks and power circuits.

---

## 🧹 Teardown & Clean-up

> [!NOTE]
> A placement group cannot be deleted until all instances inside it are terminated and reached the `terminated` state.

```bash
# 1. Terminate instances
aws ec2 terminate-instances --instance-ids ${INSTANCE_IDS}
aws ec2 wait instance-terminated --instance-ids ${INSTANCE_IDS}

# 2. Delete placement groups
aws ec2 delete-placement-group --group-name "pg-hpc-cluster"
aws ec2 delete-placement-group --group-name "pg-ha-spread"
aws ec2 delete-placement-group --group-name "pg-kafka-partition"

echo "Lab 3.4 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-03-networking-eni-placement/lab-03-enhanced-networking-ena/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 03](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-04-security-iam-ssm/lab-01-security-groups-nacls/README.md)**

</div>
