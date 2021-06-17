#!/bin/bash

### Configuration options for resources. Modify for your environment.

# RESOURCE_GROUP_NAME: The name of your Resource Group
RESOURCE_GROUP_NAME=sgse2021ResourceGroup

# ACR_NAME: The name of your Azure Container Registry. Must be unique within Azure
ACR_NAME=sgse2021ContainerRegistry

# AKS_NAME: The name of your Azure Kubernetes Cluster
AKS_NAME=sgse2021AKSCluster

# AKS_NODE_COUNT: Number of nodes in your cluster
AKS_NODE_COUNT=5

# MICROSERVICES_NAMESPACE:
MICROSERVICES_NAMESPACE=microservicesNamespace

# PUBLIC_IP_NAME: Name of the public IP address
PUBLIC_IP_NAME=sgse2021PublicIP

# INGRESS_NSP: Namespace for the ingress controller
INGRESS_NAMESPACE=ingressControllerNamespace

# IP_DNS_LABEL: DNS label used by ingress
IP_DNS_LABEL=sgse2021

# DATABASE_NAMESPACE: Namespace for database services
DATABASE_NAMESPACE=databaseNamespace

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
ACR_LOGIN_SERVER=$(az acr create --resource-group $RESOURCE_GROUP_NAME --name $ACR_NAME --sku Basic --query loginServer --output tsv)
echo "ACR Name: ACR_NAME$"
echo "ACR Login Server: $ACR_LOGIN_SERVER"

# Create a kubernetes cluster
NODE_RESOURCE_GROUP=$(az aks create --resource-group $RESOURCE_GROUP_NAME --name $AKS_NAME --node-count $AKS_NODE_COUNT --attach-acr $ACR_NAME --generate-ssh-keys --enable-managed-identity --query nodeResourceGroup --output tsv)
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
PUBLIC_IP=$(az network public-ip create --resource-group $NODE_RESOURCE_GROUP --name $PUBLIC_IP_NAME --sku Standard --allocation-method static --query publicIp.ipAddress -o tsv)
echo "Public IP: $PUBLIC_IP"

# Create a namespace for your ingress resources
kubectl create namespace $INGRESS_NAMESPACE

# Add the ingress-nginx repository
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
	
DNS_RECORD=$(az network public-ip list --resource-group $NODE_RESOURCE_GROUP --query "[?name=='$PUBLIC_IP_NAME'].[dnsSettings.fqdn]" -o tsv)
echo "DNS Record: $DNS_RECORD"

# Label the cert-manager namespace to disable resource validation
kubectl label namespace ingress-basic cert-manager.io/disable-validation=true

# Install the cert-manager Helm chart
helm install cert-manager --namespace $INGRESS_NAMESPACE --version v1.3.1 --set installCRDs=true --set nodeSelector."beta\.kubernetes\.io/os"=linux jetstack/cert-manager

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
# Database Setup
#
# Deploy services that provide persistent databases used by other services



#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# CI/CD Setup
#
# Create resources for CI/CD pipelines

# Create service principal with rights scoped to the resource group and save the credentials.
# The credentials can be used for authentication in automatic workflows (e.g. Github actions)
SP_CREDENTIALS=$(az ad sp create-for-rbac --name http://$SERVICE_PRINCIPAL_NAME --scope $GROUP_ID --role Contributor --sdk-auth)
echo "Service Principal Credentials. Save these for use in automation (e.g. Github actions)"
echo "$SP_CREDENTIALS"
#----------------------------------------------------------------------------------------------------