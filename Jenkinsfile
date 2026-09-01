pipeline {
    agent any

    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['qa', 'dev', 'prod'],
            description: 'Which environment to deploy'
        )
    }

    environment {
        AWS_REGION   = 'eu-west-1'
        ECR_REGISTRY = '231733667519.dkr.ecr.eu-west-1.amazonaws.com'
        CLUSTER      = 'poc2-three-tier-cluster'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Configure kubeconfig') {
            steps {
                sh '''
                    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER
                    kubectl get nodes
                '''
            }
        }

        stage('ECR Login') {
            steps {
                sh '''
                    aws ecr get-login-password --region $AWS_REGION | \
                    docker login --username AWS --password-stdin $ECR_REGISTRY
                '''
            }
        }

        stage('Backend: Build & Push') {
            steps {
                dir('app-tier') {
                    sh """
                        docker build -t backend:\$BUILD_NUMBER .
                        docker tag backend:\$BUILD_NUMBER \$ECR_REGISTRY/poc2-three-tier-backend:\$BUILD_NUMBER
                        docker push \$ECR_REGISTRY/poc2-three-tier-backend:\$BUILD_NUMBER
                    """
                }
            }
        }

        stage('Frontend: Build & Push') {
            steps {
                dir('web-tier') {
                    sh """
                        docker build -t frontend:\$BUILD_NUMBER .
                        docker tag frontend:\$BUILD_NUMBER \$ECR_REGISTRY/poc2-three-tier-frontend:\$BUILD_NUMBER
                        docker push \$ECR_REGISTRY/poc2-three-tier-frontend:\$BUILD_NUMBER
                    """
                }
            }
        }

        stage('Deploy via Helm') {
            steps {
                dir('charts/three-tier-app') {
                    sh """
                        helm dependency update
                        helm upgrade --install three-tier-app-${ENVIRONMENT} . -f values-${ENVIRONMENT}.yaml \
                          --set-string backend.image.tag=\$BUILD_NUMBER \
                          --set-string frontend.image.tag=\$BUILD_NUMBER
                    """
                }
            }
        }

        stage('Reload Ingress Controller') {
            steps {
                sh '''
                    kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
                    kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=90s
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    kubectl get pods -n ${ENVIRONMENT}
                    kubectl get ingress -n ${ENVIRONMENT}
                """
            }
        }
    }

    post {
        success {
            echo "Deployment to ${params.ENVIRONMENT} completed successfully."
        }
        failure {
            echo 'Pipeline failed. Check logs above.'
        }
        always {
            cleanWs()
        }
    }
}