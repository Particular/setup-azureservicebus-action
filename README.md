# setup-azureservicebus-action

This action handles the setup and teardown of an Azure Service Bus namespace for running tests.

## Usage

```yaml
      - name: Setup infrastructure
        uses: Particular/setup-azureservicebus-action@v1.0.0
        with:
          connection-string-name: EnvVarToCreateWithConnectionString
          azure-credentials: ${{ secrets.AZURE_ACI_CREDENTIALS }}
          tag: PackageName
```

The setup action also automatically propagates an environment variable called `EnvVarToCreateWithConnectionString_Restricted` with a dedicated connection string that only provides `Listen` and `Send` right. With that connection string, it is not possible to manage entities like queues, topics, subscriptions and rules. The connection string can be used to verify least-privilege scenarios.

## License

The scripts and documentation in this project are released under the [MIT License](LICENSE).

## Development

Open the folder in Visual Studio Code. If you don't already have them, you will be prompted to install remote development extensions. After installing them, and re-opening the folder in a container, do the following:

Log into Azure

```bash
az login
az account set --subscription SUBSCRIPTION_ID
```

When changing `index.js`, either run `npm run dev` beforehand, which will watch the file for changes and automatically compile it, or run `npm run prepare` afterwards.

## Testing

### With PowerShell

To test the setup action set the required environment variables and execute `setup.ps1` with the desired parameters.

```bash
$Env:RESOURCE_GROUP_OVERRIDE=yourResourceGroup
$Env:REGION_OVERRIDE=yourRegion
.\setup.ps1 -ASBName psw-asb-1 -ConnectionStringName AzureServiceBus_ConnectionString -Tag setup-azureservicebus-action
```

To test the cleanup action set the required environment variables and execute `cleanup.ps1` with the desired parameters.

```bash
$Env:RESOURCE_GROUP_OVERRIDE=yourResourceGroup
.\cleanup.ps1 -ASBName psw-asb-1
```