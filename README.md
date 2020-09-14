# fb-web-deploy
Tools and configuration for deploying the [framebastard](https://github.com/rcashie/fb-web) website.

## Building and deploying locally

### Install Docker
1. Install [Docker](https://docs.docker.com/install/).

2. Initialize your local Docker instance as a swarm manager:
    ```sh
    docker swarm init
    ```

3. Tag your local machine as a host for both [couchbase](./containers/stack-couchbase.yml) and [app](./containers/stack-app.yml) stacks:
    ```sh
    docker node update --label-add couchbase=true --label-add generic=true "$(docker node ls -q)"
    ```

### Building

1. From the [containers](./containers) directory run the [build](./containers/build.sh) bash script. See the script source for default arguments you can override:
    ```sh
    ./build.sh
    ```

### Deploying

1. Create a file named `local.config.json` using the [local.config.json.template](./containers/fb-web/local.config.json.template) template file in the [containers/fb-web](./containers/fb-web) directory. Fill out the property values.

2. Generate a self signed SSL certificate and place it in the [haproxy](./containers/haproxy) directory as `ssl-cert.pem`.

3. From the [containers](./containers) directory run the [deploy](./containers/deploy.sh) bash script. See the source script for default arguments you can override. You must specify at least one stack to deploy:
    ```sh
    ./deploy.sh [--app] [--couchbase]
    ```

4. For a **new couchbase stack** deployment use the [setup_docker.sh](https://github.com/rcashie/fb-web/blob/master/couchbase/setup_docker.sh) bash script from the main fb-web repo:
    ```sh
    ./setup_docker.sh --container <container id/name> --user <username> --password <password>
    ```

## Building and deploying to production

The production environment consists of a set of virtual machines in [Vultr](https://www.vultr.com/) running the Docker engine. We use `docker-machine` to deploy containers to them.

### Configure docker-machine
1. Install [docker-machine](https://docs.docker.com/machine/install-machine/)

2. Make sure all virtual machines are registered with `docker-machine`. For each virtual machine run the [create command](https://docs.docker.com/machine/drivers/generic):
    ```sh
   docker-machine create --driver generic --generic-ip-address=<virtual machine ip address> --generic-ssh-key <ssh key> <machine-alias>
    ```

### Building and deploying
1. Create a file named `prod.config.json` using the [local.config.json.template](./containers/fb-web/local.config.json.template) template file in the [containers/fb-web](./containers/fb-web) directory. Fill out the property values.

2. Place the Cloudflare SSL certificate in the [haproxy](./containers/haproxy) directory as `ssl-cert.pem`.

3. Edit the [deploy-to-prod.sh](./containers/deploy-to-prod.sh) bash script and update the target variable to the latest release tag of the [fb-web](https://github.com/rcashie/fb-web) project in Github. Make sure to check in this change after deploying.

4. From the [containers](./containers) directory run the [deploy-to-prod](./containers/deploy-to-prod.sh) bash script.
    ```sh
    ./deploy-to-prod.sh [--app] [--couchbase]
    ```

## Deploying infrastructure in production
This repository uses Terraform to provision resources in Vultr. Make sure you have the [Terraform cli](https://learn.hashicorp.com/tutorials/terraform/install-cli) installed.

### Configuring a new Docker swarm node in Vultr

There are two types of Docker swarm nodes within a framebastard deployment: `generic` nodes for running non-couchbase containers and `couchbase` nodes for running Couchbase containers. Couchbase nodes typically have more memory and processing capacity. A node is `tagged` with the type it's identified as.

1. Place the shared `terraform.tfstate` file into the [infrastructure](./infrastructure) folder. If you are deploying to an entirely different environment a new file will be generated.

2. Edit the [main.tf](./infrastructure/main.tf) Terraform file and add a new `vultr_server` resource: Copy an existing `swarm_node_generic_x` or `swarm_node_couchbase_x` definition and update the `name`, `tag`, `label` and `host` parameters accordingly.

3. In the same [main.tf](./infrastructure/main.tf) Terraform file add a new `vultr_block_storage` resource: Copy an existing definition and update the `name` and `attached_id` parameters accordingly.

4. From the [infrastructure](./infrastructure) folder _"plan"_ the Terraform execution then _"apply"_ once validated:
    ```sh
    export VULTR_API_KEY=<API KEY>
    terraform plan

    # ^^^validate the Terraform execution plan output above before running the following:
    terraform apply
    ```

5. Register the new virtual machine with docker-machine:
    ```sh
    docker-machine create --driver generic --generic-ip-address=<virtual machine ip address> --generic-ssh-key <ssh key> <machine-alias>
    ```

6. `ssh` into the machine:
    ```sh
    docker-machine ssh <machine-alias>
    ```

7. Perform the following steps while on the machine (TODO: Make this into a script):
    ```sh
    # 1. Install containerd (required by Docker):
    yum install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm

    # 2. Open the ssh configuration file:
    sudo vi /etc/ssh/sshd_config

    # 3. ~~~Change the parameter PasswordAuthentication to no

    # 4. Restart the ssh service:
    sudo service sshd restart

    # 5. Follow the instructions here to setup the private network:
    # https://www.vultr.com/docs/how-to-configure-a-private-network-on-centos/

    # 6. Assign the private nic (ens7) to the internal firewall zone:
    firewall-cmd --zone=internal --change-interface=ens7 --permanent

    # 7. Configure the firewall:
    firewall-cmd --zone=public --permanent --add-masquerade             # Allows source NAT
    firewall-cmd --zone=internal --permanent --add-service=docker-swarm # Allows Docker swarm communication
    firewall-cmd --zone=public --permanent --add-port=2376/tcp          # Allows client to remote daemon coms over tls
    firewall-cmd --reload

    # 8. (Only for public facing nodes) Configure the firewall or public facing nodes:
    firewall-cmd --zone=public --permanent --add-service=http
    firewall-cmd --zone=public --permanent --add-service=https
    firewall-cmd --reload

    # 9. Follow the instructions to mount the block storage:
    # https://www.vultr.com/docs/block-storage
    ```

8. Install Docker on the new virtual machine:
    ```sh
    docker-machine provision <machine-alias>
    ```

9. Add the machine as a node to the swarm:
    ```sh
    # 1. Switch context to the manager node
    eval $(docker-machine env swarm-node-generic-a)

    # 2. Get the command to run
    docker swarm join-token worker

    # 3. Switch context to the new virtual machine
    eval $(docker-machine env <machine-alias>)

    # 4. Execute the command retrieved from step 2
    ```

10. Tag the new node as `generic` or `couchbase` using the manager node:
    ```sh
    eval $(docker-machine env swarm-node-generic-a)
    docker node update --label-add generic|couchbase=true <machine-alias>
    ```
