/*

  SonarQube: the slightly unnecessary ECS version.

*/


provider "aws" {
  region = "${var.region}"
}


variable region {
  default = "eu-west-1"
}


variable "images" {
  type = "map"

  default = {
    us-east-1 = "ami-04351e12"
    eu-west-1 = "ami-809f84e6"
  }
}

variable "zones" {
  type = "map"

  default = {
    us-east-1 = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e"]
    eu-west-1 = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  }
}

resource "aws_security_group" "sonarqube_elb_sg" {

  name = "sonarqube-elb-sg"

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "sonarqube_db_sg" {

  name = "sonarqube-db-sg"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # FIXME figure out what the correct port is
    security_groups = ["${aws_security_group.sonarqube_ecs_instance_sg.id}"]
  }

}

resource "aws_security_group" "sonarqube_ecs_instance_sg" {

  name = "sonarqube-ecs-instance-sg"
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    security_groups = ["${aws_security_group.sonarqube_elb_sg.id}"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

}


resource "aws_db_instance" "sonarqube" {

  allocated_storage   = 64
  engine              = "mysql"
  storage_type        = "standard"
  instance_class      = "db.t1.micro"
  skip_final_snapshot = "true" # FIXME

  vpc_security_group_ids = ["${aws_security_group.sonarqube_db_sg.id}"]

  name     = "sonar"

  username = "sonarqube"
  password = "sonarqube"

  parameter_group_name = "sonarqube-db-params"
  depends_on = ["aws_db_parameter_group.sonarqube"] # not automatic

  tags {
    Name          = "sonarqube-db"
  }

}


resource "aws_db_parameter_group" "sonarqube" {

  name = "sonarqube-db-params"
  family = "mysql5.6"

  parameter {
    name  = "max_allowed_packet"
    value = 268435456
  }

  tags {
    Name          = "sonarqube-db-params"
  }

}

## ECS CLUSTER

resource "aws_ecs_cluster" "sonarqube" {

  name = "sonarqube-ecs-cluster"

  # can't have tags
}

resource "aws_launch_configuration" "sonarqube_ecs_nodes" {
  name_prefix   = "sonarqube-ecs-cluster-"
  image_id      = "${var.images[var.region]}"
  instance_type = "t2.micro"

  lifecycle {
    create_before_destroy = true
  }

  iam_instance_profile = "${aws_iam_instance_profile.sonarqube_ecs_host.name}"

  security_groups = ["${aws_security_group.sonarqube_ecs_instance_sg.name}"]

  user_data     = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.sonarqube.name} >> /etc/ecs/ecs.config
EOF

}

resource "aws_autoscaling_group" "sonarqube_cluster" {

  name = "sonarqube-asg"

  availability_zones = "${var.zones[var.region]}"

  max_size         = 1
  min_size         = 1
  desired_capacity = 1

  launch_configuration = "${aws_launch_configuration.sonarqube_ecs_nodes.name}"

  health_check_type = "ELB"

}


resource "aws_iam_instance_profile" "sonarqube_ecs_host" {
  name = "sonarqube-ecs-host"
  role = "${aws_iam_role.sonarqube_ecs.name}"
}


resource "aws_ecs_task_definition" "sonarqube_web" {

  family = "sonar-web"
  network_mode = "bridge"

  container_definitions = <<DEFINITION
[
  {
    "essential": true,
    "image": "sonarqube:latest",
    "memory": 1024,
    "memoryReservation": 64,
    "name": "sonarqube",
    "portMappings": [
      { 
        "hostPort": 9000,
        "containerPort": 9000
      }
    ],
    "environment": [ 
      {
        "name": "SONARQUBE_JDBC_USERNAME",
        "value": "sonarqube"
      },
      { 
        "name": "SONARQUBE_JDBC_PASSWORD",
        "value": "sonarqube"
      },
      {
        "name": "SONARQUBE_JDBC_URL",
        "value": "jdbc:mysql://${aws_db_instance.sonarqube.endpoint}/sonar?useUnicode=true&characterEncoding=utf8&rewriteBatchedStatements=true"
      }
    ]
  }
]
DEFINITION

  # can't have tags

}


resource "aws_elb" "sonarqube" {

  name = "sonarqube-elb"
  # FIXME associate a dns entry

  availability_zones = "${var.zones[var.region]}"

  security_groups = ["${aws_security_group.sonarqube_elb_sg.id}"]
  listener {
    instance_port     = 9000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags {
    Name          = "sonarqube ECS Load Balancer"
  }

}

# AmazonEC2ContainerServiceforEC2Role

resource "aws_iam_role" "sonarqube_ecs" {

  name = "sonarqube-ecs"

  assume_role_policy = <<ROLE
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ecs.amazonaws.com", "ec2.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
ROLE

  # can't have tags

}


resource "aws_iam_role_policy_attachment" "sonarqube_ecs_service" {
  name        = "sonarqube-ecs-service"
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  role        = "${aws_iam_role.sonarqube_ecs.name}"
}

resource "aws_iam_role_policy_attachment" "sonarqube_ecs_elb" {
  name        = "sonarqube-ecs-elb"
  role        = "${aws_iam_role.sonarqube_ecs.name}"
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}


resource "aws_ecs_service" "sonarqube" {

  name            = "sonarqube-ecs-service"
  task_definition = "${aws_ecs_task_definition.sonarqube_web.arn}"
  cluster         = "${aws_ecs_cluster.sonarqube.id}"
  desired_count   = 1

  iam_role        = "${aws_iam_role.sonarqube_ecs.arn}" # required for elb

  load_balancer = {
    elb_name       = "sonarqube-elb"
    container_name = "sonarqube"
    container_port = "9000"
  }

  # can't have tags

}


output "db_endpoint" {
  value = "${aws_db_instance.sonarqube.endpoint}"
}

output "elb_dns" {
  value = "${aws_elb.sonarqube.dns_name}"
}
