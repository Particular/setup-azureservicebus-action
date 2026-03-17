using Azure.Messaging.ServiceBus;
using Azure.Messaging.ServiceBus.Administration;
using NUnit.Framework;

namespace Tests;

[TestFixture]
public class ConnectionStringTests
{
    static bool UseEmulator => string.Equals(Environment.GetEnvironmentVariable("ASBUseEmulator"), "true", StringComparison.OrdinalIgnoreCase);
    static string RuntimeConnectionString => Environment.GetEnvironmentVariable("ASBConnectionString")!;
    static string AdminConnectionString => Environment.GetEnvironmentVariable("ASBConnectionString_Admin") ?? RuntimeConnectionString;

    [Test]
    public async Task Should_establish_connection_with_manage_rights()
    {
        var client = new ServiceBusAdministrationClient(AdminConnectionString);
        await client.CreateQueueAsync("testqueue");
    }
    
    [Test]
    public async Task Should_have_send_claims_with_manage_rights()
    {
        await CreateQueueWithManageRightsIfNotExists();
        
        await using var client = new ServiceBusClient(RuntimeConnectionString);
        var sender = client.CreateSender("testqueue");
        await sender.SendMessageAsync(new ServiceBusMessage(nameof(Should_have_send_claims_with_manage_rights)));
    }

    [Test]
    public async Task Should_have_receive_claims_with_manage_rights()
    {
        await CreateQueueWithManageRightsIfNotExists();

        await using var client = new ServiceBusClient(RuntimeConnectionString);
        var receiver = client.CreateReceiver("testqueue");
        await receiver.ReceiveMessageAsync(TimeSpan.FromMilliseconds(500));
    }
    
    async Task CreateQueueWithManageRightsIfNotExists()
    {
        var serviceBusAdminClient = new ServiceBusAdministrationClient(AdminConnectionString);
        if (!await serviceBusAdminClient.QueueExistsAsync("testqueue"))
        {
            await serviceBusAdminClient.CreateQueueAsync("testqueue");            
        }
    }

    [Test]
    public void Should_establish_connection_without_manage_rights()
    {
        if (UseEmulator)
        {
            Assert.Ignore("Emulator does not expose a restricted SAS rule in this action.");
        }

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
