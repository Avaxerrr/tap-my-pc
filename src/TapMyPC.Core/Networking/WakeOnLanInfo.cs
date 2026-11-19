using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;

namespace TapMyPC.Core.Networking;

public sealed record WakeOnLanInfo(string Mac, string Destination, int Port = 9)
{
    public static WakeOnLanInfo? FromAdapter(IPAddress address, int prefixLength, byte[] mac)
    {
        if (address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(address) ||
            prefixLength is < 1 or > 30 || mac.Length != 6 || (mac[0] & 1) != 0 ||
            mac.All(octet => octet == 0))
            return null;

        var broadcast = address.GetAddressBytes();
        var hostBits = uint.MaxValue >> prefixLength;
        BinaryPrimitives.WriteUInt32BigEndian(broadcast,
            BinaryPrimitives.ReadUInt32BigEndian(broadcast) | hostBits);
        return new(string.Join(":", mac.Select(octet => octet.ToString("X2"))),
            new IPAddress(broadcast).ToString());
    }
}
