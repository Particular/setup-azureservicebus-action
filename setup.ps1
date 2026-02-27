param (
    [string]$connectionStringName,
    [string]$tagName,
    [string]$azureCredentials,
    [string]$useEmulator = "false",
    [string]$emulatorHost = "localhost",
    [string]$emulatorAmqpPort = "5672",
    [string]$emulatorHttpPort = "5300",
    [string]$emulatorSqlPassword = "StrongP@ssword!123"
)

function Save-State {
    param(
        [string]$Name,
        [string]$Value
    )

    if ($env:GITHUB_STATE) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_STATE -Encoding utf8 -Append
    }
}

function Export-Env {
    param(
        [string]$Name,
        [string]$Value
    )

    "$Name=$Value" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
}

function New-MinimalEmulatorConfig {
    param(
        [string]$Path
    )

    $config = @'
{
  "UserConfig": {
    "Namespaces": [
      {
        "Name": "sbemulatorns",
        "Queues": [],
        "Topics": []
      }
    ],
    "Logging": {
      "Type": "File"
    }
  }
}
'@

    Set-Content -Path $Path -Value $config -NoNewline
}

function Export-EmulatorConnectionStrings {
    param(
        [string]$EmulatorHost,
        [string]$AmqpPort,
        [string]$HttpPort
    )

    $runtimeConnectionString = "Endpoint=sb://${EmulatorHost}:${AmqpPort};SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;"
    $adminConnectionString = "Endpoint=sb://${EmulatorHost}:${HttpPort};SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;"
    $restrictedConnectionStringName = "$($connectionStringName)_Restricted"
    $adminConnectionStringName = "$($connectionStringName)_Admin"

    Write-Output "::add-mask::$runtimeConnectionString"
    Write-Output "::add-mask::$adminConnectionString"

    Export-Env -Name $connectionStringName -Value $runtimeConnectionString
    Export-Env -Name $restrictedConnectionStringName -Value $runtimeConnectionString
    Export-Env -Name $adminConnectionStringName -Value $adminConnectionString
    Export-Env -Name "ASBUseEmulator" -Value "true"
}

function Get-RunnerRegion {
    if ($Env:REGION_OVERRIDE) {
        return $Env:REGION_OVERRIDE
    }

    try {
        $hostInfo = curl --silent -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | ConvertFrom-Json
        if ($hostInfo.compute.location) {
            return $hostInfo.compute.location
        }
    }
    catch {
    }

    Write-Output "Could not determine region from metadata, defaulting to eastus"
    return "eastus"
}

function Wait-ForEmulatorHealth {
    param(
        [string]$EmulatorHost,
        [string]$EmulatorPort,
        [string]$ComposeFilePath,
        [int]$TimeoutSeconds = 300
    )

    $healthUrl = "http://${EmulatorHost}:${EmulatorPort}/health"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0

    while ((Get-Date) -lt $deadline) {
        $attempt++
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Output "Azure Service Bus Emulator health check succeeded at $healthUrl"
                return
            }
        }
        catch {
        }

        if (($attempt % 5) -eq 0) {
            Write-Output "Waiting for Azure Service Bus Emulator health endpoint at $healthUrl"
        }

        Start-Sleep -Seconds 1
    }

    if ($ComposeFilePath) {
        Write-Output "Emulator health check timed out, collecting Docker diagnostics"
        docker compose -f $ComposeFilePath ps
        docker compose -f $ComposeFilePath logs --no-color emulator
        docker compose -f $ComposeFilePath logs --no-color sqledge
    }

    throw "Azure Service Bus Emulator did not become healthy at $healthUrl within $TimeoutSeconds seconds."
}

function Setup-EmulatorWithDockerCompose {
    $emulatorAssetPath = Join-Path ([System.IO.Path]::GetTempPath()) ("azure-service-bus-emulator-assets-" + [guid]::NewGuid().ToString("N"))
    $composeFilePath = Join-Path $emulatorAssetPath "docker-compose-default.yml"
    $configFilePath = Join-Path $emulatorAssetPath "Config.json"

    New-Item -Path $emulatorAssetPath -ItemType Directory -Force > $null

    Write-Output "Creating minimal Azure Service Bus Emulator config"
    New-MinimalEmulatorConfig -Path $configFilePath
    $configFilePathForCompose = $configFilePath.Replace('\\', '/')

    $composeContent = @'
name: microsoft-azure-servicebus-emulator
services:
  emulator:
    container_name: "servicebus-emulator"
    image: mcr.microsoft.com/azure-messaging/servicebus-emulator:latest
    pull_policy: always
    volumes:
      - "__CONFIG_PATH__:/ServiceBus_Emulator/ConfigFiles/Config.json"
    ports:
      - "${EMULATOR_AMQP_PORT:-5672}:5672"
      - "${EMULATOR_HTTP_PORT:-5300}:5300"
    environment:
      SQL_SERVER: sqledge
      MSSQL_SA_PASSWORD: "${SQL_PASSWORD}"
      ACCEPT_EULA: ${ACCEPT_EULA}
      SQL_WAIT_INTERVAL: ${SQL_WAIT_INTERVAL}
      EMULATOR_HTTP_PORT: 5300
    depends_on:
      - sqledge
    networks:
      sb-emulator:
        aliases:
          - "sb-emulator"
  sqledge:
    container_name: "sqledge"
    image: "mcr.microsoft.com/azure-sql-edge:latest"
    networks:
      sb-emulator:
        aliases:
          - "sqledge"
    environment:
      ACCEPT_EULA: ${ACCEPT_EULA}
      MSSQL_SA_PASSWORD: "${SQL_PASSWORD}"

networks:
  sb-emulator:
'@

    $composeContent = $composeContent.Replace('__CONFIG_PATH__', $configFilePathForCompose)

    Set-Content -Path $composeFilePath -Value $composeContent -NoNewline

    $env:ACCEPT_EULA = "Y"
    $env:SQL_PASSWORD = $emulatorSqlPassword
    $env:SQL_WAIT_INTERVAL = "15"
    $env:EMULATOR_HTTP_PORT = $emulatorHttpPort
    $env:EMULATOR_AMQP_PORT = $emulatorAmqpPort

    $dockerServerOs = (docker version --format '{{.Server.Os}}' 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dockerServerOs)) {
        throw "Failed to determine Docker server OS. Ensure Docker is installed and running."
    }

    if ($dockerServerOs -ne "linux") {
        throw "Azure Service Bus Emulator requires Linux containers. Docker server OS is '$dockerServerOs'."
    }

    Write-Output "Starting Azure Service Bus Emulator using Docker Compose"
    docker compose -f $composeFilePath down
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to run docker compose down for emulator."
    }

    docker compose -f $composeFilePath up -d
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to run docker compose up for emulator."
    }

    $emulatorContainerState = docker compose -f $composeFilePath ps -q emulator
    if (-not $emulatorContainerState) {
        docker compose -f $composeFilePath logs --no-color emulator
        throw "Emulator container did not start successfully."
    }

    Wait-ForEmulatorHealth -EmulatorHost $emulatorHost -EmulatorPort $emulatorHttpPort -ComposeFilePath $composeFilePath
    Export-EmulatorConnectionStrings -EmulatorHost $emulatorHost -AmqpPort $emulatorAmqpPort -HttpPort $emulatorHttpPort

    Save-State -Name "UseEmulator" -Value "true"
    Save-State -Name "UseAciEmulator" -Value "false"
    Save-State -Name "EmulatorAssetPath" -Value $emulatorAssetPath
    Save-State -Name "EmulatorComposeFilePath" -Value $composeFilePath
}

function Setup-EmulatorWithAci {
    if (-not $azureCredentials) {
        throw "Input azure-credentials is required for emulator on Windows (ACI mode)."
    }

    $resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"
    $region = Get-RunnerRegion
    $effectiveTagName = if ($tagName) { $tagName } else { "setup-azureservicebus-action" }
    $containerGroupName = "psw-asb-" + (Get-Random -Minimum 1000000000 -Maximum 9999999999)

    if ($emulatorAmqpPort -ne "5672") {
        Write-Output "AMQP port override is not supported in ACI mode. Using 5672."
        $emulatorAmqpPort = "5672"
    }

    if ($emulatorHttpPort -ne "5300") {
        Write-Output "HTTP management port override is not supported in ACI mode. Using 5300."
        $emulatorHttpPort = "5300"
    }

    $emulatorAssetPath = Join-Path ([System.IO.Path]::GetTempPath()) ("azure-service-bus-emulator-assets-" + [guid]::NewGuid().ToString("N"))
    $configFilePath = Join-Path $emulatorAssetPath "Config.json"
    $aciTemplatePath = Join-Path $emulatorAssetPath "aci-template.yaml"
    New-Item -Path $emulatorAssetPath -ItemType Directory -Force > $null

    Write-Output "Creating minimal Azure Service Bus Emulator config"
    New-MinimalEmulatorConfig -Path $configFilePath
    $configBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($configFilePath))

    $dateTag = Get-Date -Format "yyyy-MM-dd"
    $runnerOsTag = $Env:RUNNER_OS

    $aciTemplate = @"
apiVersion: '2021-10-01'
location: $region
name: $containerGroupName
type: Microsoft.ContainerInstance/containerGroups
tags:
  Package: '$effectiveTagName'
  RunnerOS: '$runnerOsTag'
  Created: '$dateTag'
properties:
  osType: Linux
  restartPolicy: Always
  ipAddress:
    type: Public
    ports:
      - protocol: tcp
        port: 5672
      - protocol: tcp
        port: 5300
  containers:
    - name: sqledge
      properties:
        image: mcr.microsoft.com/azure-sql-edge:latest
        environmentVariables:
          - name: ACCEPT_EULA
            value: 'Y'
          - name: MSSQL_SA_PASSWORD
            secureValue: '$emulatorSqlPassword'
        resources:
          requests:
            cpu: 1
            memoryInGB: 2
    - name: servicebus-emulator
      properties:
        image: mcr.microsoft.com/azure-messaging/servicebus-emulator:latest
        ports:
          - port: 5672
          - port: 5300
        environmentVariables:
          - name: SQL_SERVER
            value: localhost
          - name: MSSQL_SA_PASSWORD
            secureValue: '$emulatorSqlPassword'
          - name: ACCEPT_EULA
            value: 'Y'
          - name: SQL_WAIT_INTERVAL
            value: '15'
          - name: EMULATOR_HTTP_PORT
            value: '5300'
        volumeMounts:
          - name: emulator-config
            mountPath: /ServiceBus_Emulator/ConfigFiles
        resources:
          requests:
            cpu: 1
            memoryInGB: 2
  volumes:
    - name: emulator-config
      secret:
        Config.json: '$configBase64'
"@

    Set-Content -Path $aciTemplatePath -Value $aciTemplate -NoNewline

    Write-Output "Creating Azure Container Instance group $containerGroupName in $region"
    az container create --resource-group $resourceGroup --file $aciTemplatePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Azure Container Instance group for emulator."
    }

    $containerHost = az container show --resource-group $resourceGroup --name $containerGroupName --query ipAddress.ip -o tsv
    if (-not $containerHost) {
        throw "Failed to get public IP for Azure Container Instance group $containerGroupName."
    }

    Wait-ForEmulatorHealth -EmulatorHost $containerHost -EmulatorPort $emulatorHttpPort -TimeoutSeconds 420
    Export-EmulatorConnectionStrings -EmulatorHost $containerHost -AmqpPort "5672" -HttpPort $emulatorHttpPort

    Save-State -Name "UseEmulator" -Value "true"
    Save-State -Name "UseAciEmulator" -Value "true"
    Save-State -Name "ASBName" -Value $containerGroupName
    Save-State -Name "EmulatorAssetPath" -Value $emulatorAssetPath
}

function Setup-Emulator {
    $runnerOs = $Env:RUNNER_OS

    if ($runnerOs -eq "Windows") {
        Setup-EmulatorWithAci
    }
    else {
        Setup-EmulatorWithDockerCompose
    }
}

function Setup-Azure {
    if (-not $azureCredentials) {
        throw "Input azure-credentials is required when use-emulator is false."
    }

    if (-not $tagName) {
        throw "Input tag is required when use-emulator is false."
    }

    $credentials = $azureCredentials | ConvertFrom-Json
    $resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"

    if ($Env:REGION_OVERRIDE) {
        $region = $Env:REGION_OVERRIDE
    }
    else {
        Write-Output "Getting the Azure region in which this workflow is running..."
        $hostInfo = curl --silent -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | ConvertFrom-Json
        $region = $hostInfo.compute.location
    }
    Write-Output "Actions agent running in Azure region $region"

    $packageTag = "Package=$tagName"
    $runnerOsTag = "RunnerOS=$($Env:RUNNER_OS)"
    $dateTag = "Created=$(Get-Date -Format "yyyy-MM-dd")"
    $ASBName = "psw-asb-" + (Get-Random -Minimum 1000000000 -Maximum 9999999999)

    Write-Output "Creating Azure Service Bus namespace $ASBName (This can take a while.)"
    $details = az servicebus namespace create --resource-group $resourceGroup --name $ASBName --location $region --tags $packageTag $runnerOsTag $dateTag | ConvertFrom-Json

    Write-Output "Assigning roles to Azure Service Bus namespace $ASBName"
    az role assignment create --assignee $credentials.principalId --role "Azure Service Bus Data Owner" --scope $details.id > $null

    Write-Output "Getting connection string"
    $keys = az servicebus namespace authorization-rule keys list --resource-group $resourceGroup --namespace-name $ASBName --name RootManageSharedAccessKey | ConvertFrom-Json
    $connectString = $keys.primaryConnectionString
    Write-Output "::add-mask::$connectString"

    Write-Output "Getting connection string without manage rights"
    az servicebus namespace authorization-rule create --resource-group $resourceGroup --namespace-name $ASBName --name RootNoManageSharedAccessKey --rights Send Listen > $null
    $noManageKeys = az servicebus namespace authorization-rule keys list --resource-group $resourceGroup --namespace-name $ASBName --name RootNoManageSharedAccessKey | ConvertFrom-Json
    $noManageConnectString = $noManageKeys.primaryConnectionString
    Write-Output "::add-mask::$noManageConnectString"

    $noManageConnectionStringName = "$($connectionStringName)_Restricted"
    $adminConnectionStringName = "$($connectionStringName)_Admin"

    Export-Env -Name $connectionStringName -Value $connectString
    Export-Env -Name $noManageConnectionStringName -Value $noManageConnectString
    Export-Env -Name $adminConnectionStringName -Value $connectString
    Export-Env -Name "ASBUseEmulator" -Value "false"

    Save-State -Name "UseEmulator" -Value "false"
    Save-State -Name "ASBName" -Value $ASBName
}

if ($useEmulator -eq "true") {
    Setup-Emulator
}
else {
    Setup-Azure
}
