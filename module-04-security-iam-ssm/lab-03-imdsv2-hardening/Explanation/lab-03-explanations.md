# Step-by-Step Technical Command Explanations: Lab 4.3

This guide breaks down every single command, security header, and hypervisor mitigation mechanism used in **Lab 4.3: IMDSv2 Hardening & SSRF Threat Mitigation**.

---

### Command 1: Auditing Legacy IMDSv1 Vulnerability Mechanics

```bash
# Inside the guest operating system:
curl -i -s http://169.254.169.254/latest/meta-data/instance-id
```

#### 1. Detailed Breakdown of Every Component

• `http://169.254.169.254`  
A Link-Local non-routable IPv4 address hardcoded into the AWS hypervisor network stack to serve instance metadata.

• `curl -i -s`  
- `-i`: Includes HTTP response status headers in the output.  
- `-s`: Silent mode (suppresses progress meters).

• The IMDSv1 Architectural Flaw:  
In IMDSv1, any simple, unauthenticated HTTP `GET` request returns metadata and IAM credentials.  
If an attacker discovers a **Server-Side Request Forgery (SSRF)** vulnerability in a web application running on this instance (e.g. an image fetcher, PDF exporter, or webhook tester like `https://example.com/fetch?url=http://169.254.169.254/latest/meta-data/iam/security-credentials/`), the vulnerable application makes the GET request internally and returns the credentials to the attacker.

──────
#### 2. Why This is Critical in Production Automation

This exact vulnerability was weaponized in several high-profile enterprise cloud data breaches (including the Capital One breach), leading to the exfiltration of millions of customer records. IMDSv1 is now flagged as a Critical finding by AWS Security Hub and AWS GuardDuty.

---

### Command 2: Modifying Instance Metadata Options Live (Enforcing IMDSv2)

```bash
aws ec2 modify-instance-metadata-options \
  --instance-id "${INSTANCE_ID}" \
  --http-tokens required \
  --http-put-response-hop-limit 1 \
  --http-endpoint enabled
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 modify-instance-metadata-options`  
Updates the hypervisor's metadata enforcement rules on a live, running EC2 instance with zero downtime.

• `--http-tokens required` (The Core Hardening Flag):  
Disables IMDSv1 entirely. Any incoming request that does not present a valid, signed, session-oriented IMDSv2 token is immediately rejected by the hypervisor with `HTTP/1.1 401 Unauthorized`.

• `--http-put-response-hop-limit 1` (The Anti-Proxy / Container Shield):  
Sets the IP packet Time-To-Live (TTL) header of metadata responses to **1**.  
- In IP networking, every time a packet crosses a network router, bridge, or reverse proxy (like Nginx, Squid, or a Docker/Kubernetes container bridge), the TTL is decremented by 1.  
- With a hop limit of `1`, the packet can reach the host OS kernel, but if a Docker container or reverse proxy tries to forward the packet, the TTL drops to `0` and the packet is destroyed by the network stack!

• `--http-endpoint enabled`  
Ensures the metadata service is accessible to local applications.

──────
#### 2. Why This is Critical in Production Automation

This command hardens the instance against both direct SSRF attacks and container breakout attacks. Any enterprise running containerized workloads (Docker, ECS, EKS) directly on EC2 should set `HttpPutResponseHopLimit=1` to prevent containers from accessing the underlying host's IAM instance profile.

---

### Command 3: Acquiring and Utilizing an IMDSv2 Session Token

```bash
# 1. Acquire Token via HTTP PUT
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# 2. Access metadata using the token header
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id
```

#### 1. Detailed Breakdown of Every Component

• `-X PUT "http://169.254.169.254/latest/api/token"`  
IMDSv2 **requires an HTTP `PUT` request**. Standard SSRF vulnerabilities (e.g. `?url=...` image injections) only perform HTTP `GET` requests and cannot be coerced into sending arbitrary `PUT` methods.

• `-H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`  
**Mandatory Header**: Requests a session token valid for 21,600 seconds (6 hours). Web application firewalls (WAFs) and standard web exploits cannot forge custom HTTP headers.

• `-H "X-aws-ec2-metadata-token: $TOKEN"`  
Passes the acquired secret token as a request header to unlock metadata queries.

──────
#### 2. Why This is Critical in Production Automation

IMDSv2 neutralizes 99% of SSRF attack vectors by requiring both an HTTP `PUT` verb and custom request headers that external attackers cannot inject.

---

### Command 4: Account-Wide Default Hardening for Future EC2 Deployments

```bash
aws ec2 modify-instance-metadata-defaults \
  --http-tokens required \
  --http-put-response-hop-limit 1
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 modify-instance-metadata-defaults`  
A regional account-level policy setting introduced by AWS.

• Effect on Future Infrastructure:  
Any engineer or automated tool (Terraform, CloudFormation) that subsequently executes `aws ec2 run-instances` in this region will automatically have `--metadata-options "HttpTokens=required,HttpPutResponseHopLimit=1"` enforced by default, even if the engineer forgets to include the parameter!

──────
#### 2. Why This is Critical in Production Automation

This command implements "Secure by Default" governance across entire engineering organizations, preventing junior developers or third-party deployment scripts from launching vulnerable IMDSv1 instances.
