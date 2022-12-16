#!/bin/bash

# Add Docker repo
wget -qO - https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/trusted.gpg.d/docker-archive-keyring.asc
echo "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list

# Install containerd from docker repo
sudo apt update
sudo apt install -y containerd.io

# Configure containerd and start service
sudo mkdir -p /etc/containerd
sudo containerd config default>/etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# restart containerd
systemctl restart containerd
systemctl enable containerd
systemctl status  containerd

# Let's install our VIP for apiserver
export VIP=10.0.0.10
read INTERFACE
export KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name")
ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
alias kube-vip="ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"
kube-vip manifest pod --interface $INTERFACE --address $VIP --controlplane --arp --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml
#kube-vip manifest pod     --interface $INTERFACE     --address $VIP     --controlplane     --services     --arp     --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml

systemctl enable kubelet
