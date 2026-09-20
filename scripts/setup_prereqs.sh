#!/usr/bin/env bash
# ==============================================================================
# AWS EC2 Master Labs - Pre-flight Verification Script
# ==============================================================================

# Command Description:
# Enable bash strict error-handling mode:
#   -e: Exit immediately if any command returns a non-zero exit status.
#   -u: Treat unset variables and parameters as an error when expanding.
#   -o pipefail: Pipeline return status is that of the last command to exit with a
#                non-zero status, preventing errors in pipe chains from being masked.
set -euo pipefail

# Command Description:
# Print script header banner to the terminal output.
echo "============================================================"
echo "  AWS EC2 Master Labs: Pre-flight Environment Verification  "
echo "============================================================"

# ==============================================================================
# 1. Check AWS CLI Installation
# ==============================================================================

# Command Description:
# Check if the 'aws' executable is present and accessible in the system's PATH.
# Redirects both stdout and stderr to /dev/null for silent exit code verification.
if ! command -v aws &>/dev/null; then
  # Command Description:
  # Display an error message and provide the official installation guide URL.
  echo "[-] ERROR: AWS CLI is not installed."
  echo "    Install instructions: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  
  # Command Description:
  # Terminate script execution with exit code 1 indicating prerequisite failure.
  exit 1
fi

# Command Description:
# Query the installed AWS CLI version and capture stderr/stdout into a variable.
AWS_CLI_VERSION=$(aws --version 2>&1)

# Command Description:
# Print the detected AWS CLI version, Python environment, and CPU architecture.
echo "[+] AWS CLI found: ${AWS_CLI_VERSION}"

# ==============================================================================
# 2. Check AWS Credentials & STS Caller Identity
# ==============================================================================

# Command Description:
# Notify user that credential and identity verification has begun.
echo "[*] Checking AWS identity..."

# Command Description:
# Call the AWS Security Token Service (STS) 'get-caller-identity' API in JSON format.
# Verifies that active credentials (access key, session token, or IAM role) are valid.
# Suppresses stderr to handle missing credentials gracefully via the conditional block.
if ! CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null); then
  # Command Description:
  # Display authentication failure guidance if credentials are missing or expired.
  echo "[-] ERROR: Unable to authenticate with AWS. Run 'aws configure' or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY."
  
  # Command Description:
  # Exit script with error code 1.
  exit 1
fi

# Command Description:
# Parse the 12-digit AWS Account ID from the STS JSON response using pattern extraction.
ACCOUNT_ID=$(echo "${CALLER_IDENTITY}" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)

# Command Description:
# Parse the authenticated principal's Amazon Resource Name (ARN) from the STS JSON response.
ARN=$(echo "${CALLER_IDENTITY}" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)

# Command Description:
# Print the authenticated IAM User/Role ARN and 12-digit AWS Account ID.
echo "[+] Authenticated as: ${ARN}"
echo "[+] AWS Account ID:  ${ACCOUNT_ID}"

# ==============================================================================
# 3. Check and Set Default AWS Region
# ==============================================================================

# Command Description:
# Read the default AWS region configured in ~/.aws/config using 'aws configure get'.
# If not set in the CLI profile, fallback to the AWS_DEFAULT_REGION environment variable.
AWS_REGION=$(aws configure get region 2>/dev/null || echo "${AWS_DEFAULT_REGION:-}")

# Command Description:
# Verify whether an active region was resolved; if empty, fallback to 'us-east-1'.
if [[ -z "${AWS_REGION}" ]]; then
  # Command Description:
  # Warn the user that no region was configured and default to us-east-1.
  echo "[!] WARNING: No default region set in AWS CLI. Defaulting to us-east-1."
  
  # Command Description:
  # Export the fallback region to the current environment.
  export AWS_DEFAULT_REGION="us-east-1"
  
  # Command Description:
  # Set the local variable to the fallback region.
  AWS_REGION="us-east-1"
fi

# Command Description:
# Display the active AWS region that will be used for lab resource deployments.
echo "[+] Active AWS Region: ${AWS_REGION}"

# ==============================================================================
# 4. Check Default VPC Availability
# ==============================================================================

# Command Description:
# Notify user that Default VPC discovery has started in the target region.
echo "[*] Verifying Default VPC in region ${AWS_REGION}..."

# Command Description:
# Query the EC2 API for a Default VPC (isDefault=true) using JMESPath query filtering.
# If no default VPC exists in the region, falls back to returning the string 'None'.
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")

# Command Description:
# Evaluate whether a Default VPC ID was found.
if [[ "${DEFAULT_VPC}" == "None" || -z "${DEFAULT_VPC}" ]]; then
  # Command Description:
  # Inform user that custom VPC selection will be required for lab networking.
  echo "[!] NOTICE: No Default VPC found in ${AWS_REGION}. You may need to specify a custom VPC ID in labs."
else
  # Command Description:
  # Print the discovered Default VPC ID.
  echo "[+] Default VPC ID: ${DEFAULT_VPC}"
fi

# ==============================================================================
# 5. Check AWS Session Manager Plugin (Zero-SSH Access)
# ==============================================================================

# Command Description:
# Check if the 'session-manager-plugin' binary is installed in the system PATH.
# This plugin is required for browserless, keyless interactive shell sessions via SSM.
if command -v session-manager-plugin &>/dev/null; then
  # Command Description:
  # Confirm that the Session Manager Plugin is available.
  echo "[+] AWS Session Manager Plugin is installed."
else
  # Command Description:
  # Inform user that the plugin is missing and provide the official installation URL.
  echo "[!] NOTE: AWS Session Manager Plugin not found. Recommended for Lab 4.4."
  echo "    Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
fi

# Command Description:
# Print success completion footer indicating the environment is verified.
echo "============================================================"
echo "[SUCCESS] Environment is ready for AWS EC2 Master Labs!"
echo "============================================================"
