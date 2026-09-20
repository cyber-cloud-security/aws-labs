# Lab 7.1: EC2 Status Checks & CloudWatch Automated Hardware Recovery - Command Explanations

This document provides a line-by-line, component-by-component architectural and operational breakdown of every command used in Lab 7.1.

---

### Command 1 & 2: Launching EC2 with Detailed Monitoring

```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
export SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[0].SubnetId" --output text)

AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_ID}" \
  --monitoring "Enabled=true" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=auto-recovery-node}]" \
  --query "Instances[0].InstanceId" --output text)

echo "Launched instance with detailed monitoring: ${INSTANCE_ID}"
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
```

#### 1. Detailed Breakdown of Every Component
• `export AWS_REGION=...`, `VPC_ID=...`, `SUBNET_ID=...`: Discovers regional network infrastructure for instance deployment.  
• `AMI_ID=$(aws ssm get-parameter ...)`: Resolves the latest Amazon Linux 2023 base image dynamically.  
• `aws ec2 run-instances`: Boots an EC2 virtual machine.  
• `--monitoring "Enabled=true"`: Activates **Detailed CloudWatch Monitoring**. By default, EC2 provides **Basic Monitoring** which emits metric data (CPU, Network, Disk) at 5-minute intervals free of charge. Detailed Monitoring reduces metric emission frequency to **1-minute intervals**, enabling faster anomaly detection and rapid auto-scaling reactions.  
• `aws ec2 wait instance-running`: Blocks until the instance status transitions to running.

──────
#### 2. Why This is Critical in Production Automation
Automated failovers and auto-recovery mechanisms depend on timely metric ingestion. A 5-minute metric reporting interval introduces up to 10 minutes of lag before an outage is detected and remediated. Enabling Detailed Monitoring cuts MTTR (Mean Time to Recovery) to under 2 minutes.

---

### Command 3: Configuring the CloudWatch Auto-Recovery Alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "ec2-hardware-recovery-${INSTANCE_ID}" \
  --alarm-description "Auto-recover instance upon physical hardware failure" \
  --metric-name "StatusCheckFailed_System" \
  --namespace "AWS/EC2" \
  --statistic "Maximum" \
  --dimensions "Name=InstanceId,Value=${INSTANCE_ID}" \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator "GreaterThanOrEqualToThreshold" \
  --alarm-actions "arn:aws:automate:${AWS_REGION}:ec2:recover"
```

#### 1. Detailed Breakdown of Every Component
• `aws cloudwatch put-metric-alarm`: Creates or updates a CloudWatch alarm.  
• `--alarm-name "ec2-hardware-recovery-${INSTANCE_ID}"`: Uniquely identifies the alarm bound to this instance.  
• `--metric-name "StatusCheckFailed_System"`: Monitors the hypervisor and physical host server level (loss of power, physical NIC failure, or hardware degradation). This is distinct from `StatusCheckFailed_Instance` which reflects guest OS failure.  
• `--namespace "AWS/EC2"`: Identifies the EC2 CloudWatch namespace.  
• `--statistic "Maximum"`: Uses the peak value observed during each period.  
• `--dimensions "Name=InstanceId,Value=${INSTANCE_ID}"`: Scopes metric evaluation strictly to the specific EC2 instance.  
• `--period 60`: Sets metric evaluation period to 60 seconds (1 minute).  
• `--evaluation-periods 2`: Requires the condition to persist across 2 consecutive periods (2 minutes) to prevent false-positive recoveries during brief transient network blips.  
• `--threshold 1`: Triggers when the failure metric equals or exceeds 1.  
• `--alarm-actions "arn:aws:automate:${AWS_REGION}:ec2:recover"`: AWS predefined ARN action that executes automated physical host recovery.

──────
#### 2. Why This is Critical in Production Automation
When physical rack hardware fails in an AWS data center, `arn:aws:automate:<region>:ec2:recover` instructs the AWS hypervisor plane to stop the damaged instance on the broken host and restart it on a healthy physical host in the same Availability Zone. The recovered instance **preserves its Instance ID, private IPv4 address, Elastic IP, and all attached EBS volume mappings**, fully automating hardware migration without human intervention.

---

### Command 4: Inspecting System and Instance Status Checks

```bash
aws ec2 describe-instance-status \
  --instance-ids "${INSTANCE_ID}" \
  --query "InstanceStatuses[0].[InstanceId,SystemStatus.Status,InstanceStatus.Status]" \
  --output table
```

#### 1. Detailed Breakdown of Every Component
• `aws ec2 describe-instance-status`: Returns the real-time health verification checks of an EC2 instance.  
• `--query "InstanceStatuses[0].[InstanceId,SystemStatus.Status,InstanceStatus.Status]"`: Extracts:  
  - `SystemStatus.Status`: Health of physical host hardware, hypervisor, and network switching (values: `ok`, `impaired`, `initializing`).  
  - `InstanceStatus.Status`: Health of the guest operating system (OS kernel, file system, network routing).  
• `--output table`: Displays the checks in a tabular format.

──────
#### 2. Why This is Critical in Production Automation
Distinguishing between system failure and instance failure is critical for automated self-healing. System check failures require physical relocation (`ec2:recover`), whereas instance check failures typically require an OS-level reboot or serial console intervention.

---

### Command 5: Verifying Alarm State

```bash
aws cloudwatch describe-alarms \
  --alarm-names "ec2-hardware-recovery-${INSTANCE_ID}" \
  --query "MetricAlarms[0].[AlarmName,StateValue,MetricName]" \
  --output table
```

#### 1. Detailed Breakdown of Every Component
• `aws cloudwatch describe-alarms`: Inspects configuration and state of CloudWatch alarms.  
• `--query "MetricAlarms[0].[AlarmName,StateValue,MetricName]"`: Confirms that `StateValue` has initialized to `OK`.

──────
#### 2. Why This is Critical in Production Automation
Verifies that the monitoring alarm is actively listening to EC2 metrics and ready to fire recovery actions should underlying physical hardware fail.

---

### Command 6: Automated Teardown and Cleanup

```bash
aws cloudwatch delete-alarms --alarm-names "ec2-hardware-recovery-${INSTANCE_ID}"
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
```

#### 1. Detailed Breakdown of Every Component
• `aws cloudwatch delete-alarms`: Deletes the alarm definition. Deleting an EC2 instance does not automatically delete its CloudWatch alarms, which would leave orphaned alarms in an `INSUFFICIENT_DATA` state.  
• `aws ec2 terminate-instances` and `wait`: Destroys the EC2 instance and waits until termination completes.

──────
#### 2. Why This is Critical in Production Automation
CloudWatch alarms carry monthly charges per metric alarm. Clean scripts must delete alarms alongside instances to prevent resource leakage.
