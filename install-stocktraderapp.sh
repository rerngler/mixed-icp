source ./lib.sh
source ./variables.sh
# create a configmap kafka-config from the local directory containing the es-cert.jks
kubectl create configmap kafka-cert-config -n ${NAMESPACE} --from-file=./kafka-configmap/

# install the from helm chart in directory stocktrader-amd64
eval "cat <<EOF
$(<stapp-values.yaml)
EOF
" | helm install stocktrader-amd64 --tls --name stapp --namespace ${NAMESPACE} -f -
TRADER_NODEPORT=$(kubectl get service -l app=trader -n ${NAMESPACE} -o jsonpath="{.items[0].spec.ports[1].nodePort}")
TRADEHISTORY_NODEPORT=$(kubectl get service -l app=trade-history -n ${NAMESPACE} -o jsonpath="{.items[0].spec.ports[0].nodePort}")
PROXY_IP=$(kubectl get configmap ibmcloud-cluster-info -n kube-public -o jsonpath="{.data.proxy_address}")

echo "To start processing kafka event, open your browser to http://$PROXY_IP:$TRADEHISTORY_NODEPORT" > tradehistory.out
cat ./tradehistory.out
echo "Open your browser to https://$PROXY_IP:$TRADER_NODEPORT/trader/login" > ./trader.out
echo "or https://stocktrader.ibm.com/trader/login (if stocktrader.ibm.com is defined in dns)" >> ./trader.out
cat ./trader.out
