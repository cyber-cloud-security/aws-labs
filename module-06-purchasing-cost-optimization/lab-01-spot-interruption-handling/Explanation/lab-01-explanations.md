# Lab 6.1: Spot Instances & Automated 2-Minute Interruption Warning Handling - Command Explanations

This document provides a line-by-line, component-by-component architectural and operational breakdown of every command used in Lab 6.1.

---

### Command 1 & 2: Launching an EC2 Spot Instance

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
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' \
  --metadata-options "HttpEndpoint=enabled,HttpTokens=required" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=spot-worker}]" \
  --query "Instances[0].InstanceId" --output text)

echo "Launched Spot Instance: ${INSTANCE_ID}"
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
```

#### 1. Detailed Breakdown of Every Component
• `aws ec2 run-instances`: Launches virtual machine capacity in AWS.  
• `--instance-market-options`: Configures pricing and purchasing model parameters:  
  - `"MarketType": "spot"`: Informs EC2 to fulfill this request using spare, unallocated compute capacity at dynamic Spot pricing (up to 90% discount compared to On-Demand).  
  - `"SpotInstanceType": "one-time"`: Requests a single, one-off Spot instance without creating a persistent, recurring Spot fleet request.  
  - `"InstanceInterruptionBehavior": "terminate"`: Configures what happens when AWS reclaims the instance capacity. Options are `terminate`, `stop`, or `hibernate`.  
• `--metadata-options "HttpEndpoint=enabled,HttpTokens=required"`: Enforces IMDSv2 session token authentication.  
• `--query "Instances[0].InstanceId" --output text`: Extracts the newly created instance ID.  
• `aws ec2 wait instance-running`: Blocks shell execution until the instance reaches the `running` state.

──────
#### 2. Why This is Critical in Production Automation
Spot instances offer massive cost reductions for fault-tolerant, stateless, or horizontally scalable architectures (e.g., CI/CD runners, containerized microservices, batch processing). Explicitly defining `--instance-market-options` with `InstanceInterruptionBehavior` guarantees that automation cleanly handles reclamation.

---

### Command 3: Verifying Spot Lifecycle and Request ID

```bash
aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query "Reservations[0].Instances[0].[InstanceLifecycle,SpotInstanceRequestId]" \
  --output table
```

#### 1. Detailed Breakdown of Every Component
• `aws ec2 describe-instances`: Queries EC2 instance attributes.  
• `--instance-ids "${INSTANCE_ID}"`: The target instance.  
• `--query "Reservations[0].Instances[0].[InstanceLifecycle,SpotInstanceRequestId]"`: Extracts two specific attributes:  
  - `InstanceLifecycle`: Returns `spot` (for standard On-Demand instances, this attribute returns `null` or is omitted).  
  - `SpotInstanceRequestId`: The internal AWS identifier representing the fulfilled Spot bid/request (e.g., `sir-1234abcd`).  
• `--output table`: Formats the results into an ASCII table.

──────
#### 2. Why This is Critical in Production Automation
Automated deployment pipelines and configuration management scripts (Ansible, Chef, Puppet) can inspect `InstanceLifecycle` to dynamically adjust logging intensity, local cache policies, or worker deregistration handlers based on whether the host is Spot or On-Demand.

---

### Command 4: Deploying the Guest OS Spot Interruption Watchdog Daemon

```bash
cat <<'SCRIPT' > /usr/local/bin/spot_watchdog.sh
#!/bin/bash
echo "[*] Starting Spot Interruption Watchdog Daemon..."

while true; do
  # 1. Fetch IMDSv2 Token
  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)

  # 2. Query spot instance action
  HTTP_STATUS=$(curl -s -o /tmp/spot_action.json -w "%{http_code}" \
    -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/spot/instance-action)

  if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "[!] CRITICAL: Spot Interruption Notice received at $(date)!"
    cat /tmp/spot_action.json
    
    # 3. Trigger graceful application drain:
    echo "[*] Flushing local buffers to remote storage..."
    sync
    echo "[*] Application safely prepared for termination."
    exit 0
  fi

  # Poll interval: 5 seconds
  sleep 5
done
SCRIPT

chmod +x /usr/local/bin/spot_watchdog.sh
```

#### 1. Detailed Breakdown of Every Component
• `cat <<'SCRIPT' > ...`: Heredoc with quoted delimiter `'SCRIPT'` to prevent parameter expansion by the host shell, preserving variables like `$TOKEN` and `$HTTP_STATUS` for the script itself.  
• `curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60"`: Acquires an IMDSv2 session token valid for 60 seconds.  
• `curl -s -o /tmp/spot_action.json -w "%{http_code}" ... http://169.254.169.254/latest/meta-data/spot/instance-action`:  
  - `-s`: Silent mode (suppresses progress bar).  
  - `-o /tmp/spot_action.json`: Saves response body to a temporary file.  
  - `-w "%{http_code}"`: Emits only the HTTP response status code.  
• Path `/latest/meta-data/spot/instance-action`: Under normal operation, this path returns HTTP 404. Exactly 2 minutes before AWS reclaims the instance, AWS begins returning HTTP 200 with a JSON payload specifying `"action": "terminate"` and `"time": "<timestamp>"`.  
• `if [ "$HTTP_STATUS" -eq 200 ]; then ...`: Evaluates the HTTP response code. If 200, triggers the graceful drain sequence: flushes operating system buffers (`sync`), logs the event, and exits.  
• `sleep 5`: Configures polling interval to 5 seconds.  
• `chmod +x /usr/local/bin/spot_watchdog.sh`: Grants execution permissions to the script.

──────
#### 2. Why This is Critical in Production Automation
AWS guarantees a 2-minute notice before terminating a Spot instance. Polling IMDSv2 directly from within the operating system provides sub-second latency to trigger fast graceful degradation: saving application checkpoints, flushing Redis/Kafka buffers, deregistering from consul/cluster managers, and closing database connections cleanly.

---

### Command 5: Automated Teardown and Cleanup

```bash
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
echo "Lab 6.1 clean-up completed successfully."
```

#### 1. Detailed Breakdown of Every Component
• `aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"`: Sends an immediate termination signal for the instance.  
• `aws ec2 wait instance-terminated`: Polls the EC2 API until the instance status changes to `terminated`.

──────
#### 2. Why This is Critical in Production Automation
Ensures automated test environments clean up all compute resources synchronously, avoiding dangling compute charges and maintaining clean AWS account environments.
