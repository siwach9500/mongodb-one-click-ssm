# One-click MongoDB Replica Set — Terraform + Ansible + Jenkins + SSM

This lab provisions three private Ubuntu 22.04 EC2 instances in `ap-south-1`,
installs MongoDB 7.0, and configures replica set `rs0`. No bastion and no
inbound SSH are used. Ansible connects through `community.aws.aws_ssm`.

## Demo sizing and cost notes
- EC2: 3 x `t3.micro` by default (change `instance_type` if your account/region needs it).
- Root EBS: 8 GiB gp3 per node, encrypted; MongoDB data lives on the root filesystem.
- This is suitable only for a small disposable demo, not production. MongoDB packages,
  Ubuntu updates, SSM and Ansible transfer require outbound connectivity.
- A single NAT Gateway is created to provide outbound connectivity from private subnets.
  NAT Gateway hourly/data charges can exceed the cost of the tiny EC2 instances. Destroy
  the lab when finished. For lower cost, prebuild images or replace NAT with appropriately
  configured VPC endpoints and a controlled package mirror.
- Three nodes provide a replica-set demo; they are not a high-availability production design.
- The Jenkins controller/agent must be able to reach AWS APIs and have Terraform, AWS CLI,
  Session Manager plugin, Python, Ansible, and the required collections installed.

## Layout
- `terraform/`: VPC, private/public subnets, NAT, security groups, IAM/SSM, three EC2 nodes, S3 transfer bucket.
- `ansible/`: SSM inventory template, MongoDB install/configure, replica set initialization, verification.
- `Jenkinsfile`: `apply` or `destroy`, with optional approval before applying/destroying.

## One-time setup
1. Push this directory to a Git repository.
2. Configure Jenkins to use that repository and select `Jenkinsfile`.
3. Configure a Jenkins AWS credential of type **AWS Credentials** with ID `aws-lab-credentials`
   (or change `AWS_CREDENTIALS_ID` in `Jenkinsfile`). The identity needs permissions to create
   the resources in this lab and pass the EC2 role. Prefer a dedicated least-privilege lab role.
4. Ensure the Jenkins agent has:
   - Terraform 1.6+ and AWS CLI v2
   - Python 3, `pip`, Ansible
   - `session-manager-plugin`
   - `community.aws` Ansible collection and its Python dependencies
5. Run Jenkins with `ACTION=apply`. Confirm the plan and approve if enabled.

The pipeline writes a temporary inventory from Terraform outputs. For SSM connection,
`ansible_host` is the EC2 instance ID, while `mongo_private_ip` is the private address
advertised to other replica-set members. An S3 bucket is used by the Ansible SSM connection
plugin to transfer files; it is private and encrypted.

## Manual use
```bash
cd terraform
terraform init
terraform plan
terraform apply
terraform output -json > ../ansible/terraform-outputs.json
cd ../ansible
ansible-galaxy collection install community.aws
pip install boto3 botocore
# Use the Jenkins pipeline as the canonical inventory-generation example.
```

## Important operational details
- The VPC has no inbound SSH rule. MongoDB TCP/27017 is allowed only between instances
  in the MongoDB security group.
- SSM requires the instance profile, SSM agent, and outbound access. User data installs
  the SSM agent if it is not already installed.
- Terraform state is kept in the Jenkins workspace so a later `destroy` build can find it.
  Do not delete that workspace between apply and destroy. This is acceptable only for a
  single-controller demo; for shared/team use, configure an encrypted, access-controlled
  remote state backend (S3 with versioning and locking) before using this pipeline.
  Do not commit state or credentials.
- Destroy removes the instances and the transfer bucket. The bucket is configured for
  force destroy because it is only for temporary Ansible SSM transfers.
- `terraform destroy` deletes the demo database. Back up anything important first.
