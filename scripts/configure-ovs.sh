_ovs-vsctl() {
  ovs-vsctl --no-wait --timeout 15 "$@"
}

_ovs-vsctl set Open_vSwitch . other_config:doca-init=true
_ovs-vsctl set Open_vSwitch . other_config:dpdk-max-memzones=50000
_ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
_ovs-vsctl set Open_vSwitch . other_config:pmd-quiet-idle=true
_ovs-vsctl set Open_vSwitch . other_config:max-idle=20000
_ovs-vsctl set Open_vSwitch . other_config:max-revalidator=5000
_ovs-vsctl --if-exists del-br ovsbr1
_ovs-vsctl --if-exists del-br ovsbr2
_ovs-vsctl --may-exist add-br br-sfc
_ovs-vsctl set bridge br-sfc datapath_type=netdev
_ovs-vsctl set bridge br-sfc fail_mode=secure
_ovs-vsctl --may-exist add-port br-sfc p0
_ovs-vsctl set Interface p0 type=dpdk
_ovs-vsctl set Interface p0 mtu_request=9216
_ovs-vsctl set Port p0 external_ids:dpf-type=physical
_ovs-vsctl --may-exist add-port br-sfc p1
_ovs-vsctl set Interface p1 type=dpdk
_ovs-vsctl set Interface p1 mtu_request=9216
_ovs-vsctl set Port p1 external_ids:dpf-type=physical

_ovs-vsctl set Open_vSwitch . external-ids:ovn-bridge-datapath-type=netdev
_ovs-vsctl --may-exist add-br br-ovn
_ovs-vsctl set bridge br-ovn datapath_type=netdev
_ovs-vsctl set Interface br-ovn mtu_request=9216
_ovs-vsctl --may-exist add-port br-ovn pf0hpf
_ovs-vsctl set Interface pf0hpf type=dpdk
_ovs-vsctl set Interface pf0hpf mtu_request=9216