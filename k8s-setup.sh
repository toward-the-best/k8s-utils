#!/bin/bash
 
#DOCS
#1. 방화벽 설정 가이드
#  https://kubernetes.io/docs/setup/production-environment/container-runtimes/
#
#2. containerd 설치 가이드
#  https://github.com/containerd/containerd/blob/main/docs/getting-started.md#installing-containerd
#
#3. CNI(Container Network Interface)
#  k8s 1.25 부터추가
# 
 
#########################
#k8s 버전
#########################a
#k8s_ver=1.22.9-00
#k8s_ver=1.23.13-00
#k8s_ver=1.24.7-00
k8s_ver=1.25.3-00
#k8s_ver=1.23.13-00

#########################
# Containerd 버전
#########################
containerd_ver=1.6.8
runc_ver=1.1.4

################
# CNI 버전
################
calico_ver=3.24.4
cilium_ver=1.12.3
 
 #########################################
#
# global 설정 
#
#########################################
setup_docker_iptables_bridge() {
    #1. 방화벽 해제
    ufw disable
    #1. iptables bridge 설정
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
    sudo modprobe br_netfilter
 
# 필요한 sysctl 파라미터를 설정하면, 재부팅 후에도 값이 유지된다.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
# 재부팅하지 않고 sysctl 파라미터 적용하기
    sudo sysctl --system
}

setup_containerd_iptables_bridge() {
    #1. 방화벽 해제
    ufw disable
    #1. iptables bridge 설정
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter
 
# 필요한 sysctl 파라미터를 설정하면, 재부팅 후에도 값이 유지된다.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
# 재부팅하지 않고 sysctl 파라미터 적용하기
    sudo sysctl --system
}

 
#########################################
#
# cir-o 관련 함수
#
#########################################
check_os_setting()
{
    if test -z $OS;then
        echo "settig OS environment https://github.com/cri-o/cri-o/blob/main/install.md#apt-based-operating-systems"
        exit
    fi
}

setup_cir-o_runtime()
{
    OS=xUbuntu_20.04
}

#########################################
#
# containerd 관련 함수
#
#########################################
dowload_cri() {
    wget --no-check-certificate https://github.com/containerd/containerd/releases/download/v${containerd_ver}/containerd-${containerd_ver}-linux-amd64.tar.gz
}

 
setup_containerd_runtime() {
    # containerd 설치
    tar Cxzvf /usr/local containerd-${containerd_ver}-linux-amd64.tar.gz
 
    # containerd systemd 등록
    wget --no-check-certificate https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    mv containerd.service /etc/systemd/system/
 
    mkdir -p /etc/containerd
    containerd config default>/etc/containerd/config.toml
#    line_num=`cat /etc/containerd/config.toml | grep -n systemd_cgroup | awk -F':' '{print $1}'`
#    sed -i "${line_num}s/.*/    systemd_cgroup = true/g" /etc/containerd/config.toml
 
    systemctl daemon-reload
    systemctl enable --now containerd
}
 
setup_runc() {
    #runc 설치
    wget --no-check-certificate https://github.com/opencontainers/runc/releases/download/v${runc_ver}/runc.amd64
    install -m 755 runc.amd64 /usr/local/sbin/runc
}


#########################################
#
# docker 관련 함수
#
#########################################
setting_docker_repo() {
#apt 업데이트
    sudo apt-get update	-y
	sudo apt-get install -y ca-certificates curl gnupg lsb-release
#docker GPG key 추가
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
#docker stable repo  설정
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
}

setting_docker_install() {
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io
sudo docker version
}

setting_docker() {
cat <<EOF | sudo tee /etc/docker/daemon.json
{
"exec-opts": ["native.cgroupdriver=systemd"],
"log-driver": "json-file",
"log-opts": {
"max-size": "100m"
},
"storage-driver": "overlay2"
}
EOF

sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker
}

 
 
setup_kubeadm() {
#설치
swapoff -a
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update -y
#sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-get install -y kubelet=${k8s_ver} kubeadm=${k8s_ver} kubectl=${k8s_ver}
sudo apt-mark hold kubelet kubeadm kubectl
}
 
#사용법 모름
setup_kubeadm_config() {
#cgroup 설저 파일 생성
cat <<EOF | sudo tee kubeadm-config.yaml
# kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta3
kubernetesVersion: v1.24.3
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
#calico를 사용하려면network 세팅은 필수
networking:
    podSubnet: 192.168.0.0/16
EOF
}
 
init_kubeadm() {
#    kubeadm init --config kubeadm-config.yaml
#    kubeadm init --pod-network-cidr=192.167.0.0/16
    kubeadm init --apiserver-advertise-address 192.168.0.26 --pod-network-cidr=192.167.0.0/16
 
    #The connection to the server localhost:8080 was refused - did you specify the right host or port? 를 해결
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
 
}

setup_cni_calico() {
curl https://raw.githubusercontent.com/projectcalico/calico/v${calico_ver}/manifests/calico.yaml -O
kubectl apply -f calico.yaml
}

uninstall_cni_calico() {
kubectl delete -f calico.yaml
}

setup_cni_cilium() {
snap install helm --classic
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version ${cilium_ver} --namespace kube-system
}

uninstall_cni_cilium() {
helm uninstall cilium -n kube-system
}

setup_cni_flannel() {
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
}

uninstall_cni_flannel() {
kubectl delete -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
}


setup_iptables_bridge() {
    if [ $1 == "docker" ];then
    	setup_docker_iptables_bridge
    elif [ $1 == "containerd" ];then
    	setup_containerd_iptables_bridge
	fi
}

setup_containerd() {
    dowload_cri
    setup_containerd_runtime
    setup_runc
}

setup_docker() {
    setting_docker_repo
    setting_docker_install
    setting_docker
}

setup_runtime() {
    echo "$1"
    if [ $1 == "docker" ];then
    	setup_docker
    elif [ $1 == "containerd" ];then
		setup_containerd
   fi 
}

#################################################
#                                               #
#                    MAIN                       #
#                                               #         
#################################################
if [ $# -lt 1 ];then
	echo "./$0 command run_time node_type cni"
	echo ""
	echo "Ex) "
	echo "    $0 install containerd master cilium"
	echo "    $0 install containerd worker"
	echo "    $0 install docker master cilium"
	echo "    $0 install docker worker"
	echo ""
	echo "Command Option"
    echo ""
    echo "Command :"
    echo "     install"
	echo "     uninstall"
	echo ""
	echo "run_time :"
	echo "     docker"
	echo "     containerd"
	echo ""
	echo "node_type :" 
	echo "     master : kubeadm 초기화 및 cni 설치"
	echo "     worker : kubeadm 만 설치"
	echo ""
	echo "cni :" 
	echo "     calico"
	echo "     cilium"

fi

if [ $# -ge 2 ];then
    case $1 in
        install)
            run_time=
            if [ $2 == "docker" ];then
                run_time="docker"
            elif [ $2 == "containerd" ];then
                run_time="containerd"
            fi 
            #########################
            # iptable 설정 
            #########################
            setup_iptables_bridge $run_time

            #########################
            # container runtime 설치
            #########################
            setup_runtime $run_time
    
            ########################
            #k8s 설치
            ########################
            setup_kubeadm

            if [ $# -ge 4 ] && [ $3 == "master" ];then
                #setup_kubeadm_config
                init_kubeadm
                #######################
                # CNI (container  설치
                #######################
                if [ $4 == "calico" ];then
                    setup_cni_calico
                elif [ $4 == "cilium" ];then
                    setup_cni_cilium
                fi
            fi
            ;;
        uninstall)
            ;;
        *)
            ;;
    esac
fi 

