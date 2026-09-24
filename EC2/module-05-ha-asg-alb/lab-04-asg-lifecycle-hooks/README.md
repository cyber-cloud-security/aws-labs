<div align="center">

# 🔬 Lab 5.4: ASG Lifecycle Hooks & Graceful State Flushing

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 05](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-20_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate_to_Advanced-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-05_%E2%80%94_High_Availability-fd8c73?style=flat-square)

**[⬅️ Previous Lab](../../module-05-ha-asg-alb/lab-03-asg-dynamic-scaling/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-06-purchasing-cost-optimization/lab-01-spot-interruption-handling/README.md)**

</div>

---

## 📌 Lab Objectives

- [x] Understand the complete **Auto Scaling Instance Lifecycle State Machine**.
- [x] Configure a termination lifecycle hook: `autoscaling:EC2_INSTANCE_TERMINATING`.
- [x] Intercept an instance before termination and pause the shutdown in `Terminating:Wait` state.
- [x] Execute an automated graceful drainage routine (exporting in-flight logs and state to S3) before signaling `complete-lifecycle-action` with `CONTINUE`.

---

## 🏗️ Lifecycle Hook Architecture

![Architecture Diagram](./images/architecture-lab-04.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
stateDiagram-v2
    [*] --> InService
    InService --> Terminating: Scale-In / Health Check Trigger
    Terminating --> TerminatingWait: Intercepted by Lifecycle Hook!

    state TerminatingWait {
        [*] --> RunningDrainScript
        RunningDrainScript --> FlushLogsToS3
        FlushLogsToS3 --> FinishWork
        FinishWork --> SignalComplete: complete-lifecycle-action
    }

    TerminatingWait --> TerminatingProceed: Action=CONTINUE or Timeout
    TerminatingProceed --> Terminated
    Terminated --> [*]
```

</details>

---

## 💡 Key Architectural Concepts

1. **Why Termination Hooks?**:
   - Without a hook, when an ASG scales in or rebalances, the instance receives an immediate `SIGTERM` followed quickly by `SIGKILL`, abruptly aborting active user transactions and leaving unsaved logs on local disks.
2. **`Terminating:Wait` State**:
   - Freezes the instance termination for up to `HeartbeatTimeout` seconds (default 3600 seconds), giving automated scripts or EventBridge handlers time to finish work.
3. **Heartbeat Extensions**:
   - If a long-running batch job needs more time, a script can call `aws autoscaling record-lifecycle-action-heartbeat` to extend the countdown timer repeatedly.

---

## ⏱️ Prerequisites & Cost

> [!TIP]
> **AWS Free Tier & Cost Guardrail**
> - **AWS Free Tier Eligible**: Yes (`t3.micro`).
> - **Estimated Duration**: 20 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Create an ASG with 1 Instance
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

AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

# Create Launch Template
cat <<JSON > hook-lt.json
{
  "ImageId": "${AMI_ID}",
  "InstanceType": "t3.micro",
  "MetadataOptions": { "HttpTokens": "required" }
}
JSON

LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "lt-hook-demo" \
  --launch-template-data file://hook-lt.json \
  --query "LaunchTemplate.LaunchTemplateId" --output text)

# Create ASG
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "asg-hook-demo" \
  --launch-template "LaunchTemplateId=${LT_ID},Version=\$Latest" \
  --min-size 1 \
  --max-size 1 \
  --desired-capacity 1 \
  --vpc-zone-identifier "${SUBNET_1}"

echo "Waiting for instance to launch..."
sleep 20
```

### Step 2: Attach Termination Lifecycle Hook
Configure a 300-second pause when an instance is chosen for termination:
```bash
aws autoscaling put-lifecycle-hook \
  --lifecycle-hook-name "graceful-drain-hook" \
  --auto-scaling-group-name "asg-hook-demo" \
  --lifecycle-transition "autoscaling:EC2_INSTANCE_TERMINATING" \
  --heartbeat-timeout 300 \
  --default-result "CONTINUE"

echo "Configured termination lifecycle hook."
```

---

## 🔍 Verification & Drain Simulation

### 1. Trigger Scale-In / Termination
Find the instance ID and terminate it via the ASG:
```bash
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "asg-hook-demo" \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)

echo "Triggering termination on: ${INSTANCE_ID}"
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id "${INSTANCE_ID}" \
  --should-decrement-desired-capacity
```

### 2. Observe `Terminating:Wait` Status
Check the instance lifecycle state:
```bash
aws autoscaling describe-auto-scaling-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "AutoScalingInstances[0].LifecycleState" --output text
```
**Expected Output**: `Terminating:Wait`
Notice the instance **remains powered on** and accessible! The ASG does not terminate it immediately.

### 3. Simulate Graceful Drainage and Complete Action
Assume your cleanup script finishes flushing local logs and completes its work:
```bash
echo "Cleanup script finished. Sending complete-lifecycle-action..."

aws autoscaling complete-lifecycle-action \
  --lifecycle-hook-name "graceful-drain-hook" \
  --auto-scaling-group-name "asg-hook-demo" \
  --lifecycle-action-result "CONTINUE" \
  --instance-id "${INSTANCE_ID}"

echo "Lifecycle action signaled. Instance will now transition to Terminating:Proceed and terminate."
```

---

## 📘 Deep-Dive Command & Flag Reference

> [!TIP]
> **Line-by-Line Production Analysis**: Every command executed in this lab is dissected below, explaining each CLI flag, JMESPath query, Linux kernel parameter, and why it is critical in production automation.

<details open>
<summary>📘 <b>Command 1 & 2: Environment Discovery and Launch Template Creation</b></summary>

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

AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

cat <<JSON > hook-lt.json
{
  "ImageId": "${AMI_ID}",
  "InstanceType": "t3.micro",
  "MetadataOptions": { "HttpTokens": "required" }
}
JSON

LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "lt-hook-demo" \
  --launch-template-data file://hook-lt.json \
  --query "LaunchTemplate.LaunchTemplateId" --output text)
```

#### 🔍 Parameter & Component Breakdown
- **`export AWS_REGION=...`, `VPC_ID=...`, `SUBNET_1=...`** — Discovers default networking infrastructure for instance placement.
- **`AMI_ID=$(aws ssm get-parameter ...)`** — Dynamically retrieves the latest Amazon Linux 2023 x86_64 AMI ID.
- **`cat <<JSON > hook-lt.json`** — Writes an EC2 launch template configuration payload enforcing IMDSv2 (`"HttpTokens": "required"`).
- **`aws ec2 create-launch-template`** — Creates the launch template and captures the generated ID into `$LT_ID`.

> 🏭 **Why This Matters in Production Automation**
> Separating the instance launch blueprint into a Launch Template decouples compute definitions from scaling logic, facilitating controlled Canary and Blue/Green ASG instance refresh deployments.

</details>

<details open>
<summary>📘 <b>Command 3: Provisioning the Auto Scaling Group</b></summary>

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "asg-hook-demo" \
  --launch-template "LaunchTemplateId=${LT_ID},Version=\$Latest" \
  --min-size 1 \
  --max-size 1 \
  --desired-capacity 1 \
  --vpc-zone-identifier "${SUBNET_1}"

sleep 20
```

#### 🔍 Parameter & Component Breakdown
- **`aws autoscaling create-auto-scaling-group`** — Provisions the initial single-instance ASG.
- **`--auto-scaling-group-name "asg-hook-demo"`** — Unique group identifier.
- **`--launch-template "LaunchTemplateId=${LT_ID},Version=\$Latest"`** — Specifies the template and instructs the ASG to adopt `$Latest` versions automatically.
- **`--min-size 1 --max-size 1 --desired-capacity 1`** — Fixes group boundaries to exactly 1 instance for the test.
- **`--vpc-zone-identifier "${SUBNET_1}"`** — Sets the target subnet for instance deployment.
- **`sleep 20`** — Pauses shell execution to permit the ASG control loop to initiate the EC2 launch.

> 🏭 **Why This Matters in Production Automation**
> The ASG abstracts direct EC2 instance management into an autonomous self-healing fleet. By standardizing capacity limits, automation guarantees predictable workload availability.

</details>

<details open>
<summary>📘 <b>Command 4: Attaching the Termination Lifecycle Hook</b></summary>

```bash
aws autoscaling put-lifecycle-hook \
  --lifecycle-hook-name "graceful-drain-hook" \
  --auto-scaling-group-name "asg-hook-demo" \
  --lifecycle-transition "autoscaling:EC2_INSTANCE_TERMINATING" \
  --heartbeat-timeout 300 \
  --default-result "CONTINUE"
```

#### 🔍 Parameter & Component Breakdown
- **`aws autoscaling put-lifecycle-hook`** — Creates or modifies a lifecycle hook on the ASG.
- **`--lifecycle-hook-name "graceful-drain-hook"`** — Identifies the hook.
- **`--auto-scaling-group-name "asg-hook-demo"`** — Identifies the parent ASG.
- **`--lifecycle-transition "autoscaling:EC2_INSTANCE_TERMINATING"`** — Configures the hook to intercept instances that are transitioning from `InService` to termination (scale-in, health check failure, or manual termination).
- **`--heartbeat-timeout 300`** — Sets the pause duration to 300 seconds (5 minutes). The instance remains in `Terminating:Wait` state for up to 300 seconds before taking default action.
- **`--default-result "CONTINUE"`** — Fallback decision if no script or Lambda signals completion before the 300-second timeout expires. `CONTINUE` allows termination to proceed, whereas `ABANDON` stops termination and marks the action failed.

> 🏭 **Why This Matters in Production Automation**
> Without lifecycle hooks, scaling in immediately terminates instances, destroying active web sockets, aborting in-flight transactions, and leaving ephemeral log files unbacked. The hook pauses shutdown, allowing external systems (or local daemons) to drain traffic, complete batch items, and upload state.

</details>

<details open>
<summary>📘 <b>Command 5: Triggering Scale-In Termination via ASG</b></summary>

```bash
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "asg-hook-demo" \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)

aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id "${INSTANCE_ID}" \
  --should-decrement-desired-capacity
```

#### 🔍 Parameter & Component Breakdown
- **`aws autoscaling describe-auto-scaling-groups ... --query ...`** — Retrieves the active instance ID managed by the ASG.
- **`aws autoscaling terminate-instance-in-auto-scaling-group`** — Directs the ASG to terminate the specified instance.
- **`--instance-id "${INSTANCE_ID}"`** — Target EC2 instance ID.
- **`--should-decrement-desired-capacity`** — Decrements the ASG `DesiredCapacity` by 1. Without this flag, the ASG would immediately launch a replacement instance to keep desired capacity at 1.

> 🏭 **Why This Matters in Production Automation**
> In production systems, scale-in events occur automatically via scaling policies. Using `--should-decrement-desired-capacity` simulates an authentic scale-in event without triggering immediate instance replacement.

</details>

<details open>
<summary>📘 <b>Command 6: Verifying the `Terminating:Wait` Lifecycle State</b></summary>

```bash
aws autoscaling describe-auto-scaling-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "AutoScalingInstances[0].LifecycleState" --output text
```

#### 🔍 Parameter & Component Breakdown
- **`aws autoscaling describe-auto-scaling-instances`** — Queries ASG-specific metadata for individual EC2 instances.
- **`--instance-ids "${INSTANCE_ID}"`** — The target instance.
- **`--query "AutoScalingInstances[0].LifecycleState" --output text`** — Extracts the lifecycle state string.

> 🏭 **Why This Matters in Production Automation**
> Confirms that the lifecycle hook successfully intercepted the termination event. The instance is paused in `Terminating:Wait`. The operating system is fully operational and networking is intact, enabling automated drainage agents or SSM Run Commands to execute cleanup tasks safely.

</details>

<details open>
<summary>📘 <b>Command 7: Signaling Completion of the Lifecycle Action</b></summary>

```bash
aws autoscaling complete-lifecycle-action \
  --lifecycle-hook-name "graceful-drain-hook" \
  --auto-scaling-group-name "asg-hook-demo" \
  --lifecycle-action-result "CONTINUE" \
  --instance-id "${INSTANCE_ID}"
```

#### 🔍 Parameter & Component Breakdown
- **`aws autoscaling complete-lifecycle-action`** — Signals to the Auto Scaling engine that custom drain procedures have finished.
- **`--lifecycle-hook-name "graceful-drain-hook"`** — Identifies the active hook.
- **`--auto-scaling-group-name "asg-hook-demo"`** — Parent ASG name.
- **`--lifecycle-action-result "CONTINUE"`** — Informs ASG that the drain succeeded and it can now proceed with terminating the instance (`Terminating:Proceed`).
- **`--instance-id "${INSTANCE_ID}"`** — The instance that has completed its drain tasks.

> 🏭 **Why This Matters in Production Automation**
> Waiting for the full 300-second heartbeat timeout slows down scaling and wastes compute cost. Signaling `complete-lifecycle-action` immediately upon drain completion ensures rapid, cost-efficient infrastructure cycling without unnecessary idle delays.

</details>

<details open>
<summary>📘 <b>Command 8: Automated Teardown and Cleanup</b></summary>

```bash
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "asg-hook-demo" \
  --force-delete
aws ec2 delete-launch-template --launch-template-id "${LT_ID}"
rm -f hook-lt.json
```

#### 🔍 Parameter & Component Breakdown
- **`aws autoscaling delete-auto-scaling-group --force-delete`** — Destroys the ASG immediately, bypassing waiting periods.
- **`aws ec2 delete-launch-template`** — Removes the launch template resource.
- **`rm -f hook-lt.json`** — Removes the local temporary configuration file.

> 🏭 **Why This Matters in Production Automation**
> Ensures zero orphaned resources remain in the AWS account, preventing unexpected billing and quota consumption.

</details>

---

## 🧹 Teardown & Clean-up


> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

```bash
# 1. Delete ASG
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "asg-hook-demo" \
  --force-delete

# 2. Delete Launch Template
aws ec2 delete-launch-template --launch-template-id "${LT_ID}"
rm -f hook-lt.json

echo "Lab 5.4 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-05-ha-asg-alb/lab-03-asg-dynamic-scaling/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 05](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-06-purchasing-cost-optimization/lab-01-spot-interruption-handling/README.md)**

</div>
