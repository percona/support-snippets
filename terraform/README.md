
```
aws configure sso

aws ec2 create-key-pair --key-name <some key name> --query KeyMaterial --output text > ~/.ssh/<some key name>.pem
chmod 0600 ~/.ssh/<some key name>.pem
ssh-keygen -p -f ~/.ssh/<some key name>.pem
terraform plan
terraform apply -var="engineer_name=$(whoami)" -var="project_name=test" -var="key_name=<some key name>"
terraform state list
terraform state show aws_instance.web
```
