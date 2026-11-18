using System.Text.Json;
using TapMyPC.Core.Devices;

namespace TapMyPC.Api.Contracts;

public static class PairingInvitation
{
    public static string CreateJson(string name, string address, string fingerprint, PairingSession session) =>
        JsonSerializer.Serialize(new
        {
            type = "tapmypc-pair", version = 1, name, address, fingerprint,
            secret = session.QrSecret, expiresAt = session.ExpiresAt
        });
}
