#!/bin/bash

# debug by prining all the commands executed:
## set -x

VARS_FILE=$1

if [ -z "$VARS_FILE" ]; then
  echo "Usage: $0 <PATH_TO_VARS_FILE>"
  exit 1
fi

# source the vars file passed in first argument
echo -e "Souring variables file: '$VARS_FILE'"
source $VARS_FILE

echo -e "Variables file content:"
cat $VARS_FILE

# counter to track number of failed test cases
failed_testcase_count=0

# variable to store test_results summary
test_results_summary="Test Results Summary:
--------------------"

# Function to parse output of ping cmd and report packet loss
check_ping_packet_loss() {
  # output is in first agument
  output=$1

  if [ -z "${output}" ]; then
    echo "Usage: check_ping_packet_loss <PING_OUTPUT>"
    exit 1
  fi

  # move later to if debug
  # echo -e "Argument passed to function check_ping_packet_loss() is: \n${output}"
  # Extract packet loss
  PACKET_LOSS=$(echo "${output}" | grep -Eo '[0-9]+% packet loss' | awk '{print $1}' | tr -d '%')

  # echo "Packet loss is: ${PACKET_LOSS}"

  if [ "$PACKET_LOSS" -eq 0 ]; then
      echo "Packet loss percent is: ${PACKET_LOSS}"
      echo "Pass"
      return 0
  else
      echo "Packet loss percent is: ${PACKET_LOSS}, not 0"
      echo "Fail"
      # increment the failed testcase counter
      ((failed_testcase_count++))
      return 1
  fi
}

# function to translate results
format_result () {
  result=$1
   if [ "$result" -eq 0 ]; then
      echo "Pass"
  else
      echo "Fail"
  fi 
}

# Function to find degraded or progressing cluster operators and report status condition
check_cluster_operators() {
  local kubeconfig="$1"   # Optional: pass kubeconfig path
  local oc_cmd="oc"

  [[ -n "$kubeconfig" ]] && oc_cmd="oc --kubeconfig=${kubeconfig}"


  # If none found, print a healthy message
  if ! oc get co -o json --kubeconfig=${kubeconfig} | jq -e '.items[] | .status.conditions[] | select((.type=="Degraded" or .type=="Progressing") and .status=="True")' >/dev/null; then
    echo "✅ No operators are Degraded or Progressing."
    return 0
  else
    ((failed_testcase_count++))
    # Header
    printf "%-25s %-12s %-s\n" "OPERATOR" "STATUS" "MESSAGE"
    printf "%-25s %-12s %-s\n" "--------" "------" "-------"

    # Get cluster operators JSON and parse
    $oc_cmd get co -o json --kubeconfig=${kubeconfig}  | jq -r '
      .items[] as $op |
      $op.status.conditions[] |
      select((.type=="Degraded" or .type=="Progressing") and .status=="True") |
      [$op.metadata.name, .type, .message] | @tsv
    ' | while IFS=$'\t' read -r name type msg; do
      printf "%-25s %-12s %-s\n" "$name" "$type" "$msg"
      done
    return 1
  fi
}


echo -e "\nfailed_testcase_count is: ${failed_testcase_count}"

testcase_title="Checking if any cluster operators are degraded or progressing on admin cluster" 
echo -e "\n${testcase_title}"

check_cluster_operators "${admin_kubecfg}"
result_check_cluster_operators=$?
test_results_summary+="\n${testcase_title}: $(format_result ${result_check_cluster_operators})"

echo -e "\nfailed_testcase_count is: ${failed_testcase_count}"

testcase_title="Checking if any cluster operators are degraded or progressing on hosted cluster" 
echo -e "\n${testcase_title}"
check_cluster_operators "${hosted_kubecfg}"
result_check_cluster_operators=$?
test_results_summary+="\n${testcase_title}: $(format_result ${result_check_cluster_operators})"

echo -e "\nfailed_testcase_count is: ${failed_testcase_count}"


echo -e "\nChecking if workload namespace exists on admin cluster, otherwise create it"
if oc get namespace "${sriov_test_pod_namespace}" --kubeconfig="${admin_kubecfg}" >/dev/null 2>&1; then
  echo "✅ Namespace '${sriov_test_pod_namespace}' exists."
  echo -e "Checking if workload sriov test pods have already been deployed on admin cluster" 
else
  echo "❌ Namespace '${sriov_test_pod_namespace}' does NOT exist."
  echo "Creating namespace '${sriov_test_pod_namespace}' and applying the yaml file '${sriov_test_pod_yaml_file_path}'"

  # Note: the workload.yaml file also creates the workload namesace and resources it needs
  if oc create -f "${sriov_test_pod_yaml_file_path}" --kubeconfig="${admin_kubecfg}" >/dev/null 2>&1; then
    echo "✅ Namespace '${sriov_test_pod_namespace}' and workload.yaml file applied successfully."

    ###### Note: here we need to allow time for all the pods to be running before we check
    ###### replace with checks that all pods are running
    sleep 300

  else
    echo "❌ Failed to create namespace '${sriov_test_pod_namespace}' and applying '${sriov_test_pod_yaml_file_path}' file."
    exit 1
  fi

fi


echo -e "\nCheck that all the pods are running in the '${sriov_test_pod_namespace}' namespace, otherwise exit:"

oc get deployment -n ${sriov_test_pod_namespace} --kubeconfig="${admin_kubecfg}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.readyReplicas}{" "}{.spec.replicas}{"\n"}{end}' \
| awk '{if($2!=$3){print "Deployment "$1" not ready ("$2"/"$3")"; exit 1} else {print "Deployment "$1" ready ("$2"/"$3")"}}'


echo -e "\nWorking with two DPU worker nodes: '${worker_node1}' and '${worker_node2}'"

echo -e "\noc get nodes --kubeconfig=${admin_kubecfg} output:"
oc get nodes --kubeconfig=${admin_kubecfg}

echo -e "\noc get nodes --kubeconfig=${hosted_kubecfg} output:"
oc get nodes --kubeconfig=${hosted_kubecfg}

echo -e "\noc get pods -n dpf-operator-system --kubeconfig=${admin_kubecfg} -o wide output:"
oc get pods -n dpf-operator-system --kubeconfig="${admin_kubecfg}" -o wide

# Find doca-hb-pod names on each DPU worker node
echo -e "\noc get pods -n dpf-operator-system --kubeconfig=${hosted_kubecfg} -o wide output:"
oc get pods -n dpf-operator-system --kubeconfig="${hosted_kubecfg}" -o wide

doca_hbn_pod_worker_node1=$(oc get pods -n dpf-operator-system --kubeconfig="${hosted_kubecfg}" -o wide | grep "${worker_node1}" | grep hbn | awk {'print $1'})
doca_hbn_pod_worker_node2=$(oc get pods -n dpf-operator-system --kubeconfig="${hosted_kubecfg}" -o wide | grep "${worker_node2}" | grep hbn | awk {'print $1'})

echo -e "\ndoca_hbn_pod_worker_node1 is: '${doca_hbn_pod_worker_node1}'"
echo -e "doca_hbn_pod_worker_node2 is: '${doca_hbn_pod_worker_node2}'"

# Get the doca-hbn container ip addresses
doca_hbn_pod_worker_node1_ip=$(oc exec "${doca_hbn_pod_worker_node1}" -n dpf-operator-system  --kubeconfig="${hosted_kubecfg}" -c doca-hbn -- ip a show pf2dpu2_if | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

doca_hbn_pod_worker_node2_ip=$(oc exec "${doca_hbn_pod_worker_node2}" -n dpf-operator-system  --kubeconfig="${hosted_kubecfg}" -c doca-hbn -- ip a show pf2dpu2_if | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

echo -e "\ndoca_hbn_pod_worker_node1_ip is: '${doca_hbn_pod_worker_node1_ip}'"
echo -e "doca_hbn_pod_worker_node2_ip is: '${doca_hbn_pod_worker_node2_ip}'"

oc get pods -n workload --kubeconfig=${admin_kubecfg} -o wide
output_workload_namespace=$(oc get pods -n workload --kubeconfig=${admin_kubecfg} -o wide)

echo -e "\nOutput of oc get pods -n workload: $output_workload_namespace\n"


############### Test pings from sriovtest-master pods to doca-hbn pods on 2 worker nodes:

sriov_test_pod_master=$(oc get pods -n workload --kubeconfig="${admin_kubecfg}" | grep master | awk '{print $1}')
echo -e "\nsriov master test pod is: ${sriov_test_pod_master}"

# Function to perform the ping test with arguments
ping_mtu_test() {
  tc_title=$1
  source_pod=$2
  namespace=$3
  kubecfg=$4
  ping_count=$5
  ping_mtu=$6
  destination_ip=$7


  if [ "$ping_mtu" = "normal" ]; then
    testcase_cmd="oc exec ${source_pod} -n $namespace --kubeconfig=${kubecfg} -- ping -c ${ping_count} ${destination_ip}"
  else
    testcase_cmd="oc exec ${source_pod} -n $namespace --kubeconfig=${kubecfg} -- ping -c ${ping_count} -M do -s ${ping_mtu}  ${destination_ip}"
  fi 

  # testcase_cmd="oc exec ${sriov_test_pod_master} -n workload --kubeconfig=${admin_kubecfg} -- ping -c 20 -M do -s 1490 ${doca_hbn_pod_worker_node1_ip}"
  ## testcase_cmd="oc exec ${source_pod} -n $namespace --kubeconfig=${kubecfg} -- ping -c ${ping_count} -M do -s ${ping_mtu}  ${destination_ip}"

  echo -e "\n${tc_title}:\n${testcase_cmd}"

  testcase_output=$(eval ${testcase_cmd})

  echo -e "${testcase_output}"

  check_ping_packet_loss "${testcase_output}"
  testcase_result=$?
  echo -e "tescase_result is: ${testcase_result}"

  test_results_summary+="\n${tc_title}: $(format_result ${testcase_result})"
}

echo -e "Test Results Summary is:\n$test_results_summary"

#------------ worker_node1
# Test ping from sriov master test pod to doca-hbn pod on worker_node1
testcase_title="Test pings from sriov master test pod to doca-hbn pod on node '${worker_node1}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_master}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 1490 "${doca_hbn_pod_worker_node1_ip}"


# Test ping from sriov master test pod to doca-hbn pod on worker_node2
testcase_title="Test pings from sriov master test pod to doca-hbn pod on node '${worker_node2}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_master}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 1490 "${doca_hbn_pod_worker_node2_ip}"


# get the test worker pod names on worker_node1
sriov_test_pod_worker1=$(oc get pods -n workload --kubeconfig="${admin_kubecfg}" -o wide | grep "${worker_node1}" | awk '{print $1}' | grep -v hostnetwork)
sriov_test_pod_hostnetwork_worker1=$(oc get pods -n workload --kubeconfig="${admin_kubecfg}" -o wide | grep "${worker_node1}" | awk '{print $1}' | grep hostnetwork)

echo -e "\nsriov worker test pod: '${sriov_test_pod_worker1}'"
echo -e "sriov worker test pod using host network: '${sriov_test_pod_hostnetwork_worker1}'"

# Test pings from sriov test-worker pod on worker_node1:
testcase_title="Test pings mtu 1490 from sriov worker test pod to doca-hbn pod on '${worker_node1}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_worker1}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 1490 "${doca_hbn_pod_worker_node1_ip}"


# Test pings mtu 1490 from sriov test-worker hostnetwork pod on worker_node1:
testcase_title="Test pings mtu 1490 from sriov worker hostnetwork test pods to doca-hbn pod on '${worker_node1}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_hostnetwork_worker1}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 1490 "${doca_hbn_pod_worker_node1_ip}"


# Test pings mtu 8970 from sriov test-worker hostnetwork pod on worker_node1:
testcase_title="Test pings mtu 8970 from sriov worker hostnetwork test pods to doca-hbn pod on '${worker_node1}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_hostnetwork_worker1}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 8970 "${doca_hbn_pod_worker_node1_ip}"


#------------ worker_node2
# get the test worker pod names on worker_node2
sriov_test_pod_worker2=$(oc get pods -n workload --kubeconfig="${admin_kubecfg}" -o wide | grep "${worker_node2}" | awk '{print $1}' | grep -v hostnetwork)
sriov_test_pod_hostnetwork_worker2=$(oc get pods -n workload --kubeconfig="${admin_kubecfg}" -o wide | grep "${worker_node2}" | awk '{print $1}' | grep hostnetwork)


echo -e "\nsriov worker test pod: '${sriov_test_pod_worker2}'"
echo -e "sriov worker test pod using host network: '${sriov_test_pod_hostnetwork_worker2}'"


# Test pings from sriov test-worker pod on worker_node2:
testcase_title="Test pings mtu 1490 from sriov worker test pod to doca-hbn pod on '${worker_node2}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_worker2}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 1490 "${doca_hbn_pod_worker_node2_ip}"


# Test pings mtu 1490 from sriov test-worker hostnetwork pod on worker_node2:
testcase_title="Test pings mtu 1490 from sriov worker hostnetwork test pods to doca-hbn pod on '${worker_node2}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_hostnetwork_worker2}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 1490 "${doca_hbn_pod_worker_node2_ip}"


# Test pings mtu 8970 from sriov test-worker hostnetwork pod on worker_node2:
testcase_title="Test pings mtu 8970 from sriov worker hostnetwork test pods to doca-hbn pod on '${worker_node2}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_hostnetwork_worker2}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 8970 "${doca_hbn_pod_worker_node2_ip}"


#----------  ping google.com on worker node 1
# Test pings from sriov test-worker pod on worker_node1 to 8.8.8.8 google.com:
testcase_title="Test pings from sriov worker test pods to 8.8.8.8 google.com on '${worker_node1}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_worker1}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 normal "8.8.8.8"


# Test pings from sriov test-worker hostnetwork pod on worker_node1 to 8.8.8.8 google.com:
testcase_title="Test pings from sriov worker hostnetwork test pods to 8.8.8.8 google.com on '${worker_node1}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_hostnetwork_worker1}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 "normal" "8.8.8.8"


#----------  ping google.com on worker node 2
# Test pings from sriov test-worker pod on worker_node2 to 8.8.8.8 google.com:
testcase_title="Test pings from sriov worker test pods to 8.8.8.8 google.com on '${worker_node2}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_worker2}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 "normal" "8.8.8.8"


# Test pings from sriov test-worker hostnetwork pod on worker_node2 to 8.8.8.8 google.com:
testcase_title="Test pings from sriov worker hostnetwork test pods to 8.8.8.8 google.com on '${worker_node2}'"

ping_mtu_test "$testcase_title" "${sriov_test_pod_hostnetwork_worker2}" "${sriov_test_pod_namespace}" "${admin_kubecfg}" 20 "normal" "8.8.8.8"


#------------------ test ping between doca-hbn pods on the two DPU nodes
# Test ping MTU 8970 between doca-hbn pods on DPU hosts
echo -e "\n======== Test ping MTU 8970 from doca-hbn pod on '${worker_node1}' to doca-hbn pod on '${worker_node2}': \
     \noc exec ${doca_hbn_pod_worker_node1} -n dpf-operator-system --kubeconfig=${hosted_kubecfg} -c doca-hbn -- ping -c 20 -M do -s 8970 ${doca_hbn_pod_worker_node2_ip}"

echo -e "\nList of interfaces that are up on doca-hbn pod '${doca_hbn_pod_worker_node1}':"
oc exec "${doca_hbn_pod_worker_node1}" -n dpf-operator-system  --kubeconfig="${hosted_kubecfg}" -c doca-hbn -- ip -4 -o a

echo -e "\nList of interfaces that are up on doca-hbn pod '${doca_hbn_pod_worker_node2}':"
oc exec "${doca_hbn_pod_worker_node2}" -n dpf-operator-system  --kubeconfig="${hosted_kubecfg}" -c doca-hbn -- ip -4 -o a


OUTPUT_PING_DOCA_HBN_WORKER1_to_DOCA_HBN_WORKER2=$(oc exec "${doca_hbn_pod_worker_node1}" -n dpf-operator-system --kubeconfig="${hosted_kubecfg}" -- ping -c 20 -M do -s 8970 "${doca_hbn_pod_worker_node2_ip}")

echo -e "\nOutput of OUTPUT_PING_DOCA_HBN_WORKER1_to_DOCA_HBN_WORKER2 is: \n${OUTPUT_PING_DOCA_HBN_WORKER1_to_DOCA_HBN_WORKER2}"

check_ping_packet_loss "${OUTPUT_PING_DOCA_HBN_WORKER1_to_DOCA_HBN_WORKER2}"


echo -e "\nTest Results Summary is:\n$test_results_summary"

echo "Number of failed tests: ${failed_testcase_count}"

if [ "${failed_testcase_count}" -gt 0 ]; then
  echo "${failed_testcase_count} tests failed !"
  exit 1
else
  echo "All tests passed"
  exit 0 
fi

