param (
    [string]$connectionStringName,
    [string]$tagName,
    [string]$azureCredentials,
    [string]$useEmulator = "false",
    [string]$emulatorHost = "",
    [string]$emulatorAmqpPort = "5672",
    [string]$emulatorHttpPort = "5300"
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

    Write-Host "Could not determine region from metadata, defaulting to eastus"
    return "eastus"
}

function Get-NearbyRegions {
    param([string]$Primary)

    switch -Regex ($Primary) {
        '^westus\d*$' { return @($Primary, "westus", "westus2", "westus3", "westcentralus", "southcentralus", "centralus", "northcentralus", "eastus2", "eastus") }
        '^eastus\d*$' { return @($Primary, "eastus", "eastus2", "centralus", "northcentralus", "southcentralus", "westus", "westus2", "westus3", "westcentralus") }
        '^centralus$' { return @($Primary, "northcentralus", "southcentralus", "eastus", "eastus2", "westus", "westus2", "westus3", "westcentralus") }
        '^northcentralus$' { return @($Primary, "centralus", "southcentralus", "eastus", "eastus2", "westus", "westus2", "westus3", "westcentralus") }
        '^southcentralus$' { return @($Primary, "centralus", "northcentralus", "westus", "westus2", "westus3", "westcentralus", "eastus", "eastus2") }
        '^westcentralus$' { return @($Primary, "westus", "westus2", "westus3", "southcentralus", "centralus", "northcentralus", "eastus2", "eastus") }
    }

    return @($Primary, "centralus", "northcentralus", "southcentralus", "eastus2", "eastus", "westus2", "westus", "westus3", "westcentralus")
}

function Get-CandidateRegions {
    param(
        [string]$ProviderNamespace,
        [string]$ResourceType
    )

    $primary = (Get-RunnerRegion).ToLowerInvariant()
    Write-Host "Actions agent running in Azure region $primary"

    if ($Env:REGION_OVERRIDE) {
        return @($primary)
    }

    $candidates = Get-NearbyRegions -Primary $primary | Select-Object -Unique

    # Best effort: drop regions where the resource type isn't offered (e.g. Service Bus in eastus3).
    $providerJson = az provider show --namespace $ProviderNamespace --only-show-errors --output json
    if ($LASTEXITCODE -eq 0 -and $providerJson) {
        $offered = (($providerJson | ConvertFrom-Json).resourceTypes |
            Where-Object { $_.resourceType -eq $ResourceType }).locations |
            ForEach-Object { ($_ -replace '\s', '').ToLowerInvariant() }

        $filtered = @($candidates | Where-Object { $offered -contains $_ })
        $skipped = @($candidates | Where-Object { $offered -notcontains $_ })
        if ($skipped.Count -gt 0) {
            Write-Host "Skipping regions where $ProviderNamespace/$ResourceType is not available: $($skipped -join ', ')"
        }
        if ($filtered.Count -gt 0) {
            $candidates = $filtered
        }
    }

    Write-Host "Candidate regions in order: $($candidates -join ', ')"
    return $candidates
}

function Invoke-AzCli {
    $output = & az @args 2>&1
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        ExitCode = $exitCode
        StdOut   = ($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
        StdErr   = ($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join "`n"
    }
}

function Test-RegionRetriableError {
    param([string]$ErrorText)

    return $ErrorText -match 'LocationNotAvailableForResourceType|NoRegisteredProviderFound|LocationNotSupported|RegionNotSupported|SkuNotAvailable|ServiceUnavailable|ResourceUnavailable|InternalServerError|high demand|capacity|quota'
}

function Test-AzResourceGone {
    # Only an explicit not-found counts; a failed lookup could hide a leftover resource.
    $result = Invoke-AzCli @args --only-show-errors --output none
    return $result.ExitCode -ne 0 -and $result.StdErr -match 'ResourceNotFound|NotFound|could not be found|was not found'
}

function Invoke-DockerCompose {
    param(
        [string]$ComposeFilePath,
        [string[]]$Arguments,
        [switch]$CheckExitCode
    )

    if ($Env:RUNNER_OS -eq "Windows") {
        $wslComposeFilePath = ConvertTo-WslPath $ComposeFilePath
        Invoke-Wsl -CheckExitCode:$CheckExitCode -Command "docker compose -f '$wslComposeFilePath' $($Arguments -join ' ')"
    }
    else {
        docker compose -f $ComposeFilePath @Arguments
        if ($CheckExitCode -and $LASTEXITCODE -ne 0) {
            throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
        }
    }
}

function Wait-ForEmulatorHealth {
    param(
        [string]$EmulatorHost,
        [string]$EmulatorPort,
        [string]$ComposeFilePath,
        [int]$TimeoutSeconds = 300
    )

    $healthUrl = "http://${EmulatorHost}:${EmulatorPort}/health"
    Write-Output "::add-mask::$healthUrl"
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

    Write-Output "Emulator health check timed out, collecting Docker diagnostics"
    Invoke-DockerCompose -ComposeFilePath $ComposeFilePath -Arguments "ps"
    Invoke-DockerCompose -ComposeFilePath $ComposeFilePath -Arguments "logs", "--no-color", "emulator"
    Invoke-DockerCompose -ComposeFilePath $ComposeFilePath -Arguments "logs", "--no-color", "sqledge"

    throw "Azure Service Bus Emulator did not become healthy at $healthUrl within $TimeoutSeconds seconds."
}

function Setup-Emulator {
    if (-not $Env:WSL_TOOLS_MODULE_PATH) {
        throw "use-emulator requires Particular/setup-wsl-action to run first. It provisions WSL/Docker on Windows and exports WSL_IP and the WslTools module at WSL_TOOLS_MODULE_PATH."
    }
    Import-Module $Env:WSL_TOOLS_MODULE_PATH -Force

    $connectionHost = if ($emulatorHost) { $emulatorHost } else { $Env:WSL_IP }
    if (-not $connectionHost) {
        throw "WSL_IP is not set. Run Particular/setup-wsl-action before this action."
    }

    $emulatorAssetPath = Join-Path ([System.IO.Path]::GetTempPath()) ("azure-service-bus-emulator-assets-" + [guid]::NewGuid().ToString("N"))
    $composeFilePath = Join-Path $emulatorAssetPath "docker-compose-default.yml"
    $configFilePath = Join-Path $emulatorAssetPath "Config.json"

    New-Item -Path $emulatorAssetPath -ItemType Directory -Force > $null

    $emulatorSqlPassword = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
    Write-Output "::add-mask::$emulatorSqlPassword"

    Write-Output "Creating minimal Azure Service Bus Emulator config"
    New-MinimalEmulatorConfig -Path $configFilePath
    $configFilePathForCompose = if ($Env:RUNNER_OS -eq "Windows") { ConvertTo-WslPath $configFilePath } else { $configFilePath }

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
      EMULATOR_HTTP_PORT: ${EMULATOR_HTTP_PORT:-5300}
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

    # Compose reads .env next to the compose file, so the variables reach Docker inside WSL too.
    $envFileContent = @(
        "ACCEPT_EULA=Y"
        "SQL_PASSWORD=$emulatorSqlPassword"
        "SQL_WAIT_INTERVAL=15"
        "EMULATOR_HTTP_PORT=$emulatorHttpPort"
        "EMULATOR_AMQP_PORT=$emulatorAmqpPort"
    ) -join "`n"
    Set-Content -Path (Join-Path $emulatorAssetPath ".env") -Value $envFileContent -NoNewline

    Save-State -Name "UseEmulator" -Value "true"
    Save-State -Name "EmulatorAssetPath" -Value $emulatorAssetPath
    Save-State -Name "EmulatorComposeFilePath" -Value $composeFilePath

    Write-Output "Starting Azure Service Bus Emulator using Docker Compose"
    Invoke-DockerCompose -ComposeFilePath $composeFilePath -Arguments "down" -CheckExitCode
    Invoke-DockerCompose -ComposeFilePath $composeFilePath -Arguments "up", "-d" -CheckExitCode

    $emulatorContainerState = Invoke-DockerCompose -ComposeFilePath $composeFilePath -Arguments "ps", "-q", "emulator"
    if (-not $emulatorContainerState) {
        Invoke-DockerCompose -ComposeFilePath $composeFilePath -Arguments "logs", "--no-color", "emulator"
        throw "Emulator container did not start successfully."
    }

    Wait-ForEmulatorHealth -EmulatorHost $connectionHost -EmulatorPort $emulatorHttpPort -ComposeFilePath $composeFilePath
    Export-EmulatorConnectionStrings -EmulatorHost $connectionHost -AmqpPort $emulatorAmqpPort -HttpPort $emulatorHttpPort
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

    $packageTag = "Package=$tagName"
    $runnerOsTag = "RunnerOS=$($Env:RUNNER_OS)"
    $dateTag = "Created=$(Get-Date -Format "yyyy-MM-dd")"

    # There have been issues with the module loader for az servicebus failing with concurrency issues
    # under certain combinations of runner image and cli version, it seems to help by 
    # calling the command command using --help.
    # This seems to allow it to load under a different path that is not impacted 
    # with the same threading deadlock issues.
    az servicebus namespace create --help | Out-Null

    $candidateRegions = Get-CandidateRegions -ProviderNamespace "Microsoft.ServiceBus" -ResourceType "namespaces"
    $details = $null

    foreach ($tryRegion in $candidateRegions) {
        # Fresh name per attempt so a namespace stuck deleting can't block the retry.
        $ASBName = "psw-asb-" + (Get-Random -Minimum 1000000000 -Maximum 9999999999)

        Write-Output "Creating Azure Service Bus namespace $ASBName in $tryRegion (This can take a while.)"
        $result = Invoke-AzCli servicebus namespace create --resource-group $resourceGroup --name $ASBName --location $tryRegion --tags $packageTag $runnerOsTag $dateTag --only-show-errors --output json
        if ($result.ExitCode -eq 0) {
            $details = $result.StdOut | ConvertFrom-Json
            break
        }

        Write-Output $result.StdErr
        if (-not (Test-RegionRetriableError -ErrorText $result.StdErr)) {
            Write-Output "Creation in $tryRegion failed due to a non-region related error; not attempting other regions."
            break
        }

        Write-Output "Creation in $tryRegion failed due to region availability or capacity; cleaning up and trying the next region."
        az servicebus namespace delete --resource-group $resourceGroup --name $ASBName --only-show-errors 2>&1 | Out-Null
        if (-not (Test-AzResourceGone servicebus namespace show --resource-group $resourceGroup --name $ASBName)) {
            Save-State -Name "UseEmulator" -Value "false"
            Save-State -Name "ASBName" -Value $ASBName
            throw "Could not confirm cleanup of namespace $ASBName after the failed attempt in $tryRegion; stopping so the post step can delete it."
        }
    }

    if (-not $details) {
        throw "Failed to create Azure Service Bus namespace in resource group $resourceGroup in any of: $($candidateRegions -join ', ')."
    }

    # Saved right away so the post step deletes the namespace even if a later step fails.
    Save-State -Name "UseEmulator" -Value "false"
    Save-State -Name "ASBName" -Value $ASBName

    Write-Output "Assigning roles to Azure Service Bus namespace $ASBName"
    az role assignment create --assignee $credentials.principalId --role "Azure Service Bus Data Owner" --scope $details.id > $null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to assign roles to Azure Service Bus namespace $ASBName."
    }

    Write-Output "Getting connection string"
    $keys = az servicebus namespace authorization-rule keys list --resource-group $resourceGroup --namespace-name $ASBName --name RootManageSharedAccessKey | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get connection string for Azure Service Bus namespace $ASBName."
    }
    $connectString = $keys.primaryConnectionString
    Write-Output "::add-mask::$connectString"

    Write-Output "Getting connection string without manage rights"
    az servicebus namespace authorization-rule create --resource-group $resourceGroup --namespace-name $ASBName --name RootNoManageSharedAccessKey --rights Send Listen > $null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create authorization rule without manage rights for Azure Service Bus namespace $ASBName."
    }

    $noManageKeys = az servicebus namespace authorization-rule keys list --resource-group $resourceGroup --namespace-name $ASBName --name RootNoManageSharedAccessKey | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get connection string without manage rights for Azure Service Bus namespace $ASBName."
    }
    $noManageConnectString = $noManageKeys.primaryConnectionString
    Write-Output "::add-mask::$noManageConnectString"

    $noManageConnectionStringName = "$($connectionStringName)_Restricted"
    $adminConnectionStringName = "$($connectionStringName)_Admin"

    Export-Env -Name $connectionStringName -Value $connectString
    Export-Env -Name $noManageConnectionStringName -Value $noManageConnectString
    Export-Env -Name $adminConnectionStringName -Value $connectString
    Export-Env -Name "ASBUseEmulator" -Value "false"
}

if ($useEmulator -eq "true") {
    Setup-Emulator
}
else {
    Setup-Azure
}
