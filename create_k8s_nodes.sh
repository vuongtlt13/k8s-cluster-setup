#!/bin/bash
set -e

# ======================
# General configuration (customizable)
# ======================
SSH_KEY="ssh-ed25519 332423 lab@test"  # SSH public key CHANGE_THIS
BASE_IMG="ubuntu-22.04.qcow2"  # Base cloud image
DISK_SIZE_GB=40                 # Disk size per VM
NET="default"                   # libvirt network

# Node config: name -> "vCPU RAM_MB IP qcow2_file"
declare -A NODES=(
  [master]="4 4096 192.168.122.10 k8s-master.qcow2"
  [worker1]="8 10240 192.168.122.11 k8s-worker1.qcow2"
  [worker2]="8 10240 192.168.122.12 k8s-worker2.qcow2"
)

# ======================
# Check cloud-localds
# ======================
if ! command -v cloud-localds &> /dev/null; then
    echo "cloud-localds not installed. Installing..."
    sudo apt update
    sudo apt install -y cloud-image-utils
fi

# ======================
# Create user-data
# ======================
cat > user-data <<EOF
#cloud-config
manage_etc_hosts: true

users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $SSH_KEY

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF

echo ">>> user-data created"

# ======================
# Create VMs
# ======================
for name in "${!NODES[@]}"; do
    set -- ${NODES[$name]}
    vcpu=$1
    mem=$2
    ip=$3
    qcow2_file=$4

    echo ">>> Preparing $name with IP $ip..."

    # Copy base image + resize disk
    cp $BASE_IMG $qcow2_file
    qemu-img resize $qcow2_file ${DISK_SIZE_GB}G

    # Create meta-data
    cat > meta-data <<EOF
instance-id: $name
local-hostname: $name
EOF

    # Create network-config.yaml
    cat > network-config.yaml <<EOF
version: 2
ethernets:
  enp1s0:
    dhcp4: no
    addresses: [$ip/24]
    gateway4: 192.168.122.1
    nameservers:
      addresses: [8.8.8.8,1.1.1.1]
EOF

    # Create seed ISO with separate network-config
    ISO_FILE="${name}-seed.iso"
    cloud-localds --network-config=network-config.yaml $ISO_FILE user-data meta-data

    # Create VM
    virt-install --name $name \
      --vcpus $vcpu --memory $mem \
      --disk path=$qcow2_file,format=qcow2 \
      --disk path=$ISO_FILE,device=cdrom \
      --os-variant ubuntu22.04 \
      --network network=$NET,model=virtio \
      --graphics none --noautoconsole --import

    echo ">>> $name created!"
done

echo ">>> All VMs created! Use 'virsh list' and SSH to 192.168.122.10/11/12"
