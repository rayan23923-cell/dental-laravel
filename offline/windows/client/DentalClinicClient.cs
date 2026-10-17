// Dental Clinic client (2026-10-17, by request): the program for the other
// computers on the clinic network. A window around Microsoft Edge WebView2
// that opens the offline server (https://clinic.lan by default) and adds what
// a plain browser cannot do:
//   - prints with no dialog: window.print() in any page, frame or pop-up comes
//     here; tickets (pages whose @page is a paper roll) go to the thermal
//     printer through the Windows driver, USB direct (ESC/POS over winspool
//     RAW, works with "Generic / Text Only"), the network (IP:9100) or
//     Bluetooth (the paired printer's COM port); other pages go to the
//     documents printer;
//   - keeps the login: its own WebView2 profile under %LOCALAPPDATA%;
//   - trusts the clinic certificate by itself: downloads the server's Caddy
//     root from http://<server>/ca.crt and installs it, and accepts a TLS
//     error only for a certificate that chains to that root;
//   - updates itself from the server it is connected to (/client/).
// See offline/README.md.
//
// Built with the .NET Framework compiler that ships with Windows (C# 5), see
// .github/workflows/offline-windows.yml (job "client"):
//   csc /target:winexe /codepage:65001 /win32icon:icon.ico /win32manifest:app.manifest
//       /r:Microsoft.Web.WebView2.Core.dll /r:Microsoft.Web.WebView2.WinForms.dll
//       /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Management.dll
//       /r:System.Core.dll /r:System.Web.Extensions.dll DentalClinicClient.cs
// WebView2Loader.dll sits in x64\ and x86\ next to the exe.
//
// Command line: --install-cert [--server NAME] [--ip IP] (from the installer,
// elevated: saves the server and puts its certificate in the machine's
// store), --selftest <dir> [--raw-printer NAME] (CI: renders a test ticket,
// writes the image, the ESC/POS bytes and a PDF, optionally prints RAW),
// --devtools (allow F12).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.IO.Ports;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

[assembly: System.Reflection.AssemblyTitle("Dental Clinic")]
[assembly: System.Reflection.AssemblyProduct("Dental Clinic Client")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

namespace DentalClinicClient
{
    static class BuildInfo
    {
        // The offline build number; the workflow writes it before compiling.
        public const int Build = 0;
    }

    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var list = new List<string>(args);
            try
            {
                CoreWebView2Environment.SetLoaderDllFolderPath(Path.Combine(Paths.ExeDir, Environment.Is64BitProcess ? "x64" : "x86"));
            }
            catch { }

            if (list.Contains("--install-cert")) return InstallFromSetup(list);

            int st = list.IndexOf("--selftest");
            if (st >= 0)
            {
                string dir = st + 1 < list.Count ? list[st + 1] : Path.Combine(Path.GetTempPath(), "dc-selftest");
                int rp = list.IndexOf("--raw-printer");
                string raw = rp >= 0 && rp + 1 < list.Count ? list[rp + 1] : null;
                var form = new SelfTestForm(dir, raw);
                Application.Run(form);
                return form.ExitCode;
            }

            // After "apply the server settings": wait for the old window to let go
            // of the single-instance lock and the browser profile.
            int wp = list.IndexOf("--wait-pid");
            if (wp >= 0 && wp + 1 < list.Count)
            {
                int pid;
                if (int.TryParse(list[wp + 1], out pid))
                {
                    try { using (var old = Process.GetProcessById(pid)) old.WaitForExit(15000); } catch { }
                }
            }

            bool created;
            using (var mutex = new Mutex(true, "DentalClinicClient-" + Environment.UserName, out created))
            {
                if (!created)
                {
                    // Already open: bring that window forward instead of a second profile lock.
                    NativeMethods.ActivateOther("Dental Clinic");
                    return 0;
                }
                App.Settings = ClientSettings.Load();
                App.DevTools = list.Contains("--devtools");
                Log.Write("start, build " + BuildInfo.Build + ", server " + App.Settings.Server + " " + App.Settings.ServerIp);
                Application.Run(new MainForm());
            }
            return 0;
        }

        // Run by the installer (elevated): remember the server typed in the
        // wizard and trust its certificate for every user of this computer.
        static int InstallFromSetup(List<string> args)
        {
            var s = ClientSettings.Load();
            int i = args.IndexOf("--server");
            if (i >= 0 && i + 1 < args.Count && args[i + 1].Trim().Length > 0) s.Server = ClientSettings.CleanHost(args[i + 1]);
            i = args.IndexOf("--ip");
            if (i >= 0 && i + 1 < args.Count) s.ServerIp = args[i + 1].Trim();
            try { s.Save(); } catch { }
            try
            {
                var root = CertHelper.Download(s);
                CertHelper.Save(root);
                CertHelper.Install(root, true);
                Log.Write("installer: certificate installed for the machine");
                return 0;
            }
            catch (Exception ex)
            {
                // Not fatal: the program tries again on its first start.
                Log.Write("installer: certificate not installed: " + ex.Message);
                return 0;
            }
        }
    }

    static class App
    {
        public static ClientSettings Settings;
        public static bool DevTools;
        public static CoreWebView2Environment Env;
        public static Renderer Renderer;
        public static PrintService Printing;
        public static MainForm Main;

        // One environment for every window, so they all share the login.
        public static async Task<CoreWebView2Environment> EnvAsync()
        {
            if (Env != null) return Env;
            Directory.CreateDirectory(Paths.LocalDir);
            var opts = new CoreWebView2EnvironmentOptions();
            opts.AdditionalBrowserArguments = Settings.BrowserArguments();
            opts.Language = "ar";
            Env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(Paths.LocalDir, "WebView2"), opts);
            Renderer = new Renderer();
            Printing = new PrintService();
            return Env;
        }

        public static bool IsServerUri(string uri)
        {
            Uri u;
            if (!Uri.TryCreate(uri, UriKind.Absolute, out u)) return false;
            var s = Settings;
            bool hostOk = string.Equals(u.Host, s.Server, StringComparison.OrdinalIgnoreCase) ||
                (s.ServerIp.Length > 0 && u.Host == s.ServerIp);
            return hostOk && (u.Scheme == "https" || u.Scheme == "http");
        }

        // Wires a WebView2 (main window or pop-up) to the app: printing
        // bridge, pop-ups inside the app, certificate check, shortcuts.
        public static async Task SetupView(WebView2 view, Form owner)
        {
            var core = view.CoreWebView2;
            core.Settings.AreDevToolsEnabled = DevTools;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.AreDefaultScriptDialogsEnabled = true;
            core.Settings.IsGeneralAutofillEnabled = true;
            core.Settings.IsPasswordAutosaveEnabled = true;
            Bridges[core] = await core.AddScriptToExecuteOnDocumentCreatedAsync(Bridge.Script(Settings));
            owner.FormClosed += (s, e) => Bridges.Remove(core);
            core.WebMessageReceived += (s, e) => OnMessage(core, owner, e);
            core.NewWindowRequested += (s, e) => OnNewWindow(owner, e);
            core.ServerCertificateErrorDetected += OnCertError;
            core.PermissionRequested += (s, e) =>
            {
                // The QR scanner uses the camera; allow it for the clinic server only.
                if (IsServerUri(e.Uri) && (e.PermissionKind == CoreWebView2PermissionKind.Camera ||
                    e.PermissionKind == CoreWebView2PermissionKind.ClipboardRead ||
                    e.PermissionKind == CoreWebView2PermissionKind.Notifications))
                    e.State = CoreWebView2PermissionState.Allow;
            };
        }

        static readonly Dictionary<CoreWebView2, string> Bridges = new Dictionary<CoreWebView2, string>();

        // The print settings are baked into the bridge script; after saving
        // them, swap the script in every open window (applies on next load).
        public static async Task RefreshBridges()
        {
            foreach (var core in Bridges.Keys.ToList())
            {
                try
                {
                    core.RemoveScriptToExecuteOnDocumentCreated(Bridges[core]);
                    Bridges[core] = await core.AddScriptToExecuteOnDocumentCreatedAsync(Bridge.Script(Settings));
                }
                catch { Bridges.Remove(core); }
            }
        }

        static void OnMessage(CoreWebView2 core, Form owner, CoreWebView2WebMessageReceivedEventArgs e)
        {
            Dictionary<string, object> msg;
            try { msg = Json.Parse(e.WebMessageAsJson) as Dictionary<string, object>; }
            catch { return; }
            if (msg == null) return;
            string type = Json.Str(msg, "type");
            if (type == "print")
            {
                // Only the clinic's own pages may print.
                if (!IsServerUri(e.Source)) return;
                var job = new PrintRequest
                {
                    Url = Json.Str(msg, "url"),
                    Ticket = Json.Bool(msg, "ticket"),
                    TopLevel = Json.Bool(msg, "top"),
                    Title = Json.Str(msg, "title"),
                    Source = core,
                    Owner = owner,
                };
                if (!IsServerUri(job.Url)) return;
                Printing.Enqueue(job);
            }
            else if (type == "key")
            {
                var main = owner as MainForm;
                string key = Json.Str(msg, "key");
                if (main != null) main.HandleKey(key);
                else if (key == "F5") core.Reload();
            }
            else if (type == "cmd" && Main != null)
            {
                Main.HandleCommand(Json.Str(msg, "cmd"));
            }
        }

        static async void OnNewWindow(Form owner, CoreWebView2NewWindowRequestedEventArgs e)
        {
            string uri = e.Uri ?? "";
            if (uri.Length > 0 && uri != "about:blank" && !IsServerUri(uri))
            {
                // Somewhere else: the computer's own browser.
                e.Handled = true;
                try { Process.Start(uri); } catch { }
                return;
            }
            var deferral = e.GetDeferral();
            try
            {
                var popup = new PopupForm();
                popup.Show(owner);
                await popup.InitAsync();
                e.NewWindow = popup.View.CoreWebView2;
                e.Handled = true;
            }
            catch (Exception ex)
            {
                Log.Write("popup: " + ex.Message);
            }
            finally
            {
                deferral.Complete();
            }
        }

        static async void OnCertError(object sender, CoreWebView2ServerCertificateErrorDetectedEventArgs e)
        {
            var deferral = e.GetDeferral();
            try
            {
                Uri u;
                bool ok = false;
                if (Uri.TryCreate(e.RequestUri, UriKind.Absolute, out u) && IsServerUri(e.RequestUri))
                {
                    var leaf = e.ServerCertificate.ToX509Certificate2();
                    var chain = new List<string>(e.ServerCertificate.PemEncodedIssuerCertificateChain);
                    ok = await CertHelper.VerifyAsync(Settings, leaf, chain, u.Host);
                }
                e.Action = ok ? CoreWebView2ServerCertificateErrorAction.AlwaysAllow : CoreWebView2ServerCertificateErrorAction.Default;
                Log.Write("certificate error " + e.ErrorStatus + " for " + e.RequestUri + ": " + (ok ? "accepted (clinic root)" : "refused"));
            }
            catch (Exception ex)
            {
                Log.Write("certificate check: " + ex.Message);
                e.Action = CoreWebView2ServerCertificateErrorAction.Default;
            }
            finally
            {
                deferral.Complete();
            }
        }
    }

    static class Paths
    {
        public static string ExeDir { get { return Path.GetDirectoryName(Application.ExecutablePath); } }
        public static string RoamingDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DentalClinicClient"); } }
        public static string LocalDir { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DentalClinicClient"); } }
        public static string SettingsFile { get { return Path.Combine(RoamingDir, "settings.json"); } }
        public static string CertFile { get { return Path.Combine(RoamingDir, "clinic-ca.crt"); } }
        public static string LogFile { get { return Path.Combine(LocalDir, "client.log"); } }
    }

    static class Log
    {
        static readonly object Gate = new object();
        public static void Write(string line)
        {
            try
            {
                lock (Gate)
                {
                    Directory.CreateDirectory(Paths.LocalDir);
                    var fi = new FileInfo(Paths.LogFile);
                    if (fi.Exists && fi.Length > 1024 * 1024) File.Delete(Paths.LogFile);
                    File.AppendAllText(Paths.LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + line + Environment.NewLine, Encoding.UTF8);
                }
            }
            catch { }
        }
    }

    static class Json
    {
        public static JavaScriptSerializer Serializer()
        {
            return new JavaScriptSerializer { MaxJsonLength = int.MaxValue, RecursionLimit = 256 };
        }
        public static object Parse(string json) { return Serializer().DeserializeObject(json); }
        public static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            return d != null && d.TryGetValue(key, out v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : "";
        }
        public static bool Bool(Dictionary<string, object> d, string key)
        {
            object v;
            return d != null && d.TryGetValue(key, out v) && v is bool && (bool)v;
        }
        public static Dictionary<string, object> Obj(Dictionary<string, object> d, string key)
        {
            object v;
            return d != null && d.TryGetValue(key, out v) ? v as Dictionary<string, object> : null;
        }
        public static string Quote(string s) { return Serializer().Serialize(s ?? ""); }
        public static string Num(double v) { return v.ToString("0.###", CultureInfo.InvariantCulture); }
    }

    // %APPDATA%\DentalClinicClient\settings.json
    public class ClientSettings
    {
        public string Server = "clinic.lan";
        public string ServerIp = "";
        public int HttpsPort = 443;
        public int HttpPort = 80;

        // Thermal printer for tickets and receipts.
        public string TicketMode = PrintModes.Driver;
        public string TicketPrinter = "";
        public int PaperWidthMm = 80;
        public double MarginTopMm = 0;
        public double MarginBottomMm = 0;
        public double MarginSideMm = 0;
        public string NetworkHost = "";
        public int NetworkPort = 9100;
        public string ComPort = "";
        public int BaudRate = 9600;
        public bool Cut = true;
        public int Darkness = 50;      // percent: grey darker than this prints black
        public int ScalePercent = 100; // ticket content size

        // Everything else (A4 reports, case sheets).
        public string DocumentPrinter = "";
        public bool DocumentSilent = true;

        public bool ShowPrintDialog = false; // fallback: the browser's dialog for everything
        public bool ClosePrintWindows = true;
        public bool StartFullScreen = false;
        public bool AutoUpdate = true;
        public int SkippedUpdate = 0;

        public static ClientSettings Load()
        {
            try
            {
                if (File.Exists(Paths.SettingsFile))
                {
                    var s = Json.Serializer().Deserialize<ClientSettings>(File.ReadAllText(Paths.SettingsFile, Encoding.UTF8));
                    if (s != null) { s.Normalize(); return s; }
                }
            }
            catch (Exception ex) { Log.Write("settings: " + ex.Message); }
            return new ClientSettings();
        }

        public void Save()
        {
            Normalize();
            Directory.CreateDirectory(Paths.RoamingDir);
            string tmp = Paths.SettingsFile + ".tmp";
            File.WriteAllText(tmp, Json.Serializer().Serialize(this), Encoding.UTF8);
            if (File.Exists(Paths.SettingsFile)) File.Delete(Paths.SettingsFile);
            File.Move(tmp, Paths.SettingsFile);
        }

        public ClientSettings Clone()
        {
            var j = Json.Serializer();
            return j.Deserialize<ClientSettings>(j.Serialize(this));
        }

        public void Normalize()
        {
            Server = CleanHost(Server);
            if (Server.Length == 0) Server = "clinic.lan";
            ServerIp = (ServerIp ?? "").Trim();
            if (HttpsPort <= 0 || HttpsPort > 65535) HttpsPort = 443;
            if (HttpPort <= 0 || HttpPort > 65535) HttpPort = 80;
            if (PaperWidthMm != 58) PaperWidthMm = 80;
            if (!PrintModes.All.Contains(TicketMode)) TicketMode = PrintModes.Driver;
            if (NetworkPort <= 0 || NetworkPort > 65535) NetworkPort = 9100;
            if (BaudRate <= 0) BaudRate = 9600;
            Darkness = Math.Max(10, Math.Min(90, Darkness));
            ScalePercent = Math.Max(50, Math.Min(200, ScalePercent));
            MarginTopMm = Math.Max(0, Math.Min(30, MarginTopMm));
            MarginBottomMm = Math.Max(0, Math.Min(30, MarginBottomMm));
            MarginSideMm = Math.Max(0, Math.Min(15, MarginSideMm));
            TicketPrinter = TicketPrinter ?? "";
            DocumentPrinter = DocumentPrinter ?? "";
            NetworkHost = (NetworkHost ?? "").Trim();
            ComPort = ComPort ?? "";
        }

        // "https://clinic.lan:443/x" -> "clinic.lan"
        public static string CleanHost(string s)
        {
            s = (s ?? "").Trim();
            int i = s.IndexOf("://", StringComparison.Ordinal);
            if (i >= 0) s = s.Substring(i + 3);
            i = s.IndexOfAny(new[] { '/', ':', '?', '#' });
            if (i >= 0) s = s.Substring(0, i);
            return s.ToLowerInvariant();
        }

        public string HomeUrl { get { return "https://" + Server + (HttpsPort == 443 ? "" : ":" + HttpsPort) + "/"; } }

        // Plain http goes to the IP when one is set, so the certificate and
        // updates come down even before the name works on this computer.
        public string HttpBase { get { return "http://" + (ServerIp.Length > 0 ? ServerIp : Server) + (HttpPort == 80 ? "" : ":" + HttpPort); } }

        public string BrowserArguments()
        {
            var a = new List<string>();
            IPAddress ip;
            if (ServerIp.Length > 0 && IPAddress.TryParse(ServerIp, out ip))
                a.Add("--host-resolver-rules=\"MAP " + Server + " " + ServerIp + "\"");
            // The hidden window that renders tickets sits off screen; keep it painting.
            a.Add("--disable-features=CalculateNativeWinOcclusion");
            a.Add("--disable-backgrounding-occluded-windows");
            return string.Join(" ", a);
        }

        public int TicketDots { get { return PaperWidthMm == 58 ? 384 : 576; } }
        // The printable width of the roll (the head is narrower than the paper).
        public double PrintableMm { get { return PaperWidthMm == 58 ? 48 : 72; } }
    }

    static class PrintModes
    {
        public const string Driver = "driver";
        public const string Usb = "usb";
        public const string Network = "network";
        public const string Bluetooth = "bluetooth";
        public static readonly string[] All = { Driver, Usb, Network, Bluetooth };
        public static readonly string[] Labels =
        {
            "تعريف ويندوز (Windows driver)",
            "USB مباشر (ESC/POS) — يعمل مع Generic / Text Only",
            "شبكة LAN (عنوان IP، المنفذ 9100)",
            "بلوتوث (منفذ COM)",
        };
    }

    // The script every page gets before its own scripts run.
    static class Bridge
    {
        public static string Script(ClientSettings s)
        {
            string cfg = "{ticketSilent:" + (s.ShowPrintDialog ? "false" : "true") +
                ",docSilent:" + (!s.ShowPrintDialog && s.DocumentSilent ? "true" : "false") + "}";
            return @"(function () {
  if (window.__dcBridge) return;
  window.__dcBridge = true;
  var cfg = " + cfg + @";
  var original = window.print;
  // A ticket is a page whose print size is a paper roll (@page { size: 80mm auto }).
  function isTicket() {
    var found = false;
    function scan(rules) {
      for (var i = 0; rules && i < rules.length && !found; i++) {
        var r = rules[i];
        if (r.type === 6) {
          var m = /size\s*:\s*(\d+(?:\.\d+)?)mm/i.exec(r.cssText || '');
          if (m && parseFloat(m[1]) <= 112) found = true;
        } else if (r.cssRules) {
          scan(r.cssRules);
        }
      }
    }
    for (var s = 0; s < document.styleSheets.length && !found; s++) {
      try { scan(document.styleSheets[s].cssRules); } catch (e) { }
    }
    return found;
  }
  function post(msg) {
    if (window === window.top) {
      try { window.chrome.webview.postMessage(msg); return true; } catch (e) { return false; }
    }
    try { window.top.postMessage({ __dcPrint: msg }, location.origin); return true; } catch (e) { return false; }
  }
  window.print = function () {
    var ticket = isTicket();
    if (!(ticket ? cfg.ticketSilent : cfg.docSilent)) return original.call(window);
    var msg = { type: 'print', url: location.href, ticket: ticket, top: window === window.top, title: document.title };
    if (!post(msg)) return original.call(window);
  };
  if (window === window.top) {
    // Frames (the lab slip after a QR scan prints from a hidden iframe) send through here.
    window.addEventListener('message', function (e) {
      if (e.origin !== location.origin || !e.data || !e.data.__dcPrint) return;
      var m = e.data.__dcPrint; m.top = false;
      try { window.chrome.webview.postMessage(m); } catch (x) { }
    });
    document.addEventListener('keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === 'p' || e.key === 'P')) {
        e.preventDefault(); window.print(); return;
      }
      if (e.key === 'F11' || e.key === 'F5' || (e.altKey && (e.key === 'ArrowLeft' || e.key === 'ArrowRight' || e.key === 'Home'))) {
        e.preventDefault();
        try { window.chrome.webview.postMessage({ type: 'key', key: (e.altKey ? 'Alt+' : '') + e.key }); } catch (x) { }
      }
    }, true);
  }
})();";
        }
    }

    // ---------------------------------------------------------------- windows

    class MainForm : Form
    {
        public WebView2 View;
        ToolStrip bar;
        ToolStripLabel status;
        FormWindowState savedState;
        bool fullScreen;
        System.Windows.Forms.Timer updateTimer;
        bool certTried;

        public MainForm()
        {
            App.Main = this;
            Text = "Dental Clinic";
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Font = new Font("Segoe UI", 9.5f);
            WindowState = FormWindowState.Maximized;
            MinimumSize = new Size(640, 480);
            Size = new Size(1280, 800);
            KeyPreview = true;

            bar = new ToolStrip { GripStyle = ToolStripGripStyle.Hidden, RightToLeft = RightToLeft.Yes, Padding = new Padding(4, 2, 4, 2), ImageScalingSize = new Size(20, 20) };
            AddButton("→ رجوع", "رجوع (Alt+←)", () => { if (Ready && View.CoreWebView2.CanGoBack) View.CoreWebView2.GoBack(); });
            AddButton("تحديث ⟳", "تحديث الصفحة (F5)", () => { if (Ready) View.CoreWebView2.Reload(); });
            AddButton("الرئيسية", "الصفحة الرئيسية (Alt+Home)", GoHome);
            bar.Items.Add(new ToolStripSeparator());
            AddButton("الإعدادات والطباعة", "إعدادات الخادم والطابعات", OpenSettings);
            AddButton("ملء الشاشة", "ملء الشاشة (F11)", () => SetFullScreen(!fullScreen));
            status = new ToolStripLabel { Alignment = ToolStripItemAlignment.Right, ForeColor = Color.DimGray };
            bar.Items.Add(status);

            View = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.White };
            Controls.Add(View);
            Controls.Add(bar);
            Shown += async (s, e) => await InitAsync();
            FormClosed += (s, e) => { try { View.Dispose(); } catch { } };
        }

        bool Ready { get { return View.CoreWebView2 != null; } }

        void AddButton(string text, string tip, Action action)
        {
            var b = new ToolStripButton(text) { ToolTipText = tip, DisplayStyle = ToolStripItemDisplayStyle.Text, Margin = new Padding(2, 1, 2, 1) };
            b.Click += (s, e) => action();
            bar.Items.Add(b);
        }

        async Task InitAsync()
        {
            SetStatus("جارٍ التشغيل…");
            Exception failure = null;
            for (int attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    await View.EnsureCoreWebView2Async(await App.EnvAsync());
                    failure = null;
                    break;
                }
                catch (Exception ex)
                {
                    // The previous copy's browser processes may still hold the profile.
                    failure = ex;
                    App.Env = null;
                }
                await Task.Delay(2500);
            }
            if (failure != null)
            {
                var ex = failure;
                Log.Write("WebView2: " + ex);
                MessageBox.Show(this, "تعذّر تشغيل محرك المتصفح Microsoft Edge WebView2.\n" +
                    "ثبّت «Microsoft Edge WebView2 Runtime» ثم افتح البرنامج مجددًا.\n\n" + ex.Message,
                    "Dental Clinic", MessageBoxButtons.OK, MessageBoxIcon.Error, MessageBoxDefaultButton.Button1, MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign);
                Close();
                return;
            }
            Log.Write("WebView2 ready, runtime " + App.Env.BrowserVersionString);
            await App.SetupView(View, this);
            var core = View.CoreWebView2;
            core.NavigationCompleted += OnNavigated;
            core.DocumentTitleChanged += (s, e) => { Text = string.IsNullOrEmpty(core.DocumentTitle) ? "Dental Clinic" : core.DocumentTitle + " — Dental Clinic"; };
            core.ContainsFullScreenElementChanged += (s, e) => SetFullScreen(core.ContainsFullScreenElement);

            // First run: trust the clinic certificate before the first https page.
            await EnsureCertificateAsync(false);
            if (App.Settings.StartFullScreen) SetFullScreen(true);
            GoHome();
            App.Renderer.Warm();

            updateTimer = new System.Windows.Forms.Timer { Interval = 6 * 3600 * 1000 };
            updateTimer.Tick += async (s, e) => await Updater.CheckAsync(this, false);
            updateTimer.Start();
            await Task.Delay(15000);
            await Updater.CheckAsync(this, false);
        }

        // Downloads the server's root certificate and installs it for this
        // user (Windows asks once). Quiet when it is already trusted.
        public async Task<bool> EnsureCertificateAsync(bool force)
        {
            var s = App.Settings;
            try
            {
                X509Certificate2 root = CertHelper.Cached();
                if (force || root == null || !CertHelper.IsTrusted(root))
                {
                    SetStatus("جارٍ تثبيت شهادة العيادة…");
                    var fresh = await Task.Run(() => CertHelper.Download(s));
                    if (root != null && root.Thumbprint != fresh.Thumbprint && !force)
                    {
                        var ans = Ask("تغيّرت شهادة خادم العيادة (ربما أُعيد تثبيت الخادم).\nهل تثق بالشهادة الجديدة من " + s.HttpBase + "؟");
                        if (!ans) { SetStatus(""); return false; }
                    }
                    CertHelper.Save(fresh);
                    if (!CertHelper.IsTrusted(fresh))
                    {
                        try { CertHelper.Install(fresh, false); }
                        catch (Exception ex) { Log.Write("certificate install refused: " + ex.Message); }
                    }
                    Log.Write("certificate " + fresh.Thumbprint + " trusted: " + CertHelper.IsTrusted(fresh));
                }
                SetStatus("");
                return true;
            }
            catch (Exception ex)
            {
                Log.Write("certificate download: " + ex.Message);
                SetStatus("");
                return false;
            }
        }

        void OnNavigated(object sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            if (e.IsSuccess || e.WebErrorStatus == CoreWebView2WebErrorStatus.OperationCanceled) return;
            var err = e.WebErrorStatus;
            Log.Write("navigation failed: " + err + " " + View.CoreWebView2.Source);
            bool certProblem = err == CoreWebView2WebErrorStatus.CertificateCommonNameIsIncorrect ||
                err == CoreWebView2WebErrorStatus.CertificateExpired || err == CoreWebView2WebErrorStatus.ClientCertificateContainsErrors ||
                err == CoreWebView2WebErrorStatus.CertificateRevoked || err == CoreWebView2WebErrorStatus.CertificateIsInvalid;
            if (certProblem && !certTried)
            {
                certTried = true;
                BeginInvoke(new Action(async () => { if (await EnsureCertificateAsync(true)) GoHome(); else ShowError(err); }));
                return;
            }
            ShowError(err);
        }

        void ShowError(CoreWebView2WebErrorStatus err)
        {
            string why;
            switch (err)
            {
                case CoreWebView2WebErrorStatus.HostNameNotResolved:
                    why = "لم يُعثر على الاسم " + App.Settings.Server + " في الشبكة. اكتب عنوان IP للخادم في الإعدادات، أو اضغط «البحث عن الخادم».";
                    break;
                case CoreWebView2WebErrorStatus.CannotConnect:
                case CoreWebView2WebErrorStatus.ConnectionAborted:
                case CoreWebView2WebErrorStatus.ConnectionReset:
                case CoreWebView2WebErrorStatus.Disconnected:
                case CoreWebView2WebErrorStatus.Timeout:
                    why = "الخادم لا يرد. تأكد أن حاسوب الخادم يعمل وأن النظام مشغّل من لوحة التشغيل، وأن هذا الحاسوب على الشبكة نفسها.";
                    break;
                case CoreWebView2WebErrorStatus.CertificateCommonNameIsIncorrect:
                case CoreWebView2WebErrorStatus.CertificateExpired:
                case CoreWebView2WebErrorStatus.CertificateIsInvalid:
                case CoreWebView2WebErrorStatus.CertificateRevoked:
                    why = "شهادة الخادم غير موثوقة. من الإعدادات اضغط «تثبيت الشهادة الآن».";
                    break;
                default:
                    why = "تعذّر فتح النظام (" + err + ").";
                    break;
            }
            string html = "<!doctype html><html lang=ar dir=rtl><head><meta charset=utf-8><style>" +
                "body{font-family:'Segoe UI',Tahoma,sans-serif;background:#f6f7fb;color:#1f2937;margin:0;display:flex;align-items:center;justify-content:center;height:100vh}" +
                ".c{background:#fff;border-radius:12px;padding:28px 32px;max-width:560px;box-shadow:0 1px 4px rgba(0,0,0,.1);line-height:1.8}" +
                "button{font:inherit;border:0;border-radius:8px;padding:10px 18px;margin:6px 0 0 8px;cursor:pointer;background:#e5e7eb}" +
                "button.p{background:#4f46e5;color:#fff}code{direction:ltr;display:inline-block}</style></head><body><div class=c>" +
                "<h2>تعذّر الاتصال بنظام العيادة</h2><p>" + WebUtility.HtmlEncode(why) + "</p>" +
                "<p>العنوان: <code>" + WebUtility.HtmlEncode(App.Settings.HomeUrl) + "</code>" +
                (App.Settings.ServerIp.Length > 0 ? " عبر <code>" + WebUtility.HtmlEncode(App.Settings.ServerIp) + "</code>" : "") + "</p>" +
                "<button class=p onclick=\"s('retry')\">إعادة المحاولة</button><button onclick=\"s('find')\">البحث عن الخادم</button><button onclick=\"s('settings')\">الإعدادات</button>" +
                "</div><script>function s(c){chrome.webview.postMessage({type:'cmd',cmd:c})}</script></body></html>";
            View.CoreWebView2.NavigateToString(html);
        }

        public void HandleCommand(string cmd)
        {
            if (cmd == "retry") { certTried = false; GoHome(); }
            else if (cmd == "settings") OpenSettings();
            else if (cmd == "find") OpenSettings(true);
        }

        string lastKey = "";
        DateTime lastKeyAt = DateTime.MinValue;

        // A shortcut can arrive twice: from the page (bridge script) and from
        // WebView2's accelerator forwarding (ProcessCmdKey). Act once.
        public void HandleKey(string key)
        {
            if (!Ready) return;
            if (key == lastKey && (DateTime.UtcNow - lastKeyAt).TotalMilliseconds < 400) return;
            lastKey = key;
            lastKeyAt = DateTime.UtcNow;
            switch (key)
            {
                case "F11": SetFullScreen(!fullScreen); break;
                case "F5": View.CoreWebView2.Reload(); break;
                case "Alt+ArrowLeft": if (View.CoreWebView2.CanGoBack) View.CoreWebView2.GoBack(); break;
                case "Alt+ArrowRight": if (View.CoreWebView2.CanGoForward) View.CoreWebView2.GoForward(); break;
                case "Alt+Home": GoHome(); break;
            }
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            switch (keyData)
            {
                case Keys.F11: HandleKey("F11"); return true;
                case Keys.F5: HandleKey("F5"); return true;
                case Keys.Alt | Keys.Left: HandleKey("Alt+ArrowLeft"); return true;
                case Keys.Alt | Keys.Right: HandleKey("Alt+ArrowRight"); return true;
                case Keys.Alt | Keys.Home: HandleKey("Alt+Home"); return true;
                case Keys.Escape: if (fullScreen) { SetFullScreen(false); return true; } break;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        public void GoHome()
        {
            if (!Ready) return;
            View.CoreWebView2.Navigate(App.Settings.HomeUrl);
        }

        void SetFullScreen(bool on)
        {
            if (on == fullScreen) return;
            fullScreen = on;
            if (on)
            {
                savedState = WindowState;
                bar.Visible = false;
                FormBorderStyle = FormBorderStyle.None;
                WindowState = FormWindowState.Normal;
                WindowState = FormWindowState.Maximized;
            }
            else
            {
                FormBorderStyle = FormBorderStyle.Sizable;
                bar.Visible = true;
                WindowState = savedState == FormWindowState.Minimized ? FormWindowState.Maximized : savedState;
            }
        }

        public void SetStatus(string text)
        {
            if (InvokeRequired) { BeginInvoke(new Action(() => SetStatus(text))); return; }
            status.Text = text;
        }

        public bool Ask(string text)
        {
            return MessageBox.Show(this, text, "Dental Clinic", MessageBoxButtons.YesNo, MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button1, MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign) == DialogResult.Yes;
        }

        public void Tell(string text, bool error)
        {
            MessageBox.Show(this, text, "Dental Clinic", MessageBoxButtons.OK, error ? MessageBoxIcon.Warning : MessageBoxIcon.Information,
                MessageBoxDefaultButton.Button1, MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign);
        }

        void OpenSettings() { OpenSettings(false); }

        async void OpenSettings(bool find)
        {
            var before = App.Settings.Clone();
            using (var f = new SettingsForm(App.Settings.Clone(), find))
            {
                if (f.ShowDialog(this) != DialogResult.OK) return;
                var s = f.Result;
                try { s.Save(); }
                catch (Exception ex) { Tell("تعذّر حفظ الإعدادات: " + ex.Message, true); return; }
                App.Settings = s;
                bool restart = before.ServerIp != s.ServerIp || before.Server != s.Server;
                if (restart)
                {
                    // The address mapping is fixed when the browser engine starts.
                    if (Ask("تُطبَّق إعدادات الخادم بعد إعادة فتح البرنامج. إعادة الفتح الآن؟"))
                    {
                        try { Process.Start(Application.ExecutablePath, "--wait-pid " + Process.GetCurrentProcess().Id); } catch { }
                        Close();
                    }
                    return;
                }
                if (Ready)
                {
                    // New print settings reach the pages on their next load.
                    await App.RefreshBridges();
                    View.CoreWebView2.Reload();
                }
            }
        }
    }

    class PopupForm : Form
    {
        public WebView2 View;

        public PopupForm()
        {
            Text = "Dental Clinic";
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            Size = new Size(900, 760);
            StartPosition = FormStartPosition.CenterParent;
            View = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.White };
            Controls.Add(View);
            FormClosed += (s, e) => { try { View.Dispose(); } catch { } };
        }

        public async Task InitAsync()
        {
            await View.EnsureCoreWebView2Async(await App.EnvAsync());
            await App.SetupView(View, this);
            var core = View.CoreWebView2;
            core.WindowCloseRequested += (s, e) => Close();
            core.DocumentTitleChanged += (s, e) => { Text = string.IsNullOrEmpty(core.DocumentTitle) ? "Dental Clinic" : core.DocumentTitle; };
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == Keys.Escape) { Close(); return true; }
            return base.ProcessCmdKey(ref msg, keyData);
        }
    }

    // ------------------------------------------------------------- rendering

    // A WebView2 in a window off screen: loads the page to print by itself (same
    // login), so a frame's page or a ticket can be laid out at the roll's width
    // and photographed, or printed through the driver, without touching what
    // the user sees.
    class Renderer
    {
        Form host;
        WebView2 view;
        readonly SemaphoreSlim gate = new SemaphoreSlim(1, 1);
        TaskCompletionSource<bool> nav;

        public async void Warm() { try { await EnsureAsync(); } catch (Exception ex) { Log.Write("renderer: " + ex.Message); } }

        async Task EnsureAsync()
        {
            if (view != null && view.CoreWebView2 != null) return;
            host = new HiddenHost
            {
                FormBorderStyle = FormBorderStyle.None, ShowInTaskbar = false, StartPosition = FormStartPosition.Manual,
                Location = new Point(-32000, -32000), Size = new Size(820, 1000), Text = "Dental Clinic print",
            };
            view = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.White };
            host.Controls.Add(view);
            host.Show();
            host.Location = new Point(-32000, -32000);
            await view.EnsureCoreWebView2Async(await App.EnvAsync());
            var core = view.CoreWebView2;
            core.Settings.AreDefaultScriptDialogsEnabled = false;
            // The page's own print() (autoprint) must do nothing here.
            await core.AddScriptToExecuteOnDocumentCreatedAsync("window.print = function () {}; window.open = function () { return null; };");
            core.NewWindowRequested += (s, e) => { e.Handled = true; };
            core.ServerCertificateErrorDetected += async (s, e) =>
            {
                var d = e.GetDeferral();
                try
                {
                    Uri u;
                    bool ok = Uri.TryCreate(e.RequestUri, UriKind.Absolute, out u) && App.IsServerUri(e.RequestUri) &&
                        await CertHelper.VerifyAsync(App.Settings, e.ServerCertificate.ToX509Certificate2(),
                            new List<string>(e.ServerCertificate.PemEncodedIssuerCertificateChain), u.Host);
                    e.Action = ok ? CoreWebView2ServerCertificateErrorAction.AlwaysAllow : CoreWebView2ServerCertificateErrorAction.Default;
                }
                catch { e.Action = CoreWebView2ServerCertificateErrorAction.Default; }
                finally { d.Complete(); }
            };
            core.NavigationCompleted += (s, e) =>
            {
                var t = nav;
                if (t != null) t.TrySetResult(e.IsSuccess);
            };
        }

        async Task LoadAsync(string url, string html)
        {
            await EnsureAsync();
            var core = view.CoreWebView2;
            await Dev("Emulation.clearDeviceMetricsOverride", "{}");
            await Dev("Emulation.setEmulatedMedia", "{\"media\":\"\"}");
            nav = new TaskCompletionSource<bool>();
            if (html != null) core.NavigateToString(html); else core.Navigate(url);
            var done = await Task.WhenAny(nav.Task, Task.Delay(30000));
            if (done != nav.Task) throw new Exception("انتهت مهلة تحميل الصفحة للطباعة.");
            if (!nav.Task.Result) throw new Exception("تعذّر تحميل الصفحة للطباعة.");
            // Images (logo, QR) and fonts in place before measuring.
            await Dev("Runtime.evaluate", "{\"awaitPromise\":true,\"returnByValue\":true,\"expression\":" + Json.Quote(
                "(async () => { try { await document.fonts.ready; } catch (e) {} " +
                "await Promise.all([].slice.call(document.images).map(i => i.complete ? 0 : new Promise(r => { i.addEventListener('load', r); i.addEventListener('error', r); setTimeout(r, 8000); }))); " +
                "await new Promise(r => setTimeout(r, 200)); return 1; })()") + "}");
        }

        Task<string> Dev(string method, string json)
        {
            return view.CoreWebView2.CallDevToolsProtocolMethodAsync(method, json);
        }

        async Task<double> ContentHeightAsync()
        {
            string r = await Dev("Runtime.evaluate", "{\"returnByValue\":true,\"expression\":" + Json.Quote(
                "Math.ceil(Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0, document.documentElement.getBoundingClientRect().height))") + "}");
            var res = Json.Obj(Json.Parse(r) as Dictionary<string, object>, "result");
            double h;
            if (!double.TryParse(Json.Str(res, "value"), NumberStyles.Float, CultureInfo.InvariantCulture, out h) || h < 1) h = 400;
            return Math.Min(h, 30000);
        }

        // Lays the page out for print at cssWidth CSS pixels and returns it as
        // an image exactly widthPx pixels wide.
        public async Task<Bitmap> CaptureAsync(string url, string html, double cssWidth, int widthPx)
        {
            await gate.WaitAsync();
            try
            {
                await LoadAsync(url, html);
                double dsf = widthPx / cssWidth;
                await Dev("Emulation.setEmulatedMedia", "{\"media\":\"print\"}");
                await Dev("Emulation.setDeviceMetricsOverride", "{\"width\":" + (int)Math.Round(cssWidth) + ",\"height\":800,\"deviceScaleFactor\":" + Json.Num(dsf) + ",\"mobile\":false}");
                await Task.Delay(150);
                double h = await ContentHeightAsync();
                string shot = await Dev("Page.captureScreenshot", "{\"format\":\"png\",\"captureBeyondViewport\":true,\"fromSurface\":true,\"clip\":{\"x\":0,\"y\":0,\"width\":" +
                    (int)Math.Round(cssWidth) + ",\"height\":" + (int)h + ",\"scale\":1}}");
                string data = Json.Str(Json.Parse(shot) as Dictionary<string, object>, "data");
                await Dev("Emulation.clearDeviceMetricsOverride", "{}");
                await Dev("Emulation.setEmulatedMedia", "{\"media\":\"\"}");
                using (var ms = new MemoryStream(Convert.FromBase64String(data)))
                using (var img = Image.FromStream(ms))
                {
                    int outH = Math.Max(1, (int)Math.Round(img.Height * (double)widthPx / img.Width));
                    var bmp = new Bitmap(widthPx, outH, PixelFormat.Format32bppArgb);
                    using (var g = Graphics.FromImage(bmp))
                    {
                        g.Clear(Color.White);
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.DrawImage(img, new Rectangle(0, 0, widthPx, outH));
                    }
                    return bmp;
                }
            }
            finally { gate.Release(); }
        }

        // Prints through the Windows driver. rollWidthMm > 0: a page as wide
        // as the roll and as tall as the content.
        public async Task<CoreWebView2PrintStatus> PrintAsync(string url, string html, string printer, double rollWidthMm, ClientSettings s)
        {
            await gate.WaitAsync();
            try
            {
                await LoadAsync(url, html);
                var ps = App.Env.CreatePrintSettings();
                if (!string.IsNullOrEmpty(printer)) ps.PrinterName = printer;
                ps.ShouldPrintBackgrounds = true;
                ps.ShouldPrintHeaderAndFooter = false;
                if (rollWidthMm > 0)
                {
                    double contentMm = rollWidthMm - 2 * s.MarginSideMm;
                    double cssW = contentMm / 25.4 * 96;
                    await Dev("Emulation.setEmulatedMedia", "{\"media\":\"print\"}");
                    await Dev("Emulation.setDeviceMetricsOverride", "{\"width\":" + (int)Math.Round(cssW) + ",\"height\":800,\"deviceScaleFactor\":1,\"mobile\":false}");
                    await Task.Delay(150);
                    double h = await ContentHeightAsync();
                    await Dev("Emulation.clearDeviceMetricsOverride", "{}");
                    await Dev("Emulation.setEmulatedMedia", "{\"media\":\"\"}");
                    ApplyRoll(ps, s, rollWidthMm, h / 96.0);
                }
                return await view.CoreWebView2.PrintAsync(ps);
            }
            finally { gate.Release(); }
        }

        public static void ApplyRoll(CoreWebView2PrintSettings ps, ClientSettings s, double rollWidthMm, double contentInches)
        {
            ps.MediaSize = CoreWebView2PrintMediaSize.Custom;
            ps.PageWidth = rollWidthMm / 25.4;
            ps.PageHeight = Math.Max(1.0, contentInches + (s.MarginTopMm + s.MarginBottomMm) / 25.4 + 0.1);
            ps.MarginTop = s.MarginTopMm / 25.4;
            ps.MarginBottom = s.MarginBottomMm / 25.4;
            ps.MarginLeft = s.MarginSideMm / 25.4;
            ps.MarginRight = s.MarginSideMm / 25.4;
            ps.ScaleFactor = s.ScalePercent / 100.0;
        }

        public async Task<bool> PdfAsync(string html, string file)
        {
            await gate.WaitAsync();
            try
            {
                await LoadAsync(null, html);
                var ps = App.Env.CreatePrintSettings();
                ps.ShouldPrintHeaderAndFooter = false;
                ps.ShouldPrintBackgrounds = true;
                return await view.CoreWebView2.PrintToPdfAsync(file, ps);
            }
            finally { gate.Release(); }
        }
    }

    class HiddenHost : Form
    {
        protected override bool ShowWithoutActivation { get { return true; } }
    }

    // ---------------------------------------------------------------- printing

    class PrintRequest
    {
        public string Url, Title;
        public bool Ticket, TopLevel;
        public CoreWebView2 Source;
        public Form Owner;
    }

    class PrintService
    {
        Task chain = Task.FromResult(0);

        // One job at a time, in the order they came.
        public void Enqueue(PrintRequest job)
        {
            chain = chain.ContinueWith(_ => RunOnUi(job), TaskScheduler.FromCurrentSynchronizationContext()).Unwrap();
        }

        async Task RunOnUi(PrintRequest job)
        {
            var s = App.Settings;
            if (App.Main != null) App.Main.SetStatus("جارٍ الطباعة…");
            try
            {
                Log.Write("print " + (job.Ticket ? "ticket" : "document") + " " + job.Url + " (" + (job.Ticket ? s.TicketMode : "document") + ")");
                if (job.Ticket) await PrintTicket(s, job.Url, null);
                else await PrintDocument(s, job);
                if (job.TopLevel && job.Owner is PopupForm && s.ClosePrintWindows && !job.Owner.IsDisposed)
                    job.Owner.Close();
            }
            catch (Exception ex)
            {
                Log.Write("print failed: " + ex.Message);
                var owner = job.Owner != null && !job.Owner.IsDisposed ? job.Owner : (Form)App.Main;
                bool dialog = job.TopLevel && job.Source != null && MessageBox.Show(owner,
                    "تعذّرت الطباعة: " + ex.Message + "\n\nهل تريد فتح نافذة الطباعة العادية؟\n(يمكن تغيير الطابعة من «الإعدادات والطباعة»)",
                    "Dental Clinic", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1,
                    MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign) == DialogResult.Yes;
                if (!job.TopLevel)
                    MessageBox.Show(owner, "تعذّرت الطباعة: " + ex.Message + "\n(يمكن تغيير الطابعة من «الإعدادات والطباعة»)", "Dental Clinic",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button1, MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign);
                if (dialog)
                {
                    try { job.Source.ShowPrintUI(CoreWebView2PrintDialogKind.Browser); } catch { }
                }
            }
            finally
            {
                if (App.Main != null) App.Main.SetStatus("");
            }
        }

        static async Task PrintDocument(ClientSettings s, PrintRequest job)
        {
            CoreWebView2PrintStatus st;
            if (job.TopLevel && job.Source != null)
            {
                // The page itself, as the user sees it.
                var ps = App.Env.CreatePrintSettings();
                if (s.DocumentPrinter.Length > 0) ps.PrinterName = s.DocumentPrinter;
                ps.ShouldPrintBackgrounds = true;
                ps.ShouldPrintHeaderAndFooter = false;
                st = await job.Source.PrintAsync(ps);
            }
            else
            {
                st = await App.Renderer.PrintAsync(job.Url, null, s.DocumentPrinter, 0, s);
            }
            Check(st, s.DocumentPrinter);
        }

        static void Check(CoreWebView2PrintStatus st, string printer)
        {
            if (st == CoreWebView2PrintStatus.Succeeded) return;
            if (st == CoreWebView2PrintStatus.PrinterUnavailable)
                throw new Exception("الطابعة «" + (printer.Length > 0 ? printer : "الافتراضية") + "» غير متاحة.");
            throw new Exception("رفضت الطابعة المهمة.");
        }

        // A ticket (url, or html for the test page) to the thermal printer.
        public static async Task PrintTicket(ClientSettings s, string url, string html)
        {
            if (s.TicketMode == PrintModes.Driver)
            {
                if (s.TicketPrinter.Length == 0) throw new Exception("اختر الطابعة الحرارية من الإعدادات أولًا.");
                Check(await App.Renderer.PrintAsync(url, html, s.TicketPrinter, s.PaperWidthMm, s), s.TicketPrinter);
                return;
            }
            byte[] bytes = await TicketBytes(s, url, html);
            await Task.Run(() => Send(s, bytes));
        }

        public static async Task<byte[]> TicketBytes(ClientSettings s, string url, string html)
        {
            const double dotsPerMm = 8.0; // 203 dpi
            int dots = s.TicketDots;
            int side = (int)Math.Round(s.MarginSideMm * dotsPerMm);
            int contentDots = Math.Max(64, dots - 2 * side);
            double contentMm = contentDots / dotsPerMm;
            double cssWidth = contentMm / 25.4 * 96 * 100.0 / s.ScalePercent;
            using (var page = await App.Renderer.CaptureAsync(url, html, cssWidth, contentDots))
            using (var full = EscPos.Compose(page, dots, side, (int)Math.Round(s.MarginTopMm * dotsPerMm), (int)Math.Round(s.MarginBottomMm * dotsPerMm), s.Darkness))
                return EscPos.Raster(full, s.Darkness, s.Cut);
        }

        public static void Send(ClientSettings s, byte[] bytes)
        {
            switch (s.TicketMode)
            {
                case PrintModes.Usb:
                    if (s.TicketPrinter.Length == 0) throw new Exception("اختر طابعة USB من الإعدادات أولًا.");
                    RawPrinter.Write(s.TicketPrinter, bytes, "ticket");
                    break;
                case PrintModes.Network:
                    if (s.NetworkHost.Length == 0) throw new Exception("اكتب عنوان IP للطابعة في الإعدادات أولًا.");
                    NetPrinter.Write(s.NetworkHost, s.NetworkPort, bytes);
                    break;
                case PrintModes.Bluetooth:
                    if (s.ComPort.Length == 0) throw new Exception("اختر منفذ COM لطابعة البلوتوث من الإعدادات أولًا.");
                    SerialPrinter.Write(s.ComPort, s.BaudRate, bytes);
                    break;
                default:
                    throw new Exception("طريقة طباعة غير معروفة.");
            }
        }

        public static string TestTicketHtml(ClientSettings s)
        {
            var sb = new StringBuilder();
            sb.Append("<!doctype html><html lang=ar dir=rtl><head><meta charset=utf-8><style>");
            sb.Append("@page{size:80mm auto;margin:0}body{margin:0;font-family:'Segoe UI',Tahoma,sans-serif;color:#000}");
            sb.Append(".b{border:2px solid #000;padding:6px;margin:0}h1{font-size:20px;margin:4px 0;text-align:center}");
            sb.Append("table{width:100%;border-collapse:collapse;font-size:14px}td{border:1px solid #000;padding:3px 5px}");
            sb.Append(".g{height:24px;background:repeating-linear-gradient(90deg,#000 0 6px,#fff 6px 12px);-webkit-print-color-adjust:exact;print-color-adjust:exact;margin-top:6px}");
            sb.Append("</style></head><body><div class=b><h1>اختبار الطابعة</h1><table>");
            sb.Append("<tr><td>الطريقة</td><td>").Append(WebUtility.HtmlEncode(s.TicketMode)).Append("</td></tr>");
            sb.Append("<tr><td>عرض الورق</td><td>").Append(s.PaperWidthMm).Append(" mm</td></tr>");
            sb.Append("<tr><td>الوقت</td><td dir=ltr>").Append(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")).Append("</td></tr>");
            sb.Append("<tr><td>English</td><td dir=ltr>Dental Clinic 0123456789</td></tr></table>");
            sb.Append("<div class=g></div><p style='text-align:center;margin:6px 0 0'>إذا ظهر الإطار كاملًا فالعرض مضبوط ✓</p></div></body></html>");
            return sb.ToString();
        }

        public static string TestDocumentHtml()
        {
            return "<!doctype html><html lang=ar dir=rtl><head><meta charset=utf-8><style>body{font-family:'Segoe UI',Tahoma,sans-serif;padding:24px}" +
                "h1{border-bottom:2px solid #333}</style></head><body><h1>اختبار طابعة المستندات</h1><p>Dental Clinic — " +
                DateTime.Now.ToString("yyyy-MM-dd HH:mm") + "</p><p>هذه صفحة تجريبية للتأكد من أن الطباعة تعمل دون نافذة.</p></body></html>";
        }
    }

    // ESC/POS raster (port of flutter_app/lib/features/printing/data/escpos_raster.dart).
    static class EscPos
    {
        // Puts the page on a roll-wide white strip with the margins, and
        // drops blank rows at the top and bottom (saves paper).
        public static Bitmap Compose(Bitmap page, int dots, int side, int top, int bottom, int darkness)
        {
            int first = 0, last = page.Height - 1;
            var dark = DarkMap(page, darkness);
            while (first < last && !RowHasInk(dark, page.Width, first)) first++;
            while (last > first && !RowHasInk(dark, page.Width, last)) last--;
            int h = Math.Max(1, last - first + 1) + top + bottom;
            var bmp = new Bitmap(dots, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.White);
                g.DrawImage(page, new Rectangle(side, top, page.Width, last - first + 1), new Rectangle(0, first, page.Width, last - first + 1), GraphicsUnit.Pixel);
            }
            return bmp;
        }

        static bool RowHasInk(bool[] dark, int width, int y)
        {
            for (int x = 0; x < width; x++) if (dark[y * width + x]) return true;
            return false;
        }

        static bool[] DarkMap(Bitmap bmp, int darkness)
        {
            int w = bmp.Width, h = bmp.Height;
            var res = new bool[w * h];
            var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                var row = new byte[w * 4];
                double limit = 1.0 - darkness / 100.0;
                for (int y = 0; y < h; y++)
                {
                    Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, row.Length);
                    for (int x = 0; x < w; x++)
                    {
                        int i = x * 4;
                        double a = row[i + 3] / 255.0;
                        if (a < 0.5) continue; // transparent counts as white
                        double lum = (0.114 * row[i] + 0.587 * row[i + 1] + 0.299 * row[i + 2]) / 255.0;
                        if (lum < limit) res[y * w + x] = true;
                    }
                }
            }
            finally { bmp.UnlockBits(data); }
            return res;
        }

        // ESC @, the image as GS v 0 bands, feed, partial cut.
        public static byte[] Raster(Bitmap bmp, int darkness, bool cut)
        {
            int width = bmp.Width, height = bmp.Height;
            int bytesPerRow = (width + 7) >> 3;
            var dark = DarkMap(bmp, darkness);
            var o = new MemoryStream();
            o.Write(new byte[] { 0x1B, 0x40 }, 0, 2);
            const int bandRows = 255; // small commands for printers with little buffer
            for (int top = 0; top < height; top += bandRows)
            {
                int rows = Math.Min(bandRows, height - top);
                o.Write(new byte[] { 0x1D, 0x76, 0x30, 0x00, (byte)(bytesPerRow & 0xFF), (byte)(bytesPerRow >> 8), (byte)(rows & 0xFF), (byte)(rows >> 8) }, 0, 8);
                var band = new byte[bytesPerRow * rows];
                for (int y = 0; y < rows; y++)
                    for (int x = 0; x < width; x++)
                        if (dark[(top + y) * width + x]) band[y * bytesPerRow + (x >> 3)] |= (byte)(0x80 >> (x & 7));
                o.Write(band, 0, band.Length);
            }
            o.Write(new byte[] { 0x1B, 0x64, 0x04 }, 0, 3); // ESC d 4: feed past the cutter
            if (cut) o.Write(new byte[] { 0x1D, 0x56, 0x42, 0x00 }, 0, 4); // GS V B: partial cut
            return o.ToArray();
        }
    }

    // Bytes untouched to a Windows printer queue (datatype RAW), so ESC/POS
    // reaches a USB printer exactly as written, also with "Generic / Text Only".
    static class RawPrinter
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        class DOCINFOW
        {
            [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
            [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
            [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
        }

        [DllImport("winspool.drv", EntryPoint = "OpenPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool ClosePrinter(IntPtr handle);
        [DllImport("winspool.drv", EntryPoint = "StartDocPrinterW", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern int StartDocPrinter(IntPtr handle, int level, [In] DOCINFOW info);
        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool EndDocPrinter(IntPtr handle);
        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool StartPagePrinter(IntPtr handle);
        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool EndPagePrinter(IntPtr handle);
        [DllImport("winspool.drv", SetLastError = true)]
        static extern bool WritePrinter(IntPtr handle, byte[] bytes, int count, out int written);

        public static void Write(string printer, byte[] bytes, string job)
        {
            IntPtr h;
            if (!OpenPrinter(printer, out h, IntPtr.Zero))
                throw new Exception("تعذّر فتح الطابعة «" + printer + "» (" + Marshal.GetLastWin32Error() + ").");
            try
            {
                if (StartDocPrinter(h, 1, new DOCINFOW { pDocName = job, pDataType = "RAW" }) == 0)
                    throw new Exception("رفضت الطابعة «" + printer + "» الطباعة المباشرة (" + Marshal.GetLastWin32Error() + ").");
                try
                {
                    StartPagePrinter(h);
                    int written;
                    if (!WritePrinter(h, bytes, bytes.Length, out written) || written != bytes.Length)
                        throw new Exception("فشل الإرسال إلى الطابعة «" + printer + "».");
                    EndPagePrinter(h);
                }
                finally { EndDocPrinter(h); }
            }
            finally { ClosePrinter(h); }
        }
    }

    static class NetPrinter
    {
        public static void Write(string host, int port, byte[] bytes)
        {
            using (var c = new TcpClient())
            {
                var t = c.ConnectAsync(host, port);
                if (!t.Wait(5000) || !c.Connected) throw new Exception("الطابعة " + host + ":" + port + " لا ترد.");
                var st = c.GetStream();
                st.WriteTimeout = 15000;
                st.Write(bytes, 0, bytes.Length);
                st.Flush();
                c.Client.Shutdown(SocketShutdown.Send);
                Thread.Sleep(200);
            }
        }
    }

    // A paired Bluetooth (SPP) printer is an outgoing COM port in Windows.
    static class SerialPrinter
    {
        public static void Write(string portName, int baud, byte[] bytes)
        {
            using (var p = new SerialPort(portName, baud, Parity.None, 8, StopBits.One))
            {
                p.Handshake = Handshake.None;
                p.WriteTimeout = 20000;
                p.WriteBufferSize = 8192;
                try { p.Open(); }
                catch (Exception ex) { throw new Exception("تعذّر فتح المنفذ " + portName + ": " + ex.Message + " (هل الطابعة مشغّلة ومقترنة؟)"); }
                const int chunk = 256;
                for (int i = 0; i < bytes.Length; i += chunk)
                {
                    p.Write(bytes, i, Math.Min(chunk, bytes.Length - i));
                    // Small printers have a tiny buffer: let each piece go out.
                    var sw = Stopwatch.StartNew();
                    while (p.BytesToWrite > chunk * 2 && sw.ElapsedMilliseconds < 5000) Thread.Sleep(5);
                    Thread.Sleep(15);
                }
                var wait = Stopwatch.StartNew();
                while (p.BytesToWrite > 0 && wait.ElapsedMilliseconds < 20000) Thread.Sleep(20);
                Thread.Sleep(300);
            }
        }

        // "COM5" -> "COM5 — Standard Serial over Bluetooth link (COM5)"
        public static List<KeyValuePair<string, string>> Ports()
        {
            var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (var q = new ManagementObjectSearcher("SELECT Name FROM Win32_PnPEntity WHERE Name LIKE '%(COM%'"))
                    foreach (ManagementObject o in q.Get())
                    {
                        string n = Convert.ToString(o["Name"]);
                        var m = System.Text.RegularExpressions.Regex.Match(n, @"\((COM\d+)\)");
                        if (m.Success) names[m.Groups[1].Value] = n;
                    }
            }
            catch { }
            var list = new List<KeyValuePair<string, string>>();
            var all = new SortedSet<string>(SerialPort.GetPortNames(), StringComparer.OrdinalIgnoreCase);
            foreach (var k in names.Keys) all.Add(k);
            foreach (var p in all.OrderBy(x => { int n; return int.TryParse(x.Substring(3), out n) ? n : 999; }))
            {
                string label;
                list.Add(new KeyValuePair<string, string>(p, names.TryGetValue(p, out label) ? label : p));
            }
            return list;
        }
    }

    // ------------------------------------------------------------ certificate

    static class CertHelper
    {
        static readonly Dictionary<string, bool> Verified = new Dictionary<string, bool>();

        public static X509Certificate2 Cached()
        {
            try { return File.Exists(Paths.CertFile) ? new X509Certificate2(File.ReadAllBytes(Paths.CertFile)) : null; }
            catch { return null; }
        }

        public static void Save(X509Certificate2 c)
        {
            Directory.CreateDirectory(Paths.RoamingDir);
            File.WriteAllBytes(Paths.CertFile, c.Export(X509ContentType.Cert));
        }

        // http://<server>/ca.crt, the address the setup page offers.
        public static X509Certificate2 Download(ClientSettings s)
        {
            var req = (HttpWebRequest)WebRequest.Create(s.HttpBase + "/ca.crt");
            req.Timeout = 8000;
            req.ReadWriteTimeout = 8000;
            req.AllowAutoRedirect = false;
            req.Proxy = null;
            byte[] body;
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var st = resp.GetResponseStream())
            using (var ms = new MemoryStream())
            {
                st.CopyTo(ms);
                body = ms.ToArray();
            }
            var cert = new X509Certificate2(body);
            // Must be a self-signed certificate authority (Caddy's local root).
            bool ca = false;
            foreach (X509Extension ext in cert.Extensions)
            {
                var bc = ext as X509BasicConstraintsExtension;
                if (bc != null && bc.CertificateAuthority) ca = true;
            }
            if (!ca || cert.Subject != cert.Issuer) throw new Exception("الملف ليس شهادة جذر.");
            return cert;
        }

        public static bool IsTrusted(X509Certificate2 c)
        {
            foreach (var loc in new[] { StoreLocation.CurrentUser, StoreLocation.LocalMachine })
            {
                try
                {
                    using (var store = new X509Store(StoreName.Root, loc))
                    {
                        store.Open(OpenFlags.ReadOnly);
                        if (store.Certificates.Find(X509FindType.FindByThumbprint, c.Thumbprint, false).Count > 0) return true;
                    }
                }
                catch { }
            }
            return false;
        }

        // CurrentUser: Windows asks the user once. LocalMachine (installer,
        // elevated): no question, for every user of this computer.
        public static void Install(X509Certificate2 c, bool machine)
        {
            using (var store = new X509Store(StoreName.Root, machine ? StoreLocation.LocalMachine : StoreLocation.CurrentUser))
            {
                store.Open(OpenFlags.ReadWrite);
                store.Add(c);
            }
        }

        // The safety net for a TLS error: accept only a certificate for the
        // clinic server's name or IP that chains to the clinic root.
        public static async Task<bool> VerifyAsync(ClientSettings s, X509Certificate2 leaf, List<string> pemChain, string host)
        {
            string key = leaf.Thumbprint + "|" + host;
            lock (Verified) { bool v; if (Verified.TryGetValue(key, out v)) return v; }
            var root = Cached();
            if (root == null)
            {
                try { root = await Task.Run(() => Download(s)); Save(root); }
                catch (Exception ex) { Log.Write("certificate download: " + ex.Message); return false; }
            }
            bool ok = Chains(leaf, pemChain, root) && NameMatches(leaf, host);
            lock (Verified) Verified[key] = ok;
            return ok;
        }

        static bool Chains(X509Certificate2 leaf, List<string> pemChain, X509Certificate2 root)
        {
            using (var chain = new X509Chain())
            {
                chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
                chain.ChainPolicy.ExtraStore.Add(root);
                foreach (var pem in pemChain)
                {
                    try { chain.ChainPolicy.ExtraStore.Add(FromPem(pem)); } catch { }
                }
                chain.Build(leaf);
                if (chain.ChainElements.Count < 2) return false;
                foreach (X509ChainStatus st in chain.ChainStatus)
                    if (st.Status != X509ChainStatusFlags.UntrustedRoot && st.Status != X509ChainStatusFlags.NoError) return false;
                var top = chain.ChainElements[chain.ChainElements.Count - 1].Certificate;
                return top.Thumbprint == root.Thumbprint;
            }
        }

        static bool NameMatches(X509Certificate2 leaf, string host)
        {
            string dns = leaf.GetNameInfo(X509NameType.DnsName, false) ?? "";
            if (string.Equals(dns, host, StringComparison.OrdinalIgnoreCase)) return true;
            foreach (X509Extension ext in leaf.Extensions)
            {
                if (ext.Oid == null || ext.Oid.Value != "2.5.29.17") continue;
                string text = ext.Format(true);
                foreach (var line in text.Split(new[] { '\n', '\r', ',' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string v = line.Trim();
                    int eq = v.IndexOfAny(new[] { '=', ':' });
                    if (eq >= 0) v = v.Substring(eq + 1).Trim();
                    if (string.Equals(v, host, StringComparison.OrdinalIgnoreCase)) return true;
                }
            }
            return false;
        }

        static X509Certificate2 FromPem(string pem)
        {
            var b64 = System.Text.RegularExpressions.Regex.Replace(pem, "-----[^-]+-----", "");
            return new X509Certificate2(Convert.FromBase64String(b64.Trim()));
        }
    }

    // ---------------------------------------------------------------- updates

    // The server carries the newest client in client\ (from the offline
    // package): version.json says its build.
    static class Updater
    {
        static bool busy;

        public static async Task CheckAsync(MainForm form, bool tellIfNone)
        {
            var s = App.Settings;
            if (busy || (BuildInfo.Build == 0 && !tellIfNone) || (!s.AutoUpdate && !tellIfNone)) return;
            busy = true;
            try
            {
                var wc = new WebClient { Proxy = null, Encoding = Encoding.UTF8 };
                string json = await wc.DownloadStringTaskAsync(s.HttpBase + "/client/version.json");
                var info = Json.Parse(json) as Dictionary<string, object>;
                int build;
                int.TryParse(Json.Str(info, "build"), out build);
                string file = Json.Str(info, "file");
                string sha = Json.Str(info, "sha256").ToLowerInvariant();
                if (build <= BuildInfo.Build || file.Length == 0 || file.Contains("/") || file.Contains(".."))
                {
                    if (tellIfNone) form.Tell("البرنامج محدَّث (النسخة " + BuildInfo.Build + ").", false);
                    return;
                }
                if (!tellIfNone && s.SkippedUpdate == build) return;
                if (!form.Ask("نسخة جديدة من برنامج العيادة متوفرة على الخادم (" + build + "، الحالية " + BuildInfo.Build + ").\nتثبيتها الآن؟ سيُغلق البرنامج ويُفتح من جديد."))
                {
                    s.SkippedUpdate = build;
                    try { s.Save(); } catch { }
                    return;
                }
                form.SetStatus("جارٍ تنزيل التحديث…");
                string path = Path.Combine(Path.GetTempPath(), "DentalClinicClientSetup-" + build + ".exe");
                await wc.DownloadFileTaskAsync(s.HttpBase + "/client/" + Uri.EscapeDataString(file), path);
                if (sha.Length > 0)
                {
                    string got;
                    using (var h = SHA256.Create())
                    using (var f = File.OpenRead(path))
                        got = BitConverter.ToString(h.ComputeHash(f)).Replace("-", "").ToLowerInvariant();
                    if (got != sha) throw new Exception("الملف الذي نُزّل تالف، حاول لاحقًا.");
                }
                Log.Write("update to " + build);
                Process.Start(path, "/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS");
                Application.Exit();
            }
            catch (Exception ex)
            {
                Log.Write("update check: " + ex.Message);
                if (tellIfNone) form.Tell("تعذّر التحقق من التحديث: " + ex.Message, true);
            }
            finally
            {
                busy = false;
                form.SetStatus("");
            }
        }
    }

    // Looks for the clinic server on this computer's networks: every address
    // of each /24 that answers on the http port and serves /client/version.json
    // or the setup page.
    static class ServerFinder
    {
        public static async Task<string> FindAsync(int httpPort, Action<string> progress)
        {
            var bases = new List<string>();
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var a in ni.GetIPProperties().UnicastAddresses)
                {
                    if (a.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    var b = a.Address.GetAddressBytes();
                    if (b[0] == 169 && b[1] == 254) continue;
                    string pfx = b[0] + "." + b[1] + "." + b[2] + ".";
                    if (!bases.Contains(pfx)) bases.Add(pfx);
                }
            }
            foreach (var pfx in bases)
            {
                if (progress != null) progress("جارٍ البحث في " + pfx + "0/24 …");
                var tasks = new List<Task<string>>();
                for (int i = 1; i < 255; i++) tasks.Add(Probe(pfx + i, httpPort));
                var open = (await Task.WhenAll(tasks)).Where(x => x != null).ToList();
                foreach (var ip in open)
                {
                    if (await IsClinic(ip, httpPort)) return ip;
                }
            }
            return null;
        }

        static async Task<string> Probe(string ip, int port)
        {
            using (var c = new TcpClient())
            {
                try
                {
                    var t = c.ConnectAsync(ip, port);
                    if (await Task.WhenAny(t, Task.Delay(700)) != t) return null;
                    await t;
                    return c.Connected ? ip : null;
                }
                catch { return null; }
            }
        }

        static async Task<bool> IsClinic(string ip, int port)
        {
            try
            {
                var wc = new WebClient { Proxy = null, Encoding = Encoding.UTF8 };
                string url = "http://" + ip + (port == 80 ? "" : ":" + port) + "/setup";
                var t = wc.DownloadStringTaskAsync(url);
                if (await Task.WhenAny(t, Task.Delay(3000)) != t) { wc.CancelAsync(); return false; }
                string page = await t;
                return page.Contains("/ca.crt");
            }
            catch { return false; }
        }
    }

    // ---------------------------------------------------------------- settings

    class SettingsForm : Form
    {
        public ClientSettings Result;
        readonly ClientSettings s;
        TextBox server, ip, netHost;
        NumericUpDown httpsPort, httpPort, netPort, baud, mTop, mBottom, mSide, darkness, scale;
        ComboBox mode, ticketPrinter, paper, comPort, docPrinter;
        CheckBox cut, docSilent, showDialog, closeAfter, fullScreen, autoUpdate;
        Label findStatus, certStatus, testStatus;
        Control[] driverRows, usbRows, netRows, btRows;
        TableLayoutPanel ticketGrid;
        readonly Dictionary<Control, Control> labels = new Dictionary<Control, Control>();

        public SettingsForm(ClientSettings settings, bool startFind)
        {
            s = settings;
            Text = "الإعدادات — Dental Clinic";
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Font = new Font("Segoe UI", 9.5f);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(640, 600);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            var tabs = new TabControl { Dock = DockStyle.Fill, RightToLeftLayout = true };
            tabs.TabPages.Add(ServerTab());
            tabs.TabPages.Add(TicketTab());
            tabs.TabPages.Add(DocumentTab());
            tabs.TabPages.Add(GeneralTab());

            var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.LeftToRight, AutoSize = true, Padding = new Padding(8) };
            var cancel = new Button { Text = "إلغاء", DialogResult = DialogResult.Cancel, AutoSize = true, MinimumSize = new Size(90, 32) };
            var ok = new Button { Text = "حفظ", AutoSize = true, MinimumSize = new Size(90, 32) };
            ok.Click += (o, e) => { Result = Collect(); DialogResult = DialogResult.OK; Close(); };
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(ok);
            AcceptButton = ok;
            CancelButton = cancel;
            Controls.Add(tabs);
            Controls.Add(buttons);
            UpdateRows();
            if (startFind) Shown += (o, e) => Find();
        }

        static TableLayoutPanel Grid()
        {
            var g = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoScroll = true, Padding = new Padding(10) };
            g.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
            g.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            return g;
        }

        Control Row(TableLayoutPanel g, string caption, Control c)
        {
            int r = g.RowCount;
            g.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            var l = new Label { Text = caption, AutoSize = true, Margin = new Padding(3, 8, 3, 3) };
            if (caption.Length > 0) g.Controls.Add(l, 0, r);
            c.Margin = new Padding(3, 4, 3, 4);
            if (!(c is CheckBox) && !(c is Label) && !(c is FlowLayoutPanel)) c.Dock = DockStyle.Fill;
            g.Controls.Add(c, 1, r);
            g.RowCount++;
            labels[c] = l;
            return c;
        }

        static Label Note(string text)
        {
            return new Label { Text = text, AutoSize = true, ForeColor = Color.DimGray, MaximumSize = new Size(410, 0) };
        }

        static NumericUpDown Num(decimal min, decimal max, decimal value, int decimals)
        {
            return new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Max(min, Math.Min(max, value)), DecimalPlaces = decimals, Increment = decimals > 0 ? 0.5m : 1, Width = 100, RightToLeft = RightToLeft.No };
        }

        TabPage ServerTab()
        {
            var page = new TabPage("الخادم");
            var g = Grid();
            server = new TextBox { Text = s.Server, RightToLeft = RightToLeft.No };
            Row(g, "اسم الخادم", server);
            Row(g, "", Note("الافتراضي clinic.lan، وهو الاسم في config.txt على حاسوب الخادم."));
            ip = new TextBox { Text = s.ServerIp, RightToLeft = RightToLeft.No };
            Row(g, "عنوان IP للخادم (اختياري)", ip);
            Row(g, "", Note("اكتبه إذا لم يعمل الاسم على هذا الحاسوب (دون تغيير DNS)، مثل 192.168.68.10. تعرضه لوحة التشغيل على الخادم."));
            var findBtn = new Button { Text = "البحث عن الخادم في الشبكة", AutoSize = true };
            findBtn.Click += (o, e) => Find();
            findStatus = new Label { AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(6, 8, 3, 3) };
            var fp = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft };
            fp.Controls.Add(findBtn);
            fp.Controls.Add(findStatus);
            Row(g, "", fp);
            httpsPort = Num(1, 65535, s.HttpsPort, 0);
            Row(g, "منفذ HTTPS", httpsPort);
            httpPort = Num(1, 65535, s.HttpPort, 0);
            Row(g, "منفذ HTTP", httpPort);
            var certBtn = new Button { Text = "تثبيت الشهادة الآن", AutoSize = true };
            certStatus = new Label { AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(6, 8, 3, 3) };
            certBtn.Click += async (o, e) =>
            {
                var t = Collect();
                certStatus.Text = "جارٍ التنزيل…";
                try
                {
                    var c = await Task.Run(() => CertHelper.Download(t));
                    CertHelper.Save(c);
                    if (!CertHelper.IsTrusted(c)) CertHelper.Install(c, false);
                    certStatus.Text = CertHelper.IsTrusted(c) ? "الشهادة مثبتة ✓" : "لم تُثبَّت";
                }
                catch (Exception ex) { certStatus.Text = "تعذّر: " + ex.Message; }
            };
            var cp = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft };
            cp.Controls.Add(certBtn);
            cp.Controls.Add(certStatus);
            Row(g, "شهادة العيادة", cp);
            var cached = CertHelper.Cached();
            certStatus.Text = cached != null && CertHelper.IsTrusted(cached) ? "مثبتة ✓" : "غير مثبتة بعد";
            page.Controls.Add(g);
            return page;
        }

        TabPage TicketTab()
        {
            var page = new TabPage("الطابعة الحرارية");
            var g = ticketGrid = Grid();
            Row(g, "", Note("للتكت والوصولات (الصفحات المهيّأة لورق 80 أو 58 ملم). تُطبع مباشرة دون نافذة."));
            mode = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList };
            mode.Items.AddRange(PrintModes.Labels);
            mode.SelectedIndex = Math.Max(0, Array.IndexOf(PrintModes.All, s.TicketMode));
            mode.SelectedIndexChanged += (o, e) => UpdateRows();
            Row(g, "طريقة الطباعة", mode);

            ticketPrinter = PrinterCombo(s.TicketPrinter, false);
            var tp = Row(g, "الطابعة", ticketPrinter);
            var usbNote = Row(g, "", Note("في وضع USB المباشر يكفي تعريف «Generic / Text Only» على منفذ USB الطابعة."));

            netHost = new TextBox { Text = s.NetworkHost, RightToLeft = RightToLeft.No };
            var nh = Row(g, "عنوان IP للطابعة", netHost);
            netPort = Num(1, 65535, s.NetworkPort, 0);
            var np = Row(g, "المنفذ", netPort);

            comPort = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown, RightToLeft = RightToLeft.No };
            FillPorts();
            var cpRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft, WrapContents = false };
            comPort.Width = 330;
            var refresh = new Button { Text = "تحديث", AutoSize = true };
            refresh.Click += (o, e) => FillPorts();
            cpRow.Controls.Add(comPort);
            cpRow.Controls.Add(refresh);
            var cr = Row(g, "منفذ COM", cpRow);
            baud = Num(1200, 921600, s.BaudRate, 0);
            var br = Row(g, "السرعة (Baud)", baud);
            var btNote = Row(g, "", Note("اقرن الطابعة من إعدادات بلوتوث في ويندوز أولًا ثم اختر منفذ COM (الصادر Outgoing). إذا ثُبّتت طابعة البلوتوث كطابعة في ويندوز فيمكن استخدام «تعريف ويندوز» أو «USB مباشر» معها أيضًا."));

            paper = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList };
            paper.Items.AddRange(new object[] { "80 ملم (576 نقطة)", "58 ملم (384 نقطة)" });
            paper.SelectedIndex = s.PaperWidthMm == 58 ? 1 : 0;
            Row(g, "عرض الورق", paper);
            mTop = Num(0, 30, (decimal)s.MarginTopMm, 1);
            Row(g, "الهامش العلوي (ملم)", mTop);
            mBottom = Num(0, 30, (decimal)s.MarginBottomMm, 1);
            Row(g, "الهامش السفلي (ملم)", mBottom);
            mSide = Num(0, 15, (decimal)s.MarginSideMm, 1);
            Row(g, "الهامش الجانبي (ملم)", mSide);
            scale = Num(50, 200, s.ScalePercent, 0);
            Row(g, "حجم المحتوى %", scale);
            darkness = Num(10, 90, s.Darkness, 0);
            var dk = Row(g, "درجة السواد %", darkness);
            cut = new CheckBox { Text = "قص الورق بعد الطباعة", Checked = s.Cut, AutoSize = true };
            var ct = Row(g, "", cut);

            var test = new Button { Text = "طباعة تجريبية", AutoSize = true };
            testStatus = new Label { AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(6, 8, 3, 3), MaximumSize = new Size(300, 0) };
            test.Click += async (o, e) =>
            {
                var t = Collect();
                testStatus.Text = "جارٍ الطباعة…";
                test.Enabled = false;
                try
                {
                    await PrintService.PrintTicket(t, null, PrintService.TestTicketHtml(t));
                    testStatus.Text = "أُرسلت ✓";
                }
                catch (Exception ex) { testStatus.Text = "تعذّرت: " + ex.Message; }
                finally { test.Enabled = true; }
            };
            var tr = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft };
            tr.Controls.Add(test);
            tr.Controls.Add(testStatus);
            Row(g, "", tr);

            driverRows = new[] { tp };
            usbRows = new[] { tp, usbNote };
            netRows = new[] { nh, np };
            btRows = new[] { cr, br, btNote };
            dkRows = new[] { dk, ct };
            page.Controls.Add(g);
            return page;
        }

        Control[] dkRows;

        void FillPorts()
        {
            string cur = comPort.Text.Length > 0 ? PortOf(comPort.Text) : s.ComPort;
            comPort.Items.Clear();
            foreach (var p in SerialPrinter.Ports()) comPort.Items.Add(p.Value == p.Key ? p.Key : p.Key + " — " + p.Value);
            comPort.Text = cur;
            for (int i = 0; i < comPort.Items.Count; i++)
                if (PortOf(comPort.Items[i].ToString()) == cur) comPort.SelectedIndex = i;
        }

        static string PortOf(string text)
        {
            var m = System.Text.RegularExpressions.Regex.Match(text ?? "", @"^\s*(COM\d+)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value.ToUpperInvariant() : (text ?? "").Trim();
        }

        static ComboBox PrinterCombo(string current, bool allowDefault)
        {
            var c = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, RightToLeft = RightToLeft.No };
            if (allowDefault) c.Items.Add("(الطابعة الافتراضية في ويندوز)");
            try { foreach (string p in System.Drawing.Printing.PrinterSettings.InstalledPrinters) c.Items.Add(p); } catch { }
            if (current.Length > 0 && !c.Items.Contains(current)) c.Items.Add(current);
            c.SelectedItem = current.Length > 0 ? (object)current : (allowDefault ? c.Items[0] : null);
            return c;
        }

        void UpdateRows()
        {
            string m = PrintModes.All[Math.Max(0, mode.SelectedIndex)];
            var show = new HashSet<Control>();
            if (m == PrintModes.Driver) foreach (var c in driverRows) show.Add(c);
            if (m == PrintModes.Usb) foreach (var c in usbRows) show.Add(c);
            if (m == PrintModes.Network) foreach (var c in netRows) show.Add(c);
            if (m == PrintModes.Bluetooth) foreach (var c in btRows) show.Add(c);
            if (m != PrintModes.Driver) foreach (var c in dkRows) show.Add(c);
            ticketGrid.SuspendLayout();
            foreach (var c in driverRows.Concat(usbRows).Concat(netRows).Concat(btRows).Concat(dkRows).Distinct())
            {
                c.Visible = show.Contains(c);
                Control l;
                if (labels.TryGetValue(c, out l)) l.Visible = c.Visible;
            }
            ticketGrid.ResumeLayout();
        }

        TabPage DocumentTab()
        {
            var page = new TabPage("طابعة المستندات");
            var g = Grid();
            Row(g, "", Note("للتقارير وصفحات A4 (كشف الدفعات، الحالة، قائمة الأطباء)."));
            docPrinter = PrinterCombo(s.DocumentPrinter, true);
            Row(g, "الطابعة", docPrinter);
            docSilent = new CheckBox { Text = "طباعة مباشرة دون نافذة", Checked = s.DocumentSilent, AutoSize = true };
            Row(g, "", docSilent);
            var test = new Button { Text = "طباعة تجريبية", AutoSize = true };
            var st = new Label { AutoSize = true, ForeColor = Color.DimGray, Margin = new Padding(6, 8, 3, 3) };
            test.Click += async (o, e) =>
            {
                var t = Collect();
                st.Text = "جارٍ الطباعة…";
                try
                {
                    var r = await App.Renderer.PrintAsync(null, PrintService.TestDocumentHtml(), t.DocumentPrinter, 0, t);
                    st.Text = r == CoreWebView2PrintStatus.Succeeded ? "أُرسلت ✓" : "تعذّرت: " + r;
                }
                catch (Exception ex) { st.Text = "تعذّرت: " + ex.Message; }
            };
            var tr = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.RightToLeft };
            tr.Controls.Add(test);
            tr.Controls.Add(st);
            Row(g, "", tr);
            page.Controls.Add(g);
            return page;
        }

        TabPage GeneralTab()
        {
            var page = new TabPage("عام");
            var g = Grid();
            showDialog = new CheckBox { Text = "إظهار نافذة الطباعة بدل الطباعة المباشرة (لكل الصفحات)", Checked = s.ShowPrintDialog, AutoSize = true };
            Row(g, "", showDialog);
            closeAfter = new CheckBox { Text = "إغلاق نافذة الطباعة بعد الطباعة", Checked = s.ClosePrintWindows, AutoSize = true };
            Row(g, "", closeAfter);
            fullScreen = new CheckBox { Text = "البدء بملء الشاشة (F11 للتبديل)", Checked = s.StartFullScreen, AutoSize = true };
            Row(g, "", fullScreen);
            autoUpdate = new CheckBox { Text = "التحقق من التحديثات على الخادم", Checked = s.AutoUpdate, AutoSize = true };
            Row(g, "", autoUpdate);
            var upd = new Button { Text = "تحقق الآن", AutoSize = true };
            upd.Click += async (o, e) => { if (App.Main != null) await Updater.CheckAsync(App.Main, true); };
            Row(g, "النسخة " + BuildInfo.Build, upd);
            var logs = new Button { Text = "مجلد السجلات", AutoSize = true };
            logs.Click += (o, e) => { try { Directory.CreateDirectory(Paths.LocalDir); Process.Start("explorer.exe", "\"" + Paths.LocalDir + "\""); } catch { } };
            Row(g, "", logs);
            Row(g, "", Note("الدخول يبقى محفوظًا في هذا الحاسوب. لتسجيل الخروج استخدم زر الخروج في النظام."));
            page.Controls.Add(g);
            return page;
        }

        async void Find()
        {
            findStatus.Text = "جارٍ البحث…";
            try
            {
                string found = await ServerFinder.FindAsync((int)httpPort.Value, t => BeginInvoke(new Action(() => findStatus.Text = t)));
                if (found == null) findStatus.Text = "لم يُعثر على الخادم. تأكد أنه يعمل وعلى الشبكة نفسها.";
                else { ip.Text = found; findStatus.Text = "وُجد الخادم: " + found + " ✓ (احفظ)"; }
            }
            catch (Exception ex) { findStatus.Text = "تعذّر البحث: " + ex.Message; }
        }

        ClientSettings Collect()
        {
            var r = s.Clone();
            r.Server = server.Text;
            r.ServerIp = ip.Text;
            r.HttpsPort = (int)httpsPort.Value;
            r.HttpPort = (int)httpPort.Value;
            r.TicketMode = PrintModes.All[Math.Max(0, mode.SelectedIndex)];
            r.TicketPrinter = ticketPrinter.SelectedItem == null ? "" : ticketPrinter.SelectedItem.ToString();
            r.PaperWidthMm = paper.SelectedIndex == 1 ? 58 : 80;
            r.MarginTopMm = (double)mTop.Value;
            r.MarginBottomMm = (double)mBottom.Value;
            r.MarginSideMm = (double)mSide.Value;
            r.NetworkHost = netHost.Text;
            r.NetworkPort = (int)netPort.Value;
            r.ComPort = PortOf(comPort.Text);
            r.BaudRate = (int)baud.Value;
            r.Cut = cut.Checked;
            r.Darkness = (int)darkness.Value;
            r.ScalePercent = (int)scale.Value;
            r.DocumentPrinter = docPrinter.SelectedIndex <= 0 ? "" : docPrinter.SelectedItem.ToString();
            r.DocumentSilent = docSilent.Checked;
            r.ShowPrintDialog = showDialog.Checked;
            r.ClosePrintWindows = closeAfter.Checked;
            r.StartFullScreen = fullScreen.Checked;
            r.AutoUpdate = autoUpdate.Checked;
            r.Normalize();
            return r;
        }
    }

    // ---------------------------------------------------------------- CI check

    // --selftest <dir>: proves on a real Windows machine that WebView2 starts
    // and the ticket pipeline works: renders the test ticket at 384 dots,
    // writes ticket.png, ticket.bin (ESC/POS) and document.pdf, and with
    // --raw-printer sends ticket.bin through winspool RAW.
    class SelfTestForm : Form
    {
        public int ExitCode = 1;
        readonly string dir, rawPrinter;

        public SelfTestForm(string dir, string rawPrinter)
        {
            this.dir = dir;
            this.rawPrinter = rawPrinter;
            Text = "Dental Clinic self-test";
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Location = new Point(-32000, -32000);
            Size = new Size(200, 100);
            Shown += async (s, e) => await Run();
        }

        async Task Run()
        {
            var report = new StringBuilder();
            try
            {
                Directory.CreateDirectory(dir);
                App.Settings = new ClientSettings { PaperWidthMm = 58, TicketMode = PrintModes.Usb };
                var env = await App.EnvAsync();
                report.AppendLine("webview2 " + env.BrowserVersionString);
                var s = App.Settings;
                string html = PrintService.TestTicketHtml(s);
                byte[] bytes;
                using (var page = await App.Renderer.CaptureAsync(null, html, s.PrintableMm / 25.4 * 96, s.TicketDots))
                {
                    page.Save(Path.Combine(dir, "ticket.png"), ImageFormat.Png);
                    report.AppendLine("ticket image " + page.Width + "x" + page.Height);
                    if (page.Width != 384 || page.Height < 80) throw new Exception("unexpected ticket image size");
                }
                bytes = await PrintService.TicketBytes(s, null, html);
                File.WriteAllBytes(Path.Combine(dir, "ticket.bin"), bytes);
                report.AppendLine("escpos bytes " + bytes.Length);
                if (bytes.Length < 2000 || bytes[2] != 0x1D || bytes[3] != 0x76 || bytes[6] != 48) throw new Exception("unexpected ESC/POS output (384 dots = 48 bytes a row)");
                int ink = 0;
                for (int i = 10; i < bytes.Length - 7; i++) if (bytes[i] != 0) ink++;
                report.AppendLine("ink bytes " + ink);
                if (ink < 200) throw new Exception("the ticket came out blank");
                bool pdf = await App.Renderer.PdfAsync(PrintService.TestDocumentHtml(), Path.Combine(dir, "document.pdf"));
                report.AppendLine("pdf " + pdf);
                if (!pdf) throw new Exception("PrintToPdf failed");
                // The bridge script must at least be valid JavaScript.
                File.WriteAllText(Path.Combine(dir, "bridge.js"), Bridge.Script(s), Encoding.UTF8);
                if (rawPrinter != null)
                {
                    RawPrinter.Write(rawPrinter, bytes, "selftest");
                    report.AppendLine("raw print to " + rawPrinter + " ok");
                }
                ExitCode = 0;
            }
            catch (Exception ex)
            {
                report.AppendLine("FAILED: " + ex);
            }
            try { File.WriteAllText(Path.Combine(dir, "selftest.txt"), report.ToString(), Encoding.UTF8); } catch { }
            Close();
        }
    }

    static class NativeMethods
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll")]
        static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")]
        static extern bool ShowWindow(IntPtr h, int cmd);

        public static void ActivateOther(string title)
        {
            foreach (var p in Process.GetProcessesByName(Process.GetCurrentProcess().ProcessName))
            {
                if (p.Id == Process.GetCurrentProcess().Id || p.MainWindowHandle == IntPtr.Zero) continue;
                ShowWindow(p.MainWindowHandle, 9); // SW_RESTORE
                SetForegroundWindow(p.MainWindowHandle);
                return;
            }
        }
    }
}
