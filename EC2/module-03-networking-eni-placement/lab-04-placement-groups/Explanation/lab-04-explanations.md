# Step-by-Step Technical Command Explanations: Lab 3.4

This guide breaks down every single command, strategy flag, and hardware isolation mechanism used in **Lab 3.4: EC2 Placement Groups (Cluster, Spread & Partition)**.

---

### Command 1: Creating a Cluster Placement Group (HPC & Low Latency)

```bash
aws ec2 create-placement-group \
  --group-name "pg-hpc-cluster" \
  --strategy "cluster" \
  --tag-specifications "ResourceType=placement-group,Tags=[{Key=Project,Value=ec2-master-labs}]"
```

#### 1. Detailed Breakdown of Every Component

• `--strategy "cluster"`  
Tells the AWS EC2 placement engine to pack instances into a tight, close physical proximity inside a single Availability Zone. Instances sit on the same high-speed datacenter network spine switch.  
- Performance: Delivers sub-millisecond node-to-node latency and full 10/25/100 Gbps network throughput.  
- Workloads: High Performance Computing (HPC), tightly coupled MPI simulations, deep learning model training.

──────
#### 2. Why This is Critical in Production Automation

Cluster groups cannot span multiple AZs. If instances in a cluster group are launched gradually over weeks, the physical rack spine may run out of capacity, causing `InsufficientInstanceCapacity` errors. In production, launch the entire required instance count in a single `run-instances` batch.

---

### Command 2: Creating a Spread Placement Group (Hardware Rack Isolation)

```bash
aws ec2 create-placement-group \
  --group-name "pg-ha-spread" \
  --strategy "spread" \
  --spread-level "rack"
```

#### 1. Detailed Breakdown of Every Component

• `--strategy "spread"` & `--spread-level "rack"`  
Forces the AWS physical placement scheduler to guarantee that each instance is placed on a **completely separate underlying hardware rack**, each with its own independent power distribution units (PDUs) and network top-of-rack switches.  
- **Hard Quota Constraint**: AWS enforces a strict limit of **maximum 7 running instances per Availability Zone** in a spread placement group.

──────
#### 2. Why This is Critical in Production Automation

Spread groups eliminate Single Points of Failure (SPOF) for critical small clusters (such as primary/standby relational database pairs, ZooKeeper ensembles, or Paxos/Raft quorum nodes). Even if an entire server rack catches fire or blows a circuit breaker, only 1 node can fail.

---

### Command 3: Creating a Partition Placement Group (Big Data Topologies)

```bash
aws ec2 create-placement-group \
  --group-name "pg-kafka-partition" \
  --strategy "partition" \
  --partition-count 3
```

#### 1. Detailed Breakdown of Every Component

• `--strategy "partition"` & `--partition-count 3`  
Divides the placement group into 3 logical partitions within an Availability Zone. Each partition comprises its own distinct set of server racks.  
- Instances in Partition 1 do not share any hardware racks with Partition 2 or 3.  
- Can scale to hundreds of instances (unlike Spread's 7-instance limit).

──────
#### 2. Why This is Critical in Production Automation

Partition groups align perfectly with distributed data architectures (Apache Kafka, Cassandra, Hadoop HDFS). By placing Kafka partition replicas across different AWS partitions, you guarantee that a hardware rack failure cannot wipe out both primary and replica data partitions simultaneously.

---

### Command 4: Launching Instances into a Placement Group

```bash
INSTANCE_IDS=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "t3.micro" \
  --subnet-id "${SUBNET_ID}" \
  --count 2 \
  --placement "GroupName=pg-ha-spread" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=spread-node}]" \
  --query "Instances[*].InstanceId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `--placement "GroupName=pg-ha-spread"`  
Binds the compute instance to the placement group at launch time.  
*Note*: You cannot move an existing running instance into a placement group without stopping it first and using `modify-instance-placement`.

• `--count 2`  
Requests 2 instances simultaneously, allowing the AWS placement scheduler to evaluate rack constraints atomically.

──────
#### 2. Why This is Critical in Production Automation

Automated infrastructure deployments must explicitly define placement parameters during cluster creation to ensure physical topology guarantees are enforced before application services begin peer discovery.

---

### Command 5: Deletion Order Constraint (Cleanup)

```bash
aws ec2 terminate-instances --instance-ids ${INSTANCE_IDS}
aws ec2 wait instance-terminated --instance-ids ${INSTANCE_IDS}
aws ec2 delete-placement-group --group-name "pg-ha-spread"
```

#### 1. Detailed Breakdown of Every Component

• The Strict AWS Dependency Rule:  
A placement group **cannot be deleted** if any instances are associated with it—even if those instances are in the `shutting-down` state. Calling `delete-placement-group` prematurely triggers an `ActiveInstancesInPlacementGroup` error. Running `wait instance-terminated` guarantees zero dependency collisions.

──────
#### 2. Why This is Critical in Production Automation

Robust teardown scripts must account for the asynchronous shutdown lag of virtual machines before attempting to destroy organizational placement containers.
