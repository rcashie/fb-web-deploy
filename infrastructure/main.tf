provider "vultr" {
    # Set the environment variable VULTR_API_KEY
    rate_limit = 1000
}

data "vultr_region" "target" {
    filter {
        name = "name"
        values = ["New Jersey"]
    }
}

data "vultr_os" "target" {
    filter {
        name = "name"
        values = ["CentOS 8 x64"]
    }
}

data "vultr_plan" "swarm_node" {
    filter {
        name = "vcpu_count"
        values = [2]
    }

    filter {
        name = "ram"
        values = [4096]
    }

    filter {
        name = "disk"
        values = [80]
    }
}

data "vultr_ssh_key" "deploy" {
    filter {
        name = "name"
        values = ["deploy"]
    }
}

# Private network
resource "vultr_network" "swarm_nodes" {
    description = "Docker swarm private network"
    region_id = data.vultr_region.target.id
    cidr_block  = "111.0.0.0/24"
}

# Firewall groups
resource "vultr_firewall_group" "swarm_nodes" {
    description = "Docker nodes"
}

# Firewall rules
resource "vultr_firewall_rule" "ssh" {
    firewall_group_id = vultr_firewall_group.swarm_nodes.id
    protocol = "tcp"
    network = "0.0.0.0/0"
    from_port = "22"
}

resource "vultr_firewall_rule" "docker_tls" {
    firewall_group_id = vultr_firewall_group.swarm_nodes.id
    protocol = "tcp"
    network = "0.0.0.0/0"
    from_port = "2376"
}

resource "vultr_firewall_rule" "https" {
    firewall_group_id = vultr_firewall_group.swarm_nodes.id
    protocol = "tcp"
    network = "0.0.0.0/0"
    from_port = "443"
}

resource "vultr_firewall_rule" "http" {
    firewall_group_id = vultr_firewall_group.swarm_nodes.id
    protocol = "tcp"
    network = "0.0.0.0/0"
    from_port = "80"
}

# Servers
resource "vultr_server" "swarm_node_a" {
    plan_id = data.vultr_plan.swarm_node.id
    region_id = data.vultr_region.target.id
    os_id = data.vultr_os.target.id
    tag = "swarm manager"
    label = "swam-node-a"
    hostname = "swarm-node-a"
    enable_private_network = true
    network_ids = [vultr_network.swarm_nodes.id]
    firewall_group_id = vultr_firewall_group.swarm_nodes.id
    ssh_key_ids = [data.vultr_ssh_key.deploy.id]
}

# Block storage
resource "vultr_block_storage" "swarm_node_a" {
    size_gb = 10
    region_id = data.vultr_region.target.id
    attached_id = vultr_server.swarm_node_a.id
}

# Output variables
output "swarm_node_a" {
  value = vultr_server.swarm_node_a.main_ip
}
