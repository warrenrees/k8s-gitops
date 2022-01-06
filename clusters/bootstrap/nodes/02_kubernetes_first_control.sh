#!/bin/bash
sudo kubeadm config images pull --cri-socket /run/containerd/containerd.sock
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket /run/containerd/containerd.sock \
  --upload-certs \
  --control-plane-endpoint="k8s-cluster.rees.ca:6443"

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl create -f tigera-operator.yaml
kubectl create -f custom-resources.yaml
kubectl taint nodes --all node-role.kubernetes.io/master-
