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

2. Generate a self signed SSL certificate and place it in the [haproxy](./containers/haproxy) directory as `ssl-cert.pem`. From the container directory run:
    ```sh
    openssl req -nodes -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365
    cat key.pem cert.pem  >> ./haproxy/ssl-cert.pem
    ```

3. From the [containers](./containers) directory run the [deploy](./containers/deploy.sh) bash script. See the source script for default arguments you can override. You must specify at least one stack to deploy. To deploy the `app` stack the `couchbase` stack must already be running and configured (see step 4):
    ```sh
    ./deploy.sh [--app] [--couchbase]
    ```

4. To configure a new or update an existing couchbase container use the [setup_docker.sh](https://github.com/rcashie/fb-web/blob/master/couchbase/setup_docker.sh) bash script from the main fb-web repo:
    ```sh
    ./setup_docker.sh --container <container id/name> --user <username> --password <password> --create-fts-indices --create-bkt-indices
    ```

## Building and deploying to production

The production environment consists of one or more virtual machines in [Vultr](https://www.vultr.com/) that make up a Docker swarm cluster. We use `docker-machine` to deploy containers to them. Both Swarm and docker-machine are not actively being worked on but are still used here. Other orchestration solutions are overkill for this project.

**Always test deployments [locally](#building-and-deploying-locally) first before deploying to production**.

### Configure docker-machine
1. Install [docker-machine](https://docs.docker.com/machine/install-machine/)

2. Make sure all virtual machines are registered with `docker-machine`. For each virtual machine run the [create command](https://docs.docker.com/machine/drivers/generic):
    ```sh
   docker-machine create --driver generic --generic-ip-address=<virtual machine ip address> --generic-ssh-key <ssh key> <machine-alias>
    ```

### Building and deploying
1. Create a file named `prod.config.json` using the [local.config.json.template](./containers/fb-web/local.config.json.template) template file in the [containers/fb-web](./containers/fb-web) directory. Fill out the property values.

2. Place the Cloudflare SSL certificate in the [haproxy](./containers/haproxy) directory as `ssl-cert.pem`.

3. Update the [PROD](./containers/PROD) file with the [git tag](https://github.com/rcashie/fb-web/tags) you would like to build and deploy. Make sure to check in this change after deploying.

4. From the [containers](./containers) directory run the [deploy-to-prod](./containers/deploy-to-prod.sh) bash script. You must specify at least one stack to deploy. To deploy the `app` stack the `couchbase` stack must already be running and configured (see step 5):
    ```sh
    ./deploy-to-prod.sh [--app] [--couchbase]
    ```

5. To configure a new or update an existing couchbase instance use the [setup_docker.sh](https://github.com/rcashie/fb-web/blob/master/couchbase/setup_docker.sh) bash script from the main fb-web repo:
    ```sh
    eval $(docker-machine env swarm-node-couchbase-x)
    ./setup_docker.sh --container <container id/name> --user <username> --password <password> --create-fts-indices --create-bkt-indices
    ```

## Deploying infrastructure in production
This repository uses Terraform to provision resources in Vultr. Make sure you have the [Terraform cli](https://learn.hashicorp.com/tutorials/terraform/install-cli) installed.

### Configuring a new Docker swarm node in Vultr

1. Place the shared `terraform.tfstate` file into the [infrastructure](./infrastructure) folder. If you are deploying to an entirely different environment a new file will be generated.

2. Edit the [main.tf](./infrastructure/main.tf) Terraform file and add a new `vultr_server` resource: Copy an existing `swarm_node_x` definition and update the `name`, `tag`, `label` and `host` parameters accordingly.

3. In the same [main.tf](./infrastructure/main.tf) Terraform file add a new `vultr_block_storage` resource: Copy an existing definition and update the `name` and `attached_id` parameters accordingly.

4. From the [infrastructure](./infrastructure) folder _"plan"_ the Terraform execution then _"apply"_ once validated:
    ```sh
    export VULTR_API_KEY=<API KEY>
    terraform plan

    # ^^^validate the Terraform execution plan output above before running the following:
    terraform apply
    ```

5. From the [infrastructure](./infrastructure) folder execute the following:
    ```sh
    # 1. Copy the 'setup_node' bash script onto the virtual machine
    scp -i <ssh key> ./setup_node.sh root@<VM IP address>:/setup_node.sh

    # 2. Log into the virtual machine
    ssh -i <ssh key> root@<VM IP Address>

    # 3. Execute the script
    /setup_node.sh --privateIp <Private IP address> [--privateNi <private network interface>] [--publicFacing]

    # 4. Follow the instructions to mount the block storage:
    # https://www.vultr.com/docs/block-storage

    # 5. Reboot
    reboot
    ```

6. Register the new virtual machine with docker-machine:
    ```sh
    docker-machine create --driver generic --generic-ip-address=<VM IP address> --generic-ssh-key <ssh key> <machine alias>
    ```

7. Add the machine as a node to the swarm:
    ```sh
    # 1. Switch context to the manager node
    eval $(docker-machine env swarm-node-a)

    # 2. Get the command to run
    docker swarm join-token worker

    # 3. Switch context to the new virtual machine
    eval $(docker-machine env <machine alias>)

    # 4. Execute the command retrieved in step 2
    ```

8. Tag the new node as `generic` or `couchbase` using the manager node:
    ```sh
    eval $(docker-machine env swarm-node-a)
    docker node update --label-add generic|couchbase=true <machine alias>
    ```
