#!/bin/bash
# ==============================================================================
# EC2 Bootstrap Script (User Data / cloud-init)
# Demonstrates dynamic instance metadata retrieval via IMDSv2 and web server setup
# ==============================================================================

# Command Description:
# Duplicate and redirect standard output (stdout) and standard error (stderr)
# simultaneously to the log file /var/log/user-data.log and the kernel console
# buffer (/dev/console), making bootstrap output retrievable via AWS get-console-output.
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Command Description:
# Print initialization log entry with local timestamp.
echo "Starting EC2 User Data script execution at $(date)"

# ==============================================================================
# 1. Update OS Packages & Install Web Server
# ==============================================================================

# Command Description:
# Attempt to refresh OS package repositories across Amazon Linux 2023 (dnf),
# Amazon Linux 2 (yum), or Ubuntu/Debian (apt-get).
dnf update -y || yum update -y || apt-get update -y

# Command Description:
# Detect the available package manager and install Nginx and util-linux utilities.
if command -v dnf &>/dev/null; then
  # Command Description:
  # Install Nginx and util-linux via DNF (Amazon Linux 2023 / Fedora / RHEL 9).
  dnf install -y nginx util-linux
elif command -v yum &>/dev/null; then
  # Command Description:
  # Install Nginx and util-linux via YUM (Amazon Linux 2 / RHEL 7/8 / CentOS).
  yum install -y nginx util-linux
elif command -v apt-get &>/dev/null; then
  # Command Description:
  # Install Nginx and util-linux via APT (Ubuntu / Debian).
  apt-get install -y nginx util-linux
fi

# ==============================================================================
# 2. Acquire IMDSv2 Session Token
# ==============================================================================

# Command Description:
# Acquire an IMDSv2 session token from the link-local metadata address (169.254.169.254).
# Uses HTTP PUT with the mandatory 'X-aws-ec2-metadata-token-ttl-seconds' header
# specifying a 6-hour (21,600 seconds) token lifespan to mitigate SSRF attack vectors.
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# ==============================================================================
# 3. Retrieve Dynamic Instance Metadata via IMDSv2
# ==============================================================================

# Command Description:
# Query IMDSv2 for the unique EC2 instance ID (e.g. i-0a3515cd7d3f17258) using the session token.
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# Command Description:
# Query IMDSv2 for the instance type hardware profile (e.g. t4g.micro or t3.micro).
INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type)

# Command Description:
# Query IMDSv2 for the Availability Zone where this virtual machine was provisioned (e.g. ap-south-1a).
AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Command Description:
# Query IMDSv2 for the primary private IPv4 address assigned to the eth0 ENI (e.g. 10.0.1.96).
LOCAL_IPV4=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# Command Description:
# Identify the CPU machine architecture (e.g. aarch64 for Graviton, x86_64 for Intel/AMD).
ARCH=$(uname -m)

# ==============================================================================
# 4. Generate Dynamic HTML Landing Page
# ==============================================================================

# Command Description:
# Generate a responsive HTML index page populated with the retrieved runtime metadata
# and write it directly to the Nginx default root document directory.
cat <<HTML > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>AWS EC2 Master Labs - Lab 1.1</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; padding: 40px; }
        .card { background: #1e293b; border-radius: 12px; padding: 30px; max-width: 650px; margin: 0 auto; box-shadow: 0 10px 25px -5px rgba(0,0,0,0.5); border: 1px solid #334155; }
        h1 { color: #38bdf8; margin-top: 0; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 6px; font-size: 0.85em; font-weight: bold; background: #0284c7; color: white; margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { text-align: left; padding: 10px; border-bottom: 1px solid #334155; }
        th { color: #94a3b8; font-weight: 500; }
        td { font-family: monospace; color: #f1f5f9; }
    </style>
</head>
<body>
    <div class="card">
        <span class="badge">AWS EC2 Master Labs</span>
        <h1>EC2 Node Bootstrapped Successfully</h1>
        <p>This web page was generated automatically via cloud-init User Data during instance initialization.</p>
        <table>
            <tr><th>Instance ID</th><td>${INSTANCE_ID}</td></tr>
            <tr><th>Instance Type</th><td>${INSTANCE_TYPE}</td></tr>
            <tr><th>CPU Architecture</th><td>${ARCH}</td></tr>
            <tr><th>Availability Zone</th><td>${AVAILABILITY_ZONE}</td></tr>
            <tr><th>Private IPv4</th><td>${LOCAL_IPV4}</td></tr>
            <tr><th>Bootstrap Time</th><td>$(date -u)</td></tr>
        </table>
    </div>
</body>
</html>
HTML

# ==============================================================================
# 5. Start & Enable Web Server Service
# ==============================================================================

# Command Description:
# Start the Nginx systemd daemon service immediately.
systemctl start nginx

# Command Description:
# Configure the Nginx systemd service to start automatically upon system reboots.
systemctl enable nginx

# Command Description:
# Print final completion confirmation to the user-data log and system console.
echo "EC2 User Data script completed successfully."
