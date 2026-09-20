# Step-by-Step Technical Command Explanations: Lab 4.2

This guide breaks down every single command, IAM policy structure, and credential delivery mechanism used in **Lab 4.2: IAM Roles & Instance Profiles (Zero-Credential Architecture)**.

---

### Command 1: Creating an IAM Role with an EC2 Trust Policy

```bash
aws iam create-role \
  --role-name "ec2-labs-s3-reader-role" \
  --assume-role-policy-document file://ec2-trust-policy.json
```

#### 1. Detailed Breakdown of Every Component

• `aws iam create-role`  
Provisions a global IAM Role entity within your AWS account.

• `--assume-role-policy-document file://ec2-trust-policy.json`  
Defines the **Trust Relationship (Trust Policy)**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```
- `Principal: { "Service": "ec2.amazonaws.com" }`: Specifies that only the Amazon EC2 compute service is permitted to assume this identity.  
- `Action: "sts:AssumeRole"`: Grants the EC2 control plane permission to call the AWS Security Token Service (STS) on behalf of this role.

──────
#### 2. Why This is Critical in Production Automation

An IAM Role cannot be used by an EC2 instance unless the trust policy explicitly names `ec2.amazonaws.com`. Without this trust policy, AWS Security Token Service will reject credential generation requests.

---

### Command 2: Bridging the IAM Role into an EC2 Instance Profile

```bash
# 1. Create the Instance Profile container
aws iam create-instance-profile \
  --instance-profile-name "ec2-labs-s3-reader-profile"

# 2. Add the IAM Role into the Instance Profile container
aws iam add-role-to-instance-profile \
  --instance-profile-name "ec2-labs-s3-reader-profile" \
  --role-name "ec2-labs-s3-reader-role"
```

#### 1. Detailed Breakdown of Every Component

• What is an Instance Profile?  
In AWS Identity and Access Management, an **IAM Role** is a pure policy construct. However, the EC2 service requires a physical container called an **IAM Instance Profile** to pass that role to the hypervisor.  
When using the AWS Management Console, AWS automatically creates an instance profile with the exact same name as the IAM role behind the scenes. When using the AWS CLI or Terraform, this two-step binding must be performed explicitly.

• `add-role-to-instance-profile`  
Places the role inside the profile container. Each instance profile can contain at most one IAM role.

──────
#### 2. Why This is Critical in Production Automation

Attempting to attach an IAM role directly to an EC2 instance without creating an instance profile first will throw an `InvalidParameterValue` error. Automating this pairing is standard across Terraform (`aws_iam_instance_profile`) and CloudFormation (`AWS::IAM::InstanceProfile`).

---

### Command 3: Attaching an Instance Profile to a Running Instance (Zero Downtime)

```bash
ASSOC_ID=$(aws ec2 associate-iam-instance-profile \
  --instance-id "${INSTANCE_ID}" \
  --iam-instance-profile "Name=ec2-labs-s3-reader-profile" \
  --query "IamInstanceProfileAssociation.AssociationId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 associate-iam-instance-profile`  
Hot-attaches the IAM credentials provider to an active, running virtual machine.  
- Does **not** require stopping, rebooting, or interrupting the instance.  
- The hypervisor immediately contacts AWS STS, acquires temporary credentials, and begins vending them via the local IMDS endpoint (`169.254.169.254`).

• `--query "IamInstanceProfileAssociation.AssociationId"`  
Returns the association handle (e.g. `iip-assoc-0123456789abcdef0`), used if you ever need to replace or detach the profile later.

──────
#### 2. Why This is Critical in Production Automation

This allows security teams to elevate, restrict, or rotate permissions on production workloads dynamically without incurring any application downtime.

---

### Command 4: Inspecting STS Rotating Credentials via IMDSv2

```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/ec2-labs-s3-reader-role
```

#### 1. Detailed Breakdown of Every Component

• The Credential Vending Payload:  
The instance metadata service returns a JSON credential block:
```json
{
  "Code": "Success",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "IQoJb3JpZ2luX2VjE...",
  "Expiration": "2026-09-18T15:30:00Z"
}
```
- `ASIA...` Prefix: Denotes temporary credentials issued by AWS STS (as opposed to `AKIA...` for permanent, static user keys).  
- `Token`: The session token validating the temporary signature against AWS IAM.  
- `Expiration`: ISO-8601 timestamp (typically 6 hours). The AWS SDK automatically refreshes these credentials 15 minutes prior to expiry without restarting the application.

──────
#### 2. Why This is Critical in Production Automation

**The Zero-Credential Architecture**: By relying entirely on Instance Profiles, you completely eliminate static credentials (`aws_access_key_id` and `aws_secret_access_key`) from your instances. No secrets are stored in plaintext files (`~/.aws/credentials`), committed to git repositories, or baked into AMI images.
