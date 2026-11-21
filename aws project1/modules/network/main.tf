# ------------------------------------------------------------------------------
# VPC and Subnet Configuration (Free Tier Compliant)
# ------------------------------------------------------------------------------

# Fetch available availability zones if none specified
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_az = var.availability_zone != null ? var.availability_zone : data.aws_availability_zones.available.names[0]
}

# 1. Custom VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Tier        = "FreeTier"
  }
}

# 2. Internet Gateway (IGW) for the Public Subnet
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-igw"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# 3. Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.selected_az
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-public-subnet"
    Type        = "Public"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# 4. Private Subnet (Strictly isolated - NO public IP)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = local.selected_az
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-private-subnet"
    Type        = "Private"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# 5. Public Route Table (Routes out to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-public-rt"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 6. Private Route Table (NO NAT Gateway -> Zero Cost!)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-private-rt"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------------------------------
# VPC Gateway Endpoint for Amazon S3 (Always Free Tier)
# Allows EC2 in Private Subnet to communicate with S3 without NAT Gateway
# ------------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id, aws_route_table.public.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-s3-gateway-endpoint"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Cost        = "AlwaysFree"
  }
}
