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

The setup action also propagates `EnvVarToCreateWithConnectionString_Admin` for management operations. In Azure mode this is the same value as the main connection string. In emulator mode this includes the emulator management port.

### Azure Service Bus Emulator

Set `use-emulator: true` to run the action against the Azure Service Bus Emulator using Docker Compose.

```yaml
      - name: Setup emulator
        uses: Particular/setup-azureservicebus-action@v1.0.0
        with:
          connection-string-name: ASBConnectionString
          use-emulator: true
          emulator-amqp-port: 5673
          emulator-http-port: 5301
```

When `use-emulator` is `true`:

- Linux runners use Docker Compose locally.
- Windows runners use Azure Container Instances (Linux containers), so `azure-credentials` is required.
- In Windows ACI mode, emulator ports are fixed to `5672`/`5300`.

Available emulator inputs:

- `emulator-host` (default: `localhost`)
- `emulator-amqp-port` (default: `5672`)
- `emulator-http-port` (default: `5300`)
- `emulator-sql-password` (default: `StrongP@ssword!123`)

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
# Replace the principal ID with the appropriate principal ID that you used to log into AZ CLI
$azureCredentials = @"
{
     "principalId": "a28b36b8-2243-494e-9028-0e94df179913",
   }
"@
.\setup.ps1 -connectionStringName AzureServiceBus_ConnectionString -tagName setup-azureservicebus-action -azureCredentials $azureCredentials -useEmulator false
```

To test the cleanup action set the required environment variables and execute `cleanup.ps1` with the desired parameters.

```bash
$Env:RESOURCE_GROUP_OVERRIDE=yourResourceGroup
.\cleanup.ps1 -ASBName psw-asb-1 -useEmulator false
```
