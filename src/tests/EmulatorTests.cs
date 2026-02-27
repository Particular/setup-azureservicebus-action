using NUnit.Framework;

namespace Tests;

[TestFixture]
public class EmulatorTests
{
    static bool UseEmulator => string.Equals(Environment.GetEnvironmentVariable("ASBUseEmulator"), "true", StringComparison.OrdinalIgnoreCase);

    [Test]
    public void Should_expose_emulator_connection_strings()
    {
        if (!UseEmulator)
        {
            Assert.Ignore("Runs only for emulator mode.");
        }

        var runtimeConnectionString = Environment.GetEnvironmentVariable("ASBConnectionString");
        var adminConnectionString = Environment.GetEnvironmentVariable("ASBConnectionString_Admin");

        Assert.That(runtimeConnectionString, Is.Not.Null.And.Contains("UseDevelopmentEmulator=true"));
        Assert.That(adminConnectionString, Is.Not.Null.And.Contains("UseDevelopmentEmulator=true"));
        Assert.That(adminConnectionString, Is.Not.EqualTo(runtimeConnectionString));
    }

    [Test]
    public async Task Should_report_emulator_health()
    {
        if (!UseEmulator)
        {
            Assert.Ignore("Runs only for emulator mode.");
        }

        var adminConnectionString = Environment.GetEnvironmentVariable("ASBConnectionString_Admin")!;
        var endpoint = ExtractEndpoint(adminConnectionString);
        var healthUrl = $"http://{endpoint}/health";

        using var client = new HttpClient();
        var response = await client.GetAsync(healthUrl);

        Assert.That(response.IsSuccessStatusCode, Is.True, $"Health endpoint failed: {healthUrl}");
    }

    static string ExtractEndpoint(string connectionString)
    {
        var endpointSegment = connectionString.Split(';', StringSplitOptions.RemoveEmptyEntries)
            .First(part => part.StartsWith("Endpoint=", StringComparison.OrdinalIgnoreCase));

        var endpointValue = endpointSegment.Substring("Endpoint=".Length);
        return endpointValue.Replace("sb://", string.Empty, StringComparison.OrdinalIgnoreCase).TrimEnd('/');
    }
}
