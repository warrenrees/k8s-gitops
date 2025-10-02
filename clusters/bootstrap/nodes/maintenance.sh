#!/bin/bash

ctr -n k8s.io images ls | awk '{print $1}' | xargs -r ctr -n k8s.io images rm
