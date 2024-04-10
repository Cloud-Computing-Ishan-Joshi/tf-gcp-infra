# tf-gcp-infra
Cloud Computing Assignments

## Assignement 09

VPCs and custom VM instance

Infrastructure as Code w/Terraform¶

In this assignment, you will update the Terraform template to add the following resources.
Firewall¶

Set up firewall rules for you custom VPC/Subnet to allow traffic from the internet to the port your application listens to. Do not allow traffic to SSH port from the internet.
References¶

    google_compute_firewall

Compute Engine Instance (VM)¶

Create an compute engine instance with the following specifications. For any parameter not provided in the table below, you may go with default values. The instance must be launched in the VPC created by your Terraform IaC code. You cannot launch the instance in the default VPC.
Parameter 	Value
Boot disk Image 	CUSTOM IMAGE
Boot disk type 	Balanced
Size (GB) 	100
References¶

    google_compute_instance
    GCP Operating system details


## Steps:

1. Terraform init

`terraform init`

2. Terraform fmt

`terraform fmt`

3. Terraform fmt -check to check the format

`terraform fmt -check`

4. Terraform plan to see the desired GCP plan exceution to do.

`terraform plan`

5. Terraform apply to aply the plan

`terraform apply -var-file "file_name"`