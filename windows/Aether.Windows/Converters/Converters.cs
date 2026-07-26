using System.Globalization;
using System.Windows.Data;

namespace Aether.Windows.Converters;

/// <summary>
/// Unix 毫秒时间戳 → 可读时间字符串。
/// ConverterParameter 指定格式（默认 "HH:mm"），如 "MM-dd HH:mm"。
/// </summary>
public class UnixTimeConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is long ms && ms > 0)
        {
            var dt = DateTimeOffset.FromUnixTimeMilliseconds(ms).ToLocalTime();
            var format = parameter as string ?? "HH:mm";
            return dt.ToString(format, culture);
        }
        return "";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// 布尔值反转 → Visibility。true → Collapsed，false → Visible。
/// 用于 PasswordBox / TextBox 切换显示等场景。
/// </summary>
public class InverseBooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is bool b)
        {
            return b ? System.Windows.Visibility.Collapsed : System.Windows.Visibility.Visible;
        }
        return System.Windows.Visibility.Visible;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// 字符串非空 → Visible，空字符串 → Collapsed。
/// 用于错误消息栏等仅在内容存在时显示的场景。
/// </summary>
public class NonEmptyToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is string s && !string.IsNullOrEmpty(s))
        {
            return System.Windows.Visibility.Visible;
        }
        return System.Windows.Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}
