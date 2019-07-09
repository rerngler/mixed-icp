########################
# Helper functions
########################

## check if a pod is ready
## e.g __is_pod_ready <pod name>
function __is_pod_ready() {
  [[ "$(kubectl -n ${NAMESPACE} get po "$1" -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}')" == 'True' ]]
}

## Check if a list of pod (1 or more) is ready
## you can obtain the list of pod associated with a label and pass them into this function
## e.g.
## pods=$(kubectl get pods -l release=st-db2 -n stocktrader -o jsonpath="{.items[*].metadata.name}")
## wait_for_pods $pods
function wait_for_pods() {
	for pod in $@; do 
		while ! __is_pod_ready "$pod";
		do
			echo "Waiting for $pod to be Ready..."
			sleep 30s
		done
	done
}

function exit_if_error() {
	if [ $? -ne 0 ]; then
		if [ ! -z "$1" ]; then
			printf "$1\n"; 
		fi 
		exit 
	fi
}