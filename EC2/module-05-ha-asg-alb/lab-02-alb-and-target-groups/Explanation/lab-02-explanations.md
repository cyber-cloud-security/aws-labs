# Step-by-Step Technical Command Explanations: Lab 5.2

This guide breaks down every single command, health check parameter, and load balancing algorithm used in **Lab 5.2: Application Load Balancer (ALB), Target Groups & Health Checks**.

---

### Command 1: Creating an ALB Target Group with Custom Health Checks

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
```

#### 1. Detailed Breakdown of Every Component

• `aws elbv2 create-target-group`  
Defines a logical pool of destination compute backends (EC2 instances, IP addresses, or Lambda functions) that receive routed traffic.

• `--protocol HTTP` & `--port 80`  
The protocol and port the load balancer uses to forward traffic to the target instances.

• Health Check Configurations:  
- `--health-check-path "/"`: The URI endpoint queried by the ALB to verify backend application health.  
- `--health-check-interval-seconds 15`: ALB nodes query the health check endpoint every 15 seconds.  
- `--unhealthy-threshold-count 2`: If a target fails 2 consecutive checks, the ALB immediately marks it `unhealthy` and ceases routing traffic to it.  
- `--healthy-threshold-count 2`: A recovering instance must pass 2 consecutive checks before the ALB resumes routing traffic to it.

• `--target-type instance`  
Targets are identified by EC2 Instance ID.  
*Alternative*: `ip` (used for microservices running in Docker containers, ECS tasks, or Kubernetes Pods on AWS VPC CNI).

──────
#### 2. Why This is Critical in Production Automation

Target Groups decouple traffic ingress from specific compute backends. Fast health check intervals (15s interval, 2 thresholds) ensure that crashed backend nodes are ejected from service in 30 seconds rather than lingering for minutes.

---

### Command 2: Tuning Connection Draining (Deregistration Delay)

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn "${TG_ARN}" \
  --attributes "Key=deregistration_delay.timeout_seconds,Value=30"
```

#### 1. Detailed Breakdown of Every Component

• `deregistration_delay.timeout_seconds`  
Controls **Connection Draining**.  
When an instance is deregistered (e.g. during a deployment, auto scaling scale-in, or manual termination):  
1. The ALB immediately stops routing *new* connections to that target.  
2. The ALB keeps existing, in-flight HTTP connections alive for up to `Value` seconds, allowing active requests to complete gracefully.  
3. Default AWS timeout is **300 seconds** (5 minutes). Setting this to **30 seconds** accelerates CI/CD blue/green deployments and test suites.

──────
#### 2. Why This is Critical in Production Automation

Without connection draining, terminating or replacing an instance immediately severs active TCP sockets, throwing HTTP 502 Bad Gateway or 504 Gateway Timeout errors to active users.

---

### Command 3: Provisioning the Application Load Balancer

```bash
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "alb-ec2-labs" \
  --subnets "${SUBNET_1}" "${SUBNET_2}" \
  --security-groups "${ALB_SG_ID}" \
  --scheme internet-facing \
  --type application \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws elbv2 create-load-balancer`  
Provisions a dedicated Layer 7 Application Load Balancer.

• `--subnets "${SUBNET_1}" "${SUBNET_2}"`  
**Mandatory Multi-AZ Rule**:  
An Application Load Balancer **must be configured with at least two subnets located in different Availability Zones**. AWS deploys managed load balancer nodes across these zones to ensure high availability.

• `--scheme internet-facing`  
Assigns publicly routable IP addresses and public DNS names to the ALB nodes.  
*Alternative*: `internal` (used for private microservice meshes with internal-only VPC routing).

• `--type application`  
Operates at OSI Layer 7 (HTTP/HTTPS), supporting URL path routing, host routing, HTTP headers, and WebSockets.

──────
#### 2. Why This is Critical in Production Automation

ALBs automatically scale their internal capacity up and down to handle millions of requests per second, abstracting DNS round-robin and multi-datacenter failover seamlessly.

---

### Command 4: Creating the HTTP Listener

```bash
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn "${ALB_ARN}" \
  --protocol HTTP \
  --port 80 \
  --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --query "Listeners[0].ListenerArn" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws elbv2 create-listener`  
Binds a listening process to the public front door of the load balancer on port 80.

• `--default-actions "Type=forward,TargetGroupArn=${TG_ARN}"`  
Defines the default rule: any incoming request matching port 80 is forwarded directly to the backend compute instances registered in the Target Group.

──────
#### 2. Why This is Critical in Production Automation

Listeners can be configured with complex routing rule trees (e.g. forwarding `/api/*` to an API Target Group, `/static/*` to S3, and issuing automatic HTTP-to-HTTPS 301 redirects).
