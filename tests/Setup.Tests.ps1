$ErrorActionPreference = 'Stop'

function Assert-Equal($Actual, $Expected, $Message) {
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

# Exercise setup and cleanup without provisioning Azure resources or requiring Pester.
function az {
    $global:setupTest.Calls.Add(($args -join ' '))
    $global:LASTEXITCODE = 0

    if (($args[0..2] -join ' ') -eq 'servicebus namespace create') {
        if ($args -contains '--help') { return }

        $name = $args[[Array]::IndexOf($args, '--name') + 1]
        $global:setupTest.Names.Add($name)
        $savedState = Get-Content $env:GITHUB_STATE
        Assert-Equal ($savedState -contains "ASBName=$name") $true 'Namespace must be recorded before creation.'
        Assert-Equal ($savedState -contains 'UseEmulator=false') $true 'Cleanup mode must be recorded before creation.'

        if ($global:setupTest.Names.Count -le $global:setupTest.Failures) {
            $global:LASTEXITCODE = 1
            # Invalid JSON must not hide the native command's failure or prevent a retry.
            'not JSON'
            [Console]::Error.WriteLine("_frozen_importlib._DeadlockError: deadlock detected by _ModuleLock('requests.structures')")
            return
        }

        '{"id":"/subscriptions/test/resourceGroups/test/providers/Microsoft.ServiceBus/namespaces/test"}'
    }
    elseif (($args[0..4] -join ' ') -eq 'servicebus namespace authorization-rule keys list') {
        '{"primaryConnectionString":"test-connection-string"}'
    }
}

function Start-Sleep {
    param([int]$Seconds)
    $global:setupTest.Delays.Add($Seconds)
}

$tempPath = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item $tempPath -ItemType Directory > $null
$env:REGION_OVERRIDE = 'eastus'
$env:RESOURCE_GROUP_OVERRIDE = 'test'
$env:GITHUB_STATE = Join-Path $tempPath 'state'
$env:GITHUB_ENV = Join-Path $tempPath 'env'
$setupPath = Join-Path $PSScriptRoot '../setup.ps1'
$cleanupPath = Join-Path $PSScriptRoot '../cleanup.ps1'

try {
    foreach ($failures in 0..3) {
        $global:setupTest = @{
            Failures = $failures
            Names = [Collections.Generic.List[string]]::new()
            Calls = [Collections.Generic.List[string]]::new()
            Delays = [Collections.Generic.List[int]]::new()
        }
        Set-Content $env:GITHUB_STATE ''
        Set-Content $env:GITHUB_ENV ''
        $failure = $null
        try {
            & $setupPath -connectionStringName TestConnection -tagName test -azureCredentials '{"principalId":"test"}' > $null
        }
        catch {
            $failure = $_
        }

        $attempts = [Math]::Min($failures + 1, 3)
        Assert-Equal $global:setupTest.Names.Count $attempts 'Unexpected number of create attempts.'
        Assert-Equal @($global:setupTest.Names | Select-Object -Unique).Count 1 'Every attempt must use the same namespace.'
        Assert-Equal $global:setupTest.Delays.Count ($attempts - 1) 'Only sleep between attempts.'
        foreach ($delay in $global:setupTest.Delays) {
            Assert-Equal $delay 5 'Unexpected retry delay.'
        }

        $roleCalls = @($global:setupTest.Calls | Where-Object { $_ -like 'role assignment create *' })
        $exports = Get-Content $env:GITHUB_ENV
        if ($failures -eq 3) {
            Assert-Equal ($null -ne $failure) $true 'Exhausting retries must fail setup.'
            Assert-Equal ($failure.ToString() -like '*Failed to create Azure Service Bus namespace*after 3 attempts*') $true 'Keep a useful final error.'
            Assert-Equal $roleCalls.Count 0 'Do not configure a namespace after creation fails.'
            Assert-Equal ($exports -contains 'TestConnection=test-connection-string') $false 'Do not export connection strings after failure.'
        }
        else {
            if ($failure) { throw $failure }
            Assert-Equal $roleCalls.Count 1 'Configure the successful namespace once.'
            Assert-Equal ($exports -contains 'TestConnection=test-connection-string') $true 'Export the successful connection string.'
        }

        & $cleanupPath -ASBName $global:setupTest.Names[0] > $null
        Assert-Equal $global:setupTest.Calls[-1] "servicebus namespace delete --resource-group test --name $($global:setupTest.Names[0])" 'Cleanup must target the recorded namespace.'
        Write-Host "Passed: $failures initial create failures."
    }
}
finally {
    Remove-Item $tempPath -Recurse -Force
    Remove-Variable setupTest -Scope Global
}
