variable "ssh_key_name" {default = "YOUR_KEY_NAME_HERE"}
variable "aws_region_name" { default = "eu-west-1" }

provider "aws" {
  # Use keys in home dir.
  #  access_key = "ACCESS_KEY_HERE"
  #  secret_key = "SECRET_KEY_HERE"
  region = "${var.aws_region_name}"
}

data "external" "myipaddr" {
  # Pick one or the other. The second one requires an external script but uses DNS instead of https.
  #program = ["bash", "-c", "curl -s 'https://api.ipify.org?format=json'"]
  program = ["bash", "${path.module}/myipaddr.sh"]
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Request a spot instance at $0.01
# Master Node
resource "aws_spot_instance_request" "k8s-master" {
  wait_for_fulfillment = true
  #count         = "1"
  ami           = "${data.aws_ami.ubuntu.id}"
  spot_price    = "0.01"
  instance_type = "m3.medium"
  spot_type     = "one-time"

  vpc_security_group_ids = ["${aws_security_group.k8s_sg.id}"]

  key_name = "${var.ssh_key_name}"

  # not working
  tags = {
    Name   = "k8s-master"
    App    = "k8s"
    k8srole = "master"
  }
}

# workaround to set tags on spot instances (instance tas not supported by spot instance request api)
resource "aws_ec2_tag" "k8s-master-name" {
  resource_id = aws_spot_instance_request.k8s-master.spot_instance_id
  key         = "Name"
  value       = "k8s-master"
}
resource "aws_ec2_tag" "k8s-master-app" {
  resource_id = aws_spot_instance_request.k8s-master.spot_instance_id
  key         = "App"
  value       = "k8s"
}
resource "aws_ec2_tag" "k8s-master-k8srole" {
  resource_id = aws_spot_instance_request.k8s-master.spot_instance_id
  key         = "k8srole"
  value       = "master"
}

# Worker Nodes
resource "aws_spot_instance_request" "k8s-worker" {
  wait_for_fulfillment = true
  count         = "2"
  ami           = "${data.aws_ami.ubuntu.id}"
  spot_price    = "0.01"
  instance_type = "m3.medium"
  spot_type     = "one-time"

  vpc_security_group_ids = ["${aws_security_group.k8s_sg.id}"]

  key_name = "${var.ssh_key_name}"

  # not working
  tags = {
    Name   = "k8s-worker"
    App    = "k8s"
    k8srole = "worker"
  }
}

# workaround to set tags on spot instances (instance tags not supported by spot instance request api)
resource "aws_ec2_tag" "k8s-worker-name" {
  count       = length(aws_spot_instance_request.k8s-worker)
  resource_id = aws_spot_instance_request.k8s-worker[count.index].spot_instance_id
  key         = "Name"
  value       = "k8s-worker"
}
resource "aws_ec2_tag" "k8s-worker-app" {
  count       = length(aws_spot_instance_request.k8s-worker)
  resource_id = aws_spot_instance_request.k8s-worker[count.index].spot_instance_id
  key         = "App"
  value       = "k8s"
}
resource "aws_ec2_tag" "k8s-worker-k8srole" {
  count       = length(aws_spot_instance_request.k8s-worker)
  resource_id = aws_spot_instance_request.k8s-worker[count.index].spot_instance_id
  key         = "k8srole"
  value       = "worker"
}

resource "aws_security_group" "k8s_sg" {

}

resource "aws_security_group_rule" "allow_all_egress" {
  type            = "egress"
  from_port       = 0
  to_port         = 0
  protocol        = "all"
  cidr_blocks     = ["0.0.0.0/0"]
  description     = "Outbound access to ANY"

  security_group_id = "${aws_security_group.k8s_sg.id}"
}


resource "aws_security_group_rule" "allow_all_myip" {
  type            = "ingress"
  from_port       = 0
  to_port         = 0
  protocol        = "all"
  cidr_blocks     = ["${data.external.myipaddr.result["ip"]}/32"]
  description     = "Management Ports for K8s Cluster"

  security_group_id = "${aws_security_group.k8s_sg.id}"
}

resource "aws_security_group_rule" "allow_SG_any" {
  type            = "ingress"
  from_port       = 0
  to_port         = 0
  protocol        = "all"
  self            = true
  description     = "Any from SG for K8s Cluster"

  security_group_id = "${aws_security_group.k8s_sg.id}"
}

output "master_ip" {
  value = "${aws_spot_instance_request.k8s-master.public_ip}"
}
output "worker_ips" {
  value = "${aws_spot_instance_request.k8s-worker.*.public_ip}"
}