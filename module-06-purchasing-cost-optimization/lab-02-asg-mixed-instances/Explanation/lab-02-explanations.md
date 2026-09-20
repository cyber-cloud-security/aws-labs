# Lab 6.2: Auto Scaling Groups with Mixed Instances Policy (Spot + On-Demand) - Command Explanations

This document provides a line-by-line, component-by-component architectural and operational breakdown of every command used in Lab 6.2.

---

### Command 1 & 2: Environment Discovery and Base Launch Template Creation

```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)
SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[0].SubnetId" --output text)
SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[1].SubnetId" --output text)

AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" --output text)

cat <<JSON > mixed-lt.json
{
  "ImageId": "${AMI_ID}",
  "MetadataOptions": { "HttpTokens": "required" }
}
JSON

LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "lt-mixed-demo" \
  --launch-template-data file://mixed-lt.json \
  --query "LaunchTemplate.LaunchTemplateId" --output text)
```

#### 1. Detailed Breakdown of Every Component
• `export AWS_REGION=...`, `VPC_ID=...`, `SUBNET_1=...`, `SUBNET_2=...`: Discovers networking topology across two distinct Availability Zones for multi-AZ resiliency.  
• `AMI_ID=$(aws ssm get-parameter ...)`: Resolves the latest Amazon Linux 2023 AMI identifier dynamically.  
• `cat <<JSON > mixed-lt.json`: Generates the Launch Template specification. Note that `InstanceType` is omitted from the template body; instance types will be injected dynamically via the Mixed Instances Policy overrides.  
• `"MetadataOptions": { "HttpTokens": "required" }`: Enforces IMDSv2 token security across all fleet instances.  
• `LT_ID=$(aws ec2 create-launch-template ...)`: Creates the launch template and captures its ID.

──────
#### 2. Why This is Critical in Production Automation
Separating the machine image and bootstrap definitions from specific instance types allows a single template to back diverse instance families simultaneously without duplicate configuration drift.

---

### Command 3: Authoring the Mixed Instances Policy Specification

```bash
cat <<JSON > mixed-policy.json
{
  "LaunchTemplate": {
    "LaunchTemplateSpecification": {
      "LaunchTemplateId": "${LT_ID}",
      "Version": "\$Latest"
    },
    "Overrides": [
      { "InstanceType": "t3.micro" },
      { "InstanceType": "t3a.micro" },
      { "InstanceType": "t2.micro" }
    ]
  },
  "InstancesDistribution": {
    "OnDemandAllocationStrategy": "prioritized",
    "OnDemandBaseCapacity": 1,
    "OnDemandPercentageAboveBaseCapacity": 20,
    "SpotAllocationStrategy": "price-capacity-optimized"
  }
}
JSON
```

#### 1. Detailed Breakdown of Every Component
• `"LaunchTemplateSpecification"`: Binds the ASG to our base Launch Template using the dynamic `$Latest` version.  
• `"Overrides"`: Defines the instance type diversification list. The ASG can fulfill compute capacity using `t3.micro` (Intel), `t3a.micro` (AMD EPYC), or `t2.micro`.  
• `"InstancesDistribution"`: Dictates the purchasing model distribution:  
  - `"OnDemandAllocationStrategy": "prioritized"`: Launches On-Demand instances in the priority order specified by the `Overrides` list (prefers `t3.micro` first).  
  - `"OnDemandBaseCapacity": 1`: Guarantees that the first instance in the cluster is strictly On-Demand. It will never be interrupted.  
  - `"OnDemandPercentageAboveBaseCapacity": 20`: For any capacity beyond the base 1 instance, 20% will be On-Demand and 80% will be Spot.  
  - `"SpotAllocationStrategy": "price-capacity-optimized"`: Evaluates pool depth and price, provisioning Spot instances from pools with the highest spare capacity to minimize interruption frequency.

──────
#### 2. Why This is Critical in Production Automation
Relying on a single Spot instance type introduces severe availability risks if AWS reclaims capacity in that specific pool. Instance type diversification across multiple families and architectures ensures high availability, while `OnDemandBaseCapacity` ensures baseline cluster stability at up to 80% total cost savings.

---

### Command 4: Deploying the ASG with Mixed Instances Policy

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "asg-mixed-fleet-demo" \
  --mixed-instances-policy file://mixed-policy.json \
  --min-size 1 \
  --max-size 5 \
  --desired-capacity 3 \
  --vpc-zone-identifier "${SUBNET_1},${SUBNET_2}"

sleep 25
```

#### 1. Detailed Breakdown of Every Component
• `aws autoscaling create-auto-scaling-group`: Launches the Auto Scaling Group.  
• `--mixed-instances-policy file://mixed-policy.json`: Uses the mixed purchasing model rather than a standard single-type launch template.  
• `--min-size 1 --max-size 5 --desired-capacity 3`: Requests 3 total instances. According to our policy, 1 node is guaranteed On-Demand base, and the remaining 2 nodes are allocated according to the 20/80 split (resulting in Spot nodes).  
• `--vpc-zone-identifier "${SUBNET_1},${SUBNET_2}"`: Spans the instances across multiple Availability Zones.  
• `sleep 25`: Allows time for the ASG engine to evaluate pools, fulfill spot bids, and boot instances.

──────
#### 2. Why This is Critical in Production Automation
Declarative configuration via `--mixed-instances-policy` eliminates complex custom fleet provisioning scripts, allowing AWS's native control plane to manage Spot requests, pool monitoring, and automatic failover transparently.

---

### Command 5: Auditing Instance Types and Pricing Distribution

```bash
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=asg-mixed-fleet-demo" \
  --query "Reservations[*].Instances[*].[InstanceId,InstanceType,InstanceLifecycle||'on-demand',Placement.AvailabilityZone]" \
  --output table
```

#### 1. Detailed Breakdown of Every Component
• `aws ec2 describe-instances`: Queries EC2 instance attributes.  
• `--filters "Name=tag:aws:autoscaling:groupName,Values=asg-mixed-fleet-demo"`: Filters for instances managed by our ASG (AWS automatically tags instances with the ASG group name).  
• `--query "...[InstanceId,InstanceType,InstanceLifecycle||'on-demand',Placement.AvailabilityZone]"`: JMESPath projection pulling:  
  - `InstanceId`: Physical EC2 ID.  
  - `InstanceType`: Demonstrates diversification (e.g. `t3.micro` vs `t3a.micro`).  
  - `InstanceLifecycle||'on-demand'`: Shows `spot` for Spot nodes or falls back to literal `'on-demand'` for On-Demand nodes.  
  - `Placement.AvailabilityZone`: Verifies balanced deployment across multiple AZs.  
• `--output table`: Outputs a clean tabular overview.

──────
#### 2. Why This is Critical in Production Automation
Verifies that the mixed fleet policy complied precisely with architectural boundaries: proving that the base node is running On-Demand while secondary surge nodes are running on diversified Spot capacity across multiple AZs.

---

### Command 6: Automated Teardown and Cleanup

```bash
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "asg-mixed-fleet-demo" \
  --min-size 0 \
  --desired-capacity 0

sleep 15
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "asg-mixed-fleet-demo" \
  --force-delete

aws ec2 delete-launch-template --launch-template-id "${LT_ID}"
rm -f mixed-lt.json mixed-policy.json
```

#### 1. Detailed Breakdown of Every Component
• `aws autoscaling update-auto-scaling-group ... --min-size 0 --desired-capacity 0`: Triggers termination of all active On-Demand and Spot instances.  
• `aws autoscaling delete-auto-scaling-group --force-delete`: Destroys the ASG definition.  
• `aws ec2 delete-launch-template`: Removes the base Launch Template.  
• `rm -f mixed-lt.json mixed-policy.json`: Deletes local configuration files.

──────
#### 2. Why This is Critical in Production Automation
Clean removal of multi-instance pools prevents lingering compute costs and avoids resource collisions during continuous integration test suite executions.
