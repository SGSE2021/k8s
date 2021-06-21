#!/bin/bash

### Configuration options for resources. Modify for your environment.

# RESOURCE_GROUP_NAME: The name of your Resource Group
RESOURCE_GROUP_NAME=sgse2021ResourceGroup

# ACR_NAME: The name of your Azure Container Registry. Must be unique within Azure
ACR_NAME=sgse2021ContainerRegistry

# AKS_NAME: The name of your Azure Kubernetes Cluster
AKS_NAME=sgse2021AKSCluster

# AKS_NODE_COUNT: Number of nodes in your cluster
AKS_NODE_COUNT=2

# MICROSERVICES_NAMESPACE:
MICROSERVICES_NAMESPACE=microservices

# PUBLIC_IP_NAME: Name of the public IP address
PUBLIC_IP_NAME=sgse2021PublicIP

# INGRESS_NAMESPACE: Namespace for the ingress controller
INGRESS_NAMESPACE=ingress

# IP_DNS_LABEL: DNS label used by ingress
IP_DNS_LABEL=sgse2021

# DATABASE_NAMESPACE: Namespace for database services
DATABASE_NAMESPACE=databases

# MONGO_HOSTNAME: Hostname for MongoDB
MONGO_HOSTNAME=mongohost

# MONGO_DBNAME: MongoDB database name
MONGO_DBNAME=mongodb

# MONGO_PORT: MongoDB service port
MONGO_PORT=27017

# MONGO_SIZE: Size of the storage volume for MongoDB
MONGO_SIZE=1Gi

# SERVICE_PRINCIPAL_NAME: Must be unique within your AD tenant
SERVICE_PRINCIPAL_NAME=sgse2021ServicePrincipal

### End configuration

#----------------------------------------------------------------------------------------------------
# Basic Resources Setup
#
# Create the basic resources: Resource group, container registry and kubernetes cluster

# Create a resource group and save the group id.
GROUP_ID=$(az group create --name $RESOURCE_GROUP_NAME --location westeurope --query id --output tsv)
echo "Resource Group Name: $RESOURCE_GROUP_NAME"
echo "Resource Group ID: $GROUP_ID"

# Create a container registry and save the login server
ACR_LOGIN_SERVER=$(az acr create --resource-group $RESOURCE_GROUP_NAME \
                                 --name $ACR_NAME \
								 --sku Basic \
								 --query loginServer --output tsv)
echo "ACR Name: $ACR_NAME"
echo "ACR Login Server: $ACR_LOGIN_SERVER"

# Create a kubernetes cluster
NODE_RESOURCE_GROUP=$(az aks create --resource-group $RESOURCE_GROUP_NAME \
						            --name $AKS_NAME \
									--node-count $AKS_NODE_COUNT \
									--attach-acr $ACR_NAME \
									--generate-ssh-keys \
									--enable-managed-identity \
									--query nodeResourceGroup --output tsv)
echo "AKS Name: $AKS_NAME"
echo "AKS Node Resource Group: $NODE_RESOURCE_GROUP"

# Connect to cluster using kubectl
az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $AKS_NAME

# Enable monitoring
az aks enable-addons -a monitoring -n $AKS_NAME -g $RESOURCE_GROUP_NAME

# Create a namespace for microservice deployment
kubectl create namespace $MICROSERVICES_NAMESPACE
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Network Setup
#
# Create a public ip for the cluster and deploy an ingress controller

# Create public IP address
PUBLIC_IP=$(az network public-ip create --resource-group $NODE_RESOURCE_GROUP \
                                        --name $PUBLIC_IP_NAME \
										--sku Standard \
										--allocation-method static \
										--query publicIp.ipAddress -o tsv)
echo "Public IP: $PUBLIC_IP"

# Create a namespace for your ingress resources
kubectl create namespace $INGRESS_NAMESPACE

# Add the ingress-nginx Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
helm repo update

# Use Helm to deploy an NGINX ingress controller
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace $INGRESS_NAMESPACE \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set controller.service.loadBalancerIP=$PUBLIC_IP \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$IP_DNS_LABEL
	
DNS_RECORD=$(az network public-ip list --resource-group $NODE_RESOURCE_GROUP \
				--query "[?name=='$PUBLIC_IP_NAME'].[dnsSettings.fqdn]" -o tsv)
echo "DNS Record: $DNS_RECORD"

# Label the cert-manager namespace to disable resource validation
kubectl label namespace $INGRESS_NAMESPACE cert-manager.io/disable-validation=true

# Install the cert-manager Helm chart
helm install cert-manager --namespace $INGRESS_NAMESPACE \
						  --version v1.3.1 \
						  --set installCRDs=true \
						  --set nodeSelector."beta\.kubernetes\.io/os"=linux jetstack/cert-manager

# Create CA cluster issuer
kubectl apply -f cluster-issuer.yaml --namespace $INGRESS_NAMESPACE
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Hello World
#
# Deploy a simple application to test the setup

# Deploy Hello-World-App
kubectl apply -f aks-helloworld.yaml --namespace $MICROSERVICES_NAMESPACE

# Configure ingress rule
yq w ingress-rules-template.yaml "metadata.namespace" "$MICROSERVICES_NAMESPACE" | yq w - "spec.tls[0].hosts[0]" "$DNS_RECORD" | yq w - "spec.rules[0].host" "$DNS_RECORD" > ingress-rules.yaml
kubectl apply -f ingress-rules.yaml --namespace $MICROSERVICES_NAMESPACE

echo "Test application deployed under https://$DNS_RECORD/hello-world"
echo "Remove test application with 'kubectl delete -f aks-helloworld.yaml'"
echo "Ingress rules can be configured in ingress-rules.yaml and deployed with 'kubectl apply -f ingress-rules.yaml --namespace=$MICROSERVICES_NAMESPACE'"

#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Database Setup (WIP)
#
# Deploy services that provide persistent databases used by other services

# Add bitnami-azure Helm repo
helm repo add bitnami-azure https://marketplace.azurecr.io/helm/v1/repo

# Update your local Helm chart repository cache
helm repo update

# Generate random passwords and username
MONGO_ROOT_PWD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
MONGO_PWD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
MONGO_USERNAME=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)

# Install MongoDB Helm chart
helm install $MONGO_HOSTNAME bitnami-azure/mongodb \
				--namespace $DATABASE_NAMESPACE \
				--set mongodbRootPassword=$MONGO_ROOT_PWD \
				--set mongodbUsername=$MONGO_USERNAME \
				--set mongodbPassword=$MONGO_PWD \
				--set mongodbDatabase=$MONGO_DBNAME \
				--set service.port=$MONGO_PORT \
				--set replicaSet.enabled=true \
				--set persistence.size=$MONGO_SIZE

echo "MongoDB URL: mongodb://$MONGO_USERNAME:$MONGO_PWD@$MONGO_HOSTNAME.$DATABASE_NAMESPACE:$MONGO_PORT/$MONGO_DBNAME"

#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# CI/CD Setup
#
# Create resources for CI/CD pipelines

# Create service principal with rights scoped to the resource group and save the credentials.
# The credentials can be used for authentication in automatic workflows (e.g. Github actions)
SP_CREDENTIALS=$(az ad sp create-for-rbac --name http://$SERVICE_PRINCIPAL_NAME \
										  --scope $GROUP_ID \
										  --role Contributor \
										  --sdk-auth)
echo "Service Principal Credentials. Save these for use in automation (e.g. Github actions)"
echo "$SP_CREDENTIALS"
#----------------------------------------------------------------------------------------------------