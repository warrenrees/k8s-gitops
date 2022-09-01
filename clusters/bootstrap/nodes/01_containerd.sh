#!/bin/bash

# Add Docker repo
#curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
#sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Install containerd
sudo apt update
sudo apt install -y containerd

# Configure containerd and start service
sudo mkdir -p /etc/containerd
sudo containerd config default>/etc/containerd/config.toml

echo 'add this after: [plugins."io.containerd.grpc.v1.cri".containerd.runetimes.runc.options]'
echo '   SystemdCgroup = true'

sleep 10
sudo nano /etc/containerd/config.toml

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
kube-vip manifest pod     --interface $INTERFACE     --address $VIP     --controlplane     --services     --arp     --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml

systemctl enable kubelet
