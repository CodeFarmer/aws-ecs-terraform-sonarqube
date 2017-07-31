# aws-ecs-terraform-sonarqube
A small SonarQube stack running on Amazon's Elastic Container Service, built using Terraform

Prerequisites:

* Terraform
* AWS command-line credentials for Terraform to read (eg., in .aws/credentials)

Things:

* This ends up with the application being open to the internet. This might not be what you want.
* The IAM roles are a kludge, and could be made tighter and more specific.
