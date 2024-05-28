using Azure.Core.Diagnostics;
using Azure.Identity;
using Azure.Messaging.ServiceBus;
using Azure.Messaging.ServiceBus.Administration;
using NUnit.Framework;

namespace Tests;

[TestFixture]
public class DefaultCredentialTests
{
    [Test]
    public async Task Should_establish_connection_with_manage_rights()
    {
        var connectionString = Environment.GetEnvironmentVariable("ASBConnectionString");
        
        var properties = ServiceBusConnectionStringProperties.Parse(connectionString);      
       
        var client = new ServiceBusAdministrationClient(properties.FullyQualifiedNamespace, new DefaultAzureCredential());
        await client.CreateQueueAsync("testqueuedefault");
    }
}