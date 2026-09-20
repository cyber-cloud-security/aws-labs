# Lab 7.4: VPC Flow Logs & Network Traffic Forensics - Command Explanations

This document provides a line-by-line, component-by-component architectural and operational breakdown of every command used in Lab 7.4.

---

### Command 1 & 2: Creating the IAM Role for VPC Flow Logs Delivery

```bash
export AWS_REGION=$(aws configure get region || echo "us-east-1")
export VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

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
  aws iam get-role --role-name "ec2-vpc-flow-logs-publisher" --query "Role.Arn" --output text)

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

#### 1. Detailed Breakdown of Every Component
• `flow-role-trust.json`: Establishes the trust policy allowing the AWS VPC Flow Logs daemon (`vpc-flow-logs.amazonaws.com`) to assume the role.  
• `FLOW_ROLE_ARN=$(aws iam create-role ... || aws iam get-role ...)`: Provisions the role and extracts its Amazon Resource Name (ARN), falling back gracefully to query the ARN if the role already exists.  
• `flow-policy.json`: Inline permissions policy granting authorization to create log streams and publish log event batches (`logs:PutLogEvents`) into Amazon CloudWatch Logs.  
• `aws iam put-role-policy`: Attaches the permissions policy to the IAM delivery role.

──────
#### 2. Why This is Critical in Production Automation
VPC Flow Logs operate completely outside the guest EC2 operating system at the virtual network interface hypervisor boundary. Because AWS manages this capture asynchronously, AWS requires an IAM role with explicit CloudWatch publishing permissions to stream captured packet logs on behalf of the customer.

---

### Command 3: Provisioning CloudWatch Log Group and Enabling VPC Flow Logs

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

#### 1. Detailed Breakdown of Every Component
• `aws logs create-log-group`: Creates the destination log group container `/aws/vpc/ec2-labs-flowlogs` in CloudWatch Logs.  
• `aws ec2 create-flow-logs`: Creates a flow log subscription on the VPC network plane.  
• `--resource-type "VPC"`: Scopes traffic monitoring across the entire VPC (can also target a specific `Subnet` or `NetworkInterface`).  
• `--resource-ids "${VPC_ID}"`: The target resource identifier.  
• `--traffic-type "ALL"`: Captures both accepted traffic (`ACCEPT`) and dropped/rejected traffic (`REJECT`).  
• `--log-destination-type "cloud-watch-logs"`: Specifies CloudWatch as the delivery target (alternative is `s3` or `kinesis-data-firehose`).  
• `--log-group-name "/aws/vpc/ec2-labs-flowlogs"`: Destination log group path.  
• `--deliver-logs-permission-arn "${FLOW_ROLE_ARN}"`: Supplies the IAM delivery role ARN.  
• `--query "FlowLogIds[0]" --output text`: Captures the flow log identifier (e.g. `fl-0123456789abcdef0`).

──────
#### 2. Why This is Critical in Production Automation
VPC Flow Logs capture all IP traffic entering and leaving network interfaces in the VPC. Capturing `ALL` traffic is critical for security audits, forensic investigations, compliance verification (PCI-DSS, SOC 2, HIPAA), and troubleshooting firewall and security group misconfigurations.

---

### Command 4: Simulating Network Rejection

```bash
nc -z -v -w 2 <EC2_PUBLIC_IP> 22 || true
```

#### 1. Detailed Breakdown of Every Component
• `nc`: Netcat utility for arbitrary TCP and UDP connections.  
• `-z`: Zero-I/O mode (scans for listening daemons without transmitting payload data).  
• `-v`: Verbose output.  
• `-w 2`: Sets connection timeout to 2 seconds.  
• `<EC2_PUBLIC_IP> 22`: Targets port 22 on the EC2 instance. Assuming the Security Group does not authorize ingress port 22 from the source, the connection will be dropped.  
• `|| true`: Prevents netcat non-zero exit codes from terminating automated scripts.

──────
#### 2. Why This is Critical in Production Automation
Generates intentional firewall drop telemetry to validate that network monitoring and security event pipelines detect dropped packets.

---

### Command 5 & 6: Querying Flow Logs with CloudWatch Logs Insights

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

#### 1. Detailed Breakdown of Every Component
• `aws logs start-query`: Asynchronously launches a distributed analytical search job across log streams in CloudWatch Logs Insights.  
• `--log-group-name "/aws/vpc/ec2-labs-flowlogs"`: Target log group.  
• `--start-time` & `--end-time`: Defines the query time window in UNIX epoch seconds (past 1 hour up to current timestamp). Handles both macOS (`date -v -1H +%s`) and Linux (`date -d "1 hour ago" +%s`).  
• `--query-string`: The CloudWatch Insights query syntax:  
  - `fields @timestamp, srcAddr, dstAddr, dstPort, action`: Dissects standard VPC Flow Log fields.  
  - `filter action = "REJECT"`: Filters solely for packets dropped by Security Groups or Network ACLs.  
  - `stats count(*) as dropCount by srcAddr, dstPort`: Aggregates and counts dropped packets grouped by offending source IP and targeted destination port.  
  - `sort dropCount desc | limit 10`: Returns the top 10 most frequent drop events.  
• `aws logs get-query-results --query-id "${QUERY_ID}"`: Retrieves the computed aggregation results.

──────
#### 2. Why This is Critical in Production Automation
Provides automated threat intelligence and network forensics. Security automation can run scheduled Insights queries to detect malicious port scans, brute-force SSH attacks, or unauthorized lateral movement attempts within the VPC, feeding bad actor IPs into AWS WAF or automated NACL blocklists.

---

### Command 7: Automated Teardown and Cleanup

```bash
aws ec2 delete-flow-logs --flow-log-ids "${FLOW_LOG_ID}"
aws logs delete-log-group --log-group-name "/aws/vpc/ec2-labs-flowlogs" 2>/dev/null || true
aws iam delete-role-policy --role-name "ec2-vpc-flow-logs-publisher" --policy-name "VPCFlowLogsDelivery"
aws iam delete-role --role-name "ec2-vpc-flow-logs-publisher"
rm -f flow-role-trust.json flow-policy.json
```

#### 1. Detailed Breakdown of Every Component
• `aws ec2 delete-flow-logs`: Halts packet capture and deletes the subscription.  
• `aws logs delete-log-group`: Removes stored flow log records.  
• `aws iam ...`: Deletes the inline policy and delivery role.  
• `rm -f ...`: Removes local temporary JSON files.

──────
#### 2. Why This is Critical in Production Automation
Active VPC flow logs and large CloudWatch log groups generate ongoing data ingestion and storage costs. Proper teardown ensures zero billing leakage upon lab conclusion.
