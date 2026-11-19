namespace TapMyPC.Core.Networking;

/// <summary>Authenticated location hints; clients must still verify TLS identity before using them.</summary>
public sealed record NetworkConnectionInfo(string? LocalAddress, string? TailscaleAddress);
