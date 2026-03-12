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
        JIRA_PROJECT_KEY = 'IT'
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

        stage('Validate Jira') {
            when { expression { env.TF_EXIT_CODE == '2' } }
            steps {
                script {
                    String authString  = env.JIRA_USER + ':' + env.JIRA_TOKEN
                    String authEncoded = java.util.Base64.getEncoder()
                                            .encodeToString(authString.getBytes('UTF-8'))

                    // ── Check 1: Validate credentials ──
                    echo "=== Checking Jira credentials ==="
                    def authCheck = httpRequest(
                        url           : env.JIRA_URL + '/rest/api/3/myself',
                        httpMode      : 'GET',
                        customHeaders : [
                            [name: 'Authorization', value: 'Basic ' + authEncoded],
                            [name: 'Accept',        value: 'application/json']
                        ],
                        validResponseCodes: '100:599'
                    )
                    if (authCheck.status != 200) {
                        error("Jira auth FAILED (${authCheck.status}). " +
                              "Check 'jira-email' and 'jira-api-token' credentials.\n" +
                              "Response: ${authCheck.content}")
                    }
                    // ── Extract only the String value needed, discard the LazyMap immediately ──
                    String emailAddress = new groovy.json.JsonSlurper()
                                            .parseText(authCheck.content)
                                            .emailAddress as String
                    echo "Jira auth OK — logged in as: ${emailAddress}"

                    // ── Check 2: Validate project key ──
                    echo "=== Checking Jira project key: ${env.JIRA_PROJECT_KEY} ==="
                    def projectCheck = httpRequest(
                        url           : env.JIRA_URL + '/rest/api/3/project/' + env.JIRA_PROJECT_KEY,
                        httpMode      : 'GET',
                        customHeaders : [
                            [name: 'Authorization', value: 'Basic ' + authEncoded],
                            [name: 'Accept',        value: 'application/json']
                        ],
                        validResponseCodes: '100:599'
                    )
                    if (projectCheck.status != 200) {
                        error("Jira project '${env.JIRA_PROJECT_KEY}' not found (${projectCheck.status}).\n" +
                              "Response: ${projectCheck.content}")
                    }
                    // ── Extract only String values, discard the LazyMap immediately ──
                    String projectName = new groovy.json.JsonSlurper()
                                            .parseText(projectCheck.content)
                                            .name as String
                    echo "Jira project found: '${projectName}' (key: ${env.JIRA_PROJECT_KEY})"

                    // ── Check 3: List available issue types ──
                    echo "=== Checking issue types for project ${env.JIRA_PROJECT_KEY} ==="
                    def metaCheck = httpRequest(
                        url           : env.JIRA_URL + '/rest/api/3/issue/createmeta' +
                                        '?projectKeys=' + env.JIRA_PROJECT_KEY +
                                        '&expand=projects.issuetypes',
                        httpMode      : 'GET',
                        customHeaders : [
                            [name: 'Authorization', value: 'Basic ' + authEncoded],
                            [name: 'Accept',        value: 'application/json']
                        ],
                        validResponseCodes: '100:599'
                    )
                    if (metaCheck.status == 200) {
                        // ── Extract to plain List<String>, discard the LazyMap immediately ──
                        List<String> issueTypes = new groovy.json.JsonSlurper()
                                            .parseText(metaCheck.content)
                                            .projects[0]?.issuetypes
                                            ?.collect { it.name as String } ?: []
                        echo "Available issue types: ${issueTypes}"
                        if (!issueTypes.contains('Bug')) {
                            echo "WARNING: 'Bug' not found. Update issuetype in Handle Drift to one of: ${issueTypes}"
                        } else {
                            echo "Issue type 'Bug' confirmed available."
                        }
                    }

                    env.JIRA_AUTH_ENCODED = authEncoded
                }
            }
        }

        stage('Handle Drift') {
            when { expression { env.TF_EXIT_CODE == '2' } }
            steps {
                script {
                    bat 'terraform show -no-color tfplan.out > plan_readable.txt'
                    archiveArtifacts artifacts: 'plan_readable.txt', fingerprint: true

                    def jiraBody = groovy.json.JsonOutput.toJson([
                        fields: [
                            project    : [key: env.JIRA_PROJECT_KEY],
                            summary    : "Terraform Drift Detected - Build #" + env.BUILD_NUMBER,
                            description: [
                                type   : "doc",
                                version: 1,
                                content: [[
                                    type   : "paragraph",
                                    content: [[
                                        type: "text",
                                        text: "Drift detected in nightly Jenkins run. Build URL: " + env.BUILD_URL
                                    ]]
                                ]]
                            ],
                            issuetype  : [name: "Bug"],
                            priority   : [name: "High"]
                        ]
                    ])

                    echo "=== Creating Jira issue ==="
                    def response = httpRequest(
                        url           : env.JIRA_URL + '/rest/api/3/issue',
                        httpMode      : 'POST',
                        customHeaders : [
                            [name: 'Authorization', value: 'Basic ' + env.JIRA_AUTH_ENCODED],
                            [name: 'Content-Type',  value: 'application/json']
                        ],
                        requestBody        : jiraBody,
                        validResponseCodes : '100:599'
                    )

                    echo "Jira response code: ${response.status}"
                    echo "Jira response body: ${response.content}"

                    if (response.status != 200 && response.status != 201) {
                        error("Failed to create Jira issue (${response.status}).\n" +
                              "Response: ${response.content}")
                    }

                    // ── Extract only the ticket key String, discard the LazyMap immediately ──
                    String ticketKey = new groovy.json.JsonSlurper()
                                        .parseText(response.content)
                                        .key as String
                    env.JIRA_TICKET = ticketKey
                    echo "Jira ticket created: ${env.JIRA_TICKET}"
                }
            }
        }
    }

    post {
        always {
            script {
                def exitCode  = env.TF_EXIT_CODE ?: 'unknown'
                def color     = exitCode == '0' ? 'good' : exitCode == '2' ? 'danger' : 'warning'
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
