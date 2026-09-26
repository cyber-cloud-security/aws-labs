<div align="center">

# 🔬 Lab 2.2: EBS Snapshots, Data Lifecycle Manager (DLM) & io2 Multi-Attach

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 02](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-20_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Paid_%28~%240.05_--_%240.15%29-d29922?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-02_%E2%80%94_Storage_Architecture_%28EBS-fd8c73?style=flat-square)

**[⬅️ Previous Lab](../../module-02-storage-ebs-ephemeral-efs/lab-01-ebs-elastic-volumes/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-02-storage-ebs-ephemeral-efs/lab-03-instance-store-ephemeral/README.md)**

</div>

---

## 📌 Lab Objectives

- [x] Create point-in-time **EBS Snapshots** and understand incremental backup mechanics.
- [x] Configure an automated backup lifecycle using **Amazon Data Lifecycle Manager (DLM)**.
- [x] Provision an `io2` volume with **Multi-Attach** enabled and attach it concurrently to multiple EC2 instances.
- [x] Understand clustered filesystem requirements (GFS2 / OCFS2) to prevent split-brain corruption on shared block storage.

---

## 🏗️ Architecture Diagram

![Architecture Diagram](./images/architecture-lab-02.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart TD
    subgraph MultiAttachZone["Availability Zone: us-east-1a"]
        Node1["EC2 Instance A\n(Cluster Node 1)"]
        Node2["EC2 Instance B\n(Cluster Node 2)"]
        SharedVol["Shared EBS Volume\nio2 Multi-Attach Enabled\n(Target: /dev/sdf)"]

        Node1 -->|Concurrent Read/Write| SharedVol
        Node2 -->|Concurrent Read/Write| SharedVol
    end

    subgraph AWSManagement["AWS Backup & Policy Plane"]
        DLM["Data Lifecycle Manager (DLM)\nTarget Tag: BackupPolicy=daily"]
        Snap1["Snapshot Day 1 (Full)"]
        Snap2["Snapshot Day 2 (Incremental)"]
        S3Storage["Underlying S3 Bucket (Managed by AWS)"]

        DLM -->|Schedules| SharedVol
        SharedVol -->|Creates| Snap1
        SharedVol -->|Creates| Snap2
        Snap1 -.-> S3Storage
        Snap2 -.-> S3Storage
    end
```

</details>

---

## 💡 Key Architectural Concepts

1. **Incremental Snapshots**:
   - Only modified blocks (deltas) since the last snapshot are copied to Amazon S3. Even though each snapshot points back to base blocks, snapshot deletion cleans up only unique unreferenced blocks.
2. **Crash-Consistent vs Application-Consistent**:
   - Taking a snapshot of a running volume without freezing I/O is crash-consistent (equivalent to pulling power). For databases (e.g., PostgreSQL, MySQL), flush tables and acquire read-locks before snapshotting.
3. **EBS Multi-Attach**:
   - Allows an `io2` or `io1` volume to be attached simultaneously to up to 16 Nitro-based EC2 instances within the **same Availability Zone**.
   - Standard filesystems (ext4, XFS, NTFS) **are not cluster-aware**; writing concurrently from multiple nodes will corrupt the filesystem! You must use cluster software like Pacemaker with GFS2/OCFS2 or NVMe reservation primitives.

---

## ⏱️ Prerequisites & Cost

> [!WARNING]
> **Paid Instance / Storage Notice**
> - **AWS Free Tier Eligible**: DLM and Standard Snapshots are free-tier friendly. `io2` volumes incur a small hourly provisioned IOPS fee ($0.065/provisioned IOPS/month), so ensure prompt teardown.
> - **Estimated Duration**: 20 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Create a Snapshot of an Existing Volume
Assume an active EBS volume `VOLUME_ID`:
```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")

# Create snapshot with descriptive tags
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id "${VOLUME_ID}" \
  --description "Manual point-in-time backup for Lab 2.2" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=manual-backup-1}]" \
  --query "SnapshotId" --output text)

echo "Snapshot creation initiated: ${SNAPSHOT_ID}"
aws ec2 wait snapshot-completed --snapshot-ids "${SNAPSHOT_ID}"
echo "Snapshot completed."
```

### Step 2: Configure Amazon Data Lifecycle Manager (DLM) Policy
DLM automatically snapshots volumes based on tag selectors:

1. Create IAM Role for DLM:
```bash
cat <<JSON > dlm-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "dlm.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

DLM_ROLE_ARN=$(aws iam create-role \
  --role-name "ec2-labs-dlm-lifecycle-role" \
  --assume-role-policy-document file://dlm-trust-policy.json \
  --query "Role.Arn" --output text 2>/dev/null || \
  aws iam get-role \
    --role-name "ec2-labs-dlm-lifecycle-role" \
    --query "Role.Arn" \
    --output text)

aws iam attach-role-policy \
  --role-name "ec2-labs-dlm-lifecycle-role" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
```

2. Create Lifecycle Policy JSON:
```bash
cat <<JSON > dlm-policy.json
{
  "ResourceTypes": ["VOLUME"],
  "TargetTags": [
    { "Key": "BackupPolicy", "Value": "DailySnapshot" }
  ],
  "Schedules": [
    {
      "Name": "DailyRun",
      "CreateRule": {
        "Interval": 24,
        "IntervalUnit": "HOURS",
        "Times": ["03:00"]
      },
      "RetainRule": {
        "Count": 7
      },
      "CopyTags": true
    }
  ]
}
JSON

POLICY_ID=$(aws dlm create-lifecycle-policy \
  --description "Daily 7-day retention EBS snapshot policy" \
  --state ENABLED \
  --execution-role-arn "${DLM_ROLE_ARN}" \
  --policy-details file://dlm-policy.json \
  --query "PolicyId" --output text)

echo "Created DLM Policy ID: ${POLICY_ID}"
```

### Step 3: Provision an `io2` Multi-Attach Volume
Create an `io2` volume configured with Multi-Attach:
```bash
AZ="us-east-1a"

IO2_VOL_ID=$(aws ec2 create-volume \
  --availability-zone "${AZ}" \
  --volume-type "io2" \
  --size 4 \
  --iops 200 \
  --multi-attach-enabled \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=multi-attach-io2}]" \
  --query "VolumeId" --output text)

echo "Created Multi-Attach io2 Volume: ${IO2_VOL_ID}"
aws ec2 wait volume-available --volume-ids "${IO2_VOL_ID}"
```

---

## 🔍 Verification: Multi-Attach to Two Running Instances

Verify that the volume can be attached to two separate instances simultaneously:
```bash
# Attach to Instance A
aws ec2 attach-volume \
  --volume-id "${IO2_VOL_ID}" \
  --instance-id "${INSTANCE_A_ID}" \
  --device "/dev/sdf"

# Attach to Instance B (Normal EBS volumes would throw InvalidParameterCombination / VolumeInUse)
aws ec2 attach-volume \
  --volume-id "${IO2_VOL_ID}" \
  --instance-id "${INSTANCE_B_ID}" \
  --device "/dev/sdf"

# Check attachments:
aws ec2 describe-volumes \
  --volume-ids "${IO2_VOL_ID}" \
  --query "Volumes[0].Attachments[*].[InstanceId,State,Device]" \
  --output table
```
Both instances will show state: `attached`.

---

## 🧹 Teardown & Clean-up


> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

```bash
# 1. Delete DLM Policy
aws dlm delete-lifecycle-policy --policy-id "${POLICY_ID}"

# 2. Detach and delete io2 volume
aws ec2 detach-volume --volume-id "${IO2_VOL_ID}" --instance-id "${INSTANCE_A_ID}" 2>/dev/null || true
aws ec2 detach-volume --volume-id "${IO2_VOL_ID}" --instance-id "${INSTANCE_B_ID}" 2>/dev/null || true
sleep 10
aws ec2 delete-volume --volume-id "${IO2_VOL_ID}"

# 3. Delete manual snapshot
aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT_ID}"

# 4. Cleanup DLM IAM role
aws iam detach-role-policy \
  --role-name "ec2-labs-dlm-lifecycle-role" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
aws iam delete-role --role-name "ec2-labs-dlm-lifecycle-role"
rm -f dlm-trust-policy.json dlm-policy.json

echo "Lab 2.2 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-02-storage-ebs-ephemeral-efs/lab-01-ebs-elastic-volumes/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 02](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-02-storage-ebs-ephemeral-efs/lab-03-instance-store-ephemeral/README.md)**

</div>
