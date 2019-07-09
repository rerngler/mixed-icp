# 1. scripts to make dir and load the icp 3.1.2 ppc64le binary into docker
mkdir -p /opt/icp3.1.2/images
cd /opt/icp3.1.2/images
# 2. Copy all binaries for 3 platforms into the images subdirectory. Following shows the
# binaries for the different platform under the images subdirectory.
#$ ls -l
#-rw-r--r-- 1 root root 14273357266 Jun 19 19:33 ibm-cloud-private-ppc64le-3.1.2.tar.gz
#-rw-r--r-- 1 root root 11824077488 Jul  2 18:45 ibm-cloud-private-s390x-3.1.2.tar.gz
#-rw-r--r-- 1 root root 13347036806 Jul  3 18:40 ibm-cloud-private-x86_64-3.1.2.tar.gz
#-rwxr-xr-x 1 root root   113250832 Jun 19 19:28 icp-docker-18.03.1_ppc64le.bin
#-rwxr-xr-x 1 root root   122029652 Jul  2 18:46 icp-docker-18.03.1_s390x.bin
#-rwxr-xr-x 1 root root   148057785 Jul  3 18:41 icp-docker-18.03.1_x86_64.bin

# load the ppc64le binary into the docker. Output available in nohup.out
nohup $SHELL <<EOF &
tar xf ibm-cloud-private-ppc64le-3.1.2.tar.gz -O | sudo docker load
EOF

cd /opt/icp3.1.2
# 3. Extract the config.yaml and hosts file
# Modify the config.yaml and hosts to configure icp and specify workers nodes
docker run -v $(pwd):/data -e LICENSE=accept ibmcom/icp-inception-ppc64le:3.1.2-ee cp -r cluster /data

# generates id_rsa and create the ssh_key file required for installation
ssh-keygen -b 4096 -f ~/.ssh/id_rsa -N ""
sudo cp ~/.ssh/id_rsa ./cluster/ssh_key

# distribute the id_rsa to all the worker nodes
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<worker node x>

# Change to the cluster subdirectory and run the pre-install check before actual installation
cd cluster
docker run --net=host -t -e LICENSE=accept -v "$(pwd)":/installer/cluster ibmcom/icp-inception-ppc64le:3.1.2-ee check

# Install ICP via nohup as the process can be long
nohup docker run --net=host -t -e LICENSE=accept -v "$(pwd)":/installer/cluster ibmcom/icp-inception-ppc64le:3.1.2-ee install &
