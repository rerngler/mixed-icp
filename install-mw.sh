source ./lib.sh
source ./variables.sh

CLUSTER_CA_DOMAIN=$(kubectl get configmap ibmcloud-cluster-info -n kube-public -o jsonpath="{.data.cluster_ca_domain}")
exit_if_error "Make sure you do a cloudctl login.\ne.g. cloudctl login -a https://<cluster_ca_domain>:8443 --skip-ssl-validation -u <admin user> -p <admin password>"

PROXY_IP=$(kubectl get configmap ibmcloud-cluster-info -n kube-public -o jsonpath="{.data.proxy_address}")

if [[ "$DOCKER_USERNAME" == "<Enter your docker username here>" ]] || [[ "$DOCKER_PASSWORD" == "<Enter your docker password here>" ]] || [[ "$DOCKER_EMAIL" == "<Enter your docker email here>" ]]; then
  echo "Please configure your DOCKER_XXX variables in variables.sh file"
  exit
fi

echo "Deploying to ICP on cluster_ca_domain = ${CLUSTER_CA_DOMAIN}"
# the namespace need to have anyuid and priviledged for some middleware chart
kubectl create ns $NAMESPACE
exit_if_error "The namespace $NAMESPACE already exists. Please delete it using kubectl delete ns $NAMESPACE"
kubectl -n ${NAMESPACE} create rolebinding ibm-anyuid-clusterrole-rolebinding --clusterrole=ibm-anyuid-clusterrole --group=system:serviceaccounts:${NAMESPACE}
kubectl -n ${NAMESPACE} create rolebinding ibm-privileged-clusterrole-rolebinding --clusterrole=ibm-privileged-clusterrole --group=system:serviceaccounts:${NAMESPACE}
kubectl create rolebinding -n ${NAMESPACE} st-rolebinding --clusterrole=privileged  --serviceaccount=${NAMESPACE}:default

# create the st-docker-registry secret to pull db2 developer image
kubectl create secret docker-registry st-docker-registry --docker-username=${DOCKER_USERNAME} --docker-password=${DOCKER_PASSWORD} --docker-email=${DOCKER_EMAIL} --namespace=${NAMESPACE}

# deploy st-db2
echo "Installing IBM DB2 chart"
cat <<EOF | helm install -n st-db2 --namespace ${NAMESPACE} --tls ibm-charts/ibm-db2oltp-dev -f -
global:
  image:
    secretName: "st-docker-registry"
arch: "s390x"
db2inst:
  instname: "${DB2_USERNAME}"
  password: "${DB2_PASSWORD}"
options:
  databaseName: "${DB2_DATABASE}"
persistence:
  enabled: true
  useDynamicProvisioning: true
EOF

DB2_POD=$(kubectl get pods -l release=st-db2 -n ${NAMESPACE} -o jsonpath="{.items[0].metadata.name}")
wait_for_pods $DB2_POD

echo "Waiting for Databases to be active..."
# the database may still being created... so wait for all databases to be active
while [ -z "$(kubectl logs -l release=st-db2 -n ${NAMESPACE}  | grep 'All databases are now active')" ]; 
do
	sleep 30s
done
echo "Databases are now active"

# Creating the DB2 tables...
echo "Copying file to pod using 'kubectl cp ./createDBTables.ddl ${NAMESPACE}/${DB2_POD}:createDBTables.ddl'"
kubectl cp ./createDBTables.ddl ${NAMESPACE}/${DB2_POD}:createDBTables.ddl
# fix file permission
kubectl exec -it $DB2_POD -n ${NAMESPACE} -- chmod 644 /createDBTables.ddl
if [ $? -ne 0 ]; then exit; fi
echo "Creating DB2 tables"
kubectl exec -it $DB2_POD -n ${NAMESPACE} -- su - -c "db2 connect to ${DB2_DATABASE} && db2 -tf /createDBTables.ddl && db2 connect reset" ${DB2_USERNAME}
if [ $? -ne 0 ]; then exit; fi

# Install MQ
echo "Installing IBM MQ"
cat <<EOF | helm install -n st-mq --namespace ${NAMESPACE} --tls ibm-charts/ibm-mqadvanced-server-dev -f -
license: "accept"
arch:
  ppc64le: "3"
service:
  name: qmgr
  type: NodePort
queueManager:
  name: "${MQ_QMGR}"
  dev:
    adminPassword: "${MQ_ADMIN_PASSWORD}"
    appPassword: "${MQ_APP_PASSWORD}"
EOF

MQ_POD=$(kubectl get pods -l release=st-mq -n ${NAMESPACE} -o jsonpath="{.items[0].metadata.name}")
wait_for_pods $MQ_POD

echo "Sending MQ command file to MQ pod $MQ_POD"
echo kubectl cp ./defineStocktraderQueue.in ${NAMESPACE}/${MQ_POD}:/tmp/defineStocktraderQueue.in
kubectl cp ./defineStocktraderQueue.in ${NAMESPACE}/${MQ_POD}:/tmp/defineStocktraderQueue.in
if [ $? -ne 0 ]; then exit; fi

# fix file permission
echo kubectl exec -it ${MQ_POD} -n ${NAMESPACE} -- chmod 644 /tmp/defineStocktraderQueue.in
kubectl exec -it ${MQ_POD} -n ${NAMESPACE} -- chmod 644 /tmp/defineStocktraderQueue.in
if [ $? -ne 0 ]; then exit; fi

# create queue. You will be prompted to enter the password to 'admin' which is 'passw0rd'
echo "Creating MQ queue. When prompted with password for admin, enter $MQ_ADMIN_PASSWORD"
kubectl exec -it ${MQ_POD} -n ${NAMESPACE} -- su - -c "runmqsc < /tmp/defineStocktraderQueue.in" admin
if [ $? -ne 0 ]; then exit; fi

echo "Adding ${NAMESPACE}-image-policy to allow image from other sites..."
cat << EOF | kubectl apply -f -
apiVersion: securityenforcement.admission.cloud.ibm.com/v1beta1
kind: ImagePolicy
metadata:
  name: ${NAMESPACE}-image-policy
  namespace: ${NAMESPACE}
spec:
 repositories:
  # allow all images
  - name: "*"
    policy:
EOF

echo "Installing redis..."
#helm install --name st-redis stable/redis  --namespace ${NAMESPACE} --tls
kubectl run st-redis --image=s390x/redis --replicas=1 -n ${NAMESPACE} --labels="release=st-redis"
# make sure it runs in the s390x
kubectl patch deploy st-redis -n ${NAMESPACE} --type='json' -p='[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"beta.kubernetes.io/arch": "s390x" } }]'
# creates a service so other can access it
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: st-redis-service
  labels:
    release: st-redis
spec:
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    release: st-redis
EOF
REDIS_POD=$(kubectl get pods -l release=st-redis -n ${NAMESPACE} -o jsonpath="{.items[0].metadata.name}")
wait_for_pods $REDIS_POD

echo "Installing IBM ODM..."
cat <<EOF | helm install -n st-odm --namespace ${NAMESPACE} --tls ibm-charts/ibm-odm-dev -f -
image:
  arch: "s390x"
service:
  type: NodePort
internalDatabase:
  populateSampleData: true
  persistence:
    enabled: true
    useDynamicProvisioning: true
readinessProbe:
  initialDelaySeconds: 600
  periodSeconds: 60
  failureThreshold: 45
livenessProbe:
  initialDelaySeconds: 600
  periodSeconds: 60
  failureThreshold: 10  
EOF

echo "Retrieving ODM nodeport"
ODM_NODEPORT=$(kubectl get service -l app=ibm-odm-dev -n ${NAMESPACE} -o jsonpath="{.items[0].spec.ports[0].nodePort}")
echo "Retrieved ODM nodeport: $ODM_NODEPORT"
STOCKTRADER_DECISION_SERVICE=./loyalty-decision-service.zip

ODM_POD=$(kubectl get pods -l release=st-odm -n ${NAMESPACE} -o jsonpath="{.items[0].metadata.name}")
wait_for_pods $ODM_POD

# Import stocktrader decision service
echo "Importing stocktrader decision service"
STATUS=$(curl \
 -X POST -H "Content-Type: multipart/form-data" \
 -F "file=@${STOCKTRADER_DECISION_SERVICE};type=application/x-zip-compressed" \
 -w %{http_code} \
 -o import.out \
 http://${PROXY_IP}:$ODM_NODEPORT/decisioncenter-api/v1/decisionservices/import --user odmAdmin:odmAdmin)

if [ "$STATUS" != "200" ]; then
  echo "Importing stocktrader decision service failed"
  cat import.out
  exit
fi

DECISION_ID=$( cat import.out | jq -r ".decisionService.id" )
echo "Imported stocktrader decision service.  Decision service id is " $DECISION_ID

# Deploy stocktrader ruleapp to execution server
echo "Finding deployment id"
STATUS=$(curl \
 -w %{http_code} \
 -o find.out \
 http://${PROXY_IP}:$ODM_NODEPORT/decisioncenter-api/v1/decisionservices/${DECISION_ID}/deployments --user odmAdmin:odmAdmin)

if [ "$STATUS" != "200" ]; then
  echo "Finding deployment id failed"
  cat find.out
  exit
fi

DEPLOYMENT_ID=$( cat find.out | jq -r ".elements[0].id" )

echo "Found deployment ID" $DEPLOYMENT_ID ". Deploying it."
STATUS=$(curl \
 -X POST \
 -w %{http_code} \
 -o deploy.out \
 http://${PROXY_IP}:$ODM_NODEPORT/decisioncenter-api/v1/deployments/${DEPLOYMENT_ID}/deploy --user odmAdmin:odmAdmin)

if [ "$STATUS" != "200" ]; then
  echo "Deployment failed"
  cat deploy.out
  exit
fi

echo "ODM Deployment successful.. Testing using curl command..."
curl -X POST -d '{ "theLoyaltyDecision": { "tradeTotal": 75000 } }' -H "Content-Type: application/json" http://${PROXY_IP}:${ODM_NODEPORT}/DecisionService/rest/ICP_Trader_Dev_1/determineLoyalty

printf "Installing mongodb...\n"
cat <<EOF | helm install --tls -n st-mongodb --namespace ${NAMESPACE} --tls ibm-charts/ibm-mongodb-dev -f -
arch:
  s390x: "3"
persistence:
  enabled: true
  useDynamicProvisioning: true
service:
  name: ibm-mongodb-dev
  type: NodePort
  port: 27017
database :
  user: "${MONGO_USER}"
  password: "${MONGO_PASSWORD}"
  name: "${MONGO_DBNAME}"
  dbcmd: "mongo"
EOF

MONGO_POD=$(kubectl get pods -l release=st-mongodb -n ${NAMESPACE} -o jsonpath="{.items[0].metadata.name}")
wait_for_pods $MONGO_POD

echo "Installing ibm event streams..."
# You can check the values accepted by the chart via the command
# $ helm inspect values ibm-charts/ibm-eventstreams-dev
helm install --tls --name st-events --namespace=${NAMESPACE} ibm-charts/ibm-eventstreams-dev \
  --set global.arch="s390x" \
  --set license=accept \
  --set proxy.externalEndpoint=${PROXY_IP} \
  --set persistence.enabled=false \
  --set persistence.useDynamicProvisioning=false

EVENTS_PODS=$(kubectl get pods -l release=st-mongodb -n ${NAMESPACE} -o jsonpath="{.items[*].metadata.name}")
wait_for_pods $EVENTS_PODS

KAFKA_PORT=$(kubectl get svc -n ${NAMESPACE} "st-events-ibm-es-ui-svc" -o 'jsonpath={.spec.ports[?(@.name=="admin-ui-https")].nodePort}')

echo "Kafka UI can be accessed from https://${PROXY_IP}:${KAFKA_PORT}" > kafka.out
cat kafka.out
echo "Access the Kafka UI and performs the following:"
echo "Create a stocktrader topic using the Kafka UI"
echo "Download the es-cert.jks into the kakfa-configmap directory"
echo "Edit the stapp-values.yaml and assign the kafka.address variable to the bootstrap address and port from the UI"
echo "Edit the stapp-values.yaml and assign the kafka.apiKey variable to APIKey from the UI"
