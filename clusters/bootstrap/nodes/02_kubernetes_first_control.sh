#!/bin/bash
sudo kubeadm config images pull --cri-socket /run/containerd/containerd.sock
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket /run/containerd/containerd.sock \
  --upload-certs \
  --control-plane-endpoint="k8s-cluster.rees.ca:6443"
