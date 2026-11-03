$ErrorActionPreference = 'Stop'

# Temporary: Azure CLI 2.91.0 is the latest release but its Python 3.14 runtime
# hits an import deadlock during namespace creation (Azure/azure-cli#33996).
# Remove this installer once a release containing Azure/azure-cli#34201 is published.
# Follow the same workaround as Particular/ServiceControl#6014.
$version = '2.90.0'

Write-Output "Installing Azure CLI $version until the import deadlock fix is published."

switch ($env:RUNNER_OS) {
    'Linux' {
        $distribution = lsb_release -cs
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to determine the Linux distribution.'
        }
        $architecture = dpkg --print-architecture
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to determine the package architecture.'
        }

        $deb = "azure-cli_${version}-1~${distribution}_${architecture}.deb"
        $debPath = Join-Path $env:RUNNER_TEMP $deb
        curl --fail --silent --show-error --location --output $debPath "https://packages.microsoft.com/repos/azure-cli/pool/main/a/azure-cli/$deb"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to download Azure CLI $version."
        }
        sudo apt-get install -y --allow-downgrades $debPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install Azure CLI $version."
        }
    }
    'Windows' {
        # The MSI refuses to downgrade the newer CLI on the runner image. Put the
        # ZIP distribution first on PATH for this process, later steps and cleanup.
        $zip = Join-Path $env:RUNNER_TEMP "azure-cli-$version-x64.zip"
        $directory = Join-Path $env:RUNNER_TEMP "azure-cli-$version"
        Invoke-WebRequest -Uri "https://azcliprod.blob.core.windows.net/zip/azure-cli-$version-x64.zip" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $directory -Force
        $bin = Join-Path $directory 'bin'
        $env:PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"
        $bin | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
    }
    default {
        throw "The temporary Azure CLI pin supports Windows and Linux GitHub-hosted runners, not '$($env:RUNNER_OS)'."
    }
}

$installed = az version | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $installed.'azure-cli' -ne $version) {
    throw "Expected Azure CLI $version after installation."
}
Write-Output "Using Azure CLI $($installed.'azure-cli')."
