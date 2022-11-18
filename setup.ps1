param (
    [string]$ASBName,
    [string]$connectionStringName,
    [string]$tagName
)

echo "Getting the Azure region in which this workflow is running..."
$hostInfo = curl --silent -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | ConvertFrom-Json
$region = $hostInfo.compute.location
echo "Actions agent running in Azure region $region"

$packageTag = "Package=$tagName"
$runnerOsTag = "RunnerOS=$($Env:RUNNER_OS)"
$dateTag = "Created=$(Get-Date -Format "yyyy-MM-dd")"

echo "Creating Azure Service Bus namespace $ASBName (This can take awhile.)"
$details = az servicebus namespace create --resource-group GitHubActions-RG --name $ASBName --location $region --tags $packageTag $runnerOsTag $dateTag | ConvertFrom-Json

echo "Getting connection string"
$keys = az servicebus namespace authorization-rule keys list --resource-group GitHubActions-RG --namespace-name $ASBName --name RootManageSharedAccessKey | ConvertFrom-Json
$connectString = $keys.primaryConnectionString
echo "::add-mask::$connectString"

echo "Getting connection string without manage rights"
az servicebus namespace authorization-rule create --resource-group GitHubActions-RG --namespace-name $ASBName --name RootNoManageSharedAccessKey --rights Send Listen
$noManageKeys = az servicebus namespace authorization-rule keys list --resource-group GitHubActions-RG --namespace-name $ASBName --name RootNoManageSharedAccessKey | ConvertFrom-Json
$noManageConnectString = $noManageKeys.primaryConnectionString
echo "::add-mask::$noManageConnectString"

echo "$connectionStringName=$connectString" | Out-File -FilePath $Env:GITHUB_ENV -Encoding utf-8 -Append
echo "$connectionStringName_Restricted=$noManageConnectString" | Out-File -FilePath $Env:GITHUB_ENV -Encoding utf-8 -Append
