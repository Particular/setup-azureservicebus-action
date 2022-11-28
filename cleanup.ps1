param (
    [string]$ASBName
)
$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"

$identityName ="$($ASBName)-identity"

$ignore = az servicebus namespace delete --resource-group $resourceGroup --name $ASBName
$ignore = az identity delete --resource-group $resourceGroup --name $identityName