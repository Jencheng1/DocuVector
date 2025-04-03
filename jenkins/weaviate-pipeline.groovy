pipeline {
    agent any
    
    environment {
        AWS_REGION = 'us-east-1'
        ECR_REPOSITORY = 'weaviate'
        ECS_CLUSTER = 'weaviate-cluster'
        ECS_SERVICE = 'weaviate-service'
        DOCKER_IMAGE = "${ECR_REPOSITORY}:${BUILD_NUMBER}"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    docker.build(DOCKER_IMAGE, '--build-arg WEAVIATE_VERSION=1.19.0 .')
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                script {
                    docker.withRegistry('https://${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com', 'ecr:us-east-1:aws-credentials') {
                        docker.image(DOCKER_IMAGE).push()
                    }
                }
            }
        }
        
        stage('Terraform Plan') {
            steps {
                dir('infrastructure') {
                    sh 'terraform init'
                    sh 'terraform plan -out=tfplan'
                }
            }
        }
        
        stage('Terraform Apply') {
            steps {
                dir('infrastructure') {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }
        
        stage('Ansible Configuration') {
            steps {
                dir('ansible') {
                    sh 'ansible-playbook -i inventory/hosts weaviate.yml --extra-vars "weaviate_version=1.19.0"'
                }
            }
        }
        
        stage('Update ECS Service') {
            steps {
                script {
                    sh """
                        aws ecs update-service \
                            --cluster ${ECS_CLUSTER} \
                            --service ${ECS_SERVICE} \
                            --force-new-deployment
                    """
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                script {
                    sh 'python3 -m pytest tests/weaviate/'
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                script {
                    timeout(time: 5, unit: 'MINUTES') {
                        waitUntil {
                            def response = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://weaviate.${DOMAIN_NAME}/v1/meta", returnStdout: true).trim()
                            return response == "200"
                        }
                    }
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        success {
            slackSend(
                color: 'good',
                message: "Weaviate deployment successful: ${BUILD_URL}"
            )
        }
        failure {
            slackSend(
                color: 'danger',
                message: "Weaviate deployment failed: ${BUILD_URL}"
            )
        }
    }
} 