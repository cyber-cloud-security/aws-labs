# Step-by-Step Technical Command Explanations: Lab 2.3

This guide breaks down every single command, kernel flag, and performance benchmarking parameter used in **Lab 2.3: Ephemeral Storage (Instance Store) & High-IOPS Benchmarking**.

---

### Command 1: Provisioning an Instance with Local NVMe SSD Hardware

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "c5d.large" \
  --subnet-id "${SUBNET_ID}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=ec2-master-labs},{Key=Name,Value=instance-store-benchmark}]" \
  --query "Instances[0].InstanceId" --output text)
```

#### 1. Detailed Breakdown of Every Component

• `--instance-type "c5d.large"`  
**The `d` Suffix Significance**:  
In the AWS instance naming convention, the letter `d` denotes dedicated physical **direct-attached NVMe solid-state drives** (e.g. `c5d`, `m5d`, `r6id`, `i3en`).  
- Standard `c5.large`: Relies 100% on remote, network-attached Amazon EBS storage.  
- `c5d.large`: Comes pre-equipped with 50 GB of local physical NVMe SSD storage physically wired to the PCIe bus of the physical host motherboard.

──────
#### 2. Why This is Critical in Production Automation

When designing low-latency caching layers (Memcached, Redis), high-speed distributed buffers, temporary scratch spaces for big data map-reduce jobs (Hadoop/Spark), or video transcoding scratch drives, selecting an instance family with local NVMe disks delivers millions of IOPS at zero additional EBS storage fees.

---

### Command 2: Formatting and Mounting with Linux Performance Optimizations

```bash
mkfs.ext4 -E nodiscard /dev/nvme1n1
mkdir -p /mnt/ephemeral
mount -o noatime /dev/nvme1n1 /mnt/ephemeral
```

#### 1. Detailed Breakdown of Every Component

• `mkfs.ext4 -E nodiscard /dev/nvme1n1`  
- `mkfs.ext4`: Formats the local NVMe block device with the fourth extended filesystem.  
- `-E nodiscard`: **Performance Optimization**. Tells the filesystem creation tool not to send discard/TRIM commands across the entire disk during format. Because AWS allocates zeroed, sanitized virtual block ranges upon launch, skipping discard saves significant initialization time on large NVMe arrays.

• `mount -o noatime /dev/nvme1n1 /mnt/ephemeral`  
- `-o noatime`: Disables the Linux kernel's default behavior of updating file access timestamps (`atime`) every single time a file is read. In high-throughput read environments, disabling `atime` eliminates up to 30% of unnecessary filesystem write overhead.

──────
#### 2. Why This is Critical in Production Automation

Ephemeral drives must be formatted and mounted programmatically at boot (typically via `cloud-init` User Data) because every time the instance starts from a `stopped` state, the disk is delivered completely blank and unpartitioned.

---

### Command 3: Executing High-Concurrency 4K Random Write Benchmarks with `fio`

```bash
fio --name=randwrite-ephemeral \
    --ioengine=libaio \
    --iodepth=64 \
    --rw=randwrite \
    --bs=4k \
    --direct=1 \
    --size=1G \
    --numjobs=4 \
    --runtime=20 \
    --group_reporting \
    --filename=/mnt/ephemeral/fio_test.bin
```

#### 1. Detailed Breakdown of Every Component

• `fio` (Flexible I/O Tester)  
The industry-standard Linux storage benchmarking tool.

• `--ioengine=libaio`  
Uses Linux Native Asynchronous I/O (`libaio`), allowing the benchmarking process to submit I/O requests to the kernel without blocking.

• `--iodepth=64`  
Keeps 64 concurrent I/O requests constantly queued in the hardware driver pipeline, saturating device controllers.

• `--rw=randwrite`  
Executes 100% random write access patterns, simulating demanding database workloads.

• `--bs=4k`  
Sets block size to 4 Kibibytes—the standard block size for PostgreSQL, MySQL InnoDB pages, and Linux virtual memory pages.

• `--direct=1`  
**Bypasses Linux Page Cache (`O_DIRECT`)**. Forces all read/write operations to travel directly to physical disk controller hardware without caching in kernel RAM.

• `--numjobs=4`  
Spawns 4 parallel worker threads to stress multiple CPU cores and NVMe hardware submission queues.

• `--group_reporting`  
Aggregates performance statistics from all 4 worker threads into a unified summary metric.

──────
#### 2. Why This is Critical in Production Automation

Benchmarking under realistic, unbuffered conditions (`--direct=1`) reveals the true physical storage performance ceiling:  
- Local NVMe Instance Store: Delivers 40,000–100,000+ IOPS with 20–50 microsecond write latencies.  
- Network EBS (`gp3`): Capped at provisioned limits (baseline 3,000 IOPS) with 1–2 millisecond network traversal latency.

---

### Command 4: Verifying Data Volatility (Reboot vs Stop/Start Lifecycle)

```bash
# Test A: Reboot instance
sudo reboot

# Test B: Stop and Start instance
aws ec2 stop-instances --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-stopped --instance-ids "${INSTANCE_ID}"
aws ec2 start-instances --instance-ids "${INSTANCE_ID}"
```

#### 1. Detailed Breakdown of Every Component

• `sudo reboot` (Warm OS Reboot):  
The guest OS kernel reboots, but the physical server hardware remains powered on and allocated to the VM. **The data on `/dev/nvme1n1` survives completely intact.**

• `stop-instances` followed by `start-instances` (Cold Power Cycle):  
When an EC2 instance is stopped:  
1. AWS deallocates the virtual machine from the physical host server rack.  
2. The physical server's local NVMe drives are cryptographically erased and wiped for security before being reassigned to other customers.  
3. When `start-instances` is issued, the instance boots on an **entirely new physical server**.  
4. The newly allocated local NVMe drive is 100% blank; all previous data is permanently lost.

──────
#### 2. Why This is Critical in Production Automation

This lifecycle behavior dictates application architecture: **Never store stateful or irreplaceable data on an Instance Store disk without continuous, real-time application-level replication** (e.g. Cassandra or Kafka with replication factor $\ge 3$, or automated replication to S3/EBS).
