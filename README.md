# setup-azureservicebus-action

This action handles the setup and teardown of an Azure Service Bus namespace for running tests.

## Usage

```yaml
      - name: Setup infrastructure
        uses: Particular/setup-azureservicebus-action@v1.0.0
        with:
          connection-string-name: EnvVarToCreateWithConnectionString
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
