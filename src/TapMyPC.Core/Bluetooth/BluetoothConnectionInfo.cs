namespace TapMyPC.Core.Bluetooth;

public sealed record BluetoothConnectionInfo(bool Available, string? Address, string ServiceId, string? Message = null)
{
    public const string ServiceUuid = "8cf69287-4d5e-47f1-97c8-0a4ec3b5d290";
}
