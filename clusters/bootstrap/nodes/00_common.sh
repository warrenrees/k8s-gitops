#!/bin/bash
sudo apt update
sudo apt -y upgrade

# Install the intel graphics software repos
wget -qO - https://repositories.intel.com/graphics/intel-graphics.key | sudo tee /etc/apt/trusted.gpg.d/intel-graphics.asc
sudo apt-add-repository \
  'deb [arch=amd64] https://repositories.intel.com/graphics/ubuntu focal main'

sudo apt update

# Install necessary dependencies to support the Intel GPU in k8s
sudo apt -y install   intel-opencl-icd   intel-level-zero-gpu level-zero   intel-media-va-driver-non-free libigfxcmrt7 libmfx1 vainfo intel-gpu-tools


sudo apt -y install curl apt-transport-https jq build-essential nfs-common
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /etc/apt/trusted.gpg.d/gcloud.gpg
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt -y install vim git curl wget kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo sed -i '/\tswap\t/ s/^\(.*\)$/#\1/g' /etc/fstab
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

# Enable kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Add some settings to sysctl
sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Reload sysctl
sudo sysctl --system

# Configure persistent loading of modules
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
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
