// Zones available in us-west-2. A lookup only, creates nothing. Subnets need a zone
// and hardcoding "us-west-2a" breaks if AWS retires one, so we ask AWS instead.
data "aws_availability_zones" "available" {
  state = "available"
}

// VPC (Virtual Private Cloud) - AWS equivalent of Azure VNet, our isolated network.
resource "aws_vpc" "main" {
  cidr_block = "10.1.0.0/16" // 65,536 addresses. Azure uses 10.0.0.0/16, so the two clouds never overlap if we connect them later

  // Defaults to true already, set explicitly so the intent is visible.
  // Without DNS support nothing inside the VPC can resolve names.
  enable_dns_support = true

  // Defaults to FALSE. Needed for private DNS (Cloud Map, RDS endpoint names).
  // Without it internal hostnames silently fail to resolve, even if everything else is right.
  enable_dns_hostnames = true

  tags = { Name = "vpc-p3-dr" } // "Name" tag = the label shown in the console (default_tags don't set it)
}

// Public subnet, zone a - will hold the NAT gateway and one leg of the ALB.
// "Public" is not a setting on the subnet, it only means its route table points at the IGW (below).
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.1.0/24"                                  // 256 addresses, AWS reserves 5 of them
  availability_zone = data.aws_availability_zones.available.names[0] // a subnet lives in exactly ONE zone

  tags = { Name = "snet-public-a" }
}

// Public subnet, zone b - the ALB must span 2 zones, so it needs a second public subnet.
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.2.0/24" // ranges inside a VPC must not overlap
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "snet-public-b" }
}

// Private subnet, zone a - will hold the ECS (Fargate) tasks. No public IPs, no inbound from the internet.
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.11.0/24" // 11 and 12 = private, 1 and 2 = public (our convention)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = { Name = "snet-private-a" }
}

// Private subnet, zone b - RDS requires subnets in 2+ zones (via aws_db_subnet_group),
// even for a single-zone database. This is why we have two private subnets.
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.1.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = { Name = "snet-private-b" }
}

// Internet Gateway - the VPC's door to the internet, in and out. Free.
// Attaches to the VPC itself, not to a subnet. Only subnets whose route table
// points here actually get internet access.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "igw-p3-dr" }
}

// Public route table - sends internet-bound traffic to the IGW.
// Anything placed in an associated subnet uses this table automatically.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"                  // every address that isn't inside the VPC (anywhere on the internet)
    gateway_id = aws_internet_gateway.main.id // ...goes out through the IGW. Traffic inside 10.1.0.0/16 stays local automatically
  }

  tags = { Name = "rt-public" }
}

// Route table associations - required, tables don't attach themselves.
// A subnet with no association silently falls back to the VPC's main route table.
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

// Private route table - no internet route yet, so only VPC-internal traffic works (the local route is built in).
// The NAT route (0.0.0.0/0 -> NAT gateway) is added next, once the NAT exists.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "rt-private" }
}

// Both private subnets get the private table explicitly, so a later route change applies to both.
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

// ---------- NAT: lets private subnets reach the internet (outbound only) ----------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "eip-nat" }
}

// NAT lives in a PUBLIC subnet (it needs the IGW route to reach the internet).
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.main]
  tags          = { Name = "nat-p3-dr" }
}

// Private route table: everything not local goes through the NAT.
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}