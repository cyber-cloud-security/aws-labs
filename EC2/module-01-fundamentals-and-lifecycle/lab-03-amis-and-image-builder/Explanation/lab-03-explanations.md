# Step-by-Step Technical Command Explanations: Lab 1.3

This guide breaks down every single command, parameter, and architectural safeguard used in **Lab 1.3: Custom AMIs, Golden Images & Cross-Region Distribution**.

---

### Command 1: Creating a Custom Golden AMI from a Running Instance

```bash
CUSTOM_AMI_ID=$(aws ec2 create-image \
  --region "${AWS_REGION}" \
  --instance-id "${INSTANCE_ID}" \
  --name "golden-al2023-v1-$(date +%s)" \
  --description "Custom Golden AMI with pre-baked packages" \
  --no-reboot \
  --tag-specifications "ResourceType=image,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=golden-al2023-v1}]" \
  --query "ImageId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 create-image`  
Calls the `CreateImage` API endpoint. Under the hood, this initiates two parallel actions:  
1. Creates point-in-time Amazon EBS snapshots of all EBS volumes attached to the instance.  
2. Registers a new Amazon Machine Image (AMI) metadata catalog entry pointing to those newly created snapshots.

• `--name "golden-al2023-v1-$(date +%s)"`  
Sets the unique AMI name. AMI names must be unique within your account in the target region. Appending `$(date +%s)` (epoch timestamp in seconds) guarantees non-colliding names during automated daily or CI/CD golden image builds.

• `--description "..."`  
Human-readable summary of image contents, patch levels, or build pipelines.

• `--no-reboot`  
**Critical Parameter**:  
By default, AWS cleanly shuts down the instance, flushes file system buffers to disk, takes the snapshot, and powers the instance back on to guarantee crash consistency.  
Specifying `--no-reboot` forces AWS to snapshot the disks while the operating system continues running with zero downtime.  
*Caveat*: In production, ensure active database writes are quiesced before taking a `--no-reboot` image to prevent uncommitted journal corruption.

• `--query "ImageId" --output text`  
Extracts the generated AMI identifier (e.g. `ami-0a1b2c3d4e5f67890`).

──────
#### 2. Why This is Critical in Production Automation

Golden Images (pre-baked AMIs containing all base packages, hardening scripts, monitoring daemons, and security tools) form the foundation of immutable infrastructure. Instead of spending 5–10 minutes running package managers (`dnf`/`apt`) every time an Auto Scaling Group launches an instance, instances boot from a Golden AMI in less than 30 seconds.

---

### Command 2: Synchronous Polling for AMI Availability

```bash
aws ec2 wait image-available --region "${AWS_REGION}" --image-ids "${CUSTOM_AMI_ID}"
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 wait image-available`  
Polls the `DescribeImages` API endpoint at 15-second intervals until the image state changes from `pending` to `available`.

• Underlying Mechanism:  
An AMI cannot be marked `available` until its backing EBS snapshots have completed copying dirty blocks to Amazon S3. For a 10 GiB volume, this typically takes 2–4 minutes.

──────
#### 2. Why This is Critical in Production Automation

Attempting to launch an EC2 instance, copy an AMI cross-region, or share an AMI while it is still in the `pending` state will immediately throw an `InvalidAMIID.Unavailable` error. Automated pipelines must use `wait image-available` to gate downstream deployment steps.

---

### Command 3: Querying the Underlying EBS Snapshot Identifier

```bash
SNAPSHOT_ID=$(aws ec2 describe-images \
  --region "${AWS_REGION}" \
  --image-ids "${CUSTOM_AMI_ID}" \
  --query "Images[0].BlockDeviceMappings[0].Ebs.SnapshotId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 describe-images`  
Retrieves full schema attributes of the registered AMI.

• `--query "Images[0].BlockDeviceMappings[0].Ebs.SnapshotId"`  
Traverses the JSON block device mapping array to extract the specific EBS Snapshot ID (e.g. `snap-0123456789abcdef0`) linked to the root device.

──────
#### 2. Why This is Critical in Production Automation

An AMI is merely a lightweight metadata pointer; the actual data resides inside Amazon S3-backed **EBS Snapshots**. Knowing the snapshot ID is required for audit trails, disaster recovery validation, and executing clean deletions.

---

### Command 4: Copying AMIs Across AWS Regions with KMS Re-Encryption

```bash
COPIED_AMI_ID=$(aws ec2 copy-image \
  --source-region "${AWS_REGION}" \
  --source-image-id "${CUSTOM_AMI_ID}" \
  --region "${DEST_REGION}" \
  --name "golden-al2023-v1-replica" \
  --description "Cross-region replica of Golden AMI" \
  --encrypted \
  --query "ImageId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 copy-image`  
Calls the `CopyImage` API to replicate the AMI and its underlying EBS snapshots over the encrypted AWS private backbone network into a target region (e.g. from `us-east-1` to `us-west-2`).

• `--source-region` & `--source-image-id`  
Specifies where the origin image resides.

• `--region "${DEST_REGION}"`  
Specifies where the new AMI will be registered.

• `--encrypted`  
Forces the destination EBS snapshots to be encrypted using the destination region's default AWS KMS EC2 encryption key.  
*Note*: AWS KMS keys are region-specific and can never leave their origin region. When an image is copied cross-region, AWS automatically decrypts the blocks with the source key in memory and re-encrypts them with the target region's KMS key before writing them to disk.

──────
#### 2. Why This is Critical in Production Automation

Cross-region AMI replication is a fundamental requirement for multi-region active-active architectures and cross-region Disaster Recovery (DR) plans. If a primary region suffers an outage, Auto Scaling Groups in the secondary DR region can immediately spin up identical compute clusters using the pre-replicated local AMI.

---

### Command 5: Launching from the Custom Golden AMI

```bash
TEST_NODE_ID=$(aws ec2 run-instances \
  --region "${AWS_REGION}" \
  --image-id "${CUSTOM_AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_ID}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=test-ami-instance}]" \
  --query "Instances[0].InstanceId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `--image-id "${CUSTOM_AMI_ID}"`  
References the newly created custom image rather than an upstream public Amazon Linux AMI.

──────
#### 2. Why This is Critical in Production Automation

This command proves image viability. Newly created AMIs must be smoke-tested in automated CI/CD staging environments before being promoted to production Launch Templates.

---

### Commands 6, 7 & 8: The Two-Step Purge (Preventing the Dangling Snapshot Trap)

```bash
# Step 1: Deregister AMI
aws ec2 deregister-image --region "${AWS_REGION}" --image-id "${CUSTOM_AMI_ID}"

# Step 2: Delete Underlying Snapshot
aws ec2 delete-snapshot --region "${AWS_REGION}" --snapshot-id "${SNAPSHOT_ID}"
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 deregister-image`  
Removes the AMI entry from the AWS EC2 image catalog. After deregistration, no new instances can be launched from this AMI.  
**THE TRAP**: Deregistering an AMI **does NOT delete the underlying EBS snapshots**! The snapshot remains in S3 and continues to accrue monthly storage charges indefinitely.

• `aws ec2 delete-snapshot`  
Permanently deletes the underlying EBS snapshot from Amazon S3, freeing storage and stopping billing.  
*Order of Operations*: You **cannot** delete an EBS snapshot while an active AMI points to it (`ResourceInUse` error). You must always call `deregister-image` first, followed by `delete-snapshot`.

──────
#### 2. Why This is Critical in Production Automation

The "Dangling Snapshot" phenomenon is one of the most common sources of cloud waste in enterprise AWS bills. Automated golden image pipelines that build daily AMIs without a corresponding two-step cleanup script can accumulate thousands of orphaned snapshots, generating thousands of dollars in surprise monthly S3 storage charges.
