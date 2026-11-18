using System.IO;
using System.Windows.Media.Imaging;
using QRCoder;

namespace TapMyPC.Desktop.Features.Settings;

public static class PairingQrImage
{
    public static byte[] Encode(string payload) =>
        PngByteQRCodeHelper.GetQRCode(payload, QRCodeGenerator.ECCLevel.M, 8);
    public static BitmapSource Create(string payload)
    {
        using var stream = new MemoryStream(Encode(payload));
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }
}
