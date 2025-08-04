#!/usr/bin/python3

import base64
import gzip
import json
import os
import http.client
import ssl
import subprocess
import argparse
from dataclasses import dataclass
from typing import Optional
from pathlib import Path


@dataclass
class FileContents:
    inline: Optional[str] = None
    source: Optional[str] = None


@dataclass
class FileEntry:
    path: str
    overwrite: bool
    mode: int
    contents: FileContents


@dataclass
class SystemdUnit:
    name: str
    enabled: bool
    contents: Optional[str] = None


FILES_PLAIN: list[FileEntry] = [
    FileEntry(
        path="/etc/hostname",
        overwrite=True,
        mode=644,
        contents=FileContents(
            source="data:," + "{{.DPUHostName}}"
        )
    ),
    FileEntry(
        path="/etc/temp_bfcfg_strings.env",
        overwrite=True,
        mode=420,
        contents=FileContents(
            source="data:," + "bfb_pre_install%20bfb_modify_os%20bfb_post_install"
        )
    ),
    FileEntry(
        path="/usr/local/bin/dpf-ovs-script.sh",
        overwrite=True,
        mode=755,
        contents=FileContents(
            source="data:text/plain;charset=utf-8;base64," + "{{.OVSRawScript}}"
        )
    ),
    FileEntry(
        path="/etc/modules-load.d/br_netfilter.conf",
        overwrite=True,
        mode=420,
        contents=FileContents(
            source="data:," + "br_netfilter"
        )
    )
]

FILES: list[FileEntry] = [
        FileEntry(
        path="/etc/mellanox/mlnx-bf.conf",
        overwrite=True,
        mode=644,
        contents=FileContents(
            inline="""
ALLOW_SHARED_RQ="no"
IPSEC_FULL_OFFLOAD="no"
ENABLE_ESWITCH_MULTIPORT="yes"
""")
    ),
    FileEntry(
        path="/etc/mellanox/mlnx-ovs.conf",
        overwrite=True,
        mode=644,
        contents=FileContents(
            inline="""
CREATE_OVS_BRIDGES="no"
OVS_DOCA="yes"
""")
    ),
    FileEntry(
        path="/etc/NetworkManager/system-connections/pf0vf0.nmconnection",
        overwrite=True,
        mode=600,
        contents=FileContents(
            inline="""[connection]
id=pf0vf0
type=ethernet
interface-name=pf0vf0
master=br-comm-ch
slave-type=bridge

[ethernet]
mtu=9000

[bridge-port]"""
        )
    ),
    FileEntry(
        path="/etc/NetworkManager/system-connections/br-comm-ch.nmconnection",
        overwrite=True,
        mode=600,
        contents=FileContents(
            inline="""[connection]
id=br-comm-ch
type=bridge
interface-name=br-comm-ch
autoconnect-ports=1
autoconnect-slaves=1

[bridge]
stp=false

[ipv4]
dhcp-client-id=mac
dhcp-timeout=2147483647
method=auto

[ipv6]
addr-gen-mode=eui64
dhcp-timeout=2147483647
method=disabled

[proxy]""")
    ),
    FileEntry(
        path="/etc/NetworkManager/system-connections/tmfifo_net0.nmconnection",
        overwrite=True,
        mode=600,
        contents=FileContents(
            inline="""[connection]
id=tmfifo_net0
type=ethernet
interface-name=tmfifo_net0
autoconnect=true

[ethernet]

[ipv4]
method=manual
address1=192.168.100.2/24
never-default=true

[ipv6]
method=ignore
""")
    ),
    FileEntry(
        path="/etc/sysctl.d/98-dpunet.conf",
        overwrite=True,
        mode=644,
        contents=FileContents(
            inline="""
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
"""
        )
    ),
    FileEntry(
        path="/usr/local/bin/dpf-configure-sfs.sh",
        overwrite=True,
        mode=644,
        contents=FileContents(
            inline="""#!/bin/bash
set -ex
CMD=$1
PF_TOTAL_SF=$2

case $CMD in
    setup) ;;
    *)
    echo "invalid first argument. ./configure-sfs.sh {setup}"
    exit 1
    ;;
esac

if [ "$CMD" = "setup" ]; then
    # Create SF on P0 for SFC
    # System SF(index 0) has been removed, so DPF will create SF from index 0
    for i in $(seq 0 $((PF_TOTAL_SF-1))); do
        /sbin/mlnx-sf --action create --device 0000:03:00.0 --sfnum ${i} || true
    done
fi
""")
    ),
    FileEntry(
        path="/usr/local/bin/set-nvconfig-params.sh",
        overwrite=True,
        mode=755,
        contents=FileContents(
            inline="""#!/bin/bash
set -e
for dev in /dev/mst/*; do
  echo "set NVConfig on dev ${dev}"
  mlxconfig -d ${dev} -y set $@
done
echo "Finished setting nvconfig parameters"
""")
    ),
    FileEntry(
        path="/etc/sysconfig/openvswitch",
        overwrite=True,
        mode=600,
        contents=FileContents(
            inline="""OVS_USER_ID=\"root:root\"""")
    ),
]

SYSTEMD_UNITS: list[SystemdUnit] = [
    SystemdUnit(
        name="bfup-workaround.service",
        enabled=True,
        contents="""[Unit]
Description=Run bfup script 3 times with 2 minutes interval
After=network.target

[Service]
ExecStart=/bin/bash -c 'for i in {1..3}; do /usr/bin/bfup; sleep 400; done'
Type=oneshot
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
"""
    ),
    SystemdUnit(
        name="firstboot-dpf-ovs.service",
        enabled=True,
        contents="""[Unit]
Description=DPF OVS setup for first boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dpf-ovs-script.sh
RemainAfterExit=true
ConditionFirstBoot=true

[Install]
WantedBy=multi-user.target
"""),
    SystemdUnit(
        name="bootstrap-dpf.service",
        enabled=True,
        contents="""[Unit]
Description=Create Scalable Functions on the DPU required for DPF
After=network.target
Before=kubelet.service

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/local/bin/dpf-configure-sfs.sh setup {{.SFNum}}

[Install]
WantedBy=multi-user.target"""
    ),
    SystemdUnit(
        name="set-nvconfig-params.service",
        enabled=True,
        contents="""[Unit]
Description=Set firmware properties
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/set-nvconfig-params.sh {{.NVConfigParams}}
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target"""
    )
]


def octal_to_decimal(num: int) -> int:
    """
    Converts an integer interpreted as octal to its decimal equivalent.

    Args:
      num (int): The integer representing an octal number.

    Returns:
      int: The decimal equivalent of the octal number.
    """
    return int(str(num), 8)


def execute_oc_command(namespace: str, command: list[str]) -> str:
    """
    Executes an oc command in the specified namespace.
    Args:
        namespace: The namespace to execute the command in
        command: The oc command to execute (without the -n parameter)
    Returns:
        str: The command output
    """
    try:
        return subprocess.check_output(
            ["oc", "-n", namespace] + command
        ).decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        print(f"Error executing oc command: {e}")
        raise


def get_ignition_token_secret(cluster_name: str, namespace: str) -> str:
    # Get token secrets
    ignition_token_secrets = execute_oc_command(
        namespace,
        ["get", "secret", "--no-headers", "-o", "custom-columns=NAME:.metadata.name"]
    )

    # Find token-doca secret
    secrets: list[str] = [line for line in ignition_token_secrets.splitlines() if f"token-{cluster_name}" in line]
    if not secrets:
        raise Exception("No token secrets found.")
    ignition_token_secret: str = secrets[0]

    # Get ignition token
    ignition_token = execute_oc_command(
        namespace,
        ["get", "secret", ignition_token_secret, "-o", "jsonpath={.data.token}"]
    )
    return ignition_token


def pull_ignition(cluster_name: str, hc_namespace: str) -> dict:
    """
    Pulls the ignition file from the cluster and saves it as hcp.ign.
    Args:
        cluster_name: The name of the cluster to pull ignition from
        hc_namespace: The namespace for hosted clusters
    Returns:
        dict: The ignition file content
    """
    print("Pulling ignition file from cluster...")
    namespace = f"{hc_namespace}-{cluster_name}"

    try:
        # Get ignition endpoint
        ignition_endpoint = execute_oc_command(
            hc_namespace,
            ["get", "hc", cluster_name, "-o", "jsonpath={.status.ignitionEndpoint}"]
        )
        ignition_token = get_ignition_token_secret(cluster_name, namespace)

        # Download ignition file
        conn = http.client.HTTPSConnection(ignition_endpoint, context=ssl._create_unverified_context())
        conn.request("GET", "/ignition", headers={"Authorization": f"Bearer {ignition_token}"})
        response = conn.getresponse()
        if response.status != 200:
            raise Exception(f"Failed to pull ignition file: {response.status} {response.reason}")
        data = response.read()
        print("Downloaded ignition file successfully.")
        # Return the response content as JSON
        return json.loads(data.decode('utf-8'))

    except Exception as e:
        print(f"Error pulling ignition file: {e}")
        raise


def preprocess_ignition_file(ign: dict) -> dict:
    """
    Preprocesses the ignition file to disable the machine-config-daemon-firstboot.service
    and enable the openvswitch.service.
    """

    for s in ign['systemd']['units']:
        if s['name'] == 'machine-config-daemon-firstboot.service':
            s['enabled'] = False
        if s['name'] == 'openvswitch.service':
            s['enabled'] = True

    return ign


def encode_ignition(ign: dict) -> str:
    """
    Encodes the ignition file to base64.
    Args:
        ign: The ignition file content
    Returns:
        str: The base64 encoded ignition file
    """
    # Encode the ignition file to base64
    gzipped_ign = gzip.compress(json.dumps(ign, separators=(',', ':')).encode('utf-8'))
    return base64.b64encode(gzipped_ign).decode()


def create_ignition_file(encoded_ign: str) -> dict:
    """
    Creates a new ignition file with the required structure.
    """

    ign = {
        "ignition": {
            "version": "3.4.0"
        },
        "storage": {
            "files": []
        },
        "systemd": {
            "units": []
        }
    }

    ign['ignition']['config'] = {
        "merge": [
            {
                "compression": "gzip",
                "source": f"data:;base64,{encoded_ign}"
            }
        ]
    }

    add_kernel_args(ign)
    add_files(ign)
    add_systemd_units(ign)

    return ign


def add_kernel_args(ign: dict) -> None:
    """
    Adds kernel arguments templating to the ignition file.
    """
    ign['kernelArguments'] = {
        'shouldExist': [
            "{{.KernelParameters}}"
        ]
    }


def add_files(ign: dict) -> None:
    """
    Adds files to the ignition file.
    """

    ign["ignition"]["version"] = "3.4.0"

    for file in FILES_PLAIN:
        ign['storage']['files'].append({
            'path': file.path,
            'overwrite': file.overwrite,
            'mode': octal_to_decimal(file.mode),
            'contents': {
                'source': file.contents.source
            }
        })

    for file in FILES:
        ign['storage']['files'].append({
            'path': file.path,
            'overwrite': file.overwrite,
            'mode': octal_to_decimal(file.mode),
            'contents': {
                'source': "data:text/plain;charset=utf-8;base64," + base64.b64encode(
                    file.contents.inline.encode()).decode()
            }
        })


def add_systemd_units(ign: dict) -> None:
    """
    Adds systemd units to the ignition file.
    """

    for unit in SYSTEMD_UNITS:
        ign['systemd']['units'].append({
            'name': unit.name,
            'enabled': unit.enabled,
            'contents': unit.contents
        })


def create_bfb_template_cm(ign: dict, configmap_path: str) -> None:
    """Write ConfigMap to disk."""
    # Create ignition template
    ignition_template = json.dumps(ign, separators=(',', ':'))

    # Create ConfigMap
    yaml = """apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-bfb.cfg
  namespace: dpf-operator-system
data:
    BF_CFG_TEMPLATE: |
        """ + ignition_template

    with open(configmap_path, "w") as f:
        f.write(yaml)
    print(f"ConfigMap written to: {configmap_path}")


def main():
    parser = argparse.ArgumentParser(description='Generate OpenShift/DPF ignition template')
    parser.add_argument('--cluster', '-c', type=str, default='doca',
                        help='Name of the cluster to pull ignition from')
    parser.add_argument('--hosted-clusters-namespace', '-hc', type=str, default='clusters',
                        help='Namespace for hosted clusters (default: clusters)')
    parser.add_argument('--output-file', '-f', type=str, default='hcp_template.yaml',)
    args = parser.parse_args()

    # Check KUBECONFIG environment variable
    kubeconfig = os.environ.get('KUBECONFIG')
    if not kubeconfig:
        print("KUBECONFIG environment variable is not set.")
        return
    print(f"KUBECONFIG: {kubeconfig}")

    inner_ign = pull_ignition(args.cluster, args.hosted_clusters_namespace)
    inner_ign = preprocess_ignition_file(inner_ign)
    encoded_ign = encode_ignition(inner_ign)
    ign = create_ignition_file(encoded_ign)

    create_bfb_template_cm(ign, args.output_file)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"An error occurred: {e}")
        exit(1)
