#!/bin/bash
sudo apt update
sudo apt -y upgrade

# Install the intel graphics software repos
wget -qO - https://repositories.intel.com/graphics/intel-graphics.key | sudo tee /etc/apt/trusted.gpg.d/intel-graphics.asc
sudo apt-add-repository \
  'deb [arch=amd64] https://repositories.intel.com/graphics/ubuntu focal main'

sudo apt update

# Install necessary dependencies to support the Intel GPU in k8s
sudo apt -y install   intel-opencl-icd   intel-level-zero-gpu level-zero   intel-media-va-driver-non-free libigfxcmrt7 libmfx1 vainfo intel-gpu-tools ubuntu-advantage-tools


sudo apt -y install curl apt-transport-https jq build-essential nfs-common

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly

sudo apt update
sudo apt -y install vim git curl wget kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo sed -i '/\tswap\t/ s/^\(.*\)$/#\1/g' /etc/fstab
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

# Enable kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter
sudo modprobe uio
sudo modprobe uio_pci_generic
sudo modprob nvme-tcp

# Add some settings to sysctl
sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.nr_hugepages = 1024
fs.inotify.max_user_instances = 1100000
EOF

# Stop the system from managing foreign routes
sudo sed -i 's/#ManageForeignRoutingPolicyRules\=yes/ManageForeignRoutingPolicyRules\=no/g' /etc/systemd/networkd.conf
sudo sed -i 's/#ManageForeignRoutes\=yes/ManageForeignRoutes\=no/g' /etc/systemd/networkd.conf

# Reload sysctl
sudo sysctl --system

# Configure persistent loading of modules
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# Configure longhorn kernel modules
sudo tee /etc/modules-load.d/longhorn.conf <<EOF
uio
uio_pci_generic
nvme-tcp
EOF

# Install required packages
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Update multipath
sudo tee -a /etc/multipath.conf <<EOF

blacklist {
    devnode "^sd[a-z0-9]+"
}
EOF

sudo systemctl restart multipathd.service

# Update system limits
sudo tee -a /etc/security/limits.d/kubernetes.conf <<EOF
*		soft	nofile		65535
root		soft	nofile		1048576
EOF
