#!/usr/bin/env bash
# ==============================================================================
# AWS EC2 Master Labs - Global Lab Resource Auditor & Teardown Helper
# ==============================================================================

# Command Description:
# Enable bash strict error-handling mode:
#   -e: Exit immediately if any command returns a non-zero exit status.
#   -u: Treat unset variables and parameters as an error when expanding.
#   -o pipefail: Pipeline return status is that of the last command to exit with a
#                non-zero status, preventing errors in pipe chains from being masked.
set -euo pipefail

# Command Description:
# Determine the target AWS region by querying the CLI profile config (~/.aws/config),
# falling back to the AWS_DEFAULT_REGION environment variable or 'us-east-1'.
REGION=$(aws configure get region 2>/dev/null || echo "${AWS_DEFAULT_REGION:-us-east-1}")

# Command Description:
# Print the audit header banner with the resolved region.
echo "============================================================"
echo "  AWS EC2 Master Labs: Active Resource Audit (${REGION})    "
echo "============================================================"

# ==============================================================================
# 1. Audit EC2 Instances
# ==============================================================================

# Command Description:
# Notify user that EC2 instance discovery is in progress.
echo "[*] Scanning for EC2 instances tagged with 'Project=ec2-master-labs'..."

# Command Description:
# Query EC2 instances matching the lab project tag and active lifecycle states
# (pending, running, stopping, stopped), rendering the results in an ASCII table.
INSTANCES=$(aws ec2 describe-instances \
  --region "${REGION}" \
  --filters "Name=tag:Project,Values=ec2-master-labs" "Name=instance-state-name,Values=pending,running,stopped,stopping" \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,Tags[?Key=='Name'].Value|[0]]" \
  --output table)

# Command Description:
# Print the formatted table of detected EC2 instances.
echo "${INSTANCES}"

# ==============================================================================
# 2. Audit Unattached Elastic IPs (Cost Drain Prevention)
# ==============================================================================

# Command Description:
# Notify user that unassociated Elastic IP discovery has started.
echo "[*] Scanning for unattached Elastic IPs..."

# Command Description:
# Query all Elastic IP allocations in the region that have no active instance/ENI
# association (AssociationId == null), which incur hourly idle AWS charges.
UNATTACHED_EIPS=$(aws ec2 describe-addresses \
  --region "${REGION}" \
  --query "Addresses[?AssociationId==null].[AllocationId,PublicIp]" \
  --output table)

# Command Description:
# Print the table of unattached Elastic IPs found.
echo "${UNATTACHED_EIPS}"

# ==============================================================================
# 3. Audit Unattached EBS Volumes (Storage Drain Prevention)
# ==============================================================================

# Command Description:
# Notify user that unattached EBS volume discovery is executing.
echo "[*] Scanning for unattached EBS volumes tagged with 'Project=ec2-master-labs'..."

# Command Description:
# Query EBS volumes tagged with 'Project=ec2-master-labs' that are currently in
# 'available' status (detached), preventing orphaned disk charges.
UNATTACHED_VOLS=$(aws ec2 describe-volumes \
  --region "${REGION}" \
  --filters "Name=tag:Project,Values=ec2-master-labs" "Name=status,Values=available" \
  --query "Volumes[*].[VolumeId,Size,VolumeType,AvailabilityZone]" \
  --output table)

# Command Description:
# Print the table of detached EBS volumes.
echo "${UNATTACHED_VOLS}"

# ==============================================================================
# 4. Audit Auto Scaling Groups
# ==============================================================================

# Command Description:
# Notify user that Auto Scaling Group discovery is scanning.
echo "[*] Scanning for Auto Scaling Groups tagged with 'Project=ec2-master-labs'..."

# Command Description:
# Query Auto Scaling Groups that carry the lab project tag to ensure no scaling groups
# continue launching replacement instances automatically in the background.
ASGS=$(aws autoscaling describe-auto-scaling-groups \
  --region "${REGION}" \
  --query "AutoScalingGroups[?Tags[?Key=='Project' && Value=='ec2-master-labs']].AutoScalingGroupName" \
  --output table)

# Command Description:
# Print the table of active lab Auto Scaling Groups.
echo "${ASGS}"

# ==============================================================================
# 5. Remediation & Teardown Shortcuts
# ==============================================================================

# Command Description:
# Print quick remediation helper commands for manual cleanup.
echo "============================================================"
echo "TIP: To terminate any instance directly:"
echo "     aws ec2 terminate-instances --instance-ids <INSTANCE_ID>"
echo "TIP: To release an unattached Elastic IP:"
echo "     aws ec2 release-address --allocation-id <ALLOCATION_ID>"
echo "TIP: To delete an available EBS volume:"
echo "     aws ec2 delete-volume --volume-id <VOLUME_ID>"
echo "============================================================"
