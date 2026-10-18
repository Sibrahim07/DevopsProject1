# SERVER2: NODE-SERVER (Kubernetes control-plane using containerd + Flannel)
# This is a single-node control-plane bootstrap. It does not join a separate worker.
# Keep provider configuration in provider.tf.

resource "aws_security_group" "my_security_group2" {
  name        = "my-security-group4"
  description = "Allow SSH, Kubernetes API and NodePort traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubelet API (restrict to trusted IPs for production)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "my_ec2_instance2" {
  ami                    = "ami-0ed59cbb87dfa8dba"
  instance_type          = "t2.medium"
  vpc_security_group_ids = [aws_security_group.my_security_group2.id]
  key_name               = "My_Key"

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "NODE-SERVER"
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/My_Key.pem")
      host        = self.public_ip
      timeout     = "20m"
    }

    inline = [
      "set -e",
      "sudo dnf update -y",
      "sudo dnf install -y --allowerasing containerd curl iproute-tc socat conntrack-tools",
      "sudo swapoff -a",
      "sudo sed -ri '/\\sswap\\s/s/^/#/' /etc/fstab",
      "sudo modprobe overlay",
      "sudo modprobe br_netfilter",
      "sudo tee /etc/modules-load.d/k8s.conf >/dev/null <<'EOF'\noverlay\nbr_netfilter\nEOF",
      "sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null <<'EOF'\nnet.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\nEOF",
      "sudo sysctl --system",
      "sudo mkdir -p /etc/containerd",
      "sudo sh -c 'containerd config default > /etc/containerd/config.toml'",
      "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml",
      "sudo systemctl enable --now containerd",
      "sudo systemctl restart containerd",
      "sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<'EOF'\n[kubernetes]\nname=Kubernetes\nbaseurl=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/\nenabled=1\ngpgcheck=1\ngpgkey=https://pkgs.k8s.io/core:/stable:/v1.37/rpm/repodata/repomd.xml.key\nexclude=kubelet kubeadm kubectl cri-tools kubernetes-cni\nEOF",
      "sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes",
      "sudo dnf install -y kubernetes-cni cri-tools --disableexcludes=kubernetes",
      "sudo systemctl enable --now kubelet",
      "sudo kubeadm init --apiserver-advertise-address=$(hostname -I | awk '{print $1}') --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock",
      "mkdir -p $HOME/.kube",
      "sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
      "for i in $(seq 1 60); do kubectl --request-timeout=5s get --raw=/readyz >/dev/null 2>&1 && break; echo 'Waiting for Kubernetes API readiness...'; sleep 5; done; kubectl --request-timeout=10s get --raw=/readyz",
      "kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml",
      "kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true",
      "kubectl wait --for=condition=Ready node --all --timeout=300s",
      "kubectl get nodes -o wide",
      "kubectl get pods -A",
      "sudo systemctl is-active --quiet containerd",
      "sudo systemctl is-active --quiet kubelet",
      "sudo ss -lntp | grep ':6443'"
    ]
  }
}

output "NODE_SERVER_PUBLIC_IP" {
  value = aws_instance.my_ec2_instance2.public_ip
}

output "NODE_SERVER_PRIVATE_IP" {
  value = aws_instance.my_ec2_instance2.private_ip
}
