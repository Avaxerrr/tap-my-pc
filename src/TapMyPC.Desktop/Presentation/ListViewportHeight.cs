using System.Globalization;
using System.Windows.Data;

namespace TapMyPC.Desktop.Presentation;

public sealed class ListViewportHeight : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is double height ? Math.Clamp(height * 0.18, 110, 320) : 130d;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
