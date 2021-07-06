#!/bin/bash

#--------------------#
#  General Settings  #
#--------------------#

# SUPPORT_NAMESPACE: Namespace for support services
SUPPORT_NAMESPACE=support

# SB_SIZE: Database size
DB_SIZE=1Gi

# MONGO_PORT: MongoDB service port
MONGO_PORT=27017

# MARIA_PORT: MariaDB Primary K8s service port
MARIA_PORT=3306

# POSTGRESQL_PORT: PostgreSQL port
POSTGRESQL_PORT=5432

# MYSQL_PORT: MySQL port
MYSQL_PORT=3306

#----------------------#
#  Benutzerverwaltung  #
#----------------------#

USERSDB_ROOT_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
USERSDB_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
USERSDB_USERNAME=usersdb-user
USERSDB_HOSTNAME=users
USERSDB_DBNAME=usersdb
USERSDB_PORT=$POSTGRESQL_PORT
USERSDB_SIZE=$DB_SIZE

#----------------------------#
#  Kursressourcenmanagement  #
#----------------------------#

RESOURCESDB_ROOT_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
RESOURCESDB_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
RESOURCESDB_USERNAME=resourcesdb-user
RESOURCESDB_HOSTNAME=resources
RESOURCESDB_DBNAME=resourcedb
RESOURCESDB_PORT=$MONGO_PORT
RESOURCESDB_SIZE=$DB_SIZE

#---------------#
#  Nachrichten  #
#---------------#

MESSAGEDB_ROOT_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
MESSAGEDB_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
MESSAGEDB_USERNAME=messagedb-user
MESSAGEDB_HOSTNAME=messages
MESSAGEDB_DBNAME=messagedb
MESSAGEDB_PORT=$MONGO_PORT
MESSAGEDB_SIZE=$DB_SIZE

#---------------------#
#  Kurse und Termine  #
#---------------------#

COURSESDB_ROOT_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
COURSESDB_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
COURSESDB_USERNAME=coursesdb-user
COURSESDB_HOSTNAME=courses
COURSESDB_DBNAME=coursedb
COURSESDB_PORT=$MARIA_PORT
COURSESDB_SIZE=$DB_SIZE

#----------------------#
#  Prüfungsleistungen  #
#----------------------#

EXAMSDB_ROOT_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
EXAMSDB_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
EXAMSDB_USERNAME=examsdb-user
EXAMSDB_HOSTNAME=exams
EXAMSDB_DBNAME=examdb
EXAMSDB_PORT=$MYSQL_PORT
EXAMSDB_SIZE=$DB_SIZE

#---------------#
#  Stundenplan  #
#---------------#

BOOKINGSDB_PW=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n 1)
BOOKINGSDB_HOSTNAME=bookings
BOOKINGSDB_DBNAME=bookingdb
BOOKINGSDB_SIZE=$DB_SIZE

#---------------------#
#  RabbitMQ Settings  #
#---------------------#

# RABBIT_NAME: Name of the RabbitMQ service
RABBIT_NAME=rabbitmq

#RABBIT_SIZE: PVC Storage Request for RabbitMQ data volume
RABBIT_SIZE=1Gi

#----------------------------------------------------------------------------------------------------
# Setup helm repos

# Add bitnami-azure Helm repo (MongoDB, MariaDB, PostgreSQL, MySQL, RabbitMQ)
helm repo add bitnami-azure https://marketplace.azurecr.io/helm/v1/repo

# Update your local Helm chart repository cache
helm repo update
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Create a namespace

#kubectl create namespace $SUPPORT_NAMESPACE
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup bookings database (Neo4j)
                                  
helm install $BOOKINGSDB_HOSTNAME https://github.com/neo4j-contrib/neo4j-helm/releases/download/v4.2.8-1/neo4j-4.2.8-1.tgz \
		--namespace $SUPPORT_NAMESPACE \
		--set acceptLicenseAgreement=yes \
		--set core.standalone=true \
		--set neo4jPassword=$BOOKINGSDB_PW \
		--set defaultDatabase=$BOOKINGSDB_DBNAME \
		--set core.persistentVolume.size=$BOOKINGSDB_SIZE

echo "Bookings database:"
echo "URL: neo4j://$BOOKINGSDB_HOSTNAME-neo4j.$SUPPORT_NAMESPACE.svc.cluster.local"
echo "PW: $BOOKINGSDB_PW"
echo "User: neo4j"
echo "Ports: 7474 (HTTP), 7473 (HTTPS), 7687 (Bort)"
echo ""
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup exams database (MySQL)

helm install $EXAMSDB_HOSTNAME bitnami-azure/mysql \
		--namespace $SUPPORT_NAMESPACE \
		--set architecture=standalone \
		--set auth.rootPassword=$EXAMSDB_ROOT_PW \
		--set auth.username=$EXAMSDB_USERNAME \
		--set auth.password=$EXAMSDB_PW \
		--set auth.database=$EXAMSDB_DBNAME \
		--set primary.service.port= $EXAMSDB_PORT \
		--set primary.persistence.size=$EXAMSDB_SIZE
		
echo "Exams database:"
echo "User: $EXAMSDB_USERNAME"
echo "PW: $EXAMSDB_PW"
echo "Admin PW: $EXAMSDB_ROOT_PW"
echo "Database: $EXAMSDB_DBNAME"
echo "Port: $EXAMSDB_PORT"
echo ""
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup courses database (MariaDB)

helm install $COURSESDB_HOSTNAME azure-marketplace/mariadb \
		--namespace $SUPPORT_NAMESPACE \
		--set architecture=standalone \
		--set auth.rootPassword=$COURSESDB_ROOT_PW \
		--set auth.username=$COURSESDB_USERNAME \
		--set auth.password=$COURSESDB_PW \
		--set auth.database=$COURSESDB_DBNAME
		--set primary.service.port= $COURSESDB_PORT \
		--set primary.persistence.size=$COURSESDB_SIZE

echo "Courses database:"
echo "User: $COURSESDB_USERNAME"
echo "PW: $COURSESDB_PW"
echo "Admin PW: $COURSESDB_ROOT_PW"
echo "Database: $COURSESDB_DBNAME"
echo "Port: $COURSESDB_PORT"
echo ""
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup users database (PostgreSQL)

helm install $USERSDB_HOSTNAME bitnami-azure/postgresql \
		--set postgresqlPostgresPassword=$USERSDB_ROOT_PW \
		--set postgresqlUsername=$USERSDB_USERNAME \
		--set postgresqlPassword=$USERSDB_PW \
		--set postgresqlDatabase=$USERSDB_DBNAME \
		--set service.port=$USERSDB_PORT \
		--set persistence.size=$USERSDB_SIZE

echo "Users database:"
echo "User: $USERSDB_USERNAME"
echo "PW: $USERSDB_PW"
echo "Admin PW: $USERSDB_ROOT_PW"
echo "Database: $USERSDB_DBNAME"
echo "Port: $USERSDB_PORT"
echo ""
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup messages database (MongoDB)

helm install $MESSAGEDB_HOSTNAME bitnami-azure/mongodb \
		--namespace $SUPPORT_NAMESPACE \
		--set architecture=standalone \
		--set auth.rootPassword=$MESSAGEDB_ROOT_PW \
		--set auth.username=$MESSAGEDB_USERNAME \
		--set auth.password=$MESSAGEDB_PW \
		--set auth.database=$MESSAGEDB_DBNAME \
		--set service.port=$MESSAGEDB_PORT \
		--set persistence.size=$MESSAGEDB_SIZE

echo "Messages database:"
echo "URL: mongodb://$MESSAGEDB_USERNAME:$MESSAGEDB_PW@$MESSAGEDB_HOSTNAME-mongodb.$SUPPORT_NAMESPACE.svc.cluster.local:$MESSAGEDB_PORT/$MESSAGEDB_DBNAME"
echo "Root PW: $MESSAGEDB_ROOT_PW"
echo ""
#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup resource management database (MongoDB)

helm install $RESOURCESDB_HOSTNAME bitnami-azure/mongodb \
		--namespace $SUPPORT_NAMESPACE \
		--set architecture=standalone \
		--set auth.rootPassword=$RESOURCESDB_ROOT_PW \
		--set auth.username=$RESOURCESDB_USERNAME \
		--set auth.password=$RESOURCESDB_PW \
		--set auth.database=$RESOURCESDB_DBNAME \
		--set service.port=$RESOURCESDB_PORT \
		--set persistence.size=$RESOURCESDB_SIZE

echo "Messages database:"
echo "URL: mongodb://$RESOURCESDB_USERNAME:$RESOURCESDB_PW@$RESOURCESDB_HOSTNAME-mongodb.$SUPPORT_NAMESPACE.svc.cluster.local:$RESOURCESDB_PORT/$RESOURCESDB_DBNAME"
echo "Root PW: $RESOURCESDB_ROOT_PW"
echo ""

#----------------------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------------------
# Setup RabbitMQ

helm install $RABBIT_NAME bitnami-azure/rabbitmq \
		--namespace $SUPPORT_NAMESPACE \
		--set persistence.size=$RABBIT_SIZE

RABBIT_PW=$(kubectl get secret --namespace support rabbitmq -o jsonpath="{.data.rabbitmq-password}" | base64 --decode)"

echo "RabbitMQ:"
echo "URL: amqp://user:$RABBIT_PW@rabbitmq.support.svc.cluster.local:5672"
echo ""
#----------------------------------------------------------------------------------------------------