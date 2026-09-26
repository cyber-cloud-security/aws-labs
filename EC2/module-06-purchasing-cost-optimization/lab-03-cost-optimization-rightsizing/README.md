<div align="center">

# 🔬 Lab 6.3: FinOps Rightsizing, Compute Optimizer & gp2-to-gp3 Modernization

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 06](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-15_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-06_%E2%80%94_Purchasing_Models_%26_FinOps_Cost_Optimization-fd8c73?style=flat-square)

**[⬅️ Previous Lab](../../module-06-purchasing-cost-optimization/lab-02-asg-mixed-instances/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-07-monitoring-and-troubleshooting/lab-01-status-checks-autorecovery/README.md)**

</div>

---

## 📌 Lab Objectives

- [x] Implement FinOps principles to drive immediate EC2 cost reductions.
- [x] Execute an **in-place, zero-downtime migration from `gp2` to `gp3`** EBS volumes for an instant 20% storage cost reduction.
- [x] Leverage **AWS Compute Optimizer** recommendations to identify over-provisioned / zombie compute resources.
- [x] Evaluate **Savings Plans vs Reserved Instances (RIs)** economics and commitment modeling.

---

## 🏗️ Architectural Modernization

![Architecture Diagram](./images/architecture-lab-03.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart LR
    subgraph Legacy["Legacy Baseline (Higher Cost / Couplings)"]
        OldEBS["EBS gp2 Volume\n$0.10 / GB-month\nIOPS locked: 3 IOPS per GB\nBurst-bucket dependent"]
        OldCompute["Overprovisioned Instance\nm5.2xlarge (8 vCPU / 32 GB)\nAverage CPU: 4%"]
    end

    subgraph Modern["Modern Optimized Architecture"]
        NewEBS["EBS gp3 Volume\n$0.08 / GB-month (20% cheaper!)\nBaseline 3,000 IOPS / 125 MB/s\nDecoupled provisioning"]
        NewCompute["Rightsized Instance\nt4g.large (AWS Graviton)\n~60% Cost Reduction + Superior Performance"]
    end

    OldEBS ==>|aws ec2 modify-volume --volume-type gp3| NewEBS
    OldCompute ==>|Compute Optimizer Recommendation| NewCompute
```

</details>

---

## 💡 Key Architectural Concepts

### Why Migrate from `gp2` to `gp3`?
1. **Cost**: `gp3` is **20% less expensive** per GB-month ($0.08 vs $0.10).
2. **Performance Independence**:
   - In `gp2`, a small 30 GB volume gets only 90 baseline IOPS and must rely on burst credits.
   - In `gp3`, any volume size gets **3,000 IOPS and 125 MB/s baseline free of charge** without burst buckets.
   - You can scale IOPS and throughput independently of storage capacity.

### Savings Plans vs Reserved Instances
| Factor | Compute Savings Plans | EC2 Instance Savings Plans | Standard Reserved Instances |
| :--- | :--- | :--- | :--- |
| **Commitment** | $/hour (1 or 3 years) | $/hour (1 or 3 years) | Instance attributes (1 or 3 yrs) |
| **Max Savings** | Up to 66% | Up to 72% | Up to 72% |
| **Flexibility** | Any instance family, region, OS, plus ECS Fargate & Lambda | Any size or OS within the chosen family & region | Fixed instance type & region |
| **Recommendation**| **Default choice for modern cloud architectures** | For predictable database or steady core workloads | Legacy; prefer Savings Plans |

---

## ⏱️ Prerequisites & Cost

> [!TIP]
> **AWS Free Tier & Cost Guardrail**
> - **AWS Free Tier Eligible**: Yes.
> - **Estimated Duration**: 15 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Create a Legacy `gp2` Volume
```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
AZ=$(aws ec2 describe-availability-zones \
  --query "AvailabilityZones[0].ZoneName" \
  --output text)

LEGACY_VOL_ID=$(aws ec2 create-volume \
  --availability-zone "${AZ}" \
  --size 20 \
  --volume-type "gp2" \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=legacy-gp2-volume}]" \
  --query "VolumeId" --output text)

echo "Created Legacy gp2 Volume: ${LEGACY_VOL_ID}"
aws ec2 wait volume-available --volume-ids "${LEGACY_VOL_ID}"
```

### Step 2: Perform Zero-Downtime Migration to `gp3`
Convert the volume type live using Elastic Volumes:
```bash
aws ec2 modify-volume \
  --volume-id "${LEGACY_VOL_ID}" \
  --volume-type "gp3"

echo "Sent modification command: Converting gp2 -> gp3..."
```

Verify the transformation:
```bash
aws ec2 describe-volumes \
  --volume-ids "${LEGACY_VOL_ID}" \
  --query "Volumes[0].[VolumeId,VolumeType,Size,Iops,Throughput]" \
  --output table
```
**Result**: The volume immediately reports `gp3`, delivering 3,000 baseline IOPS and 125 MB/s with an automatic 20% billing discount.

---

## 🔍 AWS Compute Optimizer Inspection

Query Compute Optimizer recommendations (must be enrolled in your AWS account):
```bash
aws compute-optimizer get-ec2-instance-recommendations \
  --query "instanceRecommendations[*].[instanceArn,currentInstanceType,finding,recommendationOptions[0].instanceType]" \
  --output table 2>/dev/null || echo "Compute Optimizer requires opt-in via AWS Console."
```
Findings categorize instances as:
- `Underprovisioned`: Bottlenecked on CPU/RAM.
- `Overprovisioned`: Wasting money on excess resources.
- `Optimized`: Sized appropriately for historical load.

---

## 🧹 Teardown & Clean-up


> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

```bash
aws ec2 delete-volume --volume-id "${LEGACY_VOL_ID}"
echo "Lab 6.3 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-06-purchasing-cost-optimization/lab-02-asg-mixed-instances/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 06](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-07-monitoring-and-troubleshooting/lab-01-status-checks-autorecovery/README.md)**

</div>
