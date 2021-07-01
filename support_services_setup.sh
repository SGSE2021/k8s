#!/bin/bash

### Configuration options for resources. Modify for your environment.

# SUPPORT_NAMESPACE: Namespace for support services
SUPPORT_NAMESPACE=support

# MONGO_HOSTNAME: Hostname for MongoDB
MONGO_HOSTNAME=mongohost

# MONGO_DBNAME: MongoDB database name
MONGO_DBNAME=mongodb

# MONGO_PORT: MongoDB service port
MONGO_PORT=27017

# NEO_HOSTNAME: Hostname for Neo4j
NEO_HOSTNAME=neohost

# NEO_DBNAME: Neo4j database name
NEO_DBNAME=neo4j

# SB_SIZE: Database size
DB_SIZE=1Gi

# RABBIT_NAME: Name of the RabbitMQ service
RABBIT_NAME=rabbitmq

#----------------------------------------------------------------------------------------------------
# Setup helm repos

# Add bitnami-azure Helm repo (MongoDB, MariaDB, PostgreSQL, RabbitMQ)
helm repo add bitnami-azure https://marketplace.azurecr.io/helm/v1/repo

# Update your local Helm chart repository cache
helm repo update
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Create a namespace

kubectl create namespace $SUPPORT_NAMESPACE
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup MongoDB

# Generate random passwords and username
MONGO_ROOT_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
MONGO_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
MONGO_USERNAME=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)

# Install MongoDB Helm chart
helm install $MONGO_HOSTNAME bitnami-azure/mongodb \
		--namespace $SUPPORT_NAMESPACE \
		--set mongodbRootPassword=$MONGO_ROOT_PW \
		--set mongodbUsername=$MONGO_USERNAME \
		--set mongodbPassword=$MONGO_PW \
		--set mongodbDatabase=$MONGO_DBNAME \
		--set service.port=$MONGO_PORT \
		--set replicaSet.enabled=true \
		--set persistence.size=$DB_SIZE

echo "MongoDB URL: mongodb://$MONGO_USERNAME:$MONGO_PWD@$MONGO_HOSTNAME.$SUPPORT_NAMESPACE:$MONGO_PORT/$MONGO_DBNAME"
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup MariaDB
#helm install my-release azure-marketplace/mariadb
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup PostgreSQL
#helm install my-release bitnami-azure/postgresql
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup Neo4j (requires license for Neo4j Enterprise Edition)

# Generate random password
NEO_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)

# Install Neo4j Helm chart
helm install $NEO_HOSTNAME https://github.com/neo4j-contrib/neo4j-helm/releases/download/4.2.7-2/neo4j-4.2.7-2.tgz \
		--namespace $SUPPORT_NAMESPACE \
		--set acceptLicenseAgreement=yes \
		--set core.standalone=true \
		--set neo4jPassword=$NEO_PW \
		--set defaultDatabase= $NEO_DBNAME \
		--set core.persistentVolume.size=$DB_SIZE

echo "Neo4j Service: $NEO_HOSTNAME"
echo "Neo4j Database: $NEO_DBNAME"
echo "Neo4j PW: $NEO_PW"
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup RabbitMQ

helm install $RABBIT_NAME azure-marketplace/rabbitmq \
		--namespace $SUPPORT_NAMESPACE \
		--set persistence.size=1Gi
#----------------------------------------------------------------------------------------------------