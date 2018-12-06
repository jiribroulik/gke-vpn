#!/bin/bash -e

# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

### Creates GCP/GKE resources for GKE-to-GKE-communication-through-VPN
### Refer to https://cloud.google.com/sdk/gcloud/ for usage of gcloud
### Deployment manager templates, gcloud and kubectl commands are used.

dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
ROOT="$(dirname "$dir")"

command -v gcloud >/dev/null 2>&1 || \
	{ echo >&2 "I require gcloud but it's not installed.  Aborting.";exit 1; }

command -v kubectl >/dev/null 2>&1 || \
  	{ echo >&2 "I require kubectl but it's not installed.  Aborting."; exit 1; }

### Obtain current active PROJECT_ID
PROJECT_ID=$(gcloud config get-value project)
if [ -z "$PROJECT_ID" ]
	then echo >&2 "I require default project is set but it's not.  Aborting."; exit 1;
fi

### enable required service apis in each project
gcloud services enable \
    compute.googleapis.com \
	deploymentmanager.googleapis.com

### create networks and subnets
# gcloud deployment-manager deployments create network1-deployment \
# 	--config "$ROOT"/network/network1.yaml

# ### create clusters
# gcloud deployment-manager deployments create cluster1-deployment \
# 	--config "$ROOT"/clusters/cluster1.yaml


# ### Create static ip for VPN connections
gcloud deployment-manager deployments create static-ip-deployment5 \
	--template static-ip.jinja \
	--properties "name:vpn5-ip,region:europe-west2,network:default"

gcloud deployment-manager deployments create static-ip-deployment7 \
	--template static-ip.jinja \
	--properties "name:vpn7-ip,region:us-west1,network:network1"

#Get static VPN IP addresses
VPN5_IP=$( gcloud compute addresses list | grep vpn5 \
	| awk '{ print $3 }' )
VPN7_IP=$( gcloud compute addresses list | grep vpn7 \
	| awk '{ print $3 }' )

### Create VPN connection for network1 and network2 in us-east1 &
### us-west1 regions
gcloud deployment-manager deployments create vpn7-deployment \
	--template vpn-custom-subnet.jinja \
	--properties "region:europe-west2,network:projects/$PROJECT_ID/global/networks/default,\
vpn-ip:$VPN5_IP,peerIp:$VPN7_IP,sharedSecret:gke-to-gke-vpn,\
nodeCIDR:10.1.0.0/28,clusterCIDR:10.108.0.0/19,\
serviceCIDR:10.208.0.0/20"

gcloud deployment-manager deployments create vpn6-deployment \
	--template vpn-custom-subnet-adjusted.jinja \
	--properties "region:us-west1,network:projects/$PROJECT_ID/global/networks/network1,\
vpn-ip:$VPN7_IP,peerIp:$VPN5_IP,sharedSecret:gke-to-gke-vpn,\
nodeCIDR:10.154.0.0/20,clusterCIDR:10.24.0.0/14"


### Fetch cluster1 credentials, deploy nginx pods in cluster1 and create
### services
gcloud container clusters get-credentials cluster1-deployment-cluster1 \
	--zone us-west1-b
kubectl config set-context "$(kubectl config current-context)" --namespace=default
kubectl create -f "$ROOT"/manifests/run-my-nginx.yaml
kubectl create -f "$ROOT"/manifests/cluster-ip-svc.yaml
kubectl create -f "$ROOT"/manifests/nodeport-svc.yaml
kubectl create -f "$ROOT"/manifests/ilb-svc.yaml
kubectl create -f "$ROOT"/manifests/lb-svc.yaml
kubectl create -f "$ROOT"/manifests/ingress-svc.yaml


