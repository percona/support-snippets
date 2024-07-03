aws configure sso
# Copy AWS environment variables


terraform init
terraform apply -var-file="variables.tfvars"

terraform destroy -var-file="variables.tfvars"

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini -u ubuntu --private-key ./ec2_key.pem ./ansible/main.yaml


mongosh  "mongodb://admin:percona@localhost:27017/percona?authSource=admin"

ssh -i ./ec2_key.pem ubuntu@18.232.121.149

mongo_instance_ips = [
  "54.166.155.1",
  "54.80.196.182",
  "34.235.135.188",
]

db.getSiblingDB("percona").getCollection("company").explain("executionStats").find({
  founded: {
    $gte: ISODate('1970-01-01T00:00:00Z'),
    $lt: ISODate('1990-01-01T00:00:00Z')
  }
}).count();
