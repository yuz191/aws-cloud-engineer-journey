# Week 5 - Networking: VPC and bastion access

I completed the Week 5 network lab in `us-east-2` on October 28, 2026. The [diagram](vpc-diagram.png) shows the tested topology. I created each resource with the AWS CLI and checked it individually; this followed the handbook's network design but did not use its console "VPC and more" wizard. [lab.sh](lab.sh) records the disposable build, verification, and teardown commands. Its `.lab-state` file and the temporary SSH private key are excluded from Git.

## VPC design

| Resource | Configuration | Purpose |
| --- | --- | --- |
| VPC | `training-vpc`, `10.0.0.0/16` | Isolated network, DNS support and hostnames enabled |
| Public subnet A | `10.0.0.0/20`, `us-east-2a` | Bastion and NAT Gateway |
| Public subnet B | `10.0.16.0/20`, `us-east-2b` | Second public AZ for later labs |
| Private subnet A | `10.0.128.0/20`, `us-east-2a` | Private EC2 test instance |
| Private subnet B | `10.0.144.0/20`, `us-east-2b` | Second private AZ for later labs |
| Public route table | Both public subnets explicitly associated; `0.0.0.0/0` to Internet Gateway | Public internet path |
| Private route table | Both private subnets explicitly associated; `0.0.0.0/0` to NAT Gateway | Outbound access without inbound public access |
| NAT Gateway | One, in public subnet A, with an Elastic IP | Outbound path for both private subnets; this single-AZ design is a cost-conscious lab choice, not a highly available production design |

The bastion and private host were Amazon Linux 2023 `t3.micro` instances. The bastion had a public IPv4 address and a security group allowing TCP 22 only from my current public `/32`. The private instance had **no** public IPv4 address; its security group allowed TCP 22 only from the bastion's security group ID. No private key was copied onto the bastion. I used a temporary key pair and SSH agent forwarding (`ssh -A`); the private key stayed in Ubuntu WSL on my computer.

## Traffic path from my laptop to the private instance

1. My laptop connected by SSH to the bastion's public IP. The Internet Gateway and public route table brought this traffic to public subnet A; the bastion security group admitted only my `/32` source on port 22.
2. From the bastion, a second SSH connection went to the private instance's `10.0.133.90` address over the VPC local route. The private security group accepted the bastion security group as its source. SSH agent forwarding let the bastion authenticate without storing the private key there.
3. The private instance's outbound package update followed its private subnet's default route to the NAT Gateway in public subnet A. The NAT Gateway used its Elastic IP and the public subnet's Internet Gateway route. Return traffic came back through the NAT Gateway to the private instance. NAT does not make the private host directly reachable from the internet.

## Observed checks

- AWS returned VPC `vpc-0e8619b22a2825776`, one Internet Gateway, four subnets in `us-east-2a` and `us-east-2b`, and NAT Gateway `nat-0898027877bb1b456` in `available` state.
- The public route table's actual subnet associations included both public subnet IDs and its default route pointed to the Internet Gateway. The private route table's actual associations included both private subnet IDs and its default route pointed to the NAT Gateway. I checked the **Associations** as well as the **Routes**, because a correct route in an unassociated table would not help the instance.
- AWS showed a public IP for the bastion and `None` for the private instance's public IP. The bastion security group had a TCP 22 `/32` ingress rule. The private security group had a TCP 22 ingress rule referencing the bastion security group ID, with no public CIDR ingress rule.
- The laptop-to-bastion-to-private SSH test printed `HOP_OK` and the private instance hostname `ip-10-0-133-90.us-east-2.compute.internal`. A `curl` from that private shell returned the NAT Gateway's public egress IP, and `sudo yum update -y` completed successfully. The final verification timestamp was `2026-10-28T13:08:59Z`.

## If the private instance cannot reach the internet

First inspect the private instance's subnet ID and its effective route table. Confirm that its subnet is **explicitly associated** with a table whose `0.0.0.0/0` route targets an `available` NAT Gateway. Then check that the NAT Gateway is in a public subnet with an Elastic IP and that public subnet's route table has `0.0.0.0/0` to an attached Internet Gateway. A private subnet does not gain NAT access merely because a NAT Gateway exists in the same VPC. This was a diagnostic exercise; my private instance's update succeeded, so I did not observe the timeout symptom.

## Cleanup and weekly habit

I terminated both instances, deleted the NAT Gateway, released its Elastic IP, removed both lab security groups and all four subnet route associations, deleted the two custom route tables, detached and deleted the Internet Gateway, deleted all four subnets and the VPC, and deleted the temporary EC2 key pair and local private key. Teardown finished at `2026-10-28T13:10:54Z`.

Independent post-teardown AWS queries returned no VPC `vpc-0e8619b22a2825776`, no Elastic IP allocation `eipalloc-0fed0d6f4b6b9008b`, and no temporary key pair. Both instance IDs were `terminated`. The local `.lab-state` and private key file were absent. The Week 3 EBS snapshot described in [its runbook](../week-03/runbook.md) was outside this Week 5 lab and was not deleted here.

The handbook's separate weekly habits checklist also asks for a Billing dashboard screenshot. I did not create or claim one; the account owner will add `billing-screenshot.png` after signing in to the console. Billing data can lag resource deletion, so the resource checks above are the immediate teardown evidence.
