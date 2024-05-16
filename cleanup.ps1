param (
    [string]$ASBName
)
$resourceGroup = $Env:RESOURCE_GROUP_OVERRIDE ?? "GitHubActions-RG"

$ignore = az servicebus namespace delete --resource-group $resourceGroup --name $ASBName