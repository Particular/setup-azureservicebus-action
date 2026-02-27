const path = require('path');
const core = require('@actions/core');
const exec = require('@actions/exec');

const setupPs1 = path.resolve(__dirname, '../setup.ps1');
const cleanupPs1 = path.resolve(__dirname, '../cleanup.ps1');

console.log('Setup path: ' + setupPs1);
console.log('Cleanup path: ' + cleanupPs1);

const isPost = core.getState('IsPost');
core.saveState('IsPost', true);

const connectionStringName = core.getInput('connection-string-name');
const azureCredentials = core.getInput('azure-credentials');
const tagName = core.getInput('tag');
const useEmulator = core.getBooleanInput('use-emulator');
const emulatorHost = core.getInput('emulator-host') || 'localhost';
const emulatorAmqpPort = core.getInput('emulator-amqp-port') || '5672';
const emulatorHttpPort = core.getInput('emulator-http-port') || '5300';
const emulatorSqlPassword = core.getInput('emulator-sql-password') || 'StrongP@ssword!123';

async function run() {
    try {
        if (!isPost) {
            console.log('Running setup action');

            await exec.exec('pwsh', [
                '-File', setupPs1,
                '-connectionStringName', connectionStringName,
                '-tagName', tagName,
                '-azureCredentials', azureCredentials,
                '-useEmulator', useEmulator ? 'true' : 'false',
                '-emulatorHost', emulatorHost,
                '-emulatorAmqpPort', emulatorAmqpPort,
                '-emulatorHttpPort', emulatorHttpPort,
                '-emulatorSqlPassword', emulatorSqlPassword
            ]);
        } else {
            console.log('Running cleanup');

            await exec.exec('pwsh', [
                '-File', cleanupPs1,
                '-ASBName', core.getState('ASBName'),
                '-useEmulator', core.getState('UseEmulator'),
                '-useAciEmulator', core.getState('UseAciEmulator'),
                '-emulatorAssetPath', core.getState('EmulatorAssetPath'),
                '-emulatorComposeFilePath', core.getState('EmulatorComposeFilePath')
            ]);
        }
    } catch (err) {
        core.setFailed(err);
        console.log(err);
    }
}

run();
