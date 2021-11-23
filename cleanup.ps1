param (
    [string]$ASBName
)

$ignore = az servicebus namespace delete --resource-group GitHubActions-RG --name $ASBName