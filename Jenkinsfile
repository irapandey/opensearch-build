pipeline {
    agent any

    environment {
        REPO_URL    = 'https://github.com/irapandey/opensearch-build.git'
        BRANCH      = 'ppc64le-3.7.0'
        IMAGE_TAG   = 'opensearch-build:3.7.0-ppc64le'
        MANIFEST    = 'manifests/3.7.0/opensearch-3.7.0.yml'
    }

    stages {
        stage('Checkout') {
            steps {
                git(
                    url: "${REPO_URL}",
                    branch: "${BRANCH}"
                )
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t ${IMAGE_TAG} ."
            }
        }

        stage('Build OpenSearch') {
            steps {
                sh """
                    mkdir -p artifacts
                    docker run --rm \
                        -v \$(pwd)/artifacts:/opensearch-build/tar \
                        ${IMAGE_TAG} \
                        ./build.sh ${MANIFEST}
                """
            }
        }
    }

    post {
        always {
            echo "Build finished — artifacts available at: \$(pwd)/artifacts"
        }
        success {
            echo "OpenSearch ${IMAGE_TAG} built successfully."
        }
        failure {
            echo "Build failed. Check the console output above for details."
        }
    }
}
