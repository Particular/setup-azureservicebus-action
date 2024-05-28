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
    public void Should_establish_connection_without_manage_rights()
    {
        var client = new ServiceBusAdministrationClient(Environment.GetEnvironmentVariable("ASBConnectionString_Restricted"));
        Assert.ThrowsAsync<UnauthorizedAccessException>(async () => await client.CreateQueueAsync("testqueue"));
    }
}