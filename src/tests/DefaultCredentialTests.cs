using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Azure.Messaging.ServiceBus.Administration;
using NUnit.Framework;

namespace Tests;

[TestFixture]
public class DefaultCredentialTests
{
    string fullyQualifiedNamespace;
    bool useEmulator;

    [SetUp]
    public void Setup()
    {
        useEmulator = string.Equals(Environment.GetEnvironmentVariable("ASBUseEmulator"), "true", StringComparison.OrdinalIgnoreCase);

        if (useEmulator)
        {
            Assert.Ignore("DefaultAzureCredential tests are only valid for Azure-hosted Service Bus.");
        }

        var connectionString = Environment.GetEnvironmentVariable("ASBConnectionString_Admin")
                               ?? Environment.GetEnvironmentVariable("ASBConnectionString");
        
        fullyQualifiedNamespace = ServiceBusConnectionStringProperties.Parse(connectionString).FullyQualifiedNamespace;      
    }
    
    [Test]
    public async Task Should_establish_connection_with_manage_rights()
    {
        var serviceBusAdminClient = new ServiceBusAdministrationClient(fullyQualifiedNamespace, new DefaultAzureCredential());
        await serviceBusAdminClient.CreateQueueAsync("testqueuedefault");
    }
    
    [Test]
    public async Task Should_have_send_claims()
    {
        await CreateQueueIfNotExists();

        await using var client = new ServiceBusClient(fullyQualifiedNamespace, new DefaultAzureCredential());
        var sender = client.CreateSender("testqueuedefault");
        await sender.SendMessageAsync(new ServiceBusMessage(nameof(Should_have_send_claims)));
    }

    [Test]
    public async Task Should_have_receive_claims()
    {
        await CreateQueueIfNotExists();

        await using var client = new ServiceBusClient(fullyQualifiedNamespace, new DefaultAzureCredential());
        var receiver = client.CreateReceiver("testqueuedefault");
        await receiver.ReceiveMessageAsync(TimeSpan.FromMilliseconds(500));
    }
    
    async Task CreateQueueIfNotExists()
    {
        var serviceBusAdminClient = new ServiceBusAdministrationClient(fullyQualifiedNamespace, new DefaultAzureCredential());
        if (!await serviceBusAdminClient.QueueExistsAsync("testqueuedefault"))
        {
            await serviceBusAdminClient.CreateQueueAsync("testqueuedefault");            
        }
    }
}
