# Week 8 - Terraform VPC

This code reproduces Week 5's two-AZ network topology using the handbook's Week 8 `us-east-1` CIDRs: two public subnets, two private subnets, an Internet Gateway, and one NAT Gateway with an Elastic IP. The single NAT Gateway keeps this short lab cheaper but is a single-AZ failure point. It creates no EC2 instances.

From `week-08/`, use Terraform and AWS credentials with VPC, subnet, route table, NAT Gateway, and Elastic IP permissions:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
terraform output
terraform state list
terraform plan -destroy
terraform destroy
```

`init` downloads the pinned VPC module and AWS provider. **Plan** compares the configuration, state, and current AWS resources and previews creates, updates, replacements, and deletions; read it before proceeding. **Apply** shows a plan, asks for confirmation, makes the approved changes, and updates state. Verify the VPC and its subnet, route, and NAT resources in AWS before cleanup. **Destroy** previews and, after confirmation, removes resources recorded in this configuration's state. The NAT Gateway and Elastic IP can incur charges while deployed.

Terraform state maps resource addresses in this code to real AWS IDs, enabling later plans and destroy to manage the same objects. `terraform state list` shows what Terraform tracks; a normal `terraform plan` refreshes AWS data and reveals drift after out-of-band changes. If a resource was changed or deleted in the console, inspect the plan and AWS before choosing whether to restore the declared configuration or update it. Do not delete or edit state to hide drift. This lab uses local state; keep `terraform.tfstate*` private, backed up, and out of Git. Losing it makes cleanup and future changes harder; for shared use, migrate to a locked remote backend.

On November 18, 2026, `fmt` and `validate` passed; the plan and apply created 19 resources. AWS confirmed the VPC, four subnets, routes, and available NAT Gateway. A manual VPC `Name` tag change appeared as one in-place update in `plan`, and `apply` restored it. `destroy` removed all 19 resources; an independent AWS check found no lab VPC or Elastic IP, the NAT Gateway was `deleted`, and `terraform state list` was empty.
