using System.Collections;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using TapMyPC.Core.Networking;

namespace TapMyPC.Windows.Settings;

public static class NetworkTrust
{
    public static bool IsTrusted(IPAddress address, bool allowTailscale = false)
    {
        if (IPAddress.IsLoopback(address)) return true;
        var adapter = NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n =>
            n.GetIPProperties().UnicastAddresses.Any(a => a.Address.Equals(address)));
        if (adapter is null || adapter.OperationalStatus != OperationalStatus.Up) return false;
        if (TailscaleNetwork.IsAdapter(address.ToString(), adapter.Name, adapter.Description)) return allowTailscale;
        if (!Guid.TryParse(adapter.Id, out var adapterId)) return false;
        object? manager = null, networks = null;
        try
        {
            var type = Type.GetTypeFromCLSID(new Guid("DCB00C01-570F-4A9B-8D69-199FDBA5723B"), true)!;
            manager = Activator.CreateInstance(type)!;
            networks = ((dynamic)manager).GetNetworks(1); // connected networks
            foreach (var network in (IEnumerable)networks)
            {
                object? connections = null;
                try
                {
                    var category = (int)((dynamic)network).GetCategory();
                    connections = ((dynamic)network).GetNetworkConnections();
                    foreach (var connection in (IEnumerable)connections)
                    {
                        try
                        {
                            Marshal.ThrowExceptionForHR(((INetworkConnection)connection).GetAdapterId(out var currentAdapter));
                            if (currentAdapter == adapterId)
                                return category is 1 or 2; // Private or DomainAuthenticated
                        }
                        finally { Release(connection); }
                    }
                }
                finally { Release(connections); Release(network); }
            }
            return false;
        }
        catch (Exception ex) when (ex is COMException or ArgumentException or InvalidCastException or Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
        { return false; }
        finally { Release(networks); Release(manager); }
    }
    // GetAdapterId returns a GUID, which the Automation binder cannot marshal.
    // Use the typed dual-interface vtable from the Windows SDK instead.
    [ComImport, Guid("DCB00005-570F-4A9B-8D69-199FDBA5723B"), InterfaceType(ComInterfaceType.InterfaceIsDual)]
    private interface INetworkConnection
    {
        [PreserveSig] int GetNetwork();
        [PreserveSig] int GetIsConnectedToInternet();
        [PreserveSig] int GetIsConnected();
        [PreserveSig] int GetConnectivity();
        [PreserveSig] int GetConnectionId();
        [PreserveSig] int GetAdapterId(out Guid adapterId);
    }
    private static void Release(object? value) { if (value is not null && Marshal.IsComObject(value)) Marshal.ReleaseComObject(value); }
}
