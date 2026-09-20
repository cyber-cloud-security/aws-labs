# Lab 5.2: Application Load Balancer (ALB), Target Groups & Health Checks

## 📌 Lab Objectives
- Deploy an internet-facing **Application Load Balancer (ALB)** across multiple Availability Zones.
- Configure an **ALB Target Group** with custom HTTP health check thresholds and connection draining (**deregistration delay**).
- Register EC2 instances across different Availability Zones and monitor target health states (`healthy`, `unhealthy`, `draining`).
- Test Layer-7 request load balancing and observe round-robin distribution.

---

## 🏗️ Architecture Diagram

![Architecture Diagram](./images/architecture-lab-02.png)

<details>
<summary>Click to expand Mermaid diagram source</summary>

![Architecture Diagram](./images/architecture-lab-02.png)

<details>
<summary>Click to expand Mermaid diagram source</summary>

![Architecture Diagram](./images/architecture-lab-02.png)

<details>
<summary>Click to expand Mermaid diagram source</summary>

```mermaid
flowchart TD
    Client["Public Client Traffic"]

    subgraph ALBCluster["Application Load Balancer (Layer 7)"]
        Listener["HTTP Listener :80"]
        Rule["Routing Rule (Default Forward)"]
        Listener --> Rule
    end

    subgraph TargetGroup["ALB Target Group (Port 80 / HTTP)"]
        HC["Active Health Check: GET / (Interval: 15s)"]
    end

    subgraph MultiAZ["Multi-AZ Subnets"]
        EC2_A["EC2 Node A\n(AZ: us-east-1a)\nStatus: Healthy"]
        EC2_B["EC2 Node B\n(AZ: us-east-1b)\nStatus: Healthy"]
    end

    Client -->|HTTP Request| Listener
    Rule --> TargetGroup
    TargetGroup -->|Round-Robin Load Balancing| EC2_A
    TargetGroup -->|Round-Robin Load Balancing| EC2_B
    HC -.->|Periodic Ping| EC2_A
    HC -.->|Periodic Ping| EC2_B
```
</details>
</details>
</details>

---

## 💡 Key Architectural Concepts

1. **Target Group Health Checks**:
   - The ALB periodically sends HTTP requests to each registered target.
   - If a target fails consecutive checks matching `UnhealthyThresholdCount`, the ALB stops routing traffic to it immediately.
2. **Deregistration Delay (Connection Draining)**:
   - When an instance is removed or deregistered, the ALB stops sending *new* requests but gives active in-flight requests a graceful window (default 300 seconds, customizable down to 5 seconds) to complete.
3. **Cross-Zone Load Balancing**:
   - ALBs distribute traffic evenly across all registered targets in all enabled Availability Zones, regardless of which AZ received the client connection.

---

## ⏱️ Prerequisites & Cost
- **Cost Warning**: ALBs are billed at ~$0.0225/hour plus LCU usage. Run the test and execute teardown promptly (estimated cost < $0.05).
- **Estimated Duration**: 20 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Launch Two Web Server Instances Across Separate AZs
```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[0].SubnetId" --output text)
SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[1].SubnetId" --output text)

AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

# Launch Node A (Subnet 1)
NODE_A_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_1}" \
  --user-data "#!/bin/bash
dnf install -y nginx
echo 'Server: NODE-A' > /usr/share/nginx/html/index.html
systemctl start nginx" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=node-a}]" \
  --query "Instances[0].InstanceId" --output text)

# Launch Node B (Subnet 2)
NODE_B_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_2}" \
  --user-data "#!/bin/bash
dnf install -y nginx
echo 'Server: NODE-B' > /usr/share/nginx/html/index.html
systemctl start nginx" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=node-b}]" \
  --query "Instances[0].InstanceId" --output text)

echo "Waiting for instances to boot..."
aws ec2 wait instance-running --instance-ids "${NODE_A_ID}" "${NODE_B_ID}"
```

### Step 2: Create Security Group for ALB
```bash
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name "alb-lab-sg" \
  --description "Inbound HTTP for Application Load Balancer" \
  --vpc-id "${VPC_ID}" \
  --query "GroupId" --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "${ALB_SG_ID}" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

### Step 3: Create Target Group with Custom Health Check
```bash
TG_ARN=$(aws elbv2 create-target-group \
  --name "tg-ec2-labs" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "${VPC_ID}" \
  --health-check-protocol HTTP \
  --health-check-path "/" \
  --health-check-interval-seconds 15 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --target-type instance \
  --query "TargetGroups[0].TargetGroupArn" --output text)

# Set Deregistration Delay to 30 seconds for fast draining in labs:
aws elbv2 modify-target-group-attributes \
  --target-group-arn "${TG_ARN}" \
  --attributes "Key=deregistration_delay.timeout_seconds,Value=30"

echo "Created Target Group: ${TG_ARN}"
```

### Step 4: Register Instances to Target Group
```bash
aws elbv2 register-targets \
  --target-group-arn "${TG_ARN}" \
  --targets "Id=${NODE_A_ID}" "Id=${NODE_B_ID}"

echo "Registered nodes with Target Group."
```

### Step 5: Provision Application Load Balancer & Listener
```bash
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "alb-ec2-labs" \
  --subnets "${SUBNET_1}" "${SUBNET_2}" \
  --security-groups "${ALB_SG_ID}" \
  --scheme internet-facing \
  --type application \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)

echo "Waiting for ALB to become active..."
aws elbv2 wait load-balancer-available --load-balancer-arns "${ALB_ARN}"

# Create Listener forwarding to Target Group
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn "${ALB_ARN}" \
  --protocol HTTP \
  --port 80 \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --query "Listeners[0].ListenerArn" --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "${ALB_ARN}" \
  --query "LoadBalancers[0].DNSName" --output text)

echo "ALB Ready at: http://${ALB_DNS}"
```

---

## 🔍 Verification & Testing

### 1. Wait for Targets to Become Healthy
```bash
aws elbv2 describe-target-health \
  --target-group-arn "${TG_ARN}" \
  --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]" \
  --output table
```
Wait until both targets display `healthy`.

### 2. Test Load Balancing Distribution
Send repeated curl requests to the ALB DNS name:
```bash
for i in {1..6}; do
  curl -s "http://${ALB_DNS}"
done
```
**Expected Output**: Alternating responses:
```text
Server: NODE-A
Server: NODE-B
Server: NODE-A
Server: NODE-B
...
```

---

## 🧹 Teardown & Clean-up

```bash
# 1. Delete ALB and Listener
aws elbv2 delete-load-balancer --load-balancer-arn "${ALB_ARN}"
sleep 10
aws elbv2 delete-target-group --target-group-arn "${TG_ARN}"

# 2. Terminate instances
aws ec2 terminate-instances --instance-ids "${NODE_A_ID}" "${NODE_B_ID}"
aws ec2 wait instance-terminated --instance-ids "${NODE_A_ID}" "${NODE_B_ID}"

# 3. Delete Security Group
aws ec2 delete-security-group --group-id "${ALB_SG_ID}"

echo "Lab 5.2 clean-up completed successfully."
```
