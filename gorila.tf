provider "aws" {
    region = "us-east-1"
    access_key = ""
    secret_key = ""
}

data "aws_vpc" "gorilla_vpc" {
    id =  "vpc-a853d0d2"   
}

data "aws_eip" "lb" {
    id = "eipalloc-058783d1543b36ca8"
} 

data "aws_route_table" "gorilla_rt" {

    route_table_id = "rtb-36c5cb49"
  
}

resource "aws_subnet" "public_subnet" {
  vpc_id     = data.aws_vpc.gorilla_vpc.id
  cidr_block = "172.31.1.0/24"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "public subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = data.aws_vpc.gorilla_vpc.id
  cidr_block = "172.31.2.0/24"
  map_public_ip_on_launch = "true"
  tags = {
    Name = "private subnet"
  }
}

resource "aws_security_group" "ec2sg" {
  name        = "application sg"
  description = "Allow ssh inbound traffic"
  vpc_id      = data.aws_vpc.gorilla_vpc.id

  ingress {
    description = "ssh from outside"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "http from outside"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "http from outside"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Application sg"
  }
}

resource "aws_security_group" "elbsg" {
  name        = "elb sg"
  description = "Allow http inbound traffic"
  vpc_id      = data.aws_vpc.gorilla_vpc.id

  ingress {
    description = "http from outside"
    from_port   = 0
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ELB sg"
  }
}

resource "aws_instance" "jenkins" {
  ami           = "ami-08511356d13eb00b9"
  instance_type = "t2.micro"
  key_name = "gorilla"
  subnet_id = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.ec2sg.id]
  tags = {
    "Name" = "jenkins"
  }
  provisioner "remote-exec" {
    connection {
      # The default username for our AMI
      user = "ec2-user"
      host = "${self.public_ip}"
      type     = "ssh"
      private_key = "${file("/Users/a110755/aws-pem/gorilla.pem")}"
      }
    inline = [
      "sudo yum update -y",
      "sudo yum install git -y",
    ]
  }
}

resource "aws_instance" "application" {
  ami           = "ami-04d29b6f966df1537"
  instance_type = "t2.micro"
  key_name = "gorilla"
  subnet_id = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.ec2sg.id]
  user_data = "value"

  tags = {
    "Name" = "application"
  }

  provisioner "remote-exec" {
    connection {
      # The default username for our AMI
      user = "ec2-user"
      host = "${self.public_ip}"
      type     = "ssh"
      private_key = "${file("/Users/a110755/aws-pem/gorilla.pem")}"
      }
    inline = [
      "sudo yum update -y",
      "sudo yum install git -y",
      "curl -sL https://rpm.nodesource.com/setup_8.x | sudo bash -",
      "sudo yum install nodejs -y",
      "sudo npm install pm2 -g",
      "npm install --save sqlite3",
    ]
  } 
}

resource "aws_elb" "jenkins_elb" {
  name               = "jenkins-elb"
  subnets = [ aws_subnet.private_subnet.id]


  listener {
    instance_port     = 8080
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8080/login?from=%2F"
    interval            = 30
  }

  instances                   = [aws_instance.jenkins.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "jenkins-elb"
  }
  
  security_groups = [aws_security_group.elbsg.id]

}


resource "aws_elb" "application_elb" {
  name    = "application-elb"
  subnets = [ aws_subnet.private_subnet.id]

  listener {
    instance_port     = 3000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:3000/login/"
    interval            = 30
  }

  instances                   = [aws_instance.application.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "application-elb"
  }

  security_groups = [aws_security_group.elbsg.id]
}




