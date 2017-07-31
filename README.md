# aws-ecs-terraform-sonarqube
A small SonarQube stack running on Amazon's Elastic Container Service, built using Terraform

Prerequisites:

* Terraform
* AWS command-line credentials for Terraform to read (eg., in .aws/credentials)

Things:

* This ends up with the application being open to the internet. This might not be what you want.
* I built this using ECS because I hadn't done that before - ECS has some other requirements that mean that if I were doing this again, I would use Elastic Beanstalk or even just a plain AMI since I ended up building a lot of things that weren't really about the app.
* Backed to a very small RDS instance - again, could be more efficiently done with a MySQL installation on the same machine as the app server.
* The IAM roles are a kludge, and could be made tighter and more specific.
