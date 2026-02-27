param (
    [string]$ASBName,
    [string]$useEmulator = "false",
    [string]$useAciEmulator = "false",
    [string]$emulatorAssetPath,
    [string]$emulatorComposeFilePath
)

$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"

if ($useEmulator -eq "true") {
    if ($useAciEmulator -eq "true") {
        if ($ASBName) {
            Write-Output "Deleting Azure Container Instance emulator group $ASBName"
            az container delete --resource-group $resourceGroup --name $ASBName --yes > $null
        }
    }
    else {
        if ($emulatorComposeFilePath -and (Test-Path $emulatorComposeFilePath)) {
            Write-Output "Stopping Azure Service Bus Emulator"
            docker compose -f $emulatorComposeFilePath down
        }
    }

    if ($emulatorAssetPath -and (Test-Path $emulatorAssetPath)) {
        Remove-Item -Path $emulatorAssetPath -Recurse -Force
    }

    return
}

if ($ASBName) {
    az servicebus namespace delete --resource-group $resourceGroup --name $ASBName > $null
}
