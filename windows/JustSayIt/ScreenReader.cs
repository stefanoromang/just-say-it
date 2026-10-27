// Just Say It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Storage.Streams;

namespace JustSayIt;

/// Reads the visible text of the user's window with Windows' built-in, offline OCR.
public static class ScreenReader
{
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    public static bool Available => OcrEngine.TryCreateFromUserProfileLanguages() != null;

    public static async Task<string?> Read(IntPtr hwnd)
    {
        try
        {
            if (hwnd == IntPtr.Zero || IsIconic(hwnd) || !GetWindowRect(hwnd, out var r)) return null;
            int w = r.Right - r.Left, h = r.Bottom - r.Top;
            if (w < 200 || h < 150) return null;
            using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                var hdc = g.GetHdc();
                // PW_RENDERFULLCONTENT (2) captures Chromium/Electron/UWP windows too.
                bool ok = PrintWindow(hwnd, hdc, 2);
                g.ReleaseHdc(hdc);
                if (!ok) g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, h));
            }
            var engine = OcrEngine.TryCreateFromUserProfileLanguages();
            if (engine == null) return null;
            using var soft = await ToSoftwareBitmap(bmp);
            var result = await engine.RecognizeAsync(soft);
            var lines = result.Lines.Select(l => l.Text).Where(t => t.Length > 2);
            var text = string.Join("\n", lines);
            return text.Length == 0 ? null : (text.Length > 4000 ? text[..4000] : text);
        }
        catch { return null; }
    }

    static async Task<SoftwareBitmap> ToSoftwareBitmap(Bitmap bmp)
    {
        using var ms = new MemoryStream();
        bmp.Save(ms, ImageFormat.Png);
        ms.Position = 0;
        using var ras = new InMemoryRandomAccessStream();
        await ras.WriteAsync(ms.ToArray().AsBuffer());
        ras.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(ras);
        return await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
    }
}
