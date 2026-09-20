# Step-by-Step Technical Command Explanations: Lab 3.1

This guide breaks down every single command, network flag, and Linux kernel policy routing rule used in **Lab 3.1: Dual Elastic Network Interfaces (ENI) & Linux Policy Routing**.

---

### Command 1: Creating a Secondary Elastic Network Interface (ENI)

```bash
SECONDARY_ENI_ID=$(aws ec2 create-network-interface \
  --subnet-id "${SUBNET_2}" \
  --description "Secondary ENI for management traffic" \
  --groups "${SG_ID}" \
  --tag-specifications "ResourceType=network-interface,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=secondary-eni}]" \
  --query "NetworkInterface.NetworkInterfaceId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 create-network-interface`  
Allocates an independent virtual network interface controller (ENI) in the target VPC.

• `--subnet-id "${SUBNET_2}"`  
Binds the network interface to a completely separate subnet (e.g. Subnet 2 / Management Subnet). This gives the ENI a private IPv4 address natively allocated from Subnet 2's CIDR block.

• `--groups "${SG_ID}"`  
Attaches a security group directly to the network interface. In AWS, **security groups attach to ENIs, not to instances directly**.

• `--query "NetworkInterface.NetworkInterfaceId" --output text`  
Extracts the unique identifier (e.g. `eni-0123456789abcdef0`).

──────
#### 2. Why This is Critical in Production Automation

Multi-ENI architectures enable true network segmentation: creating dual-homed appliances (such as load balancers, reverse proxies, and Web Application Firewalls) where one interface (`eth0`) connects to an untrusted public DMZ subnet while the second interface (`eth1`) connects strictly to a protected internal database subnet.

---

### Command 2: Attaching the Secondary ENI to the Running Instance

```bash
ATTACHMENT_ID=$(aws ec2 attach-network-interface \
  --network-interface-id "${SECONDARY_ENI_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --device-index 1 \
  --query "AttachmentId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `aws ec2 attach-network-interface`  
Hot-plugs the secondary network card into the virtual PCIe bus of the running EC2 instance.

• `--device-index 1`  
**The Interface Enumeration Rule**:  
Specifies the PCIe device index:  
- `device-index 0`: Reserved for the primary interface (`eth0`), assigned at launch.  
- `device-index 1`: Maps to secondary interface (`eth1`).  
Skipping indices (e.g. attaching directly to index 2 without an index 1) will trigger an `InvalidDeviceIndex` error.

• `--query "AttachmentId" --output text`  
Extracts the attachment handle (e.g. `ela-attach-0abcdef1234567890`), required later for clean detachment.

──────
#### 2. Why This is Critical in Production Automation

Hot-attaching ENIs allows elastic network failover and live network reconfiguration without stopping or rebooting business-critical instances.

---

### Command 3: Configuring Linux Policy Routing to Fix Asymmetric Routing

```bash
# 1. Add default gateway for eth1 inside custom routing table 100
sudo ip route add default via ${GATEWAY2} dev eth1 table 100

# 2. Add rule routing all packets originating from IP2 via table 100
sudo ip rule add from ${IP2} lookup 100
```

#### 1. Detailed Breakdown of Every Component

• The Problem (Asymmetric Routing):  
By default, the Linux kernel maintains a single global routing table with only **one default gateway** (pointing out `eth0`).  
When an external client sends a request to `eth1` (`IP2`):  
1. The packet enters via `eth1`.  
2. The application receives and processes the request.  
3. When the kernel prepares the return SYN-ACK packet, it checks the default routing table and routes the response **out of `eth0`**!  
4. The client's firewall drops this packet because the connection was initiated with `eth1`'s IP, not `eth0`'s IP (or Linux Reverse Path Filtering `rp_filter` drops it internally).

• `sudo ip route add default via ${GATEWAY2} dev eth1 table 100`  
Creates an isolated, secondary routing table named `100`. Inside table 100, the default gateway is set explicitly to `eth1`'s subnet router.

• `sudo ip rule add from ${IP2} lookup 100`  
Instructs the Linux Policy Routing Engine: If any outgoing packet has a **source IP equal to `IP2`** (the secondary interface), force the kernel to evaluate routing table `100` instead of the global default table.

──────
#### 2. Why This is Critical in Production Automation

Failing to configure policy-based routing on dual-homed Linux instances causes secondary interfaces to silently drop incoming connections. This command establishes source-based policy routing, guaranteeing that all response traffic exits through the exact same network interface that received the inbound request.
