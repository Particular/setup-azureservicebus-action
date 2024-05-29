using Azure.Messaging.ServiceBus;
using Azure.Messaging.ServiceBus.Administration;
using NUnit.Framework;

namespace Tests;

[TestFixture]
public class ConnectionStringTests
{
    [Test]
    public async Task Should_establish_connection_with_manage_rights()
    {
        var client = new ServiceBusAdministrationClient(Environment.GetEnvironmentVariable("ASBConnectionString"));
        await client.CreateQueueAsync("testqueue");
    }
    
    [Test]
    public async Task Should_have_send_claims_with_manage_rights()
    {
        await CreateQueueWithManageRightsIfNotExists();
        
        await using var client = new ServiceBusClient(Environment.GetEnvironmentVariable("ASBConnectionString"));
        var sender = client.CreateSender("testqueue");
        await sender.SendMessageAsync(new ServiceBusMessage(nameof(Should_have_send_claims_with_manage_rights)));
    }

    [Test]
    public async Task Should_have_receive_claims_with_manage_rights()
    {
        await CreateQueueWithManageRightsIfNotExists();

        await using var client = new ServiceBusClient(Environment.GetEnvironmentVariable("ASBConnectionString"));
        var receiver = client.CreateReceiver("testqueue");
        await receiver.ReceiveMessageAsync(TimeSpan.FromMilliseconds(500));
    }
    
    async Task CreateQueueWithManageRightsIfNotExists()
    {
        var serviceBusAdminClient = new ServiceBusAdministrationClient(Environment.GetEnvironmentVariable("ASBConnectionString"));
        if (!await serviceBusAdminClient.QueueExistsAsync("testqueue"))
        {
            await serviceBusAdminClient.CreateQueueAsync("testqueue");            
        }
    }

    [Test]
    public void Should_establish_connection_without_manage_rights()
    {
        var client = new ServiceBusAdministrationClient(Environment.GetEnvironmentVariable("ASBConnectionString_Restricted"));
        Assert.ThrowsAsync<UnauthorizedAccessException>(async () => await client.CreateQueueAsync("testqueue"));
    }
    
    [Test]
    public async Task Should_have_send_claims_without_manage_rights()
    {
        await CreateQueueWithManageRightsIfNotExists();
        
        await using var client = new ServiceBusClient(Environment.GetEnvironmentVariable("ASBConnectionString_Restricted"));
        var sender = client.CreateSender("testqueue");
        await sender.SendMessageAsync(new ServiceBusMessage(nameof(Should_have_send_claims_without_manage_rights)));
    }

    [Test]
    public async Task Should_have_receive_claims_without_manage_rights()
    {
        await CreateQueueWithManageRightsIfNotExists();

        await using var client = new ServiceBusClient(Environment.GetEnvironmentVariable("ASBConnectionString_Restricted"));
        var receiver = client.CreateReceiver("testqueue");
        await receiver.ReceiveMessageAsync(TimeSpan.FromMilliseconds(500));
    }
}