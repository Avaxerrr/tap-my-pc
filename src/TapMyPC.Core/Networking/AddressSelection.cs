namespace TapMyPC.Core.Networking;

public record NetworkAddress(string Address, string Name, bool IsWifi, bool HasGateway, bool IsTailscale = false)
{
    public string Label => Address switch
    {
        "auto" => "Automatic network address (recommended)",
        "127.0.0.1" => "This PC only · localhost (debugging)",
        _ => IsTailscale ? $"Tailscale · {Address} (remote access)" : $"{Name} · {Address}"
    };
}

public static class AddressSelection
{
    public const string Automatic = "auto";
    public static string Resolve(string? selected, IEnumerable<NetworkAddress> available)
    {
        var candidates = available.ToArray();
        if (selected == "127.0.0.1") return selected;
        if (!string.IsNullOrWhiteSpace(selected) && selected != Automatic && candidates.Any(a => a.Address == selected)) return selected;
        if (TailscaleNetwork.IsAddress(selected))
            throw new InvalidOperationException("Waiting for the selected Tailscale address. Connect Tailscale on this PC, or select another adapter in Advanced settings.");
        return candidates.Where(a => !a.IsTailscale).OrderByDescending(a => a.HasGateway).ThenByDescending(a => a.IsWifi).FirstOrDefault()?.Address
            ?? throw new InvalidOperationException("No active private network address was found. Connect to Wi-Fi or select localhost in Advanced settings.");
    }
}
