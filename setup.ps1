param (
    [string]$ASBName,
    [string]$connectionStringName,
    [string]$tagName
)

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

Write-Output "Creating Azure Service Bus namespace $ASBName (This can take a while.)"
$details = az servicebus namespace create --resource-group $resourceGroup --name $ASBName --location $region --tags $packageTag $runnerOsTag $dateTag | ConvertFrom-Json

Write-Output "Getting connection string"
$keys = az servicebus namespace authorization-rule keys list --resource-group $resourceGroup --namespace-name $ASBName --name RootManageSharedAccessKey | ConvertFrom-Json
$connectString = $keys.primaryConnectionString
Write-Output "::add-mask::$connectString"

Write-Output "Getting connection string without manage rights"
az servicebus namespace authorization-rule create --resource-group $resourceGroup --namespace-name $ASBName --name RootNoManageSharedAccessKey --rights Send Listen
$noManageKeys = az servicebus namespace authorization-rule keys list --resource-group $resourceGroup --namespace-name $ASBName --name RootNoManageSharedAccessKey | ConvertFrom-Json
$noManageConnectString = $noManageKeys.primaryConnectionString
Write-Output "::add-mask::$noManageConnectString"
$noManageConnectionStringName = "$($connectionStringName)_Restricted"

Write-Output "$connectionStringName=$connectString" | Out-File -FilePath $Env:GITHUB_ENV -Encoding utf-8 -Append
Write-Output "$noManageConnectionStringName=$noManageConnectString" | Out-File -FilePath $Env:GITHUB_ENV -Encoding utf-8 -Append