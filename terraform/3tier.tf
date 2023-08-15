provider "aws" {
  region = "us-east-2" # Ohio region
}

resource "aws_vpc" "tommyvpc" {
  cidr_block           = "192.168.0.0/18"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "tommyvpc"
  }

}

resource "aws_subnet" "privatesub" {
  vpc_id            = aws_vpc.tommyvpc.id
  cidr_block        = "192.168.1.0/24"
  availability_zone = "us-east-2a" # Replace with your desired availability zone

  tags = {
    Name = "privatesub"
  }
}

resource "aws_subnet" "publicsub" {
  vpc_id            = aws_vpc.tommyvpc.id
  cidr_block        = "192.168.2.0/24"
  availability_zone = "us-east-2b" # Replace with your desired availability zone

  tags = {
    Name = "publicsub"
  }
}
resource "aws_eip" "tommynat" {
  vpc = true
}

resource "aws_nat_gateway" "tommynat" {
  allocation_id = aws_eip.tommynat.id
  subnet_id     = aws_subnet.publicsub.id

  tags = {
    Name = "tommynat"
  }
}
resource "aws_internet_gateway" "tommyigw" {
  vpc_id = aws_vpc.tommyvpc.id

  tags = {
    Name = "tommyigw"
  }
}


resource "aws_route_table" "publicRT" {
  vpc_id = aws_vpc.tommyvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tommyigw.id
  }

  tags = {
    Name = "publicRT"
  }
}

resource "aws_route_table" "privateRT" {
  vpc_id = aws_vpc.tommyvpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.tommynat.id
  }

  tags = {
    Name = "privateRT"
  }
}

resource "aws_route_table_association" "publicsub_assoc" {
  subnet_id      = aws_subnet.publicsub.id
  route_table_id = aws_route_table.publicRT.id
}

resource "aws_route_table_association" "privatesub_assoc" {
  subnet_id      = aws_subnet.privatesub.id
  route_table_id = aws_route_table.privateRT.id
}

resource "aws_security_group" "tommyinstance_sg" {
  name_prefix = "tommyinstance_sg"
  vpc_id      = aws_vpc.tommyvpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/18"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/18"]
  }
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/18"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "nginxinstance_sg" {
  name_prefix = "nginxinstance_sg"
  vpc_id      = aws_vpc.tommyvpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_subnet" "another_subnet" {
  vpc_id            = aws_vpc.tommyvpc.id
  cidr_block        = "192.168.4.0/24" # Use a different CIDR block
  availability_zone = "us-east-2c"     # Choose a different availability zone

  tags = {
    Name = "another_subnet"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.privatesub.id, aws_subnet.another_subnet.id]

  tags = {
    Name = "rds-subnet-group"
  }
}



resource "aws_security_group" "rds_sg" {
  name_prefix = "rds_sg"
  vpc_id      = aws_vpc.tommyvpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/18"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/18"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/18"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}




resource "aws_instance" "tommyinstance" {
  ami           = "ami-0ccabb5f82d4c9af5" # Replace with your desired AMI ID
  instance_type = "t2.micro"              # Replace with your desired instance type
  subnet_id     = aws_subnet.privatesub.id
  key_name      = "linux"
user_data = <<-EOT
#!/bin/bash
BUCKET="fdec26-sagar"

# Install Java and Tomcat
sudo yum install java-11-amazon-corretto -y
wget https://dlcdn.apache.org/tomcat/tomcat-8/v8.5.91/bin/apache-tomcat-8.5.91.zip
sudo unzip apache-tomcat-8.5.91.zip -d /mnt/tomcat
sudo mv /mnt/tomcat/apache-tomcat-8.5.91 /mnt/tomcat

# Download and deploy your application
KEY=$(aws s3 ls "$BUCKET" --recursive | sort | tail -n 1 | awk '{print $4}')
aws s3 cp "s3://$BUCKET/$KEY" "/mnt/tomcat/webapps/"

# Modify context.xml to allow remote access
sudo sed -i 's/<Context>/<Context allowRemoteAccess="true">/' /mnt/tomcat/conf/context.xml

# Modify the Resource element for JDBC connection
sudo sed -i 's#<Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource"#<Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" \
           maxTotal="500" maxIdle="30" maxWaitMillis="1000" \
           username="admin" password="12345678" driverClassName="com.mysql.jdbc.Driver" \
           url="jdbc:mysql://${aws_db_instance.rds_instance.endpoint}:${aws_db_instance.rds_instance.port}/studentapp?useUnicode=yes&amp;characterEncoding=utf8"/>#' /mnt/tomcat/conf/context.xml

# Start Tomcat
sudo chmod 0755 /mnt/tomcat/bin/*
sudo /mnt/tomcat/bin/catalina.sh start
EOT


  tags = {
    Name = "tommyinstance"
  }

  security_groups = [aws_security_group.tommyinstance_sg.id]
}

resource "aws_instance" "nginxinstance" {
  ami                         = "ami-0ccabb5f82d4c9af5" # Replace with your desired AMI ID
  instance_type               = "t2.micro"              # Replace with your desired instance type
  subnet_id                   = aws_subnet.publicsub.id
  associate_public_ip_address = true
  key_name                    = "linux"

  user_data = <<-EOT
              #!/bin/bash
              yum install -y nginx
              echo 'server {
                listen 80;
                location / {
                   proxy_pass http://${aws_instance.tommyinstance.private_ip}:8080;  # Private IP of tommyinstance
                }
              }' > /etc/nginx/conf.d/reverse-proxy.conf
              service nginx restart
              EOT

  tags = {
    Name = "nginxinstance"
  }

  security_groups = [aws_security_group.nginxinstance_sg.id]
}

resource "aws_db_instance" "rds_instance" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  identifier             = "tommyrds"
  username               = "admin"
  password               = "12345678"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name

  tags = {
    Name = "tommyrds"
  }
