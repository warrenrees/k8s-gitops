#!/bin/bash
# do things
# copy certs
# run kubeadm --join
sudo kubeadm config images pull --cri-socket /run/containerd/containerd.sock
sudo kubeadm join k8s-cluster.rees.ca:6443 --token <token> \
        --discovery-token-ca-cert-hash <ca-cert-hash> \
        --control-plane --certificate-key <cert-key>

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

## Let's allow prometheus to retrieve metrics for kube controller and scheduler
sudo sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-controller-manager.yaml
sudo sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-scheduler.yaml
