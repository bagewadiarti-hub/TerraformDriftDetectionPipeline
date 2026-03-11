pipeline {
    agent any

    triggers {
        cron('0 2 * * *')
    }

    tools {
        terraform 'terraform'
    }

    environment {
        SLACK_CHANNEL    = '#all-toshibaworkspace'
        JIRA_URL         = 'https://arti-devops.atlassian.net'
        JIRA_PROJECT_KEY = 'MyDevopsSpace'
        JIRA_USER        = credentials('jira-email')
        JIRA_TOKEN       = credentials('jira-api-token')
        ARM_CLIENT_ID       = credentials('azure-client-id')
        ARM_CLIENT_SECRET   = credentials('azure-client-secret')
        ARM_TENANT_ID       = credentials('azure-tenant-id')
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Terraform Init') {
            steps {
                bat 'terraform init'
            }
        }

        stage('Drift Detection') {
            steps {
                script {
                    def exitCode = bat(
                        script: 'terraform plan -detailed-exitcode -out=tfplan.out > plan_output.txt 2>&1',
                        returnStatus: true
                    )
                    env.TF_EXIT_CODE = exitCode.toString()
                }
            }
        }

        stage('Handle Drift') {
            when { expression { env.TF_EXIT_CODE == '2' } }
            steps {
                script {
                    bat 'terraform show -no-color tfplan.out > plan_readable.txt'
                    archiveArtifacts artifacts: 'plan_readable.txt', fingerprint: true

                    def planOutput = readFile('plan_readable.txt').take(1000)

                    def jiraPayload = groovy.json.JsonOutput.toJson([
                        fields: [
                            project    : [key: env.JIRA_PROJECT_KEY],
                            summary    : "Terraform Drift Detected - Build #" + env.BUILD_NUMBER,
                            description: "Drift detected.\n\nPlan:\n" + planOutput,
                            issuetype  : [name: 'Bug'],
                            priority   : [name: 'High']
                        ]
                    ])

                    def response = httpRequest(
                        url           : env.JIRA_URL + '/rest/api/3/issue',
                        httpMode      : 'POST',
                        authentication: 'jira-basic-auth',
                        contentType   : 'APPLICATION_JSON',
                        requestBody   : jiraPayload
                    )

                    def jiraIssue = readJSON text: response.content
                    env.JIRA_TICKET = jiraIssue.key
                }
            }
        }
    }

    post {
        always {
            script {
                def exitCode = env.TF_EXIT_CODE ?: 'unknown'
                def color = exitCode == '0' ? 'good' : exitCode == '2' ? 'danger' : 'warning'
                def statusMsg = exitCode == '0'
                    ? ':white_check_mark: *No Drift Detected*'
                    : exitCode == '2'
                        ? ':rotating_light: *Drift Detected!*'
                        : ':warning: *Terraform Plan Failed*'

                def jiraInfo = env.JIRA_TICKET
                    ? "\n*Jira:* " + env.JIRA_URL + "/browse/" + env.JIRA_TICKET
                    : ''

                slackSend(
                    channel: env.SLACK_CHANNEL,
                    color  : color,
                    message: statusMsg + "\n*Job:* " + env.JOB_NAME +
                             " #" + env.BUILD_NUMBER + jiraInfo
                )
            }
        }
    }
}
