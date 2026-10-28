pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 90, unit: 'MINUTES')
    }

    parameters {
        choice(name: 'ACTION', choices: ['apply', 'destroy'], description: 'Create/configure or destroy the demo infrastructure')
        booleanParam(name: 'REQUIRE_APPROVAL', defaultValue: true, description: 'Pause before applying or destroying infrastructure')
        booleanParam(name: 'INSERT_DEMO_DOCUMENTS', defaultValue: true, description: 'Insert two demo documents after configuration')
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        AWS_REGION = 'ap-south-1'
        AWS_CREDENTIALS_ID = 'aws-lab-credentials'
        TF_IN_AUTOMATION = 'true'
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_CONFIG = 'ansible/ansible.cfg'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Tool and syntax checks') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                sh '''
                    set -eu
                    terraform version
                    aws --version
                    ansible --version
                    command -v session-manager-plugin
                    python3 --version
                    terraform -chdir=terraform fmt -recursive
                    ansible-playbook --syntax-check ansible/site.yml
                '''
            }
        }

        stage('Prepare AWS and Ansible') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS_ID}"]]) {
                    sh '''
                        set -eu
                        aws sts get-caller-identity
                        ansible-galaxy collection install -r ansible/requirements.yml
                        python3 -m pip install --user boto3 botocore
                    '''
                }
            }
        }

        stage('Terraform Init and Plan') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS_ID}"]]) {
                    sh '''
                        set -eu
                        terraform -chdir=terraform init -input=false
                        if [ "$ACTION" = "apply" ]; then
                          terraform -chdir=terraform plan -input=false -out=tfplan
                        else
                          terraform -chdir=terraform plan -destroy -input=false -out=tfplan
                        fi
                    '''
                }
            }
        }

        stage('Approval') {
            when { expression { return params.REQUIRE_APPROVAL } }
            steps {
                script {
                    def verb = params.ACTION == 'apply' ? 'CREATE/CONFIGURE' : 'DESTROY'
                    input message: "Approve ${verb} for the MongoDB SSM demo in ap-south-1?", ok: 'Proceed'
                }
            }
        }

        stage('Terraform Apply') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS_ID}"]]) {
                    sh '''
                        set -eu
                        terraform -chdir=terraform apply -input=false -auto-approve tfplan
                        terraform -chdir=terraform output -json > ansible/terraform-outputs.json
                    '''
                }
            }
        }

        stage('Wait for SSM managed instances') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS_ID}"]]) {
                    sh '''
                        set -eu
                        python3 - <<'PY'
import json, os, subprocess, sys, time
data = json.load(open("ansible/terraform-outputs.json"))
ids = data["mongo_instance_ids"]["value"]
region = os.environ.get("AWS_REGION", "ap-south-1")
deadline = time.time() + 900
pending = set(ids)
while pending and time.time() < deadline:
    result = subprocess.run(
        ["aws", "ssm", "describe-instance-information", "--region", region,
         "--filters", "Key=InstanceIds,Values=" + ",".join(sorted(pending)),
         "--output", "json"], capture_output=True, text=True)
    if result.returncode == 0:
        online = {x["InstanceId"] for x in json.loads(result.stdout).get("InstanceInformationList", [])
                  if x.get("PingStatus") == "Online"}
        pending -= online
    if pending:
        print("Waiting for SSM online:", ", ".join(sorted(pending)))
        time.sleep(15)
if pending:
    sys.exit("SSM did not become Online for: " + ", ".join(sorted(pending)))
print("All MongoDB nodes are online in SSM.")
PY
                    '''
                }
            }
        }

        stage('Generate SSM inventory') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                sh '''
                    set -eu
                    python3 - <<'PY'
import json, os, yaml
data = json.load(open("ansible/terraform-outputs.json"))
nodes = data["mongo_instances"]["value"]
bucket = data["ssm_transfer_bucket"]["value"]
region = data["aws_region"]["value"]
inventory = {"all": {"children": {"mongo": {"vars": {
    "ansible_connection": "community.aws.aws_ssm",
    "ansible_aws_ssm_region": region,
    "ansible_aws_ssm_bucket_name": bucket,
    "ansible_user": "ubuntu",
    "replica_set_name": "rs0"
}, "hosts": {}}}}}
for node in nodes:
    inventory["all"]["children"]["mongo"]["hosts"][node["name"]] = {
        "ansible_host": node["instance_id"],
        "mongo_private_ip": node["private_ip"]
    }
with open("ansible/inventory.generated.yml", "w") as f:
    yaml.safe_dump(inventory, f, sort_keys=False)
PY
                '''
            }
        }

        stage('Configure MongoDB with Ansible over SSM') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS_ID}"]]) {
                    sh '''
                        set -eu
                        ansible-playbook -i ansible/inventory.generated.yml ansible/site.yml
                    '''
                }
            }
        }

        stage('Verify replica set and demo data') {
            when {
                allOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.INSERT_DEMO_DOCUMENTS }
                }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS_ID}"]]) {
                    sh '''
                        set -eu
                        ansible-playbook -i ansible/inventory.generated.yml ansible/verify.yml
                    '''
                }
            }
        }

        stage('Terraform Destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS_ID}"]]) {
                    sh '''
                        set -eu
                        terraform -chdir=terraform apply -input=false -auto-approve tfplan
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'rm -f ansible/terraform-outputs.json ansible/inventory.generated.yml terraform/tfplan || true'
        }
        success {
            echo "MongoDB SSM demo pipeline completed: ACTION=${params.ACTION}"
        }
        failure {
            echo 'Pipeline failed. Inspect the first failed stage and its console output before rerunning.'
        }
    }
}
