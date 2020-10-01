#!/bin/bash
printErr() {
    echo -e "\033[31mError: $1\033[0m" 1>&2
}

showInvalidOption() {
    printErr "Invalid parameter '$1'"
    exit 1
}

checkExitCode() {
    if [ $? -ne 0 ]; then
        [ -n "$1" ] && printErr "$1"
        exit 1
    fi
}

# Default values
privateNi=ens7
isPublicFacing=0

# Parse the command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --privateNi|-n) privateNi=$2; shift ;;
        --privateIp|-i) privateIp=$2; shift ;;
        --publicFacing|-p) isPublicFacing=1 ;;
        *) showInvalidOption "$1" ;;
    esac
    shift
done

if [ -z "$privateIp" ]; then
    printErr "Specify an ip address for the private network"
    exit 1
fi

# Install the docker runtime
echo "Installing 'containerd'..."
yum install -q -y https://download.docker.com/linux/centos/8/x86_64/stable/Packages/containerd.io-1.3.7-3.1.el8.x86_64.rpm
checkExitCode "Failed to install containerd"

# Configure the ssh
echo "Updating ssh configuration..."
cat <<EOF >> /etc/ssh/sshd_config
PasswordAuthentication no
EOF

checkExitCode "Failed to update ssh configuration"

# https://www.vultr.com/docs/how-to-configure-a-private-network-on-centos
echo "Configuring the private network interface..."
cat <<EOF > "/etc/sysconfig/network-scripts/ifcfg-$privateNi"
TYPE="Ethernet"
DEVICE="$privateNi"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR=$privateIp
PREFIX=16
MTU=1450
EOF

checkExitCode "Failed to configure the private network interface"

# Assign the private nic (ens7) to the internal firewall zone
firewall-cmd --zone=internal --change-interface="$privateNi" --permanent

# Configure the firewall
firewall-cmd --zone=public --permanent --add-masquerade             # Allows source NAT
firewall-cmd --zone=internal --permanent --add-service=docker-swarm # Allows Docker swarm communication
firewall-cmd --zone=public --permanent --add-port=2376/tcp          # Allows client to remote daemon coms over tls

# Configure the firewall or public facing nodes (Only for public facing nodes)
if [ $isPublicFacing -eq 1 ]; then
    firewall-cmd --zone=public --permanent --add-service=http
    firewall-cmd --zone=public --permanent --add-service=https
fi

firewall-cmd --reload