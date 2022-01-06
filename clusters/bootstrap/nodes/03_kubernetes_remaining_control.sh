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
