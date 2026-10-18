# SERVER1: MASTER-SERVER (Jenkins, Maven, Docker, Ansible, Trivy)
# Keep provider configuration in provider.tf.

resource "aws_security_group" "my_security_group1" {
  name        = "my-security-group1"
  description = "Allow SSH, HTTP, HTTPS, Jenkins and Maven"

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
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Maven repository/service if required"
    from_port   = 8081
    to_port     = 8081
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

resource "aws_instance" "my_ec2_instance1" {
  ami                    = "ami-0ed59cbb87dfa8dba"
  instance_type          = "t2.medium"
  vpc_security_group_ids = [aws_security_group.my_security_group1.id]
  key_name               = "My_Key" # EC2 key-pair name, without .pem

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "MASTER-SERVER"
  }

  # Install tools on Amazon Linux 2023. Terraform must be able to SSH using My_Key.pem.
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/My_Key.pem")
      host        = self.public_ip
      timeout     = "10m"
    }

    inline = [
      "set -e",
      "sudo dnf update -y",
      "sudo dnf install -y --allowerasing java-21-amazon-corretto-devel fontconfig git maven docker python3 python3-pip python3-devel ansible-core tar gzip curl wget",
      "sudo curl -fsSL https://pkg.jenkins.io/rpm-stable/jenkins.repo -o /etc/yum.repos.d/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key",
      "sudo dnf install -y jenkins",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now docker",
      "sudo systemctl enable --now jenkins",
      "sudo usermod -aG docker jenkins",
      "sudo systemctl restart jenkins",
      # Install Trivy from the official release install script; avoids the broken RPM repository metadata URL.
      "curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin v0.75.0",
      "sudo systemctl is-active --quiet jenkins",
      "sudo systemctl is-active --quiet docker",
      "java -version",
      "mvn -version",
      "docker --version",
      "ansible --version",
      "trivy --version"
    ]
  }
}

output "ACCESS_YOUR_JENKINS_HERE" {
  value = "http://${aws_instance.my_ec2_instance1.public_ip}:8080"
}

output "Jenkins_Initial_Password_Command" {
  value = "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
}

output "MASTER_SERVER_PUBLIC_IP" {
  value = aws_instance.my_ec2_instance1.public_ip
}

output "MASTER_SERVER_PRIVATE_IP" {
  value = aws_instance.my_ec2_instance1.private_ip
}
