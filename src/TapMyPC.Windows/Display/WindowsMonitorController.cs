using System.ComponentModel;
using System.Management;
using System.Runtime.InteropServices;
using TapMyPC.Core.Display;

namespace TapMyPC.Windows.Display;

public sealed class WindowsMonitorController : IMonitorController
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private IReadOnlyList<MonitorStatus> cached = [];
    private DateTimeOffset refreshedAt;

    public async Task<IReadOnlyList<MonitorStatus>> ListAsync()
    {
        await gate.WaitAsync();
        try
        {
            if (DateTimeOffset.UtcNow - refreshedAt < TimeSpan.FromSeconds(3)) return cached;
            cached = await Task.Run(() => WithPanels(ReadPanels));
            refreshedAt = DateTimeOffset.UtcNow;
            return cached;
        }
        finally { gate.Release(); }
    }

    public Task SetBrightnessAsync(string id, int brightness) => ChangeAsync(() => WithPanels(panels =>
    {
        if (brightness is < 0 or > 100) throw new ArgumentException("Brightness must be 0–100.");
        var panel = panels.SingleOrDefault(p => p.Id == id) ?? throw new ArgumentException("Monitor disconnected. Refresh devices.");
        var wmi = MatchWmi(panel, panels.Count, ReadWmi());
        if (wmi is not null)
        {
            using var search = new ManagementObjectSearcher(@"root\wmi", "SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE");
            using var results = search.Get();
            foreach (ManagementObject method in results)
            {
                using (method)
                {
                    if ((string)method["InstanceName"] != wmi.Instance) continue;
                    var result = method.InvokeMethod("WmiSetBrightness", new object[] { 0u, (byte)brightness });
                    if (Convert.ToUInt32(result) != 0) throw new InvalidOperationException("Windows rejected the brightness change.");
                    return true;
                }
            }
            throw new NotSupportedException("Windows brightness control is no longer available.");
        }
        if (panel.Handle is not null && !GetMonitorBrightness(panel.Handle.Value, out _, out _, out _) &&
            GetVCPFeatureAndVCPFeatureReply(panel.Handle.Value, 0x10, out _, out _, out var vcpMax) && vcpMax > 0)
        {
            if (!SetVCPFeature(panel.Handle.Value, 0x10, (uint)Math.Round(vcpMax * brightness / 100d)))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return true;
        }
        if (panel.Handle is null || !GetMonitorBrightness(panel.Handle.Value, out var min, out _, out var max) || max <= min)
            throw new NotSupportedException("This monitor does not expose brightness control. Check DDC/CI in its settings.");
        var value = min + (uint)Math.Round((max - min) * brightness / 100d);
        if (!SetMonitorBrightness(panel.Handle.Value, value)) throw new Win32Exception(Marshal.GetLastWin32Error());
        return true;
    }));

    public Task SetPowerAsync(string id, bool enabled) => ChangeAsync(() => WithPanels(panels =>
    {
        var panel = panels.SingleOrDefault(p => p.Id == id) ?? throw new NotSupportedException("The display is unreachable. It may need its physical power button.");
        if (panel.Handle is null) throw new NotSupportedException("This monitor does not expose individual power control.");
        // DPM off (04), not hard power-off (05), to preserve DDC communication where supported.
        if (!SetVCPFeature(panel.Handle.Value, 0xD6, enabled ? 1u : 4u)) throw new Win32Exception(Marshal.GetLastWin32Error());
        var previous = cached.FirstOrDefault(m => m.Id == id);
        if (previous is not null) cached = cached.Select(m => m.Id == id ? m with { IsOn = enabled } : m).ToArray();
        return true;
    }));

    private async Task ChangeAsync(Action action)
    {
        await gate.WaitAsync();
        try { await Task.Run(action); }
        finally { refreshedAt = DateTimeOffset.MinValue; gate.Release(); }
    }

    private IReadOnlyList<MonitorStatus> ReadPanels(List<Panel> panels)
    {
        var wmi = ReadWmi();
        var result = new List<MonitorStatus>();
        foreach (var panel in panels)
        {
            int? brightness = null;
            if (panel.Handle is not null && GetMonitorBrightness(panel.Handle.Value, out var min, out var current, out var max) && max > min)
                brightness = (int)Math.Clamp(Math.Round((current - (double)min) * 100 / (max - min)), 0, 100);
            if (brightness is null && panel.Handle is not null &&
                GetVCPFeatureAndVCPFeatureReply(panel.Handle.Value, 0x10, out _, out var vcpCurrent, out var vcpMax) && vcpMax > 0)
                brightness = (int)Math.Clamp(Math.Round(vcpCurrent * 100d / vcpMax), 0, 100);
            var builtIn = MatchWmi(panel, panels.Count, wmi);
            if (builtIn is not null) brightness = builtIn.Brightness;
            uint powerState = 0;
            var power = panel.Handle is not null && GetVCPFeatureAndVCPFeatureReply(panel.Handle.Value, 0xD6, out _, out powerState, out _);
            bool? isOn = null;
            if (power) isOn = powerState == 1 ? true : powerState is >= 2 and <= 5 ? false : null;
            var previous = cached.FirstOrDefault(m => m.Id == panel.Id);
            if (!power && previous is { CanSetPower: true, IsOn: false })
            { power = true; isOn = false; }
            var message = brightness is null && !power ? "Brightness and individual power control are unavailable. Check DDC/CI in the monitor settings."
                : !power ? "Individual power control is unavailable for this display."
                : "Some monitors need their physical button to wake after being turned off.";
            result.Add(new(panel.Id, panel.Name, brightness, brightness is not null, power, isOn, message));
        }
        foreach (var previous in cached.Where(m => m.IsOn == false && result.All(n => n.Id != m.Id)))
            result.Add(previous with { CanSetBrightness = false, CanSetPower = false, Message = "Display is unreachable. Use its physical button to wake it, then refresh." });
        return result;
    }

    private sealed record WmiPanel(string Instance, int Brightness);
    private static List<WmiPanel> ReadWmi()
    {
        var result = new List<WmiPanel>();
        try
        {
            using var search = new ManagementObjectSearcher(@"root\wmi", "SELECT * FROM WmiMonitorBrightness WHERE Active=TRUE");
            using var rows = search.Get();
            foreach (ManagementObject row in rows)
                using (row) result.Add(new((string)row["InstanceName"], Convert.ToInt32(row["CurrentBrightness"])));
        }
        catch (Exception ex) when (ex is ManagementException or COMException or UnauthorizedAccessException) { }
        return result;
    }
    private static WmiPanel? MatchWmi(Panel panel, int count, List<WmiPanel> rows) =>
        rows.FirstOrDefault(r => Normalize(panel.DevicePath).StartsWith(Normalize(r.Instance), StringComparison.OrdinalIgnoreCase))
        ?? (count == 1 && rows.Count == 1 ? rows[0] : null);
    private static string Normalize(string id)
    {
        id = id.Replace('#', '\\').TrimStart('\\', '?');
        var suffix = id.LastIndexOf('_');
        if (suffix >= 0 && int.TryParse(id[(suffix + 1)..], out _)) id = id[..suffix];
        return id;
    }

    // DXVA2 may return a valid physical-monitor handle of zero. Null means
    // enumeration failed; never infer availability from the numeric handle.
    private sealed record Panel(string Id, string Name, string DevicePath, IntPtr? Handle);
    private static T WithPanels<T>(Func<List<Panel>, T> action)
    {
        var panels = new List<Panel>();
        var owned = new List<PhysicalMonitor[]>();
        try
        {
            MonitorEnum callback = (IntPtr monitor, IntPtr dc, ref Rect rect, IntPtr data) =>
            {
                var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
                if (!GetMonitorInfo(monitor, ref info)) return true;
                var device = new DisplayDevice { Size = Marshal.SizeOf<DisplayDevice>() };
                var path = EnumDisplayDevices(info.Device, 0, ref device, 1) && !string.IsNullOrEmpty(device.Id) ? device.Id : info.Device;
                if (GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out var count) && count > 0)
                {
                    var physical = new PhysicalMonitor[count];
                    if (GetPhysicalMonitorsFromHMONITOR(monitor, count, physical))
                    {
                        owned.Add(physical);
                        for (var i = 0; i < physical.Length; i++)
                            panels.Add(new($"monitor:{path}:{i}", $"{info.Device.Replace(@"\\.\", "")} · {physical[i].Description}", path, physical[i].Handle));
                        return true;
                    }
                }
                panels.Add(new($"monitor:{path}:0", info.Device.Replace(@"\\.\", ""), path, null));
                return true;
            };
            if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return action(panels);
        }
        finally
        {
            foreach (var physical in owned) DestroyPhysicalMonitors((uint)physical.Length, physical);
        }
    }

    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public int Size; public Rect Monitor, Work; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DisplayDevice
    {
        public int Size;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Key;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PhysicalMonitor
    {
        public IntPtr Handle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
    }
    private delegate bool MonitorEnum(IntPtr monitor, IntPtr dc, ref Rect rect, IntPtr data);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorEnum callback, IntPtr data);
    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll", EntryPoint = "EnumDisplayDevicesW", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayDevices(string name, uint index, ref DisplayDevice device, uint flags);
    [DllImport("dxva2.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);
    [DllImport("dxva2.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, [Out] PhysicalMonitor[] physical);
    [DllImport("dxva2.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyPhysicalMonitors(uint count, PhysicalMonitor[] physical);
    [DllImport("dxva2.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorBrightness(IntPtr monitor, out uint min, out uint current, out uint max);
    [DllImport("dxva2.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetMonitorBrightness(IntPtr monitor, uint brightness);
    [DllImport("dxva2.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr monitor, byte code, out uint type, out uint current, out uint max);
    [DllImport("dxva2.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetVCPFeature(IntPtr monitor, byte code, uint value);
}
