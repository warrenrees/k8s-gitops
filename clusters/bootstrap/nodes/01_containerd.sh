#!/bin/bash

# Add Docker repo
wget -qO - https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/trusted.gpg.d/docker-archive-keyring.asc
echo "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list

# Install containerd from docker repo
sudo apt update
sudo apt install -y containerd.io

# Configure containerd and start service
sudo mkdir -p /etc/containerd
sudo containerd config default > /etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status  containerd

# Let's install our VIP for apiserver
export VIP=10.0.0.10
read INTERFACE
export KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name")
sudo ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION
alias kube-vip="sudo ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"
# Generate the manifest and inject an explicit `resources:` block on the
# kube-vip container. Without this, the kube-system LimitRange's defaults
# get stamped onto the mirror pod by the LimitRanger admission plugin, and
# the kubelet's status PATCH then conflicts with that mutation -- the
# kubelet silently stops updating the mirror pod's status and it sits
# stuck at phase=Pending with empty hostIP/ready forever (cosmetic only;
# kube-vip itself runs fine, but it trips monitoring). Setting resources
# explicitly on disk leaves LimitRanger nothing to mutate.
kube-vip manifest pod --interface $INTERFACE --address $VIP --controlplane --arp --leaderElection \
  | python3 -c '
import sys, yaml
pod = yaml.safe_load(sys.stdin)
for c in pod["spec"]["containers"]:
    if c["name"] == "kube-vip":
        c["resources"] = {
            "requests": {"cpu": "50m",  "memory": "128Mi"},
            "limits":   {"cpu": "500m", "memory": "512Mi"},
        }
yaml.safe_dump(pod, sys.stdout, default_flow_style=False)
' \
  | tee /etc/kubernetes/manifests/kube-vip.yaml
#kube-vip manifest pod     --interface $INTERFACE     --address $VIP     --controlplane     --services     --arp     --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml

sudo systemctl enable kubelet
