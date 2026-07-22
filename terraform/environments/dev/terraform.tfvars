aws_region   = "us-east-1"
project_name = "aws-ai-native-infra"

# Cost-optimized, non-prod choice: single shared fck-nat instance rather
# than one per AZ. Prod's terraform.tfvars sets nat_type = "nat-gateway"
# instead, which always gets one NAT Gateway per AZ regardless of fck_nat_ha.
nat_type   = "fck-nat"
fck_nat_ha = false

# Cost-optimized, non-prod choice: single-AZ RDS. Prod's terraform.tfvars
# sets multi_az = true (synchronous standby + automatic failover).
multi_az = false

# Cost-optimized, non-prod choice: single Redis node. Prod's
# terraform.tfvars sets automatic_failover_enabled = true (primary +
# replica across AZs).
automatic_failover_enabled = false
