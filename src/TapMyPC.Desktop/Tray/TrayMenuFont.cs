using System.Drawing;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;

namespace TapMyPC.Desktop.Tray;

// GDI+ private fonts are local to this process; no Windows font installation is needed.
internal sealed class TrayMenuFont : IDisposable
{
    private readonly PrivateFontCollection collection = new();
    private nint memory;
    public Font Font { get; }
    public TrayMenuFont()
    {
        try
        {
            using var source = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/TapMyPC;component/Assets/Fonts/Inter_18pt-Regular.ttf")).Stream;
            using var buffer = new MemoryStream();
            source.CopyTo(buffer);
            var bytes = buffer.ToArray();
            memory = Marshal.AllocHGlobal(bytes.Length);
            Marshal.Copy(bytes, 0, memory, bytes.Length);
            collection.AddMemoryFont(memory, bytes.Length);
            Font = new Font(collection.Families[0], 10, FontStyle.Regular, GraphicsUnit.Point);
        }
        catch
        {
            collection.Dispose();
            if (memory != nint.Zero) Marshal.FreeHGlobal(memory);
            throw;
        }
    }
    public void Dispose()
    {
        Font.Dispose(); collection.Dispose();
        if (memory == nint.Zero) return;
        Marshal.FreeHGlobal(memory); memory = nint.Zero;
    }
}
