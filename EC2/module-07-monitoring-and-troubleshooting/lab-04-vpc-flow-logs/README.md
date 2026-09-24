<div align="center">

# 🔬 Lab 7.4: VPC Flow Logs & Network Traffic Forensics

**[🏠 AWS Labs Root](../../../README.md)** &nbsp;•&nbsp; **[🖥️ EC2 Curriculum](../../README.md)** &nbsp;•&nbsp; **[📂 Module 07](../README.md)**

![⏱️ Duration](https://img.shields.io/badge/%E2%8F%B1%EF%B8%8F_Duration-20_minutes-0969da?style=flat-square) ![💰 Cost](https://img.shields.io/badge/%F0%9F%92%B0_Cost-Free_Tier_Eligible-2da44e?style=flat-square) ![🎯 Level](https://img.shields.io/badge/%F0%9F%8E%AF_Level-Intermediate_to_Advanced-8250df?style=flat-square) ![📂 Module](https://img.shields.io/badge/%F0%9F%93%82_Module-07_%E2%80%94_Monitoring-fd8c73?style=flat-square)

**[⬅️ Previous Lab](../../module-07-monitoring-and-troubleshooting/lab-03-serial-console-ebs-rescue/README.md)** &nbsp;|&nbsp; **[➡️ Next Lab](../../module-08-advanced-nitro/lab-01-nitro-architecture/README.md)**

</div>

---

## 📌 Lab Objectives

- [x] Enable **VPC Flow Logs** targeting an EC2 instance's Elastic Network Interface (ENI).
- [x] Deliver flow logs to an **Amazon CloudWatch Logs** log group.
- [x] Generate intentional network drops (security group block) and inspect the resulting `REJECT` log records.
- [x] Author **CloudWatch Logs Insights** queries to identify top talkers, malicious port scans, and firewall drop anomalies.

---

## 🏗️ Architecture Diagram

![Architecture Diagram](./images/architecture-lab-04.png)

<details>
<summary>📐 <b>View Mermaid Architecture Source (Click to Expand)</b></summary>

```mermaid
flowchart LR
    subgraph TrafficSource["External Traffic"]
        AllowedTraffic["HTTP Request Port 80 - Allowed by SG"]
        BlockedTraffic["SSH Attack Scan Port 22 - Blocked by SG"]
    end

    subgraph EC2Bound["EC2 ENI eth0"]
        ENI["Elastic Network Interface - VPC Flow Log Collector"]
    end

    subgraph CloudWatch["Amazon CloudWatch Logs"]
        LG["Log Group: aws vpc flow-logs"]
        Insights["CloudWatch Logs Insights - Query REJECT"]
        LG --> Insights
    end

    AllowedTraffic -->|"ACCEPT record"| ENI
    BlockedTraffic -->|"REJECT record"| ENI
    ENI -->|"Deliver batches every 1 to 10 mins"| LG
```

</details>

---

## 💡 Key Architectural Concepts

### Flow Log Record Format
A standard flow log entry:
```text
2 123456789010 eni-0a1b2c3d4e5f 198.51.100.2 172.31.1.50 54321 80 6 10 840 1695000000 1695000060 ACCEPT OK
```
- `eni-0a1b2c3d...`: The target ENI.
- `198.51.100.2`: Source IP.
- `172.31.1.50`: Destination IP (the EC2 instance).
- `54321`: Source port.
- `80`: Destination port.
- `6`: Protocol (`6` = TCP, `17` = UDP, `1` = ICMP).
- `ACCEPT` / `REJECT`: Action taken by Security Group or NACL.

---

## ⏱️ Prerequisites & Cost

> [!TIP]
> **AWS Free Tier & Cost Guardrail**
> - **AWS Free Tier Eligible**: Yes.
> - **Estimated Duration**: 20 minutes.

---

## 🚀 Step-by-Step Instructions

### Step 1: Create IAM Role for Flow Logs Publishing
```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

cat <<JSON > flow-role-trust.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "vpc-flow-logs.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

FLOW_ROLE_ARN=$(aws iam create-role \
  --role-name "ec2-vpc-flow-logs-publisher" \
  --assume-role-policy-document file://flow-role-trust.json \
  --query "Role.Arn" --output text 2>/dev/null || \
  aws iam get-role \
    --role-name "ec2-vpc-flow-logs-publisher" \
    --query "Role.Arn" \
    --output text)

cat <<JSON > flow-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
JSON

aws iam put-role-policy \
  --role-name "ec2-vpc-flow-logs-publisher" \
  --policy-name "VPCFlowLogsDelivery" \
  --policy-document file://flow-policy.json
```

### Step 2: Create CloudWatch Log Group & Enable Flow Logs
```bash
# 1. Create CloudWatch Log Group
aws logs create-log-group --log-group-name "/aws/vpc/ec2-labs-flowlogs" 2>/dev/null || true

# 2. Enable Flow Log on the VPC
FLOW_LOG_ID=$(aws ec2 create-flow-logs \
  --resource-type "VPC" \
  --resource-ids "${VPC_ID}" \
  --traffic-type "ALL" \
  --log-destination-type "cloud-watch-logs" \
  --log-group-name "/aws/vpc/ec2-labs-flowlogs" \
  --deliver-logs-permission-arn "${FLOW_ROLE_ARN}" \
  --query "FlowLogIds[0]" --output text)

echo "Enabled Flow Log: ${FLOW_LOG_ID}"
```

---

## 🔍 Verification & Logs Insights Querying

### 1. Trigger Blocked Connection (Simulated Attack)
Find any running EC2 public IP and send packets to closed port 22 or port 4444:
```bash
# Test connection that gets dropped by Security Group:
nc -z -v -w 2 <EC2_PUBLIC_IP> 22 || true
```

### 2. Query Flow Logs with CloudWatch Logs Insights
Run this CloudWatch Insights query in the AWS Console or via AWS CLI to uncover dropped packets:

```bash
QUERY_ID=$(aws logs start-query \
  --log-group-name "/aws/vpc/ec2-labs-flowlogs" \
  --start-time $(date -v -1H +%s 2>/dev/null || date -d "1 hour ago" +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count(*) as dropCount by srcAddr, dstPort
| sort dropCount desc
| limit 10' \
  --query "queryId" --output text)

echo "Executed query ID: ${QUERY_ID}"
```

Retrieve results:
```bash
aws logs get-query-results --query-id "${QUERY_ID}"
```
**Insight**: Shows exact source IP addresses attempting connections to rejected ports.

---

## 📘 Deep-Dive Command & Flag Reference

> [!TIP]
> **Line-by-Line Production Analysis**: Every command executed in this lab is dissected below, explaining each CLI flag, JMESPath query, Linux kernel parameter, and why it is critical in production automation.

<details open>
<summary>📘 <b>Command 1 & 2: Creating the IAM Role for VPC Flow Logs Delivery</b></summary>

```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

cat <<JSON > flow-role-trust.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "vpc-flow-logs.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

FLOW_ROLE_ARN=$(aws iam create-role \
  --role-name "ec2-vpc-flow-logs-publisher" \
  --assume-role-policy-document file://flow-role-trust.json \
  --query "Role.Arn" --output text 2>/dev/null || \
  aws iam get-role \
    --role-name "ec2-vpc-flow-logs-publisher" \
    --query "Role.Arn" \
    --output text)

cat <<JSON > flow-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
JSON

aws iam put-role-policy \
  --role-name "ec2-vpc-flow-logs-publisher" \
  --policy-name "VPCFlowLogsDelivery" \
  --policy-document file://flow-policy.json
```

#### 🔍 Parameter & Component Breakdown
- **`flow-role-trust.json`** — Establishes the trust policy allowing the AWS VPC Flow Logs daemon (`vpc-flow-logs.amazonaws.com`) to assume the role.
- **`FLOW_ROLE_ARN=$(aws iam create-role ... || aws iam get-role ...)`** — Provisions the role and extracts its Amazon Resource Name (ARN), falling back gracefully to query the ARN if the role already exists.
- **`flow-policy.json`** — Inline permissions policy granting authorization to create log streams and publish log event batches (`logs:PutLogEvents`) into Amazon CloudWatch Logs.
- **`aws iam put-role-policy`** — Attaches the permissions policy to the IAM delivery role.

> 🏭 **Why This Matters in Production Automation**
> VPC Flow Logs operate completely outside the guest EC2 operating system at the virtual network interface hypervisor boundary. Because AWS manages this capture asynchronously, AWS requires an IAM role with explicit CloudWatch publishing permissions to stream captured packet logs on behalf of the customer.

</details>

<details open>
<summary>📘 <b>Command 3: Provisioning CloudWatch Log Group and Enabling VPC Flow Logs</b></summary>

```bash
aws logs create-log-group --log-group-name "/aws/vpc/ec2-labs-flowlogs" 2>/dev/null || true

FLOW_LOG_ID=$(aws ec2 create-flow-logs \
  --resource-type "VPC" \
  --resource-ids "${VPC_ID}" \
  --traffic-type "ALL" \
  --log-destination-type "cloud-watch-logs" \
  --log-group-name "/aws/vpc/ec2-labs-flowlogs" \
  --deliver-logs-permission-arn "${FLOW_ROLE_ARN}" \
  --query "FlowLogIds[0]" --output text)

echo "Enabled Flow Log: ${FLOW_LOG_ID}"
```

#### 🔍 Parameter & Component Breakdown
- **`aws logs create-log-group`** — Creates the destination log group container `/aws/vpc/ec2-labs-flowlogs` in CloudWatch Logs.
- **`aws ec2 create-flow-logs`** — Creates a flow log subscription on the VPC network plane.
- **`--resource-type "VPC"`** — Scopes traffic monitoring across the entire VPC (can also target a specific `Subnet` or `NetworkInterface`).
- **`--resource-ids "${VPC_ID}"`** — The target resource identifier.
- **`--traffic-type "ALL"`** — Captures both accepted traffic (`ACCEPT`) and dropped/rejected traffic (`REJECT`).
- **`--log-destination-type "cloud-watch-logs"`** — Specifies CloudWatch as the delivery target (alternative is `s3` or `kinesis-data-firehose`).
- **`--log-group-name "/aws/vpc/ec2-labs-flowlogs"`** — Destination log group path.
- **`--deliver-logs-permission-arn "${FLOW_ROLE_ARN}"`** — Supplies the IAM delivery role ARN.
- **`--query "FlowLogIds[0]" --output text`** — Captures the flow log identifier (e.g. `fl-0123456789abcdef0`).

> 🏭 **Why This Matters in Production Automation**
> VPC Flow Logs capture all IP traffic entering and leaving network interfaces in the VPC. Capturing `ALL` traffic is critical for security audits, forensic investigations, compliance verification (PCI-DSS, SOC 2, HIPAA), and troubleshooting firewall and security group misconfigurations.

</details>

<details open>
<summary>📘 <b>Command 4: Simulating Network Rejection</b></summary>

```bash
nc -z -v -w 2 <EC2_PUBLIC_IP> 22 || true
```

#### 🔍 Parameter & Component Breakdown
- **`nc`** — Netcat utility for arbitrary TCP and UDP connections.
- **`-z`** — Zero-I/O mode (scans for listening daemons without transmitting payload data).
- **`-v`** — Verbose output.
- **`-w 2`** — Sets connection timeout to 2 seconds.
- **`<EC2_PUBLIC_IP> 22`** — Targets port 22 on the EC2 instance. Assuming the Security Group does not authorize ingress port 22 from the source, the connection will be dropped.
- **`|| true`** — Prevents netcat non-zero exit codes from terminating automated scripts.

> 🏭 **Why This Matters in Production Automation**
> Generates intentional firewall drop telemetry to validate that network monitoring and security event pipelines detect dropped packets.

</details>

<details open>
<summary>📘 <b>Command 5 & 6: Querying Flow Logs with CloudWatch Logs Insights</b></summary>

```bash
QUERY_ID=$(aws logs start-query \
  --log-group-name "/aws/vpc/ec2-labs-flowlogs" \
  --start-time $(date -v -1H +%s 2>/dev/null || date -d "1 hour ago" +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count(*) as dropCount by srcAddr, dstPort
| sort dropCount desc
| limit 10' \
  --query "queryId" --output text)

echo "Executed query ID: ${QUERY_ID}"

aws logs get-query-results --query-id "${QUERY_ID}"
```

#### 🔍 Parameter & Component Breakdown
- **`aws logs start-query`** — Asynchronously launches a distributed analytical search job across log streams in CloudWatch Logs Insights.
- **`--log-group-name "/aws/vpc/ec2-labs-flowlogs"`** — Target log group.
- **`--start-time` & `--end-time`** — Defines the query time window in UNIX epoch seconds (past 1 hour up to current timestamp). Handles both macOS (`date -v -1H +%s`) and Linux (`date -d "1 hour ago" +%s`).
- **`--query-string`** — The CloudWatch Insights query syntax:
  - **`fields @timestamp, srcAddr, dstAddr, dstPort, action`** — Dissects standard VPC Flow Log fields.
  - **`filter action = "REJECT"`** — Filters solely for packets dropped by Security Groups or Network ACLs.
  - **`stats count(*) as dropCount by srcAddr, dstPort`** — Aggregates and counts dropped packets grouped by offending source IP and targeted destination port.
  - **`sort dropCount desc | limit 10`** — Returns the top 10 most frequent drop events.
- **`aws logs get-query-results --query-id "${QUERY_ID}"`** — Retrieves the computed aggregation results.

> 🏭 **Why This Matters in Production Automation**
> Provides automated threat intelligence and network forensics. Security automation can run scheduled Insights queries to detect malicious port scans, brute-force SSH attacks, or unauthorized lateral movement attempts within the VPC, feeding bad actor IPs into AWS WAF or automated NACL blocklists.

</details>

<details open>
<summary>📘 <b>Command 7: Automated Teardown and Cleanup</b></summary>

```bash
aws ec2 delete-flow-logs --flow-log-ids "${FLOW_LOG_ID}"
aws logs delete-log-group --log-group-name "/aws/vpc/ec2-labs-flowlogs" 2>/dev/null || true
aws iam delete-role-policy \
  --role-name "ec2-vpc-flow-logs-publisher" \
  --policy-name "VPCFlowLogsDelivery"
aws iam delete-role --role-name "ec2-vpc-flow-logs-publisher"
rm -f flow-role-trust.json flow-policy.json
```

#### 🔍 Parameter & Component Breakdown
- **`aws ec2 delete-flow-logs`** — Halts packet capture and deletes the subscription.
- **`aws logs delete-log-group`** — Removes stored flow log records.
- **`aws iam ...`** — Deletes the inline policy and delivery role.
- **`rm -f ...`** — Removes local temporary JSON files.

> 🏭 **Why This Matters in Production Automation**
> Active VPC flow logs and large CloudWatch log groups generate ongoing data ingestion and storage costs. Proper teardown ensures zero billing leakage upon lab conclusion.

</details>

---

## 🧹 Teardown & Clean-up


> [!CAUTION]
> **Always Tear Down Lab Resources**: Execute the cleanup commands below immediately after completing the verification steps to prevent unintended AWS billing.

```bash
# 1. Delete Flow Log
aws ec2 delete-flow-logs --flow-log-ids "${FLOW_LOG_ID}"

# 2. Delete Log Group
aws logs delete-log-group --log-group-name "/aws/vpc/ec2-labs-flowlogs" 2>/dev/null || true

# 3. Clean up IAM Role
aws iam delete-role-policy \
  --role-name "ec2-vpc-flow-logs-publisher" \
  --policy-name "VPCFlowLogsDelivery"
aws iam delete-role --role-name "ec2-vpc-flow-logs-publisher"
rm -f flow-role-trust.json flow-policy.json

echo "Lab 7.4 clean-up completed successfully."
```

---

<div align="center">

**[⬅️ Previous Lab](../../module-07-monitoring-and-troubleshooting/lab-03-serial-console-ebs-rescue/README.md)** &nbsp;•&nbsp; **[⬆️ Back to Module 07](../README.md)** &nbsp;•&nbsp; **[🏠 EC2 Index](../../README.md)** &nbsp;•&nbsp; **[➡️ Next Lab](../../module-08-advanced-nitro/lab-01-nitro-architecture/README.md)**

</div>
