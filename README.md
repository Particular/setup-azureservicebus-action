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

## License

The scripts and documentation in this project are released under the [MIT License](LICENSE.md).
