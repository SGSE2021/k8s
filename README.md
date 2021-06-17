# k8s
Aufsetzen und Konfiguration eines Kubernetes-Clusters mit Microsoft Azure

## Voraussetzungen

- [Azure CLI Installation](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli), Version 2.0.53 oder höher
- Kubernetes CLI Installation
  - [manuell](https://kubernetes.io/docs/tasks/tools/)
  - Azure CLI: `az aks install-cli`
- [Helm Installation](https://helm.sh/docs/intro/install/)
- [yq Installation](https://mikefarah.gitbook.io/yq/)

## Verwendung

1. Azure Login: `az login`
2. Konfigurationsoptionen in k8s-setup.sh anpassen.
3. Setup Skript ausführen: `./k8s-setup.sh`
4. Speichern der ausgegebenen Anmeldedaten für den Service Principal. Diese Daten können später nicht mehr abgerufen werden.

## Github Actions

### Secrets

Das Setup Skript erzeugt einen Service Principal, der den Zugriff auf die Container Registry und den Kubernetes Cluster über [GitHub Actions](https://docs.github.com/en/actions) erlaubt. Die dafür ausgegebenen Anmeldedaten haben folgende Form (JSON Format):

{
    "clientId": "<GUID>",
    "clientSecret": "<GUID>",
    "subscriptionId": "<GUID>",
    "tenantId": "<GUID>",
    (...)
  }

Für die Verwendung in Github müssen folgende [Secrets](https://docs.github.com/en/actions/reference/encrypted-secrets) mit erstellt werden:

| Name              | Wert                                    |
| ----------------- | --------------------------------------- |
| ACR_USERNAME      | Wert der "clientId"                     |
| ACR_PASSWORD      | Wert des "clientSecret"                 |
| AZURE_CREDENTIALS | komplette JSON Ausgabe der Anmeldedaten |

### Workflow

```yaml
name: Build and deploy to AKS Cluster
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:
  
env:
  CONTAINER_REGISTRY: <ACR Login Server (e.g. mycontainerregistry.azurecr.io)>
  CLUSTER_NAME: <AKS Clusters name (e.g. myAKSCluster)>
  RESOURCE_GROUP: <Resource group name (e.g. myResourceGroup)>
  APP_NAME: <Application name (e.g. myApp)>
  DOCKERFILE: <Path to dockerfile (e.g. ./Dockerfile)>

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Login to Azure Container Registry
      uses: Azure/docker-login@v1
      with:
        login-server: ${{ env.CONTAINER_REGISTRY }}
        username: ${{ secrets.ACR_USERNAME }}
        password: ${{ secrets.ACR_PASSWORD }}
        
    - name: Build and push
      id: docker_build
      uses: docker/build-push-action@v2
      with:
          context: ./
          file: ${{ env.DOCKERFILE }}
          push: true
          tags: "${{ env.CONTAINER_REGISTRY }}/${{ env.APP_NAME }}:latest"
          
    - name: Image digest
      run: echo ${{ steps.docker_build.outputs.digest }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2

    - name: Azure authentication
      uses: azure/login@v1
      with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
          
    - name: Login to Azure Container Registry
      uses: Azure/docker-login@v1
      with:
        login-server: ${{ env.CONTAINER_REGISTRY }}
        username: ${{ secrets.ACR_USERNAME }}
        password: ${{ secrets.ACR_PASSWORD }}

    # Set the target AKS cluster.
    - uses: Azure/aks-set-context@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
        cluster-name: ${{ env.CLUSTER_NAME }}
        resource-group: ${{ env.RESOURCE_GROUP }}
        
    - uses: Azure/k8s-deploy@v1
      with:
        manifests: <YAML files for deployments/services (e.g. manifests/myapp.yaml)>

```

