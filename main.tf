# 1. Create HasiCorp Account 
# 2. Create an Organization named "FH_Technikum"
# 3. Create a Workspace named "IaC_TFWorkshop3"
# 4. Create AWS Variables for AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN
# 5. Create an API token for GitHub Actions in User Settings
# used this guide to create the github Actions setupt and workflow.yml files: https://developer.hashicorp.com/terraform/tutorials/automation/github-actions

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.52.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
  required_version = ">= 1.1.0"

  cloud { # Configures Terraform Cloud as the backend to store the Terraform state

    organization = "FH_Technikum"

    workspaces {
      name = "IaC_TFWorkshop3" # Workspace that manages the state
    }
  }

}




provider "aws" {
  region = "us-east-1" # specifies the region where the resources will be deployed
}

# 1. Create vpc

# All resources start with the "TYPE" and then a custom "NAME". Un this case aws_vpc is the resource type and workshop3_vpc is the given name
# All the following resource will follow the same kind of declaration
resource "aws_vpc" "workshop3_vpc" {
  cidr_block = "10.0.0.0/16" # the cidr block that is used for this vpc, subnets have to be within this network
  tags = {                   # sets a tag
    Name = "workshop3_vpc"   # key value pair of the tag
  }
}

# 2. Create Internet Gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.workshop3_vpc.id
}

# 3. Create Custom Route Table

resource "aws_route_table" "workshop3_RT" {
  vpc_id = aws_vpc.workshop3_vpc.id

  route {
    cidr_block = "0.0.0.0/0" # for the whole network
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "workshop3"
  }
}

# 4. Create a Subnet 

resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.workshop3_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "workshop3-subnet"
  }
}

# 5. Associate subnet with Route Table
# does not work without this association - "binds" subnet to route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.workshop3_RT.id
}

# 6. Create Security Group to allow port 80 
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.workshop3_vpc.id

  #incoming traffic/ports
  ingress {
    description = "HTTP"
    from_port   = 80 # from and to port to define port range. if both are the same than only this port is used
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # for all incoming traffic
  }

  #outgoing traffic/ports
  egress {
    from_port   = 0 # all ports
    to_port     = 0
    protocol    = "-1"          # represents all protocols
    cidr_blocks = ["0.0.0.0/0"] # for all outgoing traffic
  }

  tags = {
    Name = "allow_http"
  }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4

resource "aws_network_interface" "web-server-nic" {
  count     = 3 # <-- for number of instances
  subnet_id = aws_subnet.subnet-1.id
  #private_ips     = ["10.0.1.10", "10.0.1.11", "10.0.1.12"] #<--- ips for $count of instances
  security_groups = [aws_security_group.allow_web.id]

}

# 8. Assign an elastic IP to the network interface created in step 7

resource "aws_eip" "one" {
  count = 3 # <--- for number of instances
  #network_interface         = aws_network_interface.web-server-nic.id <-- for only one instance
  network_interface = aws_network_interface.web-server-nic[count.index].id # <--- can use index so that all three instances are assigned an EIP
  #associate_with_private_ip = element(["10.0.1.10", "10.0.1.11", "10.0.1.12"], count.index) # elemen() is a built in function, that iterates through the elements of a list using and index
  #associate_with_private_ip = "10.0.1.10"
  depends_on = [aws_internet_gateway.gw, aws_instance.web-server-instance, aws_network_interface.web-server-nic]

}

#output "server_public_ip" {     # outputs the public ip after this script is executed
#  value = aws_eip.one.public_ip # <- here we dont want the .id but the whole resource (the ip)
#}

# 9. Create Ubuntu server and install/enable apache2

resource "aws_instance" "web-server-instance" {

  count             = 3                       #<--- number instances to create
  ami               = "ami-0866a3c8686eaeeba" # ubuntu server 24.04 LTS version
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "vockey" # use existing ssh key, necessary for bash script execution to install and run apache web server

  network_interface {                                                           # the network interface that is used for this instance, we previously assigned the public ip to this interface
    device_index         = 0                                                    # first interface (starts with 0), mandatory
    network_interface_id = aws_network_interface.web-server-nic[count.index].id # <<--- once again use the [count.index] to name the interfaces
  }

  # execute bashscript: updates repositories and then installs the latest version of apache2, adds to systemctl (so it starts on instance startup)
  # then copies <h1>Hello World</h1> in the apaches default index.html file
  # added from $(hostname) so that it can be verified if the load balancer works
  user_data = <<-EOF
                #!/bin/bash
                sudo apt-get update
                sudo apt-get install -y apache2
                sudo systemctl start apache2
                sudo systemctl enable apache2
                echo "<h1>Hello World! from $(hostname -f)</h1> " | sudo tee /var/www/html/index.html
                EOF
  tags = {
    Name = "web-server"
  }
}



# 10 Create Load Balancer
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elb
resource "aws_elb" "web_elb" {
  name = "web-elb"
  #availability_zones = ["us-east-1a"]# either specify subnets or AZ not both
  security_groups = [aws_security_group.allow_web.id]
  subnets         = [aws_subnet.subnet-1.id] # either specify subnets or AZ not both

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  instances = aws_instance.web-server-instance[*].id

  tags = {
    Name = "web-elb"
  }
}

output "load_balancer_dns" {
  value = aws_elb.web_elb.dns_name # <-- outputs the dns name of the load balancer
}
