# Lab 7.2: Unified CloudWatch Agent (OS-Level RAM, Disk & Log Streaming) - Command Explanations

This document provides a line-by-line, component-by-component architectural and operational breakdown of every command used in Lab 7.2.

---

### Command 1: Discovering Network Subnets and AWS Region

```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
export SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[0].SubnetId" --output text)
```

#### 1. Detailed Breakdown of Every Component
• `export AWS_REGION=...`: Identifies target AWS region.  
• `export VPC_ID=...`: Queries the default VPC ID.  
• `export SUBNET_ID=...`: Queries the first active subnet in the default VPC for instance placement.

──────
#### 2. Why This is Critical in Production Automation
Ensures reproducible deployment targeting valid subnets with internet gateways or VPC endpoints required to reach CloudWatch APIs.

---

### Command 2: Creating the IAM Role and Instance Profile for CloudWatch Agent

```bash
cat <<JSON > cw-trust.json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
JSON

aws iam create-role --role-name "ec2-cw-agent-role" --assume-role-policy-document file://cw-trust.json 2>/dev/null || true
aws iam attach-role-policy --role-name "ec2-cw-agent-role" --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"

aws iam create-instance-profile --instance-profile-name "ec2-cw-agent-profile" 2>/dev/null || true
aws iam add-role-to-instance-profile --instance-profile-name "ec2-cw-agent-profile" --role-name "ec2-cw-agent-role" 2>/dev/null || true

sleep 10
```

#### 1. Detailed Breakdown of Every Component
• `cw-trust.json`: Defines the trust relationship allowing the EC2 service (`ec2.amazonaws.com`) to assume the role via AWS Security Token Service (`sts:AssumeRole`).  
• `aws iam create-role`: Provisions the IAM role `ec2-cw-agent-role`.  
• `aws iam attach-role-policy ... --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"`: Grants the managed policy containing exact permissions needed to publish custom metrics (`cloudwatch:PutMetricData`), write logs (`logs:PutLogEvents`, `logs:CreateLogStream`), and pull configuration from SSM Parameter Store (`ssm:GetParameter`).  
• `aws iam create-instance-profile` and `aws iam add-role-to-instance-profile`: Constructs the instance profile container required to pass IAM roles to EC2 virtual machines.  
• `sleep 10`: Mitigates IAM global eventual consistency replication delays across AWS regional endpoints.

──────
#### 2. Why This is Critical in Production Automation
Without this role and policy, the CloudWatch Agent daemon running inside the EC2 operating system will receive `AccessDenied` when attempting to push metric samples or stream logs to the AWS CloudWatch control plane.

---

### Command 3: Centralizing Agent Configuration in SSM Parameter Store

```bash
cat <<'JSON' > cw-config.json
{
  "metrics": {
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/ec2/system-logs",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
JSON

aws ssm put-parameter \
  --name "AmazonCloudWatch-linux-ec2-labs" \
  --type "String" \
  --value file://cw-config.json \
  --overwrite
```

#### 1. Detailed Breakdown of Every Component
• `cw-config.json`: JSON configuration governing the Unified CloudWatch Agent:  
  - `"metrics"`: Configures OS-level metrics collection. `mem_used_percent` calculates `(total - available) / total * 100`. `disk_used_percent` tracks root filesystem (`/`) consumption. Interval is set to 60 seconds.  
  - `"append_dimensions": {"InstanceId": "${aws:InstanceId}"}`: Automatically tags every metric point with the host's EC2 instance ID for precise filtering.  
  - `"logs"`: Specifies OS files to tail and stream. Tails `/var/log/messages` and streams lines into CloudWatch log group `/aws/ec2/system-logs` under an instance-specific stream name.  
• `aws ssm put-parameter`: Stores the JSON string inside AWS Systems Manager Parameter Store under `AmazonCloudWatch-linux-ec2-labs`.  
• `--overwrite`: Overwrites existing values if updating.

──────
#### 2. Why This is Critical in Production Automation
Hardcoding configuration files directly into individual AMIs or UserData scripts creates severe configuration drift. Centralizing the agent configuration in SSM Parameter Store enables updating metric collections, log paths, and polling intervals across thousands of production instances centrally without modifying code or rebuilding images.

---

### Command 4: Launching the Instance and Initializing CloudWatch Agent

```bash
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_ID}" \
  --iam-instance-profile "Name=ec2-cw-agent-profile" \
  --user-data "#!/bin/bash
dnf install -y amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c ssm:AmazonCloudWatch-linux-ec2-labs" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=cw-agent-node}]" \
  --query "Instances[0].InstanceId" --output text)

echo "Launched Node: ${INSTANCE_ID}"
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
echo "Waiting 60 seconds for agent to publish first metric batch..."
sleep 60
```

#### 1. Detailed Breakdown of Every Component
• `--iam-instance-profile "Name=ec2-cw-agent-profile"`: Attaches our IAM instance profile to supply temporary credentials via IMDS.  
• `--user-data`: Executes the bootstrap script during instance launch:  
  - `dnf install -y amazon-cloudwatch-agent`: Installs the official unified agent package from Amazon Linux 2023 repositories.  
  - `amazon-cloudwatch-agent-ctl`: Agent control utility.  
  - `-a fetch-config`: Action flag instructing the utility to retrieve configuration.  
  - `-m ec2`: Mode set to EC2.  
  - `-s`: Starts the agent daemon immediately as a systemd service upon configuration load.  
  - `-c ssm:AmazonCloudWatch-linux-ec2-labs`: Directs the agent to fetch its JSON configuration directly from the specified SSM Parameter.  
• `sleep 60`: Grants 60 seconds for the operating system to boot, start the agent, and transmit its first metric payload to AWS.

──────
#### 2. Why This is Critical in Production Automation
Fully automates host telemetry bootstrapping. The instance boots up, queries SSM Parameter Store for its operational blueprint, starts background log ingestion, and immediately reports OS-level health metrics to CloudWatch dashboards without manual SSH access.

---

### Command 5: Verifying OS-Level Memory and Disk Metrics in CloudWatch

```bash
aws cloudwatch list-metrics \
  --namespace "CWAgent" \
  --dimensions "Name=InstanceId,Value=${INSTANCE_ID}" \
  --query "Metrics[*].MetricName" \
  --output table
```

#### 1. Detailed Breakdown of Every Component
• `aws cloudwatch list-metrics`: Queries available metric series.  
• `--namespace "CWAgent"`: The default CloudWatch namespace used by the Unified Agent for OS-level metrics. Standard EC2 hypervisor metrics live in the separate `AWS/EC2` namespace.  
• `--dimensions "Name=InstanceId,Value=${INSTANCE_ID}"`: Restricts query to metrics tagged with our instance ID.  
• `--query "Metrics[*].MetricName"`: Pulls all registered metric names, returning `mem_used_percent` and `disk_used_percent`.

──────
#### 2. Why This is Critical in Production Automation
Hypervisor metrics (`AWS/EC2`) cannot see inside the Linux kernel page cache or filesystem allocation table. Registering metrics in `CWAgent` enables engineering teams to create CloudWatch alarms for out-of-memory (OOM) conditions and root filesystem disk exhaustion before production services crash.

---

### Command 6: Verifying Centralized Log Streaming

```bash
aws logs filter-log-events \
  --log-group-name "/aws/ec2/system-logs" \
  --limit 5 \
  --query "events[*].message" \
  --output text
```

#### 1. Detailed Breakdown of Every Component
• `aws logs filter-log-events`: Queries log events from Amazon CloudWatch Logs.  
• `--log-group-name "/aws/ec2/system-logs"`: Points to the log group created dynamically by the agent.  
• `--limit 5`: Retrieves the latest 5 log entries.  
• `--query "events[*].message" --output text`: Prints the raw log string output from `/var/log/messages`.

──────
#### 2. Why This is Critical in Production Automation
Centralized log streaming decouples telemetry from ephemeral compute. If an EC2 instance crashes, is terminated by Auto Scaling, or suffers catastrophic disk failure, all kernel syslog entries, authentication attempts, and error dumps remain permanently preserved in CloudWatch Logs for post-mortem analysis.

---

### Command 7: Automated Teardown and Cleanup

```bash
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"

aws logs delete-log-group --log-group-name "/aws/ec2/system-logs" 2>/dev/null || true

aws ssm delete-parameter --name "AmazonCloudWatch-linux-ec2-labs"
aws iam remove-role-from-instance-profile --instance-profile-name "ec2-cw-agent-profile" --role-name "ec2-cw-agent-role"
aws iam delete-instance-profile --instance-profile-name "ec2-cw-agent-profile"
aws iam detach-role-policy --role-name "ec2-cw-agent-role" --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
aws iam delete-role --role-name "ec2-cw-agent-role"
rm -f cw-trust.json cw-config.json
```

#### 1. Detailed Breakdown of Every Component
• `aws ec2 terminate-instances` and `wait`: Destroys the worker instance.  
• `aws logs delete-log-group`: Removes the log group to eliminate ongoing storage costs.  
• `aws ssm delete-parameter`: Removes the SSM configuration parameter.  
• `aws iam ...`: Detaches policies, unlinks roles from instance profiles, and destroys IAM entities in strict reverse dependency order.  
• `rm -f ...`: Removes local temporary configuration files.

──────
#### 2. Why This is Critical in Production Automation
IAM roles, SSM parameters, and CloudWatch log groups linger indefinitely unless explicitly decommissioned. Clean teardown procedures eliminate orphaned assets and reduce clutter in enterprise AWS accounts.
