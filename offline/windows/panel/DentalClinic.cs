// Dental Clinic control panel: one window that starts, watches and stops the
// whole offline system (MariaDB, PHP workers, Caddy, CoreDNS, scheduler) with
// no console windows, like the XAMPP control panel. Lives next to config.txt
// in the package root and sits in the tray; can start with Windows.
//
// Built with the .NET Framework compiler that ships with Windows (C# 5):
//   csc /target:winexe /codepage:65001 /win32icon:icon.ico /win32manifest:app.manifest
//       /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Management.dll /r:System.Core.dll
//       /r:System.Web.Extensions.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll DentalClinic.cs
//
// Command line: --autostart (from the Windows Run key: start hidden in the
// tray and start the system), --headless (no window, used by CI), --stop
// (stop everything this folder started, then exit), --apply-update <zip>
// (CI: update to that package), --after-update / --rolled-back (internal,
// see Updater), --screenshots <dir> (CI: pictures of every page, then exit).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: System.Reflection.AssemblyTitle("Dental Clinic Control Panel")]
[assembly: System.Reflection.AssemblyProduct("Dental Clinic Offline")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

namespace DentalClinicPanel
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            string root = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            var engine = new Engine(root);

            if (args.Contains("--stop"))
            {
                engine.StopLeftovers(true);
                return 0;
            }
            int shots = Array.IndexOf(args, "--screenshots");
            if (shots >= 0 && shots + 1 < args.Length)
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                var form = new MainForm(engine, new Updater(engine), false, false, false);
                form.ScreenshotDir = Path.GetFullPath(args[shots + 1]);
                Application.Run(form);
                return 0;
            }
            var updater = new Updater(engine);
            int apply = Array.IndexOf(args, "--apply-update");
            if (apply >= 0 && apply + 1 < args.Length)
            {
                try { updater.Apply(args[apply + 1], true); return 0; }
                catch (Exception ex) { engine.Log("تعذّر التحديث: " + ex.Message); return 1; }
            }
            bool afterUpdate = args.Contains("--after-update"), rolledBack = args.Contains("--rolled-back");
            if (args.Contains("--headless"))
            {
                engine.Start();
                bool started = engine.CurrentState == State.Running;
                if (afterUpdate)
                {
                    updater.AfterUpdate(started, true);
                    if (!started) return 1;
                }
                if (rolledBack && started) updater.AfterRollback();
                if (!started) return 1;
                Thread.Sleep(Timeout.Infinite);
                return 0;
            }

            bool created;
            using (var mutex = new Mutex(true, "Local\\DentalClinicPanel", out created))
            {
                if (!created && (afterUpdate || rolledBack))
                {
                    // The previous panel is still closing after handing over.
                    try { created = mutex.WaitOne(60000); } catch (AbandonedMutexException) { created = true; }
                }
                if (!created)
                {
                    // Already open: bring that window forward instead.
                    try { EventWaitHandle.OpenExisting("Local\\DentalClinicPanelShow").Set(); } catch { }
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(engine, updater, args.Contains("--autostart"), afterUpdate, rolledBack));
                GC.KeepAlive(mutex);
            }
            return 0;
        }
    }

    enum State { Stopped, Starting, Running, Stopping, Error }

    class Service
    {
        public readonly string Key, Name, Port;
        public readonly int Count;
        public readonly Func<int, Process> Launch;
        public readonly Process[] Procs;
        public readonly List<DateTime> Restarts = new List<DateTime>();
        public bool Failed;

        public Service(string key, string name, string port, int count, Func<int, Process> launch)
        {
            Key = key; Name = name; Port = port; Count = count; Launch = launch;
            Procs = new Process[count];
        }

        public int Alive
        {
            get
            {
                int n = 0;
                foreach (var p in Procs)
                {
                    try { if (p != null && !p.HasExited) n++; } catch { }
                }
                return n;
            }
        }
    }

    class Engine
    {
        public const int DbPort = 3307;
        public readonly string Root;
        public volatile State CurrentState = State.Stopped;
        public string LastError = "";
        public string LanIp = "";
        public bool DnsBusy;
        // Set while an update replaces the files: the tunnel stays down.
        public volatile bool NoTunnel;
        public event Action<string> Logged;
        public List<Service> Services = new List<Service>();

        Dictionary<string, string> cfg;
        // config.txt as last saved: the online access settings take effect
        // at once, the rest on the next start.
        volatile Dictionary<string, string> live;
        readonly object opLock = new object();
        readonly object logLock = new object();
        readonly Dictionary<string, object> fileLocks = new Dictionary<string, object>();
        System.Threading.Timer watchdog;
        int checking;

        public Engine(string root)
        {
            Root = root;
            try { Directory.CreateDirectory(LogDir); } catch { }
            cfg = LoadConfig();
            live = cfg;
            BuildServices();
        }

        public string LogDir { get { return P(@"app\storage\logs"); } }
        public string P(string rel) { return Path.Combine(Root, rel); }

        string Get(string key, string def)
        {
            string v;
            return cfg.TryGetValue(key, out v) && v.Length > 0 ? v : def;
        }
        int GetInt(string key, int def)
        {
            int v;
            return int.TryParse(Get(key, ""), out v) ? v : def;
        }
        public string ServerName { get { return Get("SERVER_NAME", "clinic.lan"); } }
        // The name server is optional (2026-10-19, by request): devices can reach
        // the system by its IP, which avoids the stalls a router DNS can cause.
        public bool DnsOn { get { return GetInt("DNS", 1) != 0; } }
        public int HttpPort { get { return GetInt("HTTP_PORT", 80); } }
        public int HttpsPort { get { return GetInt("HTTPS_PORT", 443); } }
        public int Workers { get { return Math.Max(1, GetInt("PHP_WORKERS", 16)); } }

        // Online access (2026-10-31, by request): a Cloudflare tunnel to a
        // site of the local web server that only this computer can reach
        // (TUNNEL_PORT), and the panel's remote control page (PANEL_PORT).
        public int TunnelPort { get { return GetInt("TUNNEL_PORT", 18091); } }
        public int PanelPort { get { return GetInt("PANEL_PORT", 18092); } }
        public int ActiveTunnelPort;
        string Live(string key)
        {
            string v;
            return live.TryGetValue(key, out v) ? v.Trim() : "";
        }
        public bool TunnelOn { get { return Live("TUNNEL") == "1"; } }
        // Optional: a permanent tunnel made in a Cloudflare account, with the
        // two addresses given to it there.
        public string TunnelToken { get { return Live("TUNNEL_TOKEN"); } }
        public string TunnelSiteUrl { get { return Live("TUNNEL_SITE_URL"); } }
        public string TunnelPanelUrl { get { return Live("TUNNEL_PANEL_URL"); } }
        // Backups live outside this folder so replacing or deleting the
        // program never takes them along (2026-10-13).
        public string BackupDir
        {
            get
            {
                string d = Get("BACKUP_DIR", "");
                return d.Length > 0 ? d : DefaultBackupDir(Root);
            }
        }
        public static string DefaultBackupDir(string root)
        {
            return Path.Combine(Path.GetPathRoot(root) ?? @"C:\", "DentalClinicBackups");
        }

        Dictionary<string, string> LoadConfig()
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            string f = P("config.txt");
            if (!File.Exists(f)) return d;
            foreach (var raw in File.ReadAllLines(f))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int i = line.IndexOf('=');
                if (i <= 0) continue;
                d[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
            }
            return d;
        }

        public Dictionary<string, string> ReadConfig() { return LoadConfig(); }

        // Updates the given keys in config.txt in place, keeping its comments.
        public void WriteConfig(Dictionary<string, string> values)
        {
            string f = P("config.txt");
            var lines = File.Exists(f) ? File.ReadAllLines(f).ToList() : new List<string>();
            var left = new Dictionary<string, string>(values, StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < lines.Count; i++)
            {
                string line = lines[i].Trim();
                if (line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                string key = line.Substring(0, eq).Trim();
                if (!left.ContainsKey(key)) continue;
                lines[i] = key + "=" + left[key];
                left.Remove(key);
            }
            foreach (var kv in left) lines.Add(kv.Key + "=" + kv.Value);
            File.WriteAllLines(f, lines);
            live = LoadConfig();
            Log("حُفظت الإعدادات.");
            if (CurrentState == State.Stopped || CurrentState == State.Error)
            {
                cfg = LoadConfig();
                BuildServices();
            }
        }

        public void Restart()
        {
            Stop();
            Start();
        }

        public static List<string> LocalAddresses()
        {
            var list = new List<string>();
            try
            {
                foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                    foreach (var a in ni.GetIPProperties().UnicastAddresses)
                    {
                        if (a.Address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork) continue;
                        string ip = a.Address.ToString();
                        if (!ip.StartsWith("169.254.") && !list.Contains(ip)) list.Add(ip);
                    }
                }
            }
            catch { }
            return list;
        }

        // The MAC address of the computer's real Ethernet or Wi-Fi adapter (virtual,
        // VPN and Bluetooth adapters are skipped), written like Windows does:
        // 04-D4-C4-DD-5D-5D. The adapter that carries serverIp comes first, then one
        // that is connected. Empty when there is none.
        public static string MacAddress(bool wifi, string serverIp)
        {
            string best = ""; int bestRank = -1;
            try
            {
                var type = wifi ? NetworkInterfaceType.Wireless80211 : NetworkInterfaceType.Ethernet;
                foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.NetworkInterfaceType != type) continue;
                    string desc = (ni.Description + " " + ni.Name).ToLowerInvariant();
                    if (new[] { "virtual", "hyper-v", "vmware", "vpn", "tap-", "tunnel", "bluetooth", "loopback", "wan miniport" }.Any(k => desc.Contains(k))) continue;
                    byte[] b = ni.GetPhysicalAddress().GetAddressBytes();
                    if (b.Length != 6) continue;
                    int rank = ni.OperationalStatus == OperationalStatus.Up ? 1 : 0;
                    if (serverIp.Length > 0 && ni.GetIPProperties().UnicastAddresses.Any(a => a.Address.ToString() == serverIp)) rank = 2;
                    if (rank <= bestRank) continue;
                    bestRank = rank;
                    best = string.Join("-", b.Select(x => x.ToString("X2")).ToArray());
                }
            }
            catch { }
            return best;
        }

        public void Log(string msg)
        {
            string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg;
            lock (logLock)
            {
                try { File.AppendAllText(Path.Combine(LogDir, "panel.log"), line + Environment.NewLine, Encoding.UTF8); } catch { }
            }
            var h = Logged;
            if (h != null) h(line);
        }

        void AppendTo(string file, string text)
        {
            object l;
            lock (fileLocks)
            {
                if (!fileLocks.TryGetValue(file, out l)) { l = new object(); fileLocks[file] = l; }
            }
            lock (l)
            {
                try { File.AppendAllText(file, text + Environment.NewLine); } catch { }
            }
        }

        public ProcessStartInfo Info(string file, string args, string dir)
        {
            var si = new ProcessStartInfo(file, args);
            si.UseShellExecute = false;
            si.CreateNoWindow = true;
            si.WindowStyle = ProcessWindowStyle.Hidden;
            // Every child gets real standard handles: php-cgi exits at once
            // without them.
            si.RedirectStandardInput = true;
            si.RedirectStandardOutput = true;
            si.RedirectStandardError = true;
            si.StandardOutputEncoding = Encoding.UTF8;
            si.StandardErrorEncoding = Encoding.UTF8;
            si.WorkingDirectory = dir ?? Root;
            return si;
        }

        // A long-running service; its output goes to logs\<logName>.
        Process Spawn(string file, string args, string dir, string logName)
        {
            string log = Path.Combine(LogDir, logName);
            var p = new Process();
            p.StartInfo = Info(file, args, dir);
            p.OutputDataReceived += (s, e) => { if (e.Data != null) AppendTo(log, e.Data); };
            p.ErrorDataReceived += (s, e) => { if (e.Data != null) AppendTo(log, e.Data); };
            p.Start();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            return p;
        }

        class Result { public int Code; public string Output; }

        // A one-off command: waits for it and returns its exit code and output.
        Result Run(string file, string args, string dir, int timeoutMs)
        {
            var sb = new StringBuilder();
            var p = new Process();
            p.StartInfo = Info(file, args, dir);
            DataReceivedEventHandler h = (s, e) => { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
            p.OutputDataReceived += h;
            p.ErrorDataReceived += h;
            try
            {
                p.Start();
            }
            catch (Exception ex)
            {
                return new Result { Code = -1, Output = ex.Message };
            }
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            p.StandardInput.Close();
            if (!p.WaitForExit(timeoutMs))
            {
                Kill(p.Id, true);
                return new Result { Code = -1, Output = sb + "(timed out)" };
            }
            p.WaitForExit();
            lock (sb) return new Result { Code = p.ExitCode, Output = sb.ToString().Trim() };
        }

        static string Tail(string text, int lines)
        {
            var all = (text ?? "").Split('\n').Select(s => s.TrimEnd('\r')).Where(s => s.Trim().Length > 0).ToArray();
            return string.Join(Environment.NewLine, all.Skip(Math.Max(0, all.Length - lines)));
        }

        void Kill(int pid, bool tree)
        {
            Run(Path.Combine(Environment.SystemDirectory, "taskkill.exe"), (tree ? "/T " : "") + "/F /PID " + pid, Root, 15000);
        }

        public static bool TcpInUse(int port)
        {
            return IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners().Any(ep => ep.Port == port);
        }
        // " (اسم البرنامج, PID n)" for the program listening on [port], from
        // netstat, so the user knows what to close; empty when unknown.
        string PortOwner(int port)
        {
            try
            {
                var r = Run(Path.Combine(Environment.SystemDirectory, "netstat.exe"), "-ano -p TCP", Root, 15000);
                foreach (var line in r.Output.Split('\n'))
                {
                    var f = line.Split(new[] { ' ', '\t', '\r' }, StringSplitOptions.RemoveEmptyEntries);
                    if (f.Length < 5 || f[3] != "LISTENING" || !f[1].EndsWith(":" + port)) continue;
                    int pid;
                    if (!int.TryParse(f[4], out pid)) continue;
                    if (pid == 4) return " (System - خادم ويب ويندوز، PID 4)";
                    try { using (var proc = Process.GetProcessById(pid)) return " (" + proc.ProcessName + ", PID " + pid + ")"; }
                    catch { return " (PID " + pid + ")"; }
                }
            }
            catch { }
            return "";
        }
        static bool UdpInUse(int port)
        {
            return IPGlobalProperties.GetIPGlobalProperties().GetActiveUdpListeners().Any(ep => ep.Port == port);
        }

        void BuildServices()
        {
            string data = P("data");
            string dbArgs = "--datadir=\"" + data + "\" --port=" + DbPort + " --bind-address=127.0.0.1" +
                " --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci" +
                " --max-connections=500 --innodb-buffer-pool-size=512M --console";
            int workers = Workers;
            Services = new List<Service>
            {
                new Service("db", "قاعدة البيانات (MariaDB)", DbPort.ToString(), 1,
                    i => Spawn(P(@"mariadb\bin\mariadbd.exe"), dbArgs, Root, "mariadb.log")),
                new Service("web", "خادم الويب (Caddy)", HttpPort + " / " + HttpsPort, 1,
                    i => Spawn(P(@"caddy\caddy.exe"), "run --config \"" + P("Caddyfile") + "\" --adapter caddyfile", Root, "caddy-console.log")),
                new Service("php", "معالجات PHP", "9100-" + (9100 + workers - 1), workers,
                    i => Spawn(P(@"php\php-cgi.exe"), "-b 127.0.0.1:" + (9100 + i), P(@"app\public"), "php-cgi.log")),
                new Service("dns", "خادم الأسماء (" + ServerName + ")" + (DnsOn ? "" : " - معطّل"), "53", DnsOn ? 1 : 0,
                    i => Spawn(P(@"coredns\coredns.exe"), "-conf \"" + P("Corefile") + "\"", Root, "coredns.log")),
                new Service("scheduler", "المهام المجدولة", "-", 1,
                    i => Spawn(P(@"php\php.exe"), "artisan schedule:work", P("app"), "scheduler.log")),
            };
        }

        Service Svc(string key) { return Services.First(s => s.Key == key); }

        public void Start()
        {
            lock (opLock)
            {
                if (CurrentState == State.Running) return;
                CurrentState = State.Starting;
                LastError = "";
                try
                {
                    DoStart();
                    CurrentState = State.Running;
                    Log("النظام يعمل.");
                    if (watchdog == null) watchdog = new System.Threading.Timer(_ => Check(), null, 3000, 3000);
                }
                catch (Exception ex)
                {
                    LastError = ex.Message;
                    Log("تعذّر التشغيل: " + ex.Message);
                    StopProcesses();
                    CurrentState = State.Error;
                }
            }
        }

        void DoStart()
        {
            cfg = LoadConfig();
            Log("بدء التشغيل...");
            RotateLogs();
            StopLeftovers(false);
            BuildServices();

            Environment.SetEnvironmentVariable("XDG_DATA_HOME", P("caddy-data"));
            Environment.SetEnvironmentVariable("XDG_CONFIG_HOME", P("caddy-data"));
            Environment.SetEnvironmentVariable("PHPRC", P("php"));
            Environment.SetEnvironmentVariable("PHP_FCGI_MAX_REQUESTS", "10000");
            // Read by config/backup.php (and cached by `artisan optimize`).
            Environment.SetEnvironmentVariable("BACKUP_PATH", BackupDir);
            Environment.SetEnvironmentVariable("BACKUP_DAILY", "true");
            // Activation (2026-10-17): the app works only once activated on
            // this computer, which it recognises by Windows' MachineGuid.
            Environment.SetEnvironmentVariable("OFFLINE_EDITION", "true");
            Environment.SetEnvironmentVariable("DENTAL_MACHINE_GUID", MachineGuid());
            // PHP behind FastCGI does not always see this process's
            // environment, so the id is also left where the app reads it;
            // rewritten on every start, so a copied folder gets this computer's.
            try { File.WriteAllText(P(@"app\storage\app\machine-guid.txt"), MachineGuid()); }
            catch (Exception ex) { Log("تنبيه: تعذّر حفظ رقم الحاسوب: " + ex.Message); }
            try { Directory.CreateDirectory(BackupDir); }
            catch (Exception ex) { Log("تنبيه: تعذّر إنشاء مجلد النسخ الاحتياطية " + BackupDir + ": " + ex.Message); }
            string path = Environment.GetEnvironmentVariable("PATH") ?? "";
            if (path.IndexOf(P("php"), StringComparison.OrdinalIgnoreCase) < 0)
                Environment.SetEnvironmentVariable("PATH", P("php") + ";" + P(@"mariadb\bin") + ";" + path);

            var busy = new List<string>();
            foreach (int port in new[] { HttpPort, HttpsPort, DbPort })
                if (TcpInUse(port)) busy.Add(port + PortOwner(port));
            if (busy.Count > 0)
                throw new Exception("المنفذ " + string.Join(" و ", busy) + " مستخدم من برنامج آخر (مثل XAMPP أو IIS أو Skype). " +
                    "أغلق ذلك البرنامج، أو غيّر HTTP_PORT (مثلًا 8080) من زر الإعدادات." +
                    (busy.Any(b => b.Contains("خادم ويب ويندوز")) ? " البرنامج هو خادم ويب ويندوز: شغّل في CMD كمسؤول الأمر  net stop http /y" : ""));
            DnsBusy = UdpInUse(53);
            // The tunnel's local site is left out rather than failing the start.
            ActiveTunnelPort = TcpInUse(TunnelPort) ? 0 : TunnelPort;
            if (ActiveTunnelPort == 0) Log("تنبيه: المنفذ " + TunnelPort + " مستخدم من برنامج آخر، فلن يعمل الوصول عبر الإنترنت. غيّر TUNNEL_PORT في config.txt.");

            LanIp = Prepare();
            Log("عنوان هذا الجهاز على الشبكة: " + LanIp);

            string php = P(@"php\php.exe");
            if (Run(php, "-v", Root, 30000).Code != 0)
            {
                Log("تثبيت مكتبة Microsoft Visual C++ التي يحتاجها PHP...");
                var si = new ProcessStartInfo(P("vc_redist.x64.exe"), "/install /passive /norestart");
                si.UseShellExecute = true;
                using (var p = Process.Start(si)) p.WaitForExit();
                if (Run(php, "-v", Root, 30000).Code != 0)
                    throw new Exception("PHP لا يعمل. شغّل vc_redist.x64.exe من مجلد البرنامج ثم أعد المحاولة.");
            }

            string data = P("data");
            if (!Directory.Exists(Path.Combine(data, "mysql")))
            {
                Log("أول تشغيل: إنشاء ملفات قاعدة البيانات...");
                var r = Run(P(@"mariadb\bin\mariadb-install-db.exe"), "--datadir=\"" + data + "\" --port=" + DbPort, Root, 300000);
                if (r.Code != 0) throw new Exception("تعذّر إنشاء قاعدة البيانات: " + Tail(r.Output, 3));
            }

            Log("تشغيل قاعدة البيانات...");
            var db = Svc("db");
            db.Procs[0] = db.Launch(0);
            string admin = P(@"mariadb\bin\mariadb-admin.exe");
            bool up = false;
            for (int i = 0; i < 90 && !up; i++)
            {
                if (db.Procs[0].HasExited) break;
                up = Run(admin, "--user=root --host=127.0.0.1 --port=" + DbPort + " ping", Root, 10000).Code == 0;
                if (!up) Thread.Sleep(1000);
            }
            if (!up)
                throw new Exception("قاعدة البيانات لم تبدأ. " + Tail(ReadLog("mariadb.log"), 3));
            var c = Run(P(@"mariadb\bin\mariadb.exe"), "--user=root --host=127.0.0.1 --port=" + DbPort +
                " -e \"CREATE DATABASE IF NOT EXISTS dental CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci\"", Root, 30000);
            if (c.Code != 0) throw new Exception("تعذّر إنشاء قاعدة البيانات dental: " + Tail(c.Output, 3));

            string env = P(@"app\.env");
            if (!File.Exists(env))
            {
                File.Copy(P(@"app\.env.offline"), env);
                Artisan("key:generate --force", 120000, true);
                Prepare(); // writes APP_URL into the new .env
            }
            else
            {
                // A new version brings migrations: keep a copy of the data
                // as it was before they run (the command skips otherwise).
                // The settings cached by the previous version may predate
                // the backup settings, so they are dropped first.
                Artisan("config:clear", 120000, false);
                var b = RunArtisan("backup:run --before-update", 1800000);
                if (b.Code != 0) Log("تنبيه: تعذّرت النسخة الاحتياطية قبل التحديث. التفاصيل في artisan.log");
                else if (b.Output.Contains("Backup created")) Log("حُفظت نسخة احتياطية قبل التحديث في " + BackupDir);
            }
            Log("تحديث جداول قاعدة البيانات...");
            Artisan("migrate --force", 900000, true);
            if (!File.Exists(Path.Combine(data, ".seeded")))
            {
                Log("إضافة البيانات الأولية...");
                if (Artisan("db:seed --force", 900000, false)) File.WriteAllText(Path.Combine(data, ".seeded"), "seeded");
            }
            if (!Directory.Exists(P(@"app\public\storage"))) Artisan("storage:link", 60000, false);
            Artisan("optimize", 300000, false);

            Log("تشغيل معالجات PHP وخادم الويب...");
            foreach (var key in new[] { "php", "scheduler", "dns", "web" })
            {
                var s = Svc(key);
                for (int i = 0; i < s.Count; i++) s.Procs[i] = s.Launch(i);
            }

            // Wait for the site to answer on this computer.
            bool ok = false;
            for (int i = 0; i < 30 && !ok; i++)
            {
                if (Svc("web").Procs[0].HasExited)
                    throw new Exception("خادم الويب توقف: " + Tail(ReadLog("caddy-console.log"), 3));
                ok = Answers("http://127.0.0.1" + (HttpPort == 80 ? "" : ":" + HttpPort) + "/login");
                if (!ok) Thread.Sleep(1000);
            }
            if (!ok) Log("تنبيه: الموقع لم يستجب بعد، قد يحتاج لحظات.");
            if (DnsOn && (DnsBusy || Svc("dns").Alive == 0))
                Log("تنبيه: المنفذ 53 مستخدم من برنامج آخر، فلن يعمل الاسم " + ServerName + ". يمكن الدخول بالرقم https://" + LanIp);
            SaveSettingsCopy();
        }

        // The settings and the clinic certificate, so a reinstall can put
        // them back and devices keep trusting it (BackupDir\settings).
        void SaveSettingsCopy()
        {
            try
            {
                string dest = Path.Combine(BackupDir, "settings");
                Directory.CreateDirectory(dest);
                File.Copy(P(@"app\.env"), Path.Combine(dest, ".env"), true);
                if (File.Exists(P("config.txt"))) File.Copy(P("config.txt"), Path.Combine(dest, "config.txt"), true);
                CopyDir(P("caddy-data"), Path.Combine(dest, "caddy-data"));
            }
            catch (Exception ex) { Log("تنبيه: تعذّر حفظ نسخة من الإعدادات: " + ex.Message); }
        }

        static void CopyDir(string from, string to)
        {
            if (!Directory.Exists(from)) return;
            Directory.CreateDirectory(to);
            foreach (var f in Directory.GetFiles(from)) File.Copy(f, Path.Combine(to, Path.GetFileName(f)), true);
            foreach (var d in Directory.GetDirectories(from)) CopyDir(d, Path.Combine(to, Path.GetFileName(d)));
        }

        // "نسخة احتياطية الآن": the database and uploaded files, now.
        public bool BackupNow(out string message)
        {
            var r = RunArtisan("backup:run --force", 1800000);
            bool ok = r.Code == 0;
            message = ok ? "حُفظت نسخة احتياطية في " + BackupDir : "تعذّرت النسخة الاحتياطية: " + Tail(r.Output, 3);
            Log(message);
            return ok;
        }

        public bool DatabaseUp()
        {
            return Run(P(@"mariadb\bin\mariadb-admin.exe"), "--user=root --host=127.0.0.1 --port=" + DbPort + " ping", Root, 10000).Code == 0;
        }

        public string LatestBackup()
        {
            try
            {
                var f = new DirectoryInfo(BackupDir).GetFiles("*.zip").OrderByDescending(x => x.LastWriteTimeUtc).FirstOrDefault();
                return f == null ? null : f.FullName;
            }
            catch { return null; }
        }

        // A file from elsewhere (e.g. Downloads under an Arabic user name) is
        // copied into the backups folder under a plain name first, so PHP
        // gets a path it can open (2026-10-18). A file already there is used
        // as it is, so calling this twice copies once.
        public string LocalBackupPath(string file)
        {
            string arg = file;
            try
            {
                var dir = Path.GetFullPath(BackupDir).TrimEnd('\\');
                if (!string.Equals(Path.GetDirectoryName(Path.GetFullPath(file)).TrimEnd('\\'), dir, StringComparison.OrdinalIgnoreCase)
                    || Path.GetFileName(file).Any(c => c > 127))
                {
                    Directory.CreateDirectory(dir);
                    arg = Path.Combine(dir, "restore_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + Path.GetExtension(file).ToLowerInvariant());
                    File.Copy(file, arg, true);
                }
            }
            catch (Exception ex) { Log("تنبيه: تعذّر نسخ الملف إلى مجلد النسخ: " + ex.Message); }
            return arg;
        }

        // Puts a backup back; the current data is saved first by the command.
        public bool RestoreBackup(string file, out string message)
        {
            return RestoreBackup(file, false, null, out message);
        }

        // With merge (2026-10-20, by request) nothing here is replaced: the
        // chosen tables only get the rows they lack (backup:restore --merge).
        public bool RestoreBackup(string file, bool merge, IList<string> tables, out string message)
        {
            Log((merge ? "إضافة البيانات الناقصة من النسخة " : "استعادة النسخة ") + Path.GetFileName(file) + "...");
            string arg = LocalBackupPath(file);
            string args = "backup:restore \"" + arg + "\" --force";
            if (merge)
            {
                args += " --merge";
                if (tables != null && tables.Count > 0) args += " --tables=" + string.Join(",", tables.ToArray());
            }
            var r = RunArtisan(args, 3600000);
            bool ok = r.Code == 0;
            if (merge)
                message = ok ? "أُضيفت البيانات الناقصة من " + Path.GetFileName(file) + " وبقيت البيانات الحالية كما هي. " + Tail(r.Output, 1)
                             : "تعذّرت إضافة بعض البيانات: " + Tail(r.Output, 3);
            else
                message = ok ? "تمت الاستعادة من " + Path.GetFileName(file) + ". حُفظت البيانات السابقة كنسخة احتياطية أيضًا."
                             : "تعذّرت الاستعادة: " + Tail(r.Output, 3);
            Log(message);
            return ok;
        }

        // The sections (tables) a backup holds, for choosing what to take
        // from it (2026-10-20); null with an error when it can't be read.
        public List<BackupSection> BackupSections(string file, out string error)
        {
            error = null;
            var r = RunArtisan("backup:tables \"" + file + "\"", 600000);
            var json = r.Output.Split('\n').Select(l => l.Trim()).LastOrDefault(l => l.StartsWith("["));
            if (r.Code != 0 || json == null)
            {
                error = Tail(r.Output, 3);
                return null;
            }
            var list = new List<BackupSection>();
            var items = new JavaScriptSerializer().DeserializeObject(json) as object[];
            if (items != null)
            {
                foreach (var o in items)
                {
                    var d = o as Dictionary<string, object>;
                    if (d == null || !d.ContainsKey("table")) continue;
                    list.Add(new BackupSection
                    {
                        Table = d["table"] as string,
                        Label = d.ContainsKey("label") ? d["label"] as string : d["table"] as string,
                        Rows = d.ContainsKey("rows") && d["rows"] is bool && (bool)d["rows"],
                    });
                }
            }
            return list;
        }

        static bool Answers(string url)
        {
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Timeout = 5000;
                req.AllowAutoRedirect = false;
                using (req.GetResponse()) return true;
            }
            catch (WebException ex)
            {
                return ex.Response != null; // any HTTP answer means the server is up
            }
            catch { return false; }
        }

        string ReadLog(string name)
        {
            try
            {
                using (var fs = new FileStream(Path.Combine(LogDir, name), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                using (var sr = new StreamReader(fs)) return sr.ReadToEnd();
            }
            catch { return ""; }
        }

        Result RunArtisan(string args, int timeoutMs)
        {
            var r = Run(P(@"php\php.exe"), "artisan " + args, P("app"), timeoutMs);
            AppendTo(Path.Combine(LogDir, "artisan.log"), DateTime.Now.ToString("s") + " artisan " + args + " (" + r.Code + ")" + Environment.NewLine + r.Output);
            return r;
        }

        bool Artisan(string args, int timeoutMs, bool required)
        {
            var r = RunArtisan(args, timeoutMs);
            if (r.Code != 0)
            {
                if (required) throw new Exception("فشل أمر " + args + ": " + Tail(r.Output, 3));
                Log("تنبيه: فشل أمر " + args + ". التفاصيل في artisan.log");
            }
            return r.Code == 0;
        }

        // Writes php.ini, Caddyfile, Corefile and APP_URL for this folder and
        // network; returns the computer's LAN address.
        string Prepare()
        {
            string args = string.Format(
                "-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Root \"{1}\" -ServerName \"{2}\" -Workers {3} -ServerIp \"{4}\" -HttpPort {5} -HttpsPort {6} -AutoOpen {7} -TunnelPort {8}",
                P("prepare.ps1"), Root, ServerName, Workers, Get("SERVER_IP", ""), HttpPort, HttpsPort, DnsOn ? GetInt("AUTO_OPEN", 1) : 0, ActiveTunnelPort);
            var r = Run(Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"), args, Root, 120000);
            if (r.Code != 0) throw new Exception("تعذّر تجهيز ملفات الإعداد: " + Tail(r.Output, 3));
            var ip = r.Output.Split('\n').Select(s => s.Trim()).LastOrDefault(s => Regex.IsMatch(s, @"^\d+\.\d+\.\d+\.\d+$"));
            return ip ?? "127.0.0.1";
        }

        void RotateLogs()
        {
            foreach (var name in new[] { "panel.log", "mariadb.log", "php-cgi.log", "scheduler.log", "coredns.log", "caddy-console.log", "artisan.log" })
            {
                try
                {
                    var f = new FileInfo(Path.Combine(LogDir, name));
                    if (f.Exists && f.Length > 10 * 1024 * 1024)
                    {
                        string old = f.FullName + ".old";
                        if (File.Exists(old)) File.Delete(old);
                        f.MoveTo(old);
                    }
                }
                catch { }
            }
        }

        // Restarts anything that exits while the system is running.
        void Check()
        {
            if (CurrentState != State.Running) return;
            if (Interlocked.Exchange(ref checking, 1) == 1) return;
            try
            {
                foreach (var s in Services)
                {
                    for (int i = 0; i < s.Count; i++)
                    {
                        if (CurrentState != State.Running || s.Failed) break;
                        var p = s.Procs[i];
                        bool alive;
                        try { alive = p != null && !p.HasExited; } catch { alive = false; }
                        if (alive) continue;
                        if (s.Key == "dns" && DnsBusy) continue;
                        s.Restarts.RemoveAll(t => (DateTime.Now - t).TotalMinutes > 2);
                        if (s.Restarts.Count >= s.Count * 3 + 5)
                        {
                            s.Failed = true;
                            Log("الخدمة «" + s.Name + "» تتوقف باستمرار، أوقفت إعادة تشغيلها. راجع سجلاتها.");
                            break;
                        }
                        s.Restarts.Add(DateTime.Now);
                        if (s.Key != "php") Log("الخدمة «" + s.Name + "» توقفت، تتم إعادة تشغيلها.");
                        try { s.Procs[i] = s.Launch(i); }
                        catch (Exception ex) { Log("تعذّر تشغيل «" + s.Name + "»: " + ex.Message); }
                    }
                }
            }
            finally { checking = 0; }
        }

        public void Stop()
        {
            lock (opLock)
            {
                if (CurrentState == State.Stopped) return;
                CurrentState = State.Stopping;
                Log("إيقاف الخدمات...");
                StopProcesses();
                CurrentState = State.Stopped;
                Log("تم الإيقاف.");
            }
        }

        void StopProcesses()
        {
            foreach (var s in Services)
            {
                if (s.Key == "db") continue;
                for (int i = 0; i < s.Count; i++)
                {
                    try { if (s.Procs[i] != null && !s.Procs[i].HasExited) Kill(s.Procs[i].Id, true); } catch { }
                }
            }
            StopLeftovers(false); // shuts the database down cleanly, then sweeps the rest
            foreach (var s in Services) s.Failed = false;
        }

        // Stops every process this folder started, including ones left by an
        // earlier panel or by the old Start.bat: supervisors first so nothing
        // respawns, then a clean database shutdown, then the rest.
        // The tunnel (cloudflared) is left running unless [tunnel]: a free
        // tunnel gets a new address each time it starts.
        public void StopLeftovers(bool tunnel)
        {
            var found = FindOwn(tunnel);
            var supervisors = found.Where(f => f.Item2 == "dentalclinic.exe" || f.Item2 == "cmd.exe" || f.Item2 == "powershell.exe").ToList();
            foreach (var f in supervisors) Kill(f.Item1, false);

            if (found.Any(f => f.Item2 == "mariadbd.exe" || f.Item2 == "mysqld.exe"))
            {
                Run(P(@"mariadb\bin\mariadb-admin.exe"), "--user=root --host=127.0.0.1 --port=" + DbPort + " shutdown", Root, 30000);
                for (int i = 0; i < 30; i++)
                {
                    if (!FindOwn(tunnel).Any(f => f.Item2 == "mariadbd.exe" || f.Item2 == "mysqld.exe")) break;
                    Thread.Sleep(1000);
                }
            }
            // Sweep until nothing is left: the scheduler can spawn its
            // minute's `schedule:run` (cmd + php) just as it is being
            // stopped, and that child would otherwise outlive the panel.
            for (int i = 0; i < 10; i++)
            {
                var left = FindOwn(tunnel);
                if (left.Count == 0) break;
                foreach (var f in left) Kill(f.Item1, true);
                Thread.Sleep(500);
            }
        }

        List<Tuple<int, string>> FindOwn(bool tunnel)
        {
            var list = new List<Tuple<int, string>>();
            int self = Process.GetCurrentProcess().Id;
            string prefix = Root + "\\";
            try
            {
                using (var q = new ManagementObjectSearcher("SELECT ProcessId, Name, ExecutablePath, CommandLine FROM Win32_Process"))
                {
                    foreach (ManagementObject mo in q.Get())
                    {
                        int pid = Convert.ToInt32(mo["ProcessId"]);
                        if (pid == self) continue;
                        string name = ((mo["Name"] as string) ?? "").ToLowerInvariant();
                        string exe = (mo["ExecutablePath"] as string) ?? "";
                        string cmd = (mo["CommandLine"] as string) ?? "";
                        bool mine = exe.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
                        if (!mine && (name == "cmd.exe" || name == "powershell.exe") && cmd.IndexOf(Root, StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            string c = cmd.ToLowerInvariant();
                            mine = c.Contains("start.bat") || c.Contains("workers.ps1") || c.Contains("php-cgi");
                        }
                        if (mine && !tunnel && name == "cloudflared.exe") mine = false;
                        if (mine) list.Add(Tuple.Create(pid, name));
                    }
                }
            }
            catch { }
            return list;
        }

        public bool FirewallReady()
        {
            // The rule must also cover the ports in use (they can change in Settings).
            var r = Run(Path.Combine(Environment.SystemDirectory, "netsh.exe"), "advfirewall firewall show rule name=\"DentalClinic Web\"", Root, 15000);
            return r.Code == 0 && r.Output.Contains(HttpPort + "," + HttpsPort);
        }

        // Lets devices on the local network reach the web server and DNS.
        // Asks Windows for administrator rights.
        public void SetupFirewall()
        {
            string rules =
                "netsh advfirewall firewall delete rule name=\"DentalClinic Web\" & " +
                "netsh advfirewall firewall delete rule name=\"DentalClinic DNS\" & " +
                "netsh advfirewall firewall add rule name=\"DentalClinic Web\" dir=in action=allow protocol=TCP localport=" + HttpPort + "," + HttpsPort + " remoteip=localsubnet profile=any & " +
                "netsh advfirewall firewall add rule name=\"DentalClinic DNS\" dir=in action=allow protocol=UDP localport=53 remoteip=localsubnet profile=any";
            var si = new ProcessStartInfo("cmd.exe", "/c " + rules);
            si.UseShellExecute = true;
            si.Verb = "runas";
            si.WindowStyle = ProcessWindowStyle.Hidden;
            using (var p = Process.Start(si)) p.WaitForExit();
        }

        public static string MachineGuid()
        {
            try
            {
                using (var hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (var key = hklm.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography"))
                    return key == null ? "" : (key.GetValue("MachineGuid") as string ?? "");
            }
            catch { return ""; }
        }

        public string LocalUrl { get { return "http://localhost" + (HttpPort == 80 ? "" : ":" + HttpPort); } }
        public string NetUrl { get { return "https://" + ServerName + (HttpsPort == 443 ? "" : ":" + HttpsPort); } }
        public string IpUrl { get { return "https://" + LanIp + (HttpsPort == 443 ? "" : ":" + HttpsPort); } }
        public string SetupUrl { get { return "http://" + ServerName + (HttpPort == 80 ? "" : ":" + HttpPort) + "/setup"; } }
    }

    // In-app updates (2026-10-14, by request), like Telegram Desktop: the
    // panel looks for a newer offline build on the hosting, downloads it in the
    // background with a progress bar (resuming where it stopped), checks the
    // whole file against its SHA-256, and only then offers "تحديث الآن".
    // Updating backs the data up, stops the system, swaps the program
    // folders while keeping data, config.txt, the certificate, app\.env and
    // app\storage, and starts the new version. If the new version does not
    // start, the old files come back and the data is restored from the
    // backup taken just before.
    class UpdateInfo
    {
        public int Build;
        public string Url, Sha256;
        public long Size;
    }

    enum UpdateState { Idle, Checking, UpToDate, Downloading, Paused, Ready, Applying, Error }

    class Updater
    {
        // Updates come from the hosting (2026-10-17, by request), only for a
        // computer activated with its university's code.
        const string LatestApi = "https://dental.azoclinic.duckdns.org/api/v1/offline/latest";
        const string TagPrefix = "offline-build-";
        // Never replaced by an update: the data and this computer's settings.
        static readonly string[] KeepRoot = { "data", "config.txt", "caddy-data", "Caddyfile", "Corefile", "lan-ip.txt", "updates", "panel.ini" };
        static readonly string[] KeepApp = { ".env", "storage" };

        readonly Engine engine;
        public readonly int CurrentBuild;
        public volatile UpdateState State = UpdateState.Idle;
        public volatile UpdateInfo Available;
        public string Error = "";
        public long Received, Total;
        public double Speed;
        public volatile bool PauseRequested;
        public event Action<UpdateInfo> BecameReady;
        readonly AutoResetEvent wake = new AutoResetEvent(false);
        Thread loop;

        public Updater(Engine engine)
        {
            this.engine = engine;
            CurrentBuild = ReadBuild(engine.P("version.txt"));
        }

        string Dir { get { return engine.P("updates"); } }
        string RollbackDir { get { return Path.Combine(Dir, "rollback"); } }
        string ZipPath(UpdateInfo info) { return Path.Combine(Dir, TagPrefix + info.Build + ".zip"); }

        static int ReadBuild(string file)
        {
            int n;
            try { if (File.Exists(file) && int.TryParse(File.ReadAllText(file).Trim(), out n)) return n; } catch { }
            return 0;
        }

        // Checks now and then every 3 hours; downloads by itself.
        public void StartBackground()
        {
            if (loop != null) return;
            loop = new Thread(() =>
            {
                wake.WaitOne(15000);
                while (true)
                {
                    TimeSpan next = TimeSpan.FromHours(3);
                    try
                    {
                        if (State != UpdateState.Applying && !PauseRequested) CheckAndDownload();
                    }
                    catch (Exception ex)
                    {
                        Error = ex.Message;
                        State = PauseRequested ? UpdateState.Paused : UpdateState.Error;
                        if (!PauseRequested) next = TimeSpan.FromMinutes(10);
                    }
                    wake.WaitOne(next);
                }
            });
            loop.IsBackground = true;
            loop.Start();
        }

        public void CheckNow() { PauseRequested = false; wake.Set(); }
        public void Pause() { PauseRequested = true; }

        void CheckAndDownload()
        {
            if (State == UpdateState.Ready) return;
            State = UpdateState.Checking;
            Error = "";
            var info = Check();
            if (info == null) { State = UpdateState.UpToDate; return; }
            Available = info;
            Download(info);
            State = UpdateState.Ready;
            var h = BecameReady;
            if (h != null) h(info);
        }

        UpdateInfo Check()
        {
            var license = ReadLicense();
            if (license == null) return null; // not activated yet: nothing to update
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // TLS 1.2
            var req = (HttpWebRequest)WebRequest.Create(LatestApi + "?code=" + Uri.EscapeDataString(license[0]) + "&machine=" + Uri.EscapeDataString(license[1]) + "&build=" + CurrentBuild);
            req.UserAgent = "DentalClinicPanel";
            req.Accept = "application/json";
            req.Timeout = 30000;
            string json;
            try
            {
                using (var resp = req.GetResponse())
                using (var sr = new StreamReader(resp.GetResponseStream())) json = sr.ReadToEnd();
            }
            catch (WebException ex)
            {
                var r = ex.Response as HttpWebResponse;
                if (r != null && r.StatusCode == HttpStatusCode.Forbidden)
                    throw new Exception("رمز التفعيل لهذا الحاسوب لم يعد يستلم التحديثات. راجع إدارة النظام.");
                throw;
            }
            var latest = new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string, object>;
            if (latest == null || !latest.ContainsKey("build") || !latest.ContainsKey("url")) return null;
            int n = Convert.ToInt32(latest["build"]);
            if (n <= CurrentBuild) return null;
            string sha = latest.ContainsKey("sha256") ? latest["sha256"] as string : null;
            return new UpdateInfo
            {
                Build = n,
                Url = (string)latest["url"],
                Size = Convert.ToInt64(latest["size"]),
                Sha256 = string.IsNullOrEmpty(sha) ? null : sha.ToLowerInvariant(),
            };
        }

        // The activation code and machine id saved by the app's /activate page.
        public string[] ReadLicense()
        {
            try
            {
                string file = engine.P(@"app\storage\app\offline-license.json");
                if (!File.Exists(file)) return null;
                var saved = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(file, Encoding.UTF8)) as Dictionary<string, object>;
                var payload = saved == null ? null : new JavaScriptSerializer().DeserializeObject(saved["payload"] as string) as Dictionary<string, object>;
                if (payload == null) return null;
                return new[] { payload["code"] as string, payload["machine_id"] as string };
            }
            catch { return null; }
        }

        // Resumable download into updates\, kept as .part until it is whole
        // and its SHA-256 matches.
        void Download(UpdateInfo info)
        {
            Directory.CreateDirectory(Dir);
            string done = ZipPath(info);
            Total = info.Size;
            if (File.Exists(done) && new FileInfo(done).Length == info.Size) { Received = info.Size; return; }
            foreach (var old in Directory.GetFiles(Dir, TagPrefix + "*"))
                if (!Path.GetFileName(old).StartsWith(TagPrefix + info.Build + ".")) TryDelete(old);

            long free = new DriveInfo(Path.GetPathRoot(engine.Root)).AvailableFreeSpace;
            if (free < info.Size * 4 + 500L * 1024 * 1024)
                throw new Exception("لا توجد مساحة كافية على القرص للتحديث (يحتاج " + Mb(info.Size * 4) + " م.ب تقريبًا).");

            string part = done + ".part";
            long have = File.Exists(part) ? new FileInfo(part).Length : 0;
            if (have > info.Size) { TryDelete(part); have = 0; }
            if (have < info.Size)
            {
                State = UpdateState.Downloading;
                var req = (HttpWebRequest)WebRequest.Create(info.Url);
                req.UserAgent = "DentalClinicPanel";
                req.Timeout = 30000;
                req.ReadWriteTimeout = 60000;
                if (have > 0) req.AddRange(have);
                using (var resp = (HttpWebResponse)req.GetResponse())
                {
                    bool resumed = have > 0 && resp.StatusCode == HttpStatusCode.PartialContent;
                    if (!resumed) have = 0;
                    Received = have;
                    using (var input = resp.GetResponseStream())
                    using (var output = new FileStream(part, resumed ? FileMode.Append : FileMode.Create, FileAccess.Write))
                    {
                        var buf = new byte[81920];
                        var sw = Stopwatch.StartNew();
                        long mark = Received;
                        int n;
                        while ((n = input.Read(buf, 0, buf.Length)) > 0)
                        {
                            if (PauseRequested) { State = UpdateState.Paused; throw new Exception("أُوقف التنزيل مؤقتًا."); }
                            output.Write(buf, 0, n);
                            Received += n;
                            if (sw.ElapsedMilliseconds >= 1000)
                            {
                                Speed = (Received - mark) * 1000.0 / sw.ElapsedMilliseconds;
                                mark = Received;
                                sw.Restart();
                            }
                        }
                    }
                }
            }
            if (new FileInfo(part).Length != info.Size)
                throw new Exception("انقطع التنزيل قبل اكتماله، سيُستكمل تلقائيًا.");
            if (info.Sha256 != null && Sha256Of(part) != info.Sha256)
            {
                TryDelete(part);
                throw new Exception("الملف المنزّل تالف، سيُعاد تنزيله.");
            }
            TryDelete(done);
            File.Move(part, done);
            engine.Log("نُزّل التحديث إلى النسخة " + info.Build + " بالكامل وتم التحقق منه.");
        }

        static string Sha256Of(string file)
        {
            using (var sha = System.Security.Cryptography.SHA256.Create())
            using (var fs = File.OpenRead(file))
                return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "").ToLowerInvariant();
        }

        public static string Mb(long bytes) { return (bytes / 1048576.0).ToString("0.0"); }

        // Swaps in the downloaded version and starts it; the caller exits.
        public void Apply(bool headless) { Apply(ZipPath(Available), headless); }

        public void Apply(string zip, bool headless)
        {
            var previous = State;
            State = UpdateState.Applying;
            try
            {
                engine.Log("تجهيز التحديث...");
                string staging = Path.Combine(Dir, "staging");
                DeleteDir(staging);
                ZipFile.ExtractToDirectory(zip, staging);
                string src = Path.Combine(staging, "DentalClinicOffline");
                if (!Directory.Exists(src)) src = staging;
                if (!File.Exists(Path.Combine(src, "DentalClinic.exe")) || !File.Exists(Path.Combine(src, @"app\artisan")))
                    throw new Exception("ملف التحديث لا يحتوي على النظام.");

                string backup = null;
                if (engine.DatabaseUp())
                {
                    engine.Log("نسخة احتياطية قبل التحديث...");
                    string msg;
                    if (!engine.BackupNow(out msg)) throw new Exception("تعذّرت النسخة الاحتياطية، فلم يُحدَّث النظام. " + msg);
                    backup = engine.LatestBackup();
                }

                engine.Log("إيقاف النظام للتحديث...");
                engine.NoTunnel = true;
                engine.Stop();
                engine.StopLeftovers(true);

                DeleteDir(RollbackDir);
                Directory.CreateDirectory(RollbackDir);
                var moved = new List<string>();
                try
                {
                    foreach (var item in Directory.GetFileSystemEntries(src))
                    {
                        string name = Path.GetFileName(item);
                        if (KeepRoot.Contains(name, StringComparer.OrdinalIgnoreCase)) continue;
                        string target = engine.P(name);
                        moved.Add(name);
                        if (Exists(target)) Move(target, Path.Combine(RollbackDir, name));
                        Move(item, target);
                    }
                    string oldApp = Path.Combine(RollbackDir, "app");
                    foreach (var keep in KeepApp)
                    {
                        string from = Path.Combine(oldApp, keep), to = engine.P(@"app\" + keep);
                        if (!Exists(from)) continue;
                        if (Exists(to)) DeleteAny(to);
                        Move(from, to);
                    }
                    File.WriteAllLines(Path.Combine(RollbackDir, "items.txt"), moved);
                    if (backup != null) File.WriteAllText(Path.Combine(RollbackDir, "backup.txt"), backup);
                }
                catch (Exception ex)
                {
                    engine.Log("تعذّر استبدال الملفات، إرجاع النسخة السابقة: " + ex.Message);
                    PutBack(moved);
                    engine.NoTunnel = false;
                    throw;
                }
                DeleteDir(staging);
                engine.Log("استُبدلت الملفات، تشغيل النسخة الجديدة...");
                Launch(headless ? "--headless --after-update" : "--after-update");
            }
            catch
            {
                State = previous;
                engine.NoTunnel = false;
                throw;
            }
        }

        // In the new version, after its first start.
        public void AfterUpdate(bool started, bool headless)
        {
            if (started)
            {
                engine.Log("تم التحديث إلى النسخة " + CurrentBuild + ".");
                RemoveJunctions(RollbackDir);
                DeleteDir(RollbackDir);
                foreach (var f in Directory.Exists(Dir) ? Directory.GetFiles(Dir, TagPrefix + "*") : new string[0]) TryDelete(f);
                return;
            }
            engine.Log("النسخة الجديدة لم تعمل، الرجوع إلى النسخة السابقة...");
            engine.NoTunnel = true;
            engine.Stop();
            engine.StopLeftovers(true);
            string items = Path.Combine(RollbackDir, "items.txt");
            PutBack(File.Exists(items) ? File.ReadAllLines(items).ToList() : new List<string>());
            try { File.WriteAllText(Path.Combine(Dir, "failed-build.txt"), CurrentBuild.ToString()); } catch { }
            Launch(headless ? "--headless --rolled-back" : "--rolled-back");
        }

        // In the old version again: the data goes back to how it was.
        public void AfterRollback()
        {
            string note = Path.Combine(RollbackDir, "backup.txt");
            if (File.Exists(note))
            {
                string backup = File.ReadAllText(note).Trim();
                if (File.Exists(backup))
                {
                    string msg;
                    engine.RestoreBackup(backup, out msg);
                }
            }
            engine.Log("تعذّر التحديث، فرجع النظام للنسخة السابقة كما كان.");
            RemoveJunctions(RollbackDir);
            DeleteDir(RollbackDir);
            string failed = Path.Combine(Dir, "failed");
            RemoveJunctions(failed);
            try { DeleteDir(failed); } catch { }
        }

        public int FailedBuild { get { return ReadBuild(Path.Combine(Dir, "failed-build.txt")); } }

        void PutBack(List<string> moved)
        {
            string failed = Path.Combine(Dir, "failed");
            RemoveJunctions(failed);
            DeleteDir(failed);
            Directory.CreateDirectory(failed);
            string oldApp = Path.Combine(RollbackDir, "app");
            if (Directory.Exists(oldApp))
                foreach (var keep in KeepApp)
                {
                    string from = engine.P(@"app\" + keep), to = Path.Combine(oldApp, keep);
                    if (Exists(from) && !Exists(to)) Move(from, to);
                }
            foreach (var name in moved)
            {
                string current = engine.P(name), saved = Path.Combine(RollbackDir, name);
                if (!Exists(saved)) continue;
                if (Exists(current)) Move(current, Path.Combine(failed, name));
                Move(saved, current);
            }
        }

        void Launch(string args)
        {
            var si = new ProcessStartInfo(engine.P("DentalClinic.exe"), args);
            si.UseShellExecute = false;
            si.WorkingDirectory = engine.Root;
            Process.Start(si);
        }

        static bool Exists(string path) { return File.Exists(path) || Directory.Exists(path); }

        static void Move(string from, string to)
        {
            for (int i = 0; ; i++)
            {
                try
                {
                    if (Directory.Exists(from)) Directory.Move(from, to); else File.Move(from, to);
                    return;
                }
                catch (IOException)
                {
                    // A file can stay locked for a moment after its process exits.
                    if (i >= 20) throw;
                    Thread.Sleep(500);
                }
            }
        }

        static void DeleteAny(string path)
        {
            if (Directory.Exists(path)) DeleteDir(path); else TryDelete(path);
        }

        static void TryDelete(string file)
        {
            try { if (File.Exists(file)) { File.SetAttributes(file, FileAttributes.Normal); File.Delete(file); } } catch { }
        }

        // The storage link (app\public\storage) is a junction: remove the link
        // itself so deleting an old copy can never reach the live uploads.
        static void RemoveJunctions(string dir)
        {
            string link = Path.Combine(dir, @"app\public\storage");
            try
            {
                if (Directory.Exists(link) && (new DirectoryInfo(link).Attributes & FileAttributes.ReparsePoint) != 0) Directory.Delete(link, false);
            }
            catch { }
        }

        static void DeleteDir(string dir)
        {
            var di = new DirectoryInfo(dir);
            if (!di.Exists) return;
            if ((di.Attributes & FileAttributes.ReparsePoint) != 0) { di.Delete(false); return; }
            foreach (var f in di.GetFiles()) { f.Attributes = FileAttributes.Normal; f.Delete(); }
            foreach (var d in di.GetDirectories()) DeleteDir(d.FullName);
            di.Delete(false);
        }
    }

    // Small key=value settings file next to the panel.
    // panel.ini: the panel's own choices, kept by updates.
    class Settings
    {
        readonly string file;
        public bool Exists;
        public bool AutoStartServices = true;
        // Optional password for the panel (2026-10-31, by request; none by
        // default), as a salted PBKDF2 hash. It also guards the remote
        // control page reached through the tunnel.
        public volatile string PasswordHash = "";

        public Settings(string root)
        {
            file = Path.Combine(root, "panel.ini");
            Exists = File.Exists(file);
            if (!Exists) return;
            foreach (var line in File.ReadAllLines(file))
            {
                if (line.StartsWith("AutoStartServices=")) AutoStartServices = line.EndsWith("1");
                if (line.StartsWith("PanelPassword=")) PasswordHash = line.Substring("PanelPassword=".Length).Trim();
            }
        }

        public bool HasPassword { get { return PasswordHash.Length > 0; } }

        public bool CheckPassword(string password)
        {
            return HasPassword && PanelPassword.Verify(password ?? "", PasswordHash);
        }

        // "" removes the password.
        public void SetPassword(string password)
        {
            PasswordHash = string.IsNullOrEmpty(password) ? "" : PanelPassword.Hash(password);
            Save();
        }

        public void Save()
        {
            try
            {
                File.WriteAllText(file,
                    "AutoStartServices=" + (AutoStartServices ? "1" : "0") + Environment.NewLine +
                    (HasPassword ? "PanelPassword=" + PasswordHash + Environment.NewLine : ""));
                Exists = true;
            }
            catch { }
        }
    }

    static class PanelPassword
    {
        const int Rounds = 120000;

        public static string Hash(string password)
        {
            var salt = new byte[16];
            using (var rng = new RNGCryptoServiceProvider()) rng.GetBytes(salt);
            return "pbkdf2$" + Rounds + "$" + Convert.ToBase64String(salt) + "$" + Convert.ToBase64String(Derive(password, salt, Rounds));
        }

        public static bool Verify(string password, string stored)
        {
            try
            {
                var parts = stored.Split('$');
                if (parts.Length != 4 || parts[0] != "pbkdf2") return false;
                byte[] salt = Convert.FromBase64String(parts[2]), want = Convert.FromBase64String(parts[3]);
                byte[] got = Derive(password, salt, int.Parse(parts[1]));
                int diff = got.Length ^ want.Length;
                for (int i = 0; i < Math.Min(got.Length, want.Length); i++) diff |= got[i] ^ want[i];
                return diff == 0;
            }
            catch { return false; }
        }

        static byte[] Derive(string password, byte[] salt, int rounds)
        {
            using (var kdf = new Rfc2898DeriveBytes(Encoding.UTF8.GetBytes(password), salt, rounds)) return kdf.GetBytes(32);
        }
    }

    // Colours, fonts and building blocks of the panel's look (2026-10-31
    // redesign, by request: "جميل واحترافي ومبسط"). Sizes are given at 96 DPI
    // and scaled with S(), so the panel looks the same on every screen.
    static class Ui
    {
        public static readonly Color Bg = Color.FromArgb(241, 245, 249);
        public static readonly Color Card = Color.White;
        public static readonly Color Border = Color.FromArgb(226, 232, 240);
        public static readonly Color Ink = Color.FromArgb(15, 23, 42);
        public static readonly Color Muted = Color.FromArgb(100, 116, 139);
        public static readonly Color Primary = Color.FromArgb(13, 148, 136);
        public static readonly Color PrimaryDark = Color.FromArgb(15, 118, 110);
        public static readonly Color PrimarySoft = Color.FromArgb(204, 251, 241);
        public static readonly Color Side = Color.FromArgb(17, 46, 52);
        public static readonly Color SideHover = Color.FromArgb(27, 64, 71);
        public static readonly Color SideActive = Color.FromArgb(13, 148, 136);
        public static readonly Color SideText = Color.FromArgb(186, 214, 214);
        public static readonly Color Green = Color.FromArgb(22, 163, 74);
        public static readonly Color GreenSoft = Color.FromArgb(220, 252, 231);
        public static readonly Color Red = Color.FromArgb(220, 38, 38);
        public static readonly Color RedSoft = Color.FromArgb(254, 226, 226);
        public static readonly Color Amber = Color.FromArgb(217, 119, 6);
        public static readonly Color AmberSoft = Color.FromArgb(254, 243, 199);
        public static readonly Color Gray = Color.FromArgb(100, 116, 139);
        public static readonly Color GraySoft = Color.FromArgb(241, 245, 249);
        public static readonly Color Disabled = Color.FromArgb(203, 213, 225);

        static float scale = -1;
        public static float Scale
        {
            get
            {
                if (scale < 0)
                {
                    try { using (var g = Graphics.FromHwnd(IntPtr.Zero)) scale = g.DpiX / 96f; } catch { scale = 1; }
                    if (scale < 1) scale = 1;
                }
                return scale;
            }
        }
        public static int S(int px) { return (int)Math.Round(px * Scale); }
        public static Padding P(int l, int t, int r, int b) { return new Padding(S(l), S(t), S(r), S(b)); }
        public static Padding P(int all) { return new Padding(S(all)); }

        public static Font Font(float size) { return new Font("Segoe UI", size); }
        public static Font Bold(float size) { return new Font("Segoe UI Semibold", size); }

        // Windows 10/11 icon font; no icons on older Windows.
        static string icons;
        public static string IconFont
        {
            get
            {
                if (icons == null)
                {
                    icons = "";
                    foreach (var name in new[] { "Segoe Fluent Icons", "Segoe MDL2 Assets" })
                    {
                        try { using (var f = new Font(name, 10f)) if (f.Name == name) { icons = name; break; } } catch { }
                    }
                }
                return icons;
            }
        }

        public static Label Label(string text, float size, Color color, bool bold)
        {
            return new Label { Text = text, AutoSize = true, Font = bold ? Bold(size) : Font(size), ForeColor = color, Margin = P(0, 2, 0, 2), BackColor = Color.Transparent };
        }

        // A label that wraps to its cell's width (in a TableLayoutPanel).
        public static Label Wrap(string text, float size, Color color)
        {
            var l = Label(text, size, color, false);
            l.Dock = DockStyle.Fill;
            return l;
        }

        public static Label Icon(string glyph, float size, Color color)
        {
            if (IconFont.Length == 0) return new Label { AutoSize = true, Visible = false, Text = "" };
            return new Label { Text = glyph, AutoSize = true, Font = new Font(IconFont, size), ForeColor = color, BackColor = Color.Transparent, Margin = P(0, 4, 8, 0), RightToLeft = RightToLeft.No };
        }

        public enum Kind { Primary, Secondary, Danger, Success, Warning, Link }

        public static Button Button(string text, Kind kind)
        {
            var b = new Button
            {
                Text = text, FlatStyle = FlatStyle.Flat, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
                MinimumSize = new Size(S(96), S(38)), Margin = P(0, 4, 8, 4), Padding = P(12, 0, 12, 0),
                Cursor = Cursors.Hand, Font = Bold(10f), UseVisualStyleBackColor = false,
            };
            Style(b, kind);
            return b;
        }

        public static void Style(Button b, Kind kind)
        {
            Color bg, fg, hover, border;
            switch (kind)
            {
                case Kind.Primary: bg = Primary; fg = Color.White; hover = PrimaryDark; border = bg; break;
                case Kind.Danger: bg = Red; fg = Color.White; hover = Color.FromArgb(185, 28, 28); border = bg; break;
                case Kind.Success: bg = Green; fg = Color.White; hover = Color.FromArgb(21, 128, 61); border = bg; break;
                case Kind.Warning: bg = Amber; fg = Color.White; hover = Color.FromArgb(180, 83, 9); border = bg; break;
                case Kind.Link: bg = Card; fg = PrimaryDark; hover = PrimarySoft; border = Card; break;
                default: bg = Card; fg = Ink; hover = Color.FromArgb(248, 250, 252); border = Color.FromArgb(203, 213, 225); break;
            }
            b.Tag = kind;
            b.BackColor = bg;
            b.ForeColor = fg;
            b.FlatAppearance.BorderColor = border;
            b.FlatAppearance.BorderSize = 1;
            b.FlatAppearance.MouseOverBackColor = hover;
            b.FlatAppearance.MouseDownBackColor = hover;
        }

        // Greys a button out when it can't be used (flat buttons don't).
        public static void Enable(Button b, bool on)
        {
            if (b.Enabled == on) return;
            var kind = b.Tag is Kind ? (Kind)b.Tag : Kind.Secondary;
            b.Enabled = on;
            if (on) Style(b, kind);
            else
            {
                bool filled = kind != Kind.Secondary && kind != Kind.Link;
                b.BackColor = filled ? Disabled : Card;
                b.FlatAppearance.BorderColor = filled ? Disabled : Border;
                b.Tag = kind;
            }
        }

        public static FlowLayoutPanel Row(params Control[] items)
        {
            var f = new FlowLayoutPanel { AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, WrapContents = true, Margin = P(0, 4, 0, 0), Dock = DockStyle.Fill, BackColor = Color.Transparent };
            f.Controls.AddRange(items);
            return f;
        }

        public static GraphicsPath Round(Rectangle r, int radius)
        {
            int d = Math.Max(1, radius * 2);
            var path = new GraphicsPath();
            path.AddArc(r.X, r.Y, d, d, 180, 90);
            path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        public static void Pill(Label l, string text, Color fg, Color bg)
        {
            if (l.Text != text) l.Text = text;
            l.ForeColor = fg;
            l.BackColor = bg;
        }

        public static Label NewPill()
        {
            return new Label { AutoSize = true, Font = Bold(9f), Padding = P(10, 3, 10, 3), Margin = P(0, 4, 0, 4), Text = "-" };
        }
    }

    // A white rounded card; rows are added top to bottom.
    class Card : TableLayoutPanel
    {
        public Card()
        {
            ColumnCount = 1;
            ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = Ui.P(22, 18, 22, 18);
            Margin = Ui.P(0, 0, 0, 16);
            Dock = DockStyle.Fill;
            BackColor = Ui.Card;
            DoubleBuffered = true;
            ResizeRedraw = true;
        }

        public T Add<T>(T c) where T : Control
        {
            RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(c, 0, RowCount);
            RowCount++;
            return c;
        }

        public Card Title(string title, string subtitle)
        {
            Add(Ui.Label(title, 12.5f, Ui.Ink, true)).Margin = Ui.P(0, 0, 0, 2);
            if (!string.IsNullOrEmpty(subtitle)) Add(Ui.Wrap(subtitle, 9.5f, Ui.Muted)).Margin = Ui.P(0, 0, 0, 10);
            return this;
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(Parent != null ? Parent.BackColor : Ui.Bg);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (var path = Ui.Round(r, Ui.S(12)))
            using (var fill = new SolidBrush(BackColor))
            using (var pen = new Pen(Ui.Border))
            {
                e.Graphics.FillPath(fill, path);
                e.Graphics.DrawPath(pen, path);
            }
        }
    }

    // One page of the panel: a title and cards, scrolling when the window is
    // small (2026-10-31: the bottom of the old panel was cut off until the
    // window was maximised).
    class Page : Panel
    {
        public readonly TableLayoutPanel Body;

        public Page(string title, string subtitle)
        {
            AutoScroll = true;
            BackColor = Ui.Bg;
            Dock = DockStyle.Fill;
            Padding = Ui.P(28, 22, 28, 12);
            Visible = false;
            Body = new TableLayoutPanel
            {
                Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, ColumnCount = 1,
                BackColor = Ui.Bg, Margin = Padding.Empty, Padding = Padding.Empty,
            };
            Body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            Controls.Add(Body);
            Add(Ui.Label(title, 17f, Ui.Ink, true)).Margin = Ui.P(0, 0, 0, 0);
            Add(Ui.Wrap(subtitle, 10f, Ui.Muted)).Margin = Ui.P(0, 0, 0, 16);
        }

        public T Add<T>(T c) where T : Control
        {
            Body.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Body.Controls.Add(c, 0, Body.RowCount);
            Body.RowCount++;
            return c;
        }
    }

    // An item of the side menu.
    class NavItem : Panel
    {
        readonly Label icon, text;
        public readonly Label Badge;
        bool selected, hover;

        public NavItem(string glyph, string caption)
        {
            Height = Ui.S(44);
            Dock = DockStyle.Top;
            Cursor = Cursors.Hand;
            Padding = Ui.P(18, 0, 14, 0);
            BackColor = Ui.Side;
            icon = new Label { Text = glyph, Dock = DockStyle.Left, Width = Ui.S(30), TextAlign = ContentAlignment.MiddleLeft, ForeColor = Ui.SideText, RightToLeft = RightToLeft.No };
            if (Ui.IconFont.Length > 0) icon.Font = new Font(Ui.IconFont, 12f); else icon.Visible = false;
            text = new Label { Text = caption, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, ForeColor = Ui.SideText, Font = Ui.Font(10.5f) };
            Badge = new Label { Text = "●", Dock = DockStyle.Right, Width = Ui.S(18), TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.FromArgb(251, 191, 36), Visible = false, Font = Ui.Font(9f) };
            Controls.Add(text);
            Controls.Add(Badge);
            Controls.Add(icon);
            text.BringToFront();
            foreach (Control c in new Control[] { this, icon, text, Badge })
            {
                c.MouseEnter += (s, e) => { hover = true; Paint2(); };
                c.MouseLeave += (s, e) => { hover = false; Paint2(); };
                if (c != this) c.Click += (s, e) => OnClick(e);
            }
        }

        public bool Selected
        {
            get { return selected; }
            set { selected = value; Paint2(); }
        }

        void Paint2()
        {
            BackColor = selected ? Ui.SideActive : (hover ? Ui.SideHover : Ui.Side);
            icon.ForeColor = text.ForeColor = selected ? Color.White : Ui.SideText;
            text.Font = selected ? Ui.Bold(10.5f) : Ui.Font(10.5f);
        }
    }

    static class WindowsStartup
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string Name = "DentalClinic";

        static string Command { get { return "\"" + Application.ExecutablePath + "\" --autostart"; } }

        public static bool IsOn()
        {
            using (var k = Registry.CurrentUser.OpenSubKey(RunKey)) return k != null && k.GetValue(Name) != null;
        }

        public static void Set(bool on)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (on) k.SetValue(Name, Command);
                else if (k.GetValue(Name) != null) k.DeleteValue(Name);
            }
        }

        // Keeps the entry pointing here if the folder was moved.
        public static void Refresh()
        {
            using (var k = Registry.CurrentUser.OpenSubKey(RunKey, true))
            {
                if (k != null && k.GetValue(Name) != null && (string)k.GetValue(Name) != Command) k.SetValue(Name, Command);
            }
        }
    }

    // One table of a backup, as backup:tables lists it (2026-10-20).
    class BackupSection
    {
        public string Table;
        public string Label;
        public bool Rows;
    }

    class MainForm : Form
    {
        readonly Engine engine;
        readonly Updater updater;
        readonly Settings settings;
        readonly Tunnel tunnel;
        readonly PanelWeb web;
        bool startHidden;
        bool exiting;
        bool balloonShown;
        bool firewallOk = true;
        bool unlocked;
        bool askOnStart;
        DateTime lastFirewallCheck = DateTime.MinValue, copiedAt = DateTime.MinValue;
        public string ScreenshotDir;

        // Pages and the side menu.
        readonly List<Page> pages = new List<Page>();
        readonly List<NavItem> nav = new List<NavItem>();
        Panel content;
        NavItem lockItem, updatesItem;

        // Home
        Label stateDot, stateText, stateHint, tileNet, tileIp, tileOnline;
        Button toggleBtn, openBtn, restartBtn;
        TableLayoutPanel servicesGrid;
        readonly List<Label[]> serviceRows = new List<Label[]>();
        CheckBox bootBox, servicesBox;
        // Network
        Label addrLocal, addrNet, addrIp, addrDns, macEth, macWifi, firewallText;
        DateTime lastMacCheck = DateTime.MinValue;
        string macIp;
        Button setupBtn, clientBtn, firewallBtn;
        // Backups
        Button backupBtn, restoreBtn;
        Label backupDirText, lastBackupText;
        DateTime lastBackupCheck = DateTime.MinValue;
        volatile bool backupBusy;
        // Updates
        Label updateText, updateVersion;
        ProgressBar updateBar;
        Button updateBtn;
        volatile bool updateBusy;
        // Online access
        Label onlineState, onlineHint, linkSite, linkPanel, linkDirect, remoteText;
        Button onlineBtn, remoteSettingsBtn;
        Control linkSiteRow, linkPanelRow, linkDirectRow;
        // Log
        TextBox logBox;
        readonly List<string> recentLog = new List<string>();
        // Footer
        Label footState, footVersion, footDot;

        NotifyIcon tray;
        ToolStripMenuItem trayToggle;
        System.Windows.Forms.Timer uiTimer, updateTimer;
        readonly bool afterUpdate, rolledBack;
        readonly bool autostart;
        bool initialized;

        public MainForm(Engine engine, Updater updater, bool autostart, bool afterUpdate, bool rolledBack)
        {
            this.engine = engine;
            this.updater = updater;
            this.afterUpdate = afterUpdate;
            this.rolledBack = rolledBack;
            this.autostart = autostart;
            settings = new Settings(engine.Root);
            startHidden = autostart;
            // With a password the panel opens only after it is entered; the
            // system itself starts as usual.
            if (!autostart && settings.HasPassword) { startHidden = true; askOnStart = true; }

            if (!settings.Exists)
            {
                // First launch: start with Windows and start the system by default.
                try { WindowsStartup.Set(true); } catch { }
                settings.Save();
            }
            try { WindowsStartup.Refresh(); } catch { }

            tunnel = new Tunnel(engine, updater.ReadLicense);
            web = new PanelWeb(engine.PanelPort, settings, RemoteStatus, RemoteAction, engine.Log);
            tunnel.PanelReady = () => web.Listening && settings.HasPassword;

            BuildUi();
            engine.Logged += line =>
            {
                lock (recentLog)
                {
                    recentLog.Add(line);
                    if (recentLog.Count > 300) recentLog.RemoveRange(0, 100);
                }
                if (!IsHandleCreated) return;
                try { BeginInvoke(new Action(() => AppendLog(line))); } catch { }
            };

            var show = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\DentalClinicPanelShow");
            var t = new Thread(() =>
            {
                while (true)
                {
                    show.WaitOne();
                    try { BeginInvoke(new Action(ShowPanel)); } catch { }
                }
            });
            t.IsBackground = true;
            t.Start();

            uiTimer = new System.Windows.Forms.Timer { Interval = 1000 };
            uiTimer.Tick += (s, e) => RefreshUi();
            uiTimer.Start();

            // The download progress moves faster than the rest of the panel.
            updateTimer = new System.Windows.Forms.Timer { Interval = 300 };
            updateTimer.Tick += (s, e) => RefreshUpdate();
            updateTimer.Start();
            updater.BecameReady += info =>
            {
                try
                {
                    BeginInvoke(new Action(() => tray.ShowBalloonTip(8000, "عيادة الأسنان",
                        "نُزّل تحديث جديد (النسخة " + info.Build + ") بالكامل. افتح اللوحة واضغط \"تحديث الآن\".", ToolTipIcon.Info)));
                }
                catch { }
            };

            Load += (s, e) => { FitToScreen(); Init(); };
        }

        void Init()
        {
            if (initialized) return;
            initialized = true;
            RefreshUi();
            RefreshUpdate();
            if (ScreenshotDir != null)
            {
                BeginInvoke(new Action(TakeScreenshots));
                return;
            }
            if (afterUpdate)
            {
                // First start of a new version: keep it, or go back to the old one.
                StartSystem(started =>
                {
                    updater.AfterUpdate(started, false);
                    if (!started) { exiting = true; try { BeginInvoke(new Action(() => { tray.Visible = false; Application.Exit(); })); } catch { } }
                });
            }
            else if (rolledBack)
            {
                StartSystem(started =>
                {
                    if (started) updater.AfterRollback();
                    try { BeginInvoke(new Action(() => Notify("تعذّر تشغيل النسخة الجديدة، فرجع النظام تلقائيًا للنسخة السابقة وبياناتها كما كانت.", false))); } catch { }
                });
            }
            else if (autostart || settings.AutoStartServices) StartSystem();
            CheckFirewallAsync();
            updater.StartBackground();
            web.Start();
            tunnel.Begin();
            if (askOnStart) BeginInvoke(new Action(ShowPanel));
        }

        protected override void SetVisibleCore(bool value)
        {
            if (startHidden)
            {
                // Started with Windows (or waiting for the password): stay in the tray.
                startHidden = false;
                if (!IsHandleCreated) CreateHandle();
                value = false;
                Init();
            }
            base.SetVisibleCore(value);
        }

        // The window fits the screen it opens on: the old one was taller than
        // most laptop screens, so its bottom only showed when maximised.
        void FitToScreen()
        {
            var wa = Screen.FromPoint(Cursor.Position).WorkingArea;
            int w = Math.Min(Width, wa.Width - Ui.S(24)), h = Math.Min(Height, wa.Height - Ui.S(24));
            MinimumSize = new Size(Math.Min(MinimumSize.Width, w), Math.Min(MinimumSize.Height, h));
            Size = new Size(w, h);
            Location = new Point(wa.Left + (wa.Width - w) / 2, wa.Top + (wa.Height - h) / 2);
        }

        void BuildUi()
        {
            Text = "عيادة الأسنان - لوحة التشغيل";
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Font = Ui.Font(10f);
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(Ui.S(1060), Ui.S(700));
            MinimumSize = new Size(Ui.S(820), Ui.S(540));
            StartPosition = FormStartPosition.Manual;
            BackColor = Ui.Bg;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            // Footer: always visible, whatever the window size.
            var footer = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = Ui.S(32), ColumnCount = 3, BackColor = Ui.Card, Padding = Ui.P(16, 0, 16, 0) };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            footer.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            footer.Paint += (s, e) => { using (var pen = new Pen(Ui.Border)) e.Graphics.DrawLine(pen, 0, 0, footer.Width, 0); };
            footDot = new Label { Text = "●", AutoSize = true, Anchor = AnchorStyles.Left, Font = Ui.Font(10f), ForeColor = Ui.Gray, Margin = Ui.P(0, 0, 4, 0) };
            footState = new Label { Text = "", AutoSize = true, Anchor = AnchorStyles.Left, ForeColor = Ui.Muted, Font = Ui.Font(9f) };
            footVersion = new Label { Text = "النسخة " + updater.CurrentBuild, AutoSize = true, Anchor = AnchorStyles.Right, ForeColor = Ui.Muted, Font = Ui.Font(9f) };
            footer.Controls.Add(footDot, 0, 0);
            footer.Controls.Add(footState, 1, 0);
            footer.Controls.Add(footVersion, 2, 0);

            // Side menu.
            var side = new Panel { Dock = DockStyle.Left, Width = Ui.S(232), BackColor = Ui.Side };
            var brand = new Panel { Dock = DockStyle.Top, Height = Ui.S(92), BackColor = Ui.Side, Padding = Ui.P(20, 22, 16, 10) };
            var brandIcon = new Label { Text = "\uE95E", Dock = DockStyle.Left, Width = Ui.S(44), ForeColor = Color.FromArgb(94, 234, 212), RightToLeft = RightToLeft.No, TextAlign = ContentAlignment.TopLeft };
            if (Ui.IconFont.Length > 0) brandIcon.Font = new Font(Ui.IconFont, 22f); else brandIcon.Visible = false;
            var brandText = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Side };
            var brandTitle = new Label { Text = "عيادة الأسنان", Dock = DockStyle.Top, Height = Ui.S(30), ForeColor = Color.White, Font = Ui.Bold(14f), TextAlign = ContentAlignment.MiddleLeft };
            var brandSub = new Label { Text = "خادم العيادة (بدون إنترنت)", Dock = DockStyle.Top, Height = Ui.S(22), ForeColor = Ui.SideText, Font = Ui.Font(9f), TextAlign = ContentAlignment.MiddleLeft };
            brandText.Controls.Add(brandSub);
            brandText.Controls.Add(brandTitle);
            brand.Controls.Add(brandText);
            brand.Controls.Add(brandIcon);
            brandText.BringToFront();

            var bottom = new Panel { Dock = DockStyle.Bottom, Height = Ui.S(44 * 3 + 16), BackColor = Ui.Side, Padding = Ui.P(0, 8, 0, 8) };
            var exitItem = new NavItem("\uE7E8", "إيقاف وخروج");
            exitItem.Click += (s, e) => ExitApp();
            lockItem = new NavItem("\uE72E", "قفل اللوحة");
            lockItem.Click += (s, e) => LockPanel();
            var settingsItem = new NavItem("\uE713", "الإعدادات");
            settingsItem.Click += (s, e) => OpenSettings();
            bottom.Controls.Add(exitItem);
            bottom.Controls.Add(lockItem);
            bottom.Controls.Add(settingsItem);

            var menu = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Side, Padding = Ui.P(0, 4, 0, 0) };
            side.Controls.Add(menu);
            side.Controls.Add(bottom);
            side.Controls.Add(brand);
            menu.BringToFront();

            content = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg };

            Controls.Add(content);
            Controls.Add(side);
            Controls.Add(footer);
            content.BringToFront();

            AddPage(menu, "\uE80F", "الرئيسية", BuildHome());
            AddPage(menu, "\uE968", "الشبكة والأجهزة", BuildNetwork());
            AddPage(menu, "\uE74E", "النسخ الاحتياطي", BuildBackups());
            updatesItem = AddPage(menu, "\uE895", "التحديثات", BuildUpdates());
            AddPage(menu, "\uE774", "الوصول عبر الإنترنت", BuildOnline());
            AddPage(menu, "\uE81C", "السجل", BuildLog());
            // Docked top in reverse: the first page's item goes on top.
            for (int i = nav.Count - 1; i >= 0; i--) menu.Controls.Add(nav[i]);
            ShowPage(0);

            // Tray
            var trayMenu = new ContextMenuStrip { RightToLeft = RightToLeft.Yes };
            trayMenu.Items.Add("فتح اللوحة", null, (s, e) => ShowPanel());
            trayMenu.Items.Add("فتح النظام", null, (s, e) => OpenUrl(engine.LocalUrl));
            trayToggle = new ToolStripMenuItem("تشغيل", null, (s, e) =>
            {
                if (!EnsureUnlocked()) return;
                if (engine.CurrentState == State.Running) StopSystem(); else StartSystem();
            });
            trayMenu.Items.Add(trayToggle);
            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add("إيقاف وخروج", null, (s, e) => ExitApp());
            tray = new NotifyIcon { Icon = Icon ?? SystemIcons.Application, Text = "عيادة الأسنان", Visible = ScreenshotDir == null, ContextMenuStrip = trayMenu };
            tray.DoubleClick += (s, e) => ShowPanel();
        }

        NavItem AddPage(Panel menu, string glyph, string caption, Page page)
        {
            var item = new NavItem(glyph, caption);
            int index = pages.Count;
            item.Click += (s, e) => ShowPage(index);
            nav.Add(item);
            pages.Add(page);
            content.Controls.Add(page);
            return item;
        }

        void ShowPage(int index)
        {
            for (int i = 0; i < pages.Count; i++)
            {
                nav[i].Selected = i == index;
                pages[i].Visible = i == index;
            }
            pages[index].BringToFront();
        }

        // ---- Pages ----

        Page BuildHome()
        {
            var page = new Page("الرئيسية", "حالة النظام على هذا الحاسوب. يعمل النظام لكل أجهزة العيادة ما دام هذا الحاسوب يعمل.");

            // State and the main buttons.
            var hero = page.Add(new Card());
            // The state above the buttons, so neither is squeezed in a small window.
            var heroGrid = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 1, BackColor = Ui.Card, Margin = Padding.Empty };
            heroGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            var stateBox = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, Dock = DockStyle.Fill, BackColor = Ui.Card, Margin = Padding.Empty };
            stateBox.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            stateBox.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            stateDot = new Label { Text = "●", AutoSize = true, Font = Ui.Font(26f), ForeColor = Ui.Gray, Margin = Ui.P(0, 0, 10, 0) };
            stateText = Ui.Label("النظام متوقف", 18f, Ui.Ink, true);
            stateHint = Ui.Wrap("", 10f, Ui.Muted);
            stateBox.Controls.Add(stateDot, 0, 0);
            stateBox.SetRowSpan(stateDot, 2);
            stateBox.Controls.Add(stateText, 1, 0);
            stateBox.Controls.Add(stateHint, 1, 1);
            heroGrid.Controls.Add(stateBox, 0, 0);

            toggleBtn = Ui.Button("تشغيل النظام", Ui.Kind.Success);
            toggleBtn.MinimumSize = new Size(Ui.S(140), Ui.S(44));
            toggleBtn.Click += (s, e) => { if (engine.CurrentState == State.Running) StopSystem(); else StartSystem(); };
            openBtn = Ui.Button("فتح النظام", Ui.Kind.Primary);
            openBtn.MinimumSize = new Size(Ui.S(130), Ui.S(44));
            openBtn.Click += (s, e) => OpenUrl(engine.LocalUrl);
            restartBtn = Ui.Button("إعادة التشغيل", Ui.Kind.Secondary);
            restartBtn.MinimumSize = new Size(Ui.S(120), Ui.S(44));
            restartBtn.Click += (s, e) => RestartSystem();
            var heroButtons = new FlowLayoutPanel { AutoSize = true, WrapContents = true, Dock = DockStyle.Fill, BackColor = Ui.Card, Margin = Ui.P(0, 12, 0, 0) };
            heroButtons.Controls.AddRange(new Control[] { toggleBtn, openBtn, restartBtn });
            heroGrid.Controls.Add(heroButtons, 0, 1);
            hero.Add(heroGrid);

            // Three tiles: the addresses and online access.
            var tiles = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 3, BackColor = Ui.Bg, Margin = Padding.Empty };
            for (int i = 0; i < 3; i++) tiles.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.3f));
            tileNet = Tile(tiles, 0, "\uE774", "على كل الأجهزة");
            tileIp = Tile(tiles, 1, "\uE839", "بعنوان IP");
            tileOnline = Tile(tiles, 2, "\uE753", "عبر الإنترنت");
            page.Add(tiles);

            // Services.
            var svc = page.Add(new Card()).Title("الخدمات", "يعيد البرنامج تشغيل أي خدمة تتوقف تلقائيًا.");
            servicesGrid = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 3, BackColor = Ui.Card, Margin = Padding.Empty };
            servicesGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            servicesGrid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            servicesGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(110)));
            svc.Add(servicesGrid);

            // Options.
            var opts = page.Add(new Card()).Title("خيارات التشغيل", null);
            bootBox = new CheckBox { Text = "التشغيل تلقائيًا مع ويندوز (اللوحة تبدأ مخفية بجانب الساعة)", AutoSize = true, Margin = Ui.P(0, 6, 0, 2) };
            try { bootBox.Checked = WindowsStartup.IsOn(); } catch { }
            bootBox.CheckedChanged += (s, e) => { try { WindowsStartup.Set(bootBox.Checked); } catch (Exception ex) { AppendLog(ex.Message); } };
            servicesBox = new CheckBox { Text = "بدء النظام عند فتح اللوحة", AutoSize = true, Checked = settings.AutoStartServices, Margin = Ui.P(0, 4, 0, 2) };
            servicesBox.CheckedChanged += (s, e) => { settings.AutoStartServices = servicesBox.Checked; settings.Save(); };
            opts.Add(bootBox);
            opts.Add(servicesBox);
            return page;
        }

        Label Tile(TableLayoutPanel tiles, int col, string glyph, string caption)
        {
            var card = new Card { Margin = col < 2 ? Ui.P(0, 0, 12, 16) : Ui.P(0, 0, 0, 16), Padding = Ui.P(18, 14, 18, 14) };
            var head = new FlowLayoutPanel { AutoSize = true, WrapContents = false, BackColor = Ui.Card, Margin = Padding.Empty };
            head.Controls.Add(Ui.Icon(glyph, 11f, Ui.Primary));
            head.Controls.Add(Ui.Label(caption, 9.5f, Ui.Muted, false));
            card.Add(head);
            var value = Ui.Label("-", 10.5f, Ui.Ink, true);
            value.RightToLeft = RightToLeft.No;
            value.Margin = Ui.P(0, 4, 0, 0);
            value.Cursor = Cursors.Hand;
            value.Click += (s, e) => CopyText(value.Text, null);
            card.Add(value);
            tiles.Controls.Add(card, col, 0);
            return value;
        }

        Page BuildNetwork()
        {
            var page = new Page("الشبكة والأجهزة", "عناوين النظام، وتجهيز بقية أجهزة العيادة للوصول إليه.");
            var addr = page.Add(new Card()).Title("العناوين", "اضغط «نسخ» بجانب أي عنوان لنسخه.");
            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 3, BackColor = Ui.Card, Margin = Padding.Empty };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            addrLocal = AddAddress(grid, "على هذا الحاسوب");
            addrNet = AddAddress(grid, "على كل الأجهزة");
            addrIp = AddAddress(grid, "بعنوان IP");
            addrDns = AddAddress(grid, "DNS في راوتر Deco");
            macEth = AddAddress(grid, "ماك الإيثرنت (MAC)");
            macWifi = AddAddress(grid, "ماك الواي فاي (MAC)");
            addr.Add(grid);

            var dev = page.Add(new Card()).Title("أجهزة العيادة",
                "اسمح لأجهزة الشبكة مرة واحدة، ثم افتح صفحة التجهيز على كل جهاز لتثبيت شهادة العيادة، أو ثبّت برنامج العيادة على الحواسيب الأخرى.");
            firewallText = dev.Add(Ui.NewPill());
            firewallBtn = Ui.Button("السماح لأجهزة الشبكة", Ui.Kind.Warning);
            firewallBtn.Click += (s, e) => SetupFirewall();
            setupBtn = Ui.Button("صفحة تجهيز الأجهزة", Ui.Kind.Secondary);
            setupBtn.Click += (s, e) => OpenUrl(engine.LocalUrl.Replace("localhost", "127.0.0.1") + "/setup");
            // The program for the other computers (2026-10-17), served from client\.
            clientBtn = Ui.Button("برنامج الحواسيب الأخرى", Ui.Kind.Secondary);
            clientBtn.Click += (s, e) => OpenUrl(engine.LocalUrl.Replace("localhost", "127.0.0.1") + "/client/");
            dev.Add(Ui.Row(firewallBtn, setupBtn, clientBtn));
            return page;
        }

        Label AddAddress(TableLayoutPanel g, string caption)
        {
            var cap = new Label { Text = caption, AutoSize = true, ForeColor = Ui.Muted, Margin = Ui.P(0, 10, 16, 10), Anchor = AnchorStyles.Left };
            var val = new Label { Text = "-", AutoSize = true, Margin = Ui.P(0, 10, 0, 10), RightToLeft = RightToLeft.No, Font = Ui.Bold(10.5f), ForeColor = Ui.Ink, Anchor = AnchorStyles.Left };
            int row = g.RowCount;
            g.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            g.Controls.Add(cap, 0, row);
            g.Controls.Add(val, 1, row);
            var copy = Ui.Button("نسخ", Ui.Kind.Link);
            copy.MinimumSize = new Size(Ui.S(64), Ui.S(32));
            copy.Font = Ui.Font(9f);
            copy.Click += (s, e) => CopyText(val.Text, copy);
            g.Controls.Add(copy, 2, row);
            g.RowCount++;
            return val;
        }

        Page BuildBackups()
        {
            var page = new Page("النسخ الاحتياطي", "تُحفظ نسخة من البيانات والصور يوميًا وقبل كل تحديث تلقائيًا، خارج مجلد البرنامج.");
            var card = page.Add(new Card()).Title("نسخ البيانات", null);
            backupDirText = card.Add(Ui.Wrap("", 10f, Ui.Ink));
            lastBackupText = card.Add(Ui.Wrap("", 10f, Ui.Muted));
            backupBtn = Ui.Button("نسخة احتياطية الآن", Ui.Kind.Primary);
            backupBtn.Click += (s, e) => BackupNow();
            restoreBtn = Ui.Button("استعادة نسخة", Ui.Kind.Secondary);
            restoreBtn.Click += (s, e) => RestoreBackup();
            var dirBtn = Ui.Button("فتح مجلد النسخ", Ui.Kind.Secondary);
            dirBtn.Click += (s, e) =>
            {
                try { Directory.CreateDirectory(engine.BackupDir); Process.Start("explorer.exe", "\"" + engine.BackupDir + "\""); }
                catch (Exception ex) { AppendLog(ex.Message); }
            };
            card.Add(Ui.Row(backupBtn, restoreBtn, dirBtn)).Margin = Ui.P(0, 10, 0, 0);
            var note = page.Add(new Card()).Title("الاستعادة", "عند الاستعادة تختار الأقسام التي تؤخذ من النسخة، وتُضاف البيانات الناقصة فقط دون حذف أو تغيير البيانات الحالية، إلا إذا اخترت الاستبدال الكامل.");
            note.Padding = Ui.P(22, 18, 22, 8);
            return page;
        }

        Page BuildUpdates()
        {
            var page = new Page("التحديثات", "تُنزَّل النسخ الجديدة في الخلفية من الاستضافة، وتُطبَّق عند الضغط على «تحديث الآن» مع نسخة احتياطية قبلها ورجوع تلقائي إن لم تعمل.");
            var card = page.Add(new Card());
            updateVersion = card.Add(Ui.Label("النسخة الحالية " + updater.CurrentBuild, 14f, Ui.Ink, true));
            updateText = card.Add(Ui.Wrap("", 10f, Ui.Muted));
            updateBar = card.Add(new ProgressBar { Dock = DockStyle.Fill, Height = Ui.S(10), Minimum = 0, Maximum = 1000, Margin = Ui.P(0, 10, 0, 6), Visible = false, RightToLeftLayout = true });
            updateBtn = Ui.Button("تحقق الآن", Ui.Kind.Secondary);
            updateBtn.Click += (s, e) => UpdateAction();
            card.Add(Ui.Row(updateBtn)).Margin = Ui.P(0, 8, 0, 0);
            return page;
        }

        Page BuildOnline()
        {
            var page = new Page("الوصول عبر الإنترنت",
                "افتح نظام العيادة وتحكّم بهذا الخادم من أي مكان عبر نفق Cloudflare المجاني، دون فتح منافذ في الراوتر ودون عنوان IP ثابت. يحتاج أن يكون هذا الحاسوب متصلًا بالإنترنت.");
            var card = page.Add(new Card());
            var head = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 2, BackColor = Ui.Card, Margin = Padding.Empty };
            head.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            head.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            var left = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.TopDown, WrapContents = false, BackColor = Ui.Card, Dock = DockStyle.Fill, Margin = Padding.Empty };
            left.Controls.Add(Ui.Label("النفق", 12.5f, Ui.Ink, true));
            onlineState = Ui.NewPill();
            left.Controls.Add(onlineState);
            head.Controls.Add(left, 0, 0);
            onlineBtn = Ui.Button("تفعيل الوصول عبر الإنترنت", Ui.Kind.Primary);
            onlineBtn.MinimumSize = new Size(Ui.S(150), Ui.S(44));
            onlineBtn.Anchor = AnchorStyles.Right;
            onlineBtn.Click += (s, e) => ToggleOnline();
            head.Controls.Add(onlineBtn, 1, 0);
            card.Add(head);
            onlineHint = card.Add(Ui.Wrap("", 9.5f, Ui.Muted));
            onlineHint.Margin = Ui.P(0, 8, 0, 0);

            var links = page.Add(new Card()).Title("روابط الدخول",
                "الرابط الثابت لا يتغير أبدًا: احفظه في المفضلة أو أرسله لمن يحتاجه. أما عنوان النفق نفسه فيتغير عند كل تشغيل، والرابط الثابت يقود إليه دائمًا.");
            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 4, BackColor = Ui.Card, Margin = Padding.Empty };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            linkSite = AddLink(grid, "نظام العيادة", out linkSiteRow);
            linkPanel = AddLink(grid, "لوحة التشغيل عن بعد", out linkPanelRow);
            linkDirect = AddLink(grid, "عنوان النفق الحالي", out linkDirectRow);
            links.Add(grid);

            var remote = page.Add(new Card()).Title("التحكم عن بعد", null);
            remoteText = remote.Add(Ui.Wrap("", 10f, Ui.Ink));
            remoteSettingsBtn = Ui.Button("وضع كلمة مرور للوحة", Ui.Kind.Secondary);
            remoteSettingsBtn.Click += (s, e) => OpenSettings();
            remote.Add(Ui.Row(remoteSettingsBtn)).Margin = Ui.P(0, 8, 0, 0);
            return page;
        }

        Label AddLink(TableLayoutPanel g, string caption, out Control rowMarker)
        {
            int row = g.RowCount;
            g.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            var cap = new Label { Text = caption, AutoSize = true, ForeColor = Ui.Muted, Margin = Ui.P(0, 10, 16, 10), Anchor = AnchorStyles.Left };
            var val = new Label { Text = "-", AutoSize = true, Margin = Ui.P(0, 10, 0, 10), RightToLeft = RightToLeft.No, Font = Ui.Bold(10f), ForeColor = Ui.PrimaryDark, Anchor = AnchorStyles.Left };
            var copy = Ui.Button("نسخ", Ui.Kind.Link);
            copy.MinimumSize = new Size(Ui.S(60), Ui.S(32));
            copy.Font = Ui.Font(9f);
            copy.Click += (s, e) => CopyText(val.Text, copy);
            var open = Ui.Button("فتح", Ui.Kind.Link);
            open.MinimumSize = new Size(Ui.S(60), Ui.S(32));
            open.Font = Ui.Font(9f);
            open.Click += (s, e) => { if (val.Text.StartsWith("https://")) OpenUrl(val.Text); };
            g.Controls.Add(cap, 0, row);
            g.Controls.Add(val, 1, row);
            g.Controls.Add(copy, 2, row);
            g.Controls.Add(open, 3, row);
            g.RowCount++;
            rowMarker = cap;
            return val;
        }

        Page BuildLog()
        {
            var page = new Page("السجل", "ما يجري في النظام الآن. ملفات السجل الكاملة في مجلد السجلات.");
            var card = page.Add(new Card());
            logBox = new TextBox
            {
                Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Height = Ui.S(360),
                BackColor = Color.FromArgb(248, 250, 252), BorderStyle = BorderStyle.None, Font = Ui.Font(9.5f),
                RightToLeft = RightToLeft.Yes, Margin = Padding.Empty,
            };
            card.Add(logBox);
            var logsBtn = Ui.Button("فتح مجلد السجلات", Ui.Kind.Secondary);
            logsBtn.Click += (s, e) => { try { Process.Start("explorer.exe", "\"" + engine.LogDir + "\""); } catch { } };
            card.Add(Ui.Row(logsBtn)).Margin = Ui.P(0, 10, 0, 0);
            page.Resize += (s, e) => { int h = page.ClientSize.Height - Ui.S(230); logBox.Height = Math.Max(Ui.S(200), h); };
            return page;
        }

        // ---- Actions ----

        void CopyText(string text, Button btn)
        {
            if (text.Length == 0 || text == "-") return;
            try { Clipboard.SetText(text); }
            catch (Exception ex) { AppendLog("تعذّر النسخ: " + ex.Message); return; }
            if (btn == null) { footState.Text = "نُسخ: " + text; copiedAt = DateTime.Now; return; }
            btn.Text = "تم ✓";
            var t = new System.Windows.Forms.Timer { Interval = 1500 };
            t.Tick += (s, e) => { t.Dispose(); btn.Text = "نسخ"; };
            t.Start();
        }

        void AppendLog(string line)
        {
            if (logBox.TextLength > 60000) logBox.Text = logBox.Text.Substring(logBox.TextLength - 30000);
            logBox.AppendText(line + Environment.NewLine);
        }

        void StartSystem() { StartSystem(null); }

        void StartSystem(Action<bool> done)
        {
            if (engine.CurrentState == State.Starting || engine.CurrentState == State.Stopping) return;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                engine.Start();
                if (done != null) done(engine.CurrentState == State.Running);
                CheckFirewallAsync();
                if (engine.CurrentState == State.Error && IsHandleCreated)
                {
                    try { BeginInvoke(new Action(() => { if (!Visible) tray.ShowBalloonTip(5000, "عيادة الأسنان", "تعذّر تشغيل النظام. افتح اللوحة لمعرفة السبب.", ToolTipIcon.Error); })); } catch { }
                }
            });
        }

        void StopSystem()
        {
            if (engine.CurrentState == State.Starting || engine.CurrentState == State.Stopping) return;
            ThreadPool.QueueUserWorkItem(_ => engine.Stop());
        }

        void RestartSystem()
        {
            if (engine.CurrentState == State.Starting || engine.CurrentState == State.Stopping) return;
            ThreadPool.QueueUserWorkItem(_ => engine.Restart());
        }

        void BackupNow() { BackupNow(true); }

        void BackupNow(bool tell)
        {
            if (backupBusy || engine.CurrentState != State.Running) return;
            backupBusy = true;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                string msg;
                bool ok = engine.BackupNow(out msg);
                backupBusy = false;
                lastBackupCheck = DateTime.MinValue;
                if (tell) try { BeginInvoke(new Action(() => Notify(msg, ok))); } catch { }
            });
        }

        void RestoreBackup()
        {
            if (backupBusy || engine.CurrentState != State.Running) return;
            string file;
            using (var dlg = new OpenFileDialog
            {
                Title = "اختر النسخة الاحتياطية",
                Filter = "نسخ احتياطية (*.zip;*.sql)|*.zip;*.sql",
                InitialDirectory = Directory.Exists(engine.BackupDir) ? engine.BackupDir : engine.Root,
            })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                file = dlg.FileName;
            }

            // What to take from it (2026-10-20, by request): the sections it
            // holds, added to the current data by default, never replacing it.
            string local = engine.LocalBackupPath(file);
            string error;
            List<BackupSection> sections;
            Cursor = Cursors.WaitCursor;
            try { sections = engine.BackupSections(local, out error); }
            finally { Cursor = Cursors.Default; }
            if (sections == null)
            {
                Notify("تعذّرت قراءة النسخة: " + error, false);
                return;
            }
            bool merge;
            List<string> tables;
            if (!ChooseSections(Path.GetFileName(file), sections, out merge, out tables)) return;

            if (!merge)
            {
                var r = MessageBox.Show(this,
                    "ستُستبدل كل البيانات الحالية (المرضى والمهام والمدفوعات والصور) ببيانات هذه النسخة:" + Environment.NewLine +
                    Path.GetFileName(file) + Environment.NewLine + Environment.NewLine +
                    "تُحفظ البيانات الحالية كنسخة احتياطية أولًا. هل تريد المتابعة؟",
                    "عيادة الأسنان", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2,
                    MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
                if (r != DialogResult.Yes) return;
            }
            backupBusy = true;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                string msg;
                bool ok = engine.RestoreBackup(local, merge, tables, out msg);
                backupBusy = false;
                try { BeginInvoke(new Action(() => Notify(msg, ok))); } catch { }
            });
        }

        // The sections of a backup with check boxes, and whether to add what
        // is missing (the default) or replace everything. False on cancel.
        bool ChooseSections(string fileName, List<BackupSection> sections, out bool merge, out List<string> tables)
        {
            merge = true;
            tables = new List<string>();
            using (var dlg = new Form
            {
                Text = "استعادة نسخة احتياطية",
                RightToLeft = RightToLeft.Yes,
                RightToLeftLayout = true,
                StartPosition = FormStartPosition.CenterParent,
                FormBorderStyle = FormBorderStyle.FixedDialog,
                MinimizeBox = false,
                MaximizeBox = false,
                ShowInTaskbar = false,
                AutoScaleMode = AutoScaleMode.None,
                ClientSize = new Size(Ui.S(540), Math.Min(Ui.S(560), Screen.FromControl(this).WorkingArea.Height - Ui.S(60))),
                Font = Font,
                BackColor = Ui.Card,
            })
            {
                var title = new Label { Text = "النسخة: " + fileName, Dock = DockStyle.Top, Height = Ui.S(36), Padding = Ui.P(12, 12, 12, 0), Font = Ui.Bold(10.5f) };
                var mergeRb = new RadioButton { Text = "إضافة البيانات غير الموجودة فقط (لا يُحذف أو يتغيّر شيء من البيانات الحالية)", Checked = true, Dock = DockStyle.Top, Height = Ui.S(48), Padding = Ui.P(12, 0, 12, 0) };
                var replaceRb = new RadioButton { Text = "استبدال كل البيانات الحالية بالنسخة", Dock = DockStyle.Top, Height = Ui.S(32), Padding = Ui.P(12, 0, 12, 0) };
                var hint = new Label { Text = "اختر الأقسام التي تؤخذ من النسخة:", Dock = DockStyle.Top, Height = Ui.S(28), Padding = Ui.P(12, 6, 12, 0), ForeColor = Ui.Muted };
                var list = new CheckedListBox { Dock = DockStyle.Fill, CheckOnClick = true, IntegralHeight = false, RightToLeft = RightToLeft.Yes, BorderStyle = BorderStyle.None };
                var listBox = new Panel { Dock = DockStyle.Fill, Padding = Ui.P(12, 4, 12, 4) };
                listBox.Controls.Add(list);
                foreach (var sct in sections)
                    list.Items.Add((sct.Label ?? sct.Table) + (sct.Label != sct.Table ? "  (" + sct.Table + ")" : "") + (sct.Rows ? "" : "  — فارغ"), sct.Rows);

                var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = Ui.S(60), FlowDirection = FlowDirection.LeftToRight, Padding = Ui.P(10), BackColor = Ui.Bg };
                var ok = Ui.Button("استعادة", Ui.Kind.Primary);
                ok.DialogResult = DialogResult.OK;
                var cancel = Ui.Button("إلغاء", Ui.Kind.Secondary);
                cancel.DialogResult = DialogResult.Cancel;
                var all = Ui.Button("تحديد الكل", Ui.Kind.Secondary);
                var none = Ui.Button("إلغاء التحديد", Ui.Kind.Secondary);
                all.Click += (s, e) => { for (int i = 0; i < list.Items.Count; i++) list.SetItemChecked(i, true); };
                none.Click += (s, e) => { for (int i = 0; i < list.Items.Count; i++) list.SetItemChecked(i, false); };
                EventHandler sync = (s, e) => { list.Enabled = all.Enabled = none.Enabled = hint.Enabled = mergeRb.Checked; };
                mergeRb.CheckedChanged += sync;
                replaceRb.CheckedChanged += sync;
                buttons.Controls.AddRange(new Control[] { ok, cancel, all, none });

                // Docked in reverse: the last added sits on top.
                dlg.Controls.Add(listBox);
                dlg.Controls.Add(hint);
                dlg.Controls.Add(replaceRb);
                dlg.Controls.Add(mergeRb);
                dlg.Controls.Add(title);
                dlg.Controls.Add(buttons);
                dlg.AcceptButton = ok;
                dlg.CancelButton = cancel;

                while (true)
                {
                    if (dlg.ShowDialog(this) != DialogResult.OK) return false;
                    merge = mergeRb.Checked;
                    tables.Clear();
                    if (!merge) return true;
                    foreach (int i in list.CheckedIndices) tables.Add(sections[i].Table);
                    if (tables.Count > 0) return true;
                    MessageBox.Show(dlg, "اختر قسمًا واحدًا على الأقل.", "عيادة الأسنان", MessageBoxButtons.OK, MessageBoxIcon.Information,
                        MessageBoxDefaultButton.Button1, MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
                }
            }
        }

        // The update state in words, with the button that goes with it.
        string UpdateStatus(out string btn, out Ui.Kind kind, out int progress)
        {
            var st = updater.State;
            var info = updater.Available;
            string text;
            btn = null;
            kind = Ui.Kind.Secondary;
            progress = -1;
            switch (st)
            {
                case UpdateState.Checking:
                    text = "جارٍ التحقق من وجود تحديث...";
                    break;
                case UpdateState.Downloading:
                case UpdateState.Paused:
                    long total = Math.Max(1, updater.Total), got = Math.Min(updater.Received, total);
                    progress = (int)(got * 1000 / total);
                    text = "تحديث جديد (النسخة " + (info != null ? info.Build : 0) + "): " +
                        (st == UpdateState.Paused ? "التنزيل متوقف مؤقتًا " : "جارٍ التنزيل ") + (progress / 10) + "٪، " +
                        Updater.Mb(got) + " من " + Updater.Mb(total) + " م.ب" +
                        (st == UpdateState.Downloading && updater.Speed > 0 ? "، " + Updater.Mb((long)updater.Speed) + " م.ب/ث" : "");
                    btn = st == UpdateState.Paused ? "متابعة" : "إيقاف مؤقت";
                    break;
                case UpdateState.Ready:
                    progress = 1000;
                    text = "التحديث للنسخة " + info.Build + " جاهز (نُزّل بالكامل وتم التحقق منه). يتوقف النظام دقيقة أثناء التحديث وتبقى كل البيانات.";
                    btn = "تحديث الآن";
                    kind = Ui.Kind.Success;
                    break;
                case UpdateState.Applying:
                    text = "جارٍ التحديث، لا تطفئ الحاسوب...";
                    break;
                case UpdateState.Error:
                    text = "تعذّر التحقق من التحديثات أو تنزيلها: " + updater.Error + " (يُعاد تلقائيًا)";
                    btn = "إعادة المحاولة";
                    break;
                case UpdateState.UpToDate:
                    text = "لا يوجد تحديث، هذه أحدث نسخة.";
                    btn = "تحقق الآن";
                    break;
                default:
                    text = "يتحقق البرنامج من التحديثات تلقائيًا كل 3 ساعات.";
                    btn = "تحقق الآن";
                    break;
            }
            if (st != UpdateState.Ready && st != UpdateState.Applying && updater.FailedBuild > 0 && updater.FailedBuild >= updater.CurrentBuild)
                text += Environment.NewLine + "آخر تحديث (النسخة " + updater.FailedBuild + ") لم يعمل فرجع النظام للنسخة السابقة.";
            return text;
        }

        void RefreshUpdate()
        {
            string btn; Ui.Kind kind; int progress;
            string text = UpdateStatus(out btn, out kind, out progress);
            var st = updater.State;
            if (updateText.Text != text) updateText.Text = text;
            updateText.ForeColor = st == UpdateState.Error ? Ui.Red : (st == UpdateState.Ready ? Ui.Green : Ui.Muted);

            bool marquee = st == UpdateState.Applying || st == UpdateState.Checking;
            updateBar.Visible = marquee || progress >= 0;
            updateBar.Style = marquee ? ProgressBarStyle.Marquee : ProgressBarStyle.Continuous;
            if (!marquee && progress >= 0 && updateBar.Value != progress) updateBar.Value = progress;

            updateBtn.Visible = btn != null && !updateBusy;
            if (btn != null && updateBtn.Text != btn) updateBtn.Text = btn;
            if (!(updateBtn.Tag is Ui.Kind) || (Ui.Kind)updateBtn.Tag != kind) Ui.Style(updateBtn, kind);
            updatesItem.Badge.Visible = st == UpdateState.Ready;
        }

        void UpdateAction()
        {
            switch (updater.State)
            {
                case UpdateState.Downloading: updater.Pause(); break;
                case UpdateState.Ready: ApplyUpdate(true); break;
                case UpdateState.Applying: case UpdateState.Checking: break;
                default: updater.CheckNow(); break;
            }
            RefreshUpdate();
        }

        void ApplyUpdate(bool ask)
        {
            if (updateBusy || updater.Available == null) return;
            if (ask)
            {
                var r = MessageBox.Show(this,
                    "سيُحدَّث النظام إلى النسخة " + updater.Available.Build + "." + Environment.NewLine +
                    "تُحفظ نسخة احتياطية من البيانات أولًا، ثم يتوقف النظام على كل الأجهزة دقيقة أو اثنتين ويعود وحده." + Environment.NewLine +
                    "إذا لم تعمل النسخة الجديدة يرجع النظام تلقائيًا للنسخة السابقة وبياناتها." + Environment.NewLine + Environment.NewLine +
                    "هل تريد التحديث الآن؟",
                    "عيادة الأسنان", MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2,
                    MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
                if (r != DialogResult.Yes) return;
            }
            updateBusy = true;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                try
                {
                    tunnel.End();
                    web.Stop();
                    updater.Apply(false);
                    // The new version is starting; this one steps aside.
                    try { BeginInvoke(new Action(() => { exiting = true; tray.Visible = false; Application.Exit(); })); } catch { }
                }
                catch (Exception ex)
                {
                    updateBusy = false;
                    string msg = "لم يتم التحديث، والنظام على النسخة الحالية دون تغيير: " + ex.Message;
                    engine.Log(msg);
                    web.Start();
                    tunnel.Begin();
                    if (engine.CurrentState != State.Running) StartAgain();
                    if (ask) try { BeginInvoke(new Action(() => Notify(msg, false))); } catch { }
                }
            });
        }

        void StartAgain()
        {
            try { BeginInvoke(new Action(() => StartSystem())); } catch { }
        }

        void Notify(string msg, bool ok)
        {
            MessageBox.Show(this, msg, "عيادة الأسنان", MessageBoxButtons.OK, ok ? MessageBoxIcon.Information : MessageBoxIcon.Error,
                MessageBoxDefaultButton.Button1, MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
        }

        void CheckFirewallAsync()
        {
            lastFirewallCheck = DateTime.Now;
            ThreadPool.QueueUserWorkItem(_ => { firewallOk = engine.FirewallReady(); });
        }

        void SetupFirewall()
        {
            ThreadPool.QueueUserWorkItem(_ =>
            {
                try
                {
                    engine.SetupFirewall();
                    firewallOk = engine.FirewallReady();
                    engine.Log(firewallOk ? "تم السماح لأجهزة الشبكة بالوصول للنظام." : "لم يُضبط الجدار الناري.");
                }
                catch (Exception ex)
                {
                    engine.Log("لم يُضبط الجدار الناري: " + ex.Message);
                }
            });
        }

        void ToggleOnline()
        {
            bool on = !engine.TunnelOn;
            if (on && !tunnel.Installed)
            {
                Notify("برنامج النفق (cloudflared) غير موجود في مجلد البرنامج. حدّث النسخة ثم أعد المحاولة.", false);
                return;
            }
            try { engine.WriteConfig(new Dictionary<string, string> { { "TUNNEL", on ? "1" : "0" } }); }
            catch (Exception ex) { Notify("تعذّر حفظ الإعدادات: " + ex.Message, false); return; }
            engine.Log(on ? "تفعيل الوصول عبر الإنترنت..." : "أُوقف الوصول عبر الإنترنت.");
            tunnel.Poke();
            RefreshUi();
        }

        static string StateText(State st, out Color c)
        {
            switch (st)
            {
                case State.Running: c = Ui.Green; return "النظام يعمل";
                case State.Starting: c = Ui.Amber; return "جارٍ التشغيل...";
                case State.Stopping: c = Ui.Amber; return "جارٍ الإيقاف...";
                case State.Error: c = Ui.Red; return "تعذّر التشغيل";
                default: c = Ui.Gray; return "النظام متوقف";
            }
        }

        // A service's state in words, with its colour.
        string ServiceStatus(Service s, State st, out Color color)
        {
            int alive = s.Alive;
            if (s.Failed) { color = Ui.Red; return "خطأ - راجع السجل"; }
            if (s.Count == 0) { color = Ui.Gray; return "معطّل من الإعدادات"; }
            if (alive == s.Count) { color = Ui.Green; return s.Count > 1 ? "يعمل (" + alive + ")" : "يعمل"; }
            if (alive > 0) { color = Ui.Amber; return "يعمل جزئيًا (" + alive + " من " + s.Count + ")"; }
            if (st == State.Starting) { color = Ui.Amber; return "بانتظار التشغيل"; }
            if (st == State.Running && s.Key == "dns" && engine.DnsBusy) { color = Ui.Amber; return "المنفذ 53 مشغول"; }
            color = Ui.Gray;
            return "متوقف";
        }

        static Color Soft(Color c)
        {
            if (c == Ui.Green) return Ui.GreenSoft;
            if (c == Ui.Red) return Ui.RedSoft;
            if (c == Ui.Amber) return Ui.AmberSoft;
            return Ui.GraySoft;
        }

        void RefreshUi()
        {
            var st = engine.CurrentState;
            Color c;
            string text = StateText(st, out c);
            stateDot.ForeColor = c;
            if (stateText.Text != text) stateText.Text = text;
            string hint = st == State.Error ? engine.LastError
                : st == State.Running ? "تفتحه كل أجهزة العيادة على " + engine.NetUrl + " أو بعنوان IP هذا الحاسوب."
                : st == State.Stopped ? "اضغط «تشغيل النظام» ليعمل على كل الأجهزة."
                : "قد يستغرق ذلك دقيقة في المرة الأولى.";
            if (stateHint.Text != hint) stateHint.Text = hint;
            stateHint.ForeColor = st == State.Error ? Ui.Red : Ui.Muted;

            bool busy = st == State.Starting || st == State.Stopping, running = st == State.Running;
            string toggle = running ? "إيقاف النظام" : (busy ? "انتظر..." : "تشغيل النظام");
            if (toggleBtn.Text != toggle) toggleBtn.Text = toggle;
            var want = running ? Ui.Kind.Danger : Ui.Kind.Success;
            if (!(toggleBtn.Tag is Ui.Kind) || (Ui.Kind)toggleBtn.Tag != want) Ui.Style(toggleBtn, want);
            Ui.Enable(toggleBtn, !busy);
            Ui.Enable(openBtn, running);
            Ui.Enable(restartBtn, running);
            Ui.Enable(setupBtn, running);
            Ui.Enable(clientBtn, running);
            Ui.Enable(backupBtn, running && !backupBusy);
            Ui.Enable(restoreBtn, running && !backupBusy);
            backupBtn.Text = backupBusy ? "انتظر..." : "نسخة احتياطية الآن";
            trayToggle.Text = running ? "إيقاف النظام" : "تشغيل النظام";
            trayToggle.Enabled = !busy;
            string trayText = running ? "عيادة الأسنان - يعمل" : "عيادة الأسنان - " + text;
            if (tray.Text != trayText) tray.Text = trayText;
            footDot.ForeColor = c;
            string foot = text + (running ? "   •   " + engine.NetUrl : "") + (engine.TunnelOn && tunnel.Connected ? "   •   متصل بالإنترنت" : "");
            if (footState.Text != foot && (DateTime.Now - copiedAt).TotalSeconds > 3) footState.Text = foot;

            // Addresses.
            bool hasIp = engine.LanIp.Length > 0;
            tileNet.Text = engine.NetUrl;
            tileIp.Text = hasIp ? engine.IpUrl : "-";
            addrLocal.Text = engine.LocalUrl;
            addrNet.Text = engine.NetUrl;
            addrIp.Text = hasIp ? engine.IpUrl : "-";
            addrDns.Text = hasIp ? engine.LanIp : "-";
            if (macIp != engine.LanIp || (DateTime.Now - lastMacCheck).TotalSeconds > 10)
            {
                macIp = engine.LanIp;
                lastMacCheck = DateTime.Now;
                string eth = Engine.MacAddress(false, macIp), wifi = Engine.MacAddress(true, macIp);
                macEth.Text = eth.Length > 0 ? eth : "-";
                macWifi.Text = wifi.Length > 0 ? wifi : "-";
            }

            if ((DateTime.Now - lastFirewallCheck).TotalSeconds > 60) CheckFirewallAsync();
            if (firewallOk) Ui.Pill(firewallText, "✓  أجهزة الشبكة مسموح لها بالوصول", Ui.Green, Ui.GreenSoft);
            else Ui.Pill(firewallText, "!  اسمح لأجهزة الشبكة مرة واحدة (يطلب صلاحيات المدير)", Ui.Amber, Ui.AmberSoft);
            firewallBtn.Visible = !firewallOk;

            // Services.
            var services = engine.Services;
            if (serviceRows.Count != services.Count) BuildServiceRows(services.Count);
            for (int i = 0; i < services.Count; i++)
            {
                var s = services[i];
                Color color;
                string status = ServiceStatus(s, st, out color);
                var row = serviceRows[i];
                if (row[0].Text != s.Name) row[0].Text = s.Name;
                Ui.Pill(row[1], status, color, Soft(color));
                if (row[2].Text != s.Port) row[2].Text = s.Port;
            }

            // Backups.
            backupDirText.Text = "المجلد: " + engine.BackupDir;
            if ((DateTime.Now - lastBackupCheck).TotalSeconds > 15)
            {
                lastBackupCheck = DateTime.Now;
                var last = engine.LatestBackup();
                lastBackupText.Text = last == null ? "لا توجد نسخة بعد."
                    : "آخر نسخة: " + Path.GetFileName(last) + "  (" + File.GetLastWriteTime(last).ToString("yyyy-MM-dd HH:mm") + ")";
            }

            RefreshOnline();
            lockItem.Visible = settings.HasPassword;
        }

        void BuildServiceRows(int count)
        {
            servicesGrid.SuspendLayout();
            servicesGrid.Controls.Clear();
            servicesGrid.RowStyles.Clear();
            serviceRows.Clear();
            for (int i = 0; i < count; i++)
            {
                var name = new Label { AutoSize = true, Anchor = AnchorStyles.Left, Margin = Ui.P(0, 9, 0, 9), ForeColor = Ui.Ink, Font = Ui.Font(10.5f) };
                var pill = Ui.NewPill();
                pill.Anchor = AnchorStyles.Left;
                var port = new Label { AutoSize = true, Anchor = AnchorStyles.Right, ForeColor = Ui.Muted, RightToLeft = RightToLeft.No, Font = Ui.Font(9.5f), Margin = Ui.P(12, 9, 0, 9) };
                servicesGrid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                servicesGrid.Controls.Add(name, 0, i);
                servicesGrid.Controls.Add(pill, 1, i);
                servicesGrid.Controls.Add(port, 2, i);
                serviceRows.Add(new[] { name, pill, port });
            }
            servicesGrid.RowCount = count;
            servicesGrid.ResumeLayout();
        }

        void RefreshOnline()
        {
            bool on = engine.TunnelOn;
            string state; Color fg;
            if (!on) { state = "متوقف"; fg = Ui.Gray; }
            else if (!tunnel.Installed) { state = "برنامج النفق غير موجود"; fg = Ui.Red; }
            else if (tunnel.Connected) { state = "متصل"; fg = Ui.Green; }
            else { state = "جارٍ الاتصال..."; fg = Ui.Amber; }
            Ui.Pill(onlineState, "●  " + state, fg, Soft(fg));
            tileOnline.Text = on ? state : "غير مفعّل";
            tileOnline.ForeColor = on ? fg : Ui.Muted;
            string btn = on ? "إيقاف الوصول عبر الإنترنت" : "تفعيل الوصول عبر الإنترنت";
            if (onlineBtn.Text != btn) { onlineBtn.Text = btn; Ui.Style(onlineBtn, on ? Ui.Kind.Secondary : Ui.Kind.Primary); }

            string hint;
            if (!on) hint = "عند التفعيل يعمل النفق مع النظام تلقائيًا، حتى بعد إعادة تشغيل الحاسوب.";
            else if (tunnel.Error.Length > 0 && !tunnel.Connected) hint = tunnel.Error;
            else if (tunnel.Link.Length == 0 && tunnel.Connected) hint = tunnel.LinkNote;
            else hint = "يعمل النفق ما دام هذا الحاسوب متصلًا بالإنترنت، ويعيد الاتصال وحده إذا انقطع.";
            if (onlineHint.Text != hint) onlineHint.Text = hint;
            onlineHint.ForeColor = tunnel.Error.Length > 0 && on && !tunnel.Connected ? Ui.Red : Ui.Muted;

            linkSite.Text = on && tunnel.Link.Length > 0 ? tunnel.Link : "-";
            linkPanel.Text = on && tunnel.PanelLink.Length > 0 ? tunnel.PanelLink : (on && tunnel.PanelUrl.Length > 0 ? tunnel.PanelUrl : "-");
            linkDirect.Text = on && tunnel.SiteUrl.Length > 0 ? tunnel.SiteUrl : "-";

            string remote;
            if (!settings.HasPassword)
                remote = "التحكم بلوحة التشغيل عبر الإنترنت (تشغيل وإيقاف ونسخ احتياطي وتحديث) يحتاج كلمة مرور للوحة، حتى لا يتحكم بها غيرك. ضعها من الإعدادات.";
            else if (!web.Listening)
                remote = "تعذّر تشغيل صفحة التحكم عن بعد: المنفذ " + engine.PanelPort + " مستخدم. غيّر PANEL_PORT في config.txt.";
            else
                remote = "مفعّل: افتح «لوحة التشغيل عن بعد» من أي متصفح وادخل بكلمة مرور اللوحة.";
            if (remoteText.Text != remote) remoteText.Text = remote;
            remoteSettingsBtn.Visible = !settings.HasPassword;
        }

        // ---- Password ----

        bool EnsureUnlocked()
        {
            if (!settings.HasPassword || unlocked) return true;
            using (var dlg = new PasswordForm(settings))
            {
                if (dlg.ShowDialog(Visible ? this : null) == DialogResult.OK) unlocked = true;
            }
            return unlocked;
        }

        void LockPanel()
        {
            if (!settings.HasPassword) return;
            unlocked = false;
            Hide();
            tray.ShowBalloonTip(3000, "عيادة الأسنان", "قُفلت اللوحة، والنظام مستمر. افتحها من الأيقونة بجانب الساعة.", ToolTipIcon.Info);
        }

        void OpenSettings()
        {
            using (var dlg = new SettingsForm(engine.ReadConfig(), engine.Root, settings.HasPassword))
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                var before = engine.ReadConfig();
                bool restartNeeded = dlg.Values.Any(kv =>
                {
                    string old;
                    if (!before.TryGetValue(kv.Key, out old)) old = "";
                    return !kv.Key.StartsWith("TUNNEL") && old != kv.Value;
                });
                try { engine.WriteConfig(dlg.Values); }
                catch (Exception ex)
                {
                    Notify("تعذّر حفظ الإعدادات: " + ex.Message, false);
                    return;
                }
                if (dlg.NewPassword != null)
                {
                    settings.SetPassword(dlg.NewPassword);
                    unlocked = true;
                    engine.Log(dlg.NewPassword.Length > 0 ? "وُضعت كلمة مرور للوحة التشغيل." : "أُزيلت كلمة مرور لوحة التشغيل.");
                    web.ForgetSessions();
                }
                tunnel.Poke();
                CheckFirewallAsync();
                if (restartNeeded && engine.CurrentState == State.Running)
                {
                    var r = MessageBox.Show(this, "حُفظت الإعدادات. تُطبَّق بعد إعادة تشغيل النظام (يتوقف لحظات على كل الأجهزة). إعادة التشغيل الآن؟",
                        "عيادة الأسنان", MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button1,
                        MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
                    if (r == DialogResult.Yes) RestartSystem();
                }
                RefreshUi();
            }
        }

        void ShowPanel()
        {
            if (!Visible && !EnsureUnlocked()) return;
            Show();
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Activate();
            BringToFront();
        }

        static void OpenUrl(string url)
        {
            try { Process.Start(url); } catch { }
        }

        void ExitApp()
        {
            if (!EnsureUnlocked()) return;
            if (engine.CurrentState == State.Running || engine.CurrentState == State.Starting)
            {
                var r = MessageBox.Show(this, "سيتوقف النظام على كل الأجهزة. هل تريد الإيقاف والخروج؟", "عيادة الأسنان",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2,
                    MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
                if (r != DialogResult.Yes) return;
            }
            exiting = true;
            Enabled = false;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                tunnel.End();
                web.Stop();
                engine.Stop();
                try { BeginInvoke(new Action(() => { tray.Visible = false; Application.Exit(); })); } catch { }
            });
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing && !exiting && ScreenshotDir == null)
            {
                // The close button only hides the panel; the system keeps running.
                e.Cancel = true;
                Hide();
                if (settings.HasPassword) unlocked = false;
                if (!balloonShown)
                {
                    balloonShown = true;
                    tray.ShowBalloonTip(4000, "عيادة الأسنان", "اللوحة ما زالت تعمل بجانب الساعة، والنظام مستمر.", ToolTipIcon.Info);
                }
                return;
            }
            if (e.CloseReason == CloseReason.WindowsShutDown || e.CloseReason == CloseReason.TaskManagerClosing)
            {
                // Shut the database down cleanly before Windows does.
                tunnel.End();
                engine.Stop();
            }
            tray.Visible = false;
            base.OnFormClosing(e);
        }

        // ---- Remote control (the page behind the tunnel, see PanelWeb) ----

        Dictionary<string, object> RemoteStatus()
        {
            var st = engine.CurrentState;
            Color c;
            string text = StateText(st, out c);
            var services = new List<object>();
            foreach (var s in engine.Services)
            {
                Color color;
                string status = ServiceStatus(s, st, out color);
                services.Add(new Dictionary<string, object> { { "name", s.Name }, { "status", status }, { "tone", Tone(color) } });
            }
            string btn; Ui.Kind kind; int progress;
            string upd = UpdateStatus(out btn, out kind, out progress);
            string[] log;
            lock (recentLog) log = recentLog.Skip(Math.Max(0, recentLog.Count - 40)).ToArray();
            var last = engine.LatestBackup();
            return new Dictionary<string, object>
            {
                { "state", st.ToString().ToLowerInvariant() },
                { "stateText", text },
                { "tone", Tone(c) },
                { "error", st == State.Error ? engine.LastError : "" },
                { "services", services },
                { "build", updater.CurrentBuild },
                { "update", upd },
                { "updateReady", updater.State == UpdateState.Ready },
                { "updateProgress", progress },
                { "backupBusy", backupBusy },
                { "lastBackup", last == null ? "" : Path.GetFileName(last) + " (" + File.GetLastWriteTime(last).ToString("yyyy-MM-dd HH:mm") + ")" },
                { "site", tunnel.Link.Length > 0 ? tunnel.Link : tunnel.SiteUrl },
                { "lan", engine.NetUrl },
                { "log", log },
            };
        }

        static string Tone(Color c)
        {
            if (c == Ui.Green) return "green";
            if (c == Ui.Red) return "red";
            if (c == Ui.Amber) return "amber";
            return "gray";
        }

        // Runs an action asked for on the remote page; returns what to tell.
        string RemoteAction(string action)
        {
            var st = engine.CurrentState;
            bool busy = st == State.Starting || st == State.Stopping;
            switch (action)
            {
                case "start":
                    if (busy || st == State.Running) return "النظام يعمل أو مشغول الآن.";
                    engine.Log("تشغيل النظام من التحكم عن بعد.");
                    StartSystem();
                    return "جارٍ تشغيل النظام...";
                case "stop":
                    if (st != State.Running) return "النظام ليس قيد التشغيل.";
                    engine.Log("إيقاف النظام من التحكم عن بعد.");
                    StopSystem();
                    return "جارٍ إيقاف النظام...";
                case "restart":
                    if (st != State.Running) return "النظام ليس قيد التشغيل.";
                    engine.Log("إعادة تشغيل النظام من التحكم عن بعد.");
                    RestartSystem();
                    return "جارٍ إعادة تشغيل النظام...";
                case "backup":
                    if (st != State.Running) return "شغّل النظام أولًا.";
                    if (backupBusy) return "هناك نسخة جارية الآن.";
                    engine.Log("نسخة احتياطية من التحكم عن بعد.");
                    BackupNow(false);
                    return "جارٍ حفظ نسخة احتياطية...";
                case "check-update":
                    updater.CheckNow();
                    return "جارٍ التحقق من التحديثات...";
                case "apply-update":
                    if (updater.State != UpdateState.Ready) return "لا يوجد تحديث جاهز.";
                    engine.Log("تحديث النظام من التحكم عن بعد.");
                    try { BeginInvoke(new Action(() => ApplyUpdate(false))); } catch { }
                    return "بدأ التحديث. ينقطع الاتصال دقيقة أو اثنتين ثم يعود على الرابط الثابت نفسه.";
            }
            return "أمر غير معروف.";
        }

        // ---- CI pictures of every page (--screenshots) ----

        void TakeScreenshots()
        {
            Directory.CreateDirectory(ScreenshotDir);
            TopMost = true;
            Show();
            Activate();
            var shots = new List<Action>();
            string[] names = { "1-home", "2-network", "3-backups", "4-updates", "5-online", "6-log" };
            for (int i = 0; i < pages.Count; i++)
            {
                int n = i;
                shots.Add(() => { ShowPage(n); Snap(this, names[n]); });
            }
            shots.Add(() =>
            {
                engine.CurrentState = State.Running;
                RefreshUi();
                ShowPage(0);
                Snap(this, "7-home-running");
                engine.CurrentState = State.Stopped;
            });
            shots.Add(() =>
            {
                // The smallest window: the footer and the page's scroll bar.
                WindowState = FormWindowState.Normal;
                Size = MinimumSize;
                ShowPage(0);
                Snap(this, "8-home-small");
                ShowPage(4);
                Snap(this, "9-online-small");
            });
            shots.Add(() =>
            {
                using (var dlg = new SettingsForm(engine.ReadConfig(), engine.Root, false))
                {
                    dlg.TopMost = true;
                    dlg.StartPosition = FormStartPosition.CenterScreen;
                    dlg.Show();
                    Pump();
                    Snap(dlg, "10-settings");
                    dlg.ScrollDown();
                    Pump();
                    Snap(dlg, "11-settings-end");
                    dlg.Close();
                }
                using (var dlg = new PasswordForm(settings))
                {
                    dlg.TopMost = true;
                    dlg.Show();
                    Pump();
                    Snap(dlg, "12-password");
                    dlg.Close();
                }
            });
            foreach (var shot in shots)
            {
                try { shot(); }
                catch (Exception ex) { File.AppendAllText(Path.Combine(ScreenshotDir, "errors.txt"), ex + Environment.NewLine); }
            }
            exiting = true;
            tray.Visible = false;
            Application.Exit();
        }

        static void Pump()
        {
            for (int i = 0; i < 10; i++) { Application.DoEvents(); Thread.Sleep(60); }
        }

        void Snap(Form f, string name)
        {
            Pump();
            f.Refresh();
            Pump();
            var b = f.Bounds;
            using (var bmp = new Bitmap(b.Width, b.Height))
            {
                try
                {
                    using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(b.Location, Point.Empty, b.Size);
                }
                catch
                {
                    f.DrawToBitmap(bmp, new Rectangle(Point.Empty, b.Size));
                }
                bmp.Save(Path.Combine(ScreenshotDir, name + ".png"), ImageFormat.Png);
            }
        }
    }

    // Asks for the panel's password (2026-10-31, by request).
    class PasswordForm : Form
    {
        readonly Settings settings;
        readonly TextBox box;
        readonly Label error;
        readonly Button ok;
        int wrong;

        public PasswordForm(Settings settings)
        {
            this.settings = settings;
            Text = "عيادة الأسنان";
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Font = Ui.Font(10f);
            AutoScaleMode = AutoScaleMode.None;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            BackColor = Ui.Card;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            var grid = new TableLayoutPanel { AutoSize = true, ColumnCount = 1, Padding = Ui.P(28, 24, 28, 18), BackColor = Ui.Card, Dock = DockStyle.Fill };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(340)));
            Controls.Add(grid);
            var icon = Ui.Icon("\uE72E", 22f, Ui.Primary);
            icon.Margin = Ui.P(0, 0, 0, 8);
            grid.Controls.Add(icon);
            grid.Controls.Add(Ui.Label("لوحة التشغيل محمية", 14f, Ui.Ink, true));
            var sub = Ui.Wrap("أدخل كلمة مرور اللوحة للمتابعة. النظام يعمل على كل الأجهزة في الأثناء.", 9.5f, Ui.Muted);
            sub.Margin = Ui.P(0, 2, 0, 12);
            grid.Controls.Add(sub);
            box = new TextBox { UseSystemPasswordChar = true, Dock = DockStyle.Fill, Font = Ui.Font(12f), RightToLeft = RightToLeft.No, Margin = Ui.P(0, 0, 0, 4) };
            grid.Controls.Add(box);
            error = new Label { AutoSize = true, ForeColor = Ui.Red, Text = "", Margin = Ui.P(0, 2, 0, 6), Dock = DockStyle.Fill };
            grid.Controls.Add(error);
            ok = Ui.Button("دخول", Ui.Kind.Primary);
            ok.MinimumSize = new Size(Ui.S(110), Ui.S(40));
            var cancel = Ui.Button("إلغاء", Ui.Kind.Secondary);
            cancel.DialogResult = DialogResult.Cancel;
            ok.Click += (s, e) => Try();
            grid.Controls.Add(Ui.Row(ok, cancel));
            AcceptButton = ok;
            CancelButton = cancel;
            Shown += (s, e) => box.Focus();
        }

        void Try()
        {
            if (settings.CheckPassword(box.Text)) { DialogResult = DialogResult.OK; return; }
            wrong++;
            box.SelectAll();
            box.Focus();
            if (wrong < 5) { error.Text = "كلمة المرور غير صحيحة."; return; }
            // A pause after several wrong tries.
            error.Text = "محاولات كثيرة. انتظر 30 ثانية.";
            ok.Enabled = box.Enabled = false;
            var t = new System.Windows.Forms.Timer { Interval = 30000 };
            t.Tick += (s, e) => { t.Dispose(); wrong = 0; ok.Enabled = box.Enabled = true; error.Text = ""; box.Focus(); };
            t.Start();
        }
    }

    // Edits config.txt (and the panel's password) through a form instead of
    // a text editor. The buttons stay at the bottom and the fields scroll,
    // so it fits small screens too.
    class SettingsForm : Form
    {
        const string AutoIp = "تلقائي";
        public Dictionary<string, string> Values = new Dictionary<string, string>();
        // Null: unchanged; "": removed.
        public string NewPassword;

        readonly TextBox nameBox;
        readonly ComboBox ipBox;
        readonly NumericUpDown httpBox, httpsBox, workersBox;
        readonly CheckBox autoOpenBox, dnsBox;
        readonly TextBox backupBox;
        readonly TextBox pwBox, pwConfirm;
        readonly CheckBox pwRemove;
        readonly TextBox tokenBox, siteUrlBox, panelUrlBox;
        readonly string root;
        readonly Label error;
        readonly Panel scroll;
        readonly Dictionary<string, string> cfg;

        public SettingsForm(Dictionary<string, string> cfg, string root, bool hasPassword)
        {
            this.root = root;
            this.cfg = cfg;
            Text = "الإعدادات";
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Font = Ui.Font(10f);
            AutoScaleMode = AutoScaleMode.None;
            FormBorderStyle = FormBorderStyle.Sizable;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterParent;
            BackColor = Ui.Bg;
            var wa = Screen.FromPoint(Cursor.Position).WorkingArea;
            ClientSize = new Size(Math.Min(Ui.S(720), wa.Width - Ui.S(40)), Math.Min(Ui.S(720), wa.Height - Ui.S(60)));
            MinimumSize = new Size(Math.Min(Ui.S(560), wa.Width), Math.Min(Ui.S(420), wa.Height));

            // Buttons, always visible.
            var bar = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = Ui.S(64), ColumnCount = 2, BackColor = Ui.Card, Padding = Ui.P(20, 10, 20, 10) };
            bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            bar.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            bar.Paint += (s, e) => { using (var pen = new Pen(Ui.Border)) e.Graphics.DrawLine(pen, 0, 0, bar.Width, 0); };
            error = new Label { AutoSize = true, ForeColor = Ui.Red, Anchor = AnchorStyles.Left, Text = "" };
            var save = Ui.Button("حفظ", Ui.Kind.Primary);
            var cancel = Ui.Button("إلغاء", Ui.Kind.Secondary);
            var defaults = Ui.Button("القيم الافتراضية", Ui.Kind.Secondary);
            var buttons = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Anchor = AnchorStyles.Right, BackColor = Ui.Card };
            buttons.Controls.AddRange(new Control[] { save, cancel, defaults });
            bar.Controls.Add(error, 0, 0);
            bar.Controls.Add(buttons, 1, 0);

            scroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Ui.Bg, Padding = Ui.P(20, 18, 20, 4) };
            var body = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 1, BackColor = Ui.Bg };
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            scroll.Controls.Add(body);
            Controls.Add(scroll);
            Controls.Add(bar);
            scroll.BringToFront();

            // Network
            var net = Section(body, "الشبكة", "تُطبَّق بعد إعادة تشغيل النظام.");
            nameBox = new TextBox { Width = Ui.S(300), RightToLeft = RightToLeft.No, Text = Value("SERVER_NAME", "clinic.lan") };
            AddField(net, "اسم النظام على الشبكة", nameBox, "الاسم الذي تفتح به الأجهزة النظام. الافتراضي clinic.lan");
            ipBox = new ComboBox { Width = Ui.S(300), RightToLeft = RightToLeft.No, DropDownStyle = ComboBoxStyle.DropDown };
            ipBox.Items.Add(AutoIp);
            foreach (var ip in Engine.LocalAddresses()) ipBox.Items.Add(ip);
            string savedIp = Value("SERVER_IP", "");
            ipBox.Text = savedIp.Length == 0 ? AutoIp : savedIp;
            AddField(net, "عنوان هذا الجهاز", ipBox, "اتركه «تلقائي» إلا إذا ثبّتّ للجهاز عنوانًا في راوتر Deco.");
            httpBox = Number(1, 65535, IntValue("HTTP_PORT", 80));
            AddField(net, "منفذ HTTP", httpBox, "80 افتراضيًا. غيّره فقط إذا كان برنامج آخر (مثل XAMPP) يستخدمه.");
            httpsBox = Number(1, 65535, IntValue("HTTPS_PORT", 443));
            AddField(net, "منفذ HTTPS", httpsBox, "443 افتراضيًا.");
            workersBox = Number(2, 64, IntValue("PHP_WORKERS", 16));
            AddField(net, "عدد الطلبات المتزامنة", workersBox, "16 مناسب لأغلب العيادات، و24 أو 32 مع ذاكرة 16 غيغابايت.");
            dnsBox = new CheckBox { Text = "تشغيل خادم الأسماء (DNS)", AutoSize = true, Checked = Value("DNS", "1") != "0" };
            AddField(net, "", dnsBox, "اختياري. بدونه تدخل الأجهزة بعنوان IP هذا الجهاز، وهو الأسرع والأثبت. يلزم فقط لاسم " + Value("SERVER_NAME", "clinic.lan") + " وللفتح التلقائي.");
            autoOpenBox = new CheckBox { Text = "فتح النظام تلقائيًا عند الاتصال بالواي فاي", AutoSize = true, Checked = Value("AUTO_OPEN", "1") != "0" };
            AddField(net, "", autoOpenBox, "يحتاج أن يكون هذا الجهاز خادم DNS في راوتر Deco، ومنفذ HTTP هو 80.");

            // Backups
            var bk = Section(body, "النسخ الاحتياطي", null);
            var backupRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = Padding.Empty, BackColor = Ui.Card };
            backupBox = new TextBox { Width = Ui.S(230), RightToLeft = RightToLeft.No, Text = Value("BACKUP_DIR", "") };
            if (backupBox.Text.Length == 0) backupBox.Text = Engine.DefaultBackupDir(root);
            var browse = Ui.Button("اختيار...", Ui.Kind.Secondary);
            browse.MinimumSize = new Size(Ui.S(70), Ui.S(30));
            browse.Margin = Ui.P(8, 0, 0, 0);
            browse.Click += (s, e) =>
            {
                using (var dlg = new FolderBrowserDialog { Description = "مجلد النسخ الاحتياطية", SelectedPath = backupBox.Text })
                    if (dlg.ShowDialog(this) == DialogResult.OK) backupBox.Text = dlg.SelectedPath;
            };
            backupRow.Controls.Add(backupBox);
            backupRow.Controls.Add(browse);
            AddField(bk, "مجلد النسخ الاحتياطية", backupRow, "خارج مجلد البرنامج حتى لا يُحذف معه. يمكن اختيار قرص آخر أو فلاشة تبقى موصولة.");

            // Password (2026-10-31, by request: none by default).
            var sec = Section(body, "كلمة مرور لوحة التشغيل",
                hasPassword ? "اللوحة محمية بكلمة مرور الآن. اكتب كلمة جديدة لتغييرها، أو اختر الإزالة."
                            : "اختيارية، ولا توجد كلمة مرور الآن. عند وضعها تُطلب لفتح اللوحة ولإيقاف النظام، وتُفعّل التحكم بالخادم عبر الإنترنت.");
            pwBox = new TextBox { Width = Ui.S(260), UseSystemPasswordChar = true, RightToLeft = RightToLeft.No };
            AddField(sec, hasPassword ? "كلمة مرور جديدة" : "كلمة المرور", pwBox, "6 أحرف أو أرقام على الأقل. اتركها فارغة لعدم التغيير.");
            pwConfirm = new TextBox { Width = Ui.S(260), UseSystemPasswordChar = true, RightToLeft = RightToLeft.No };
            AddField(sec, "تأكيد كلمة المرور", pwConfirm, "");
            pwRemove = new CheckBox { Text = "إزالة كلمة المرور (فتح اللوحة دون كلمة مرور)", AutoSize = true, Visible = hasPassword };
            pwRemove.CheckedChanged += (s, e) => { pwBox.Enabled = pwConfirm.Enabled = !pwRemove.Checked; };
            if (hasPassword) AddField(sec, "", pwRemove, "بدون كلمة مرور يتوقف التحكم بالخادم عبر الإنترنت، ويبقى فتح النظام نفسه عبر الإنترنت.");

            // Online access, advanced (2026-10-31).
            var online = Section(body, "الوصول عبر الإنترنت (متقدم)",
                "اختياري. يعمل الوصول عبر الإنترنت دون أي إعداد بنفق Cloudflare مجاني. لنفق دائم بنطاقك الخاص أنشئ نفقًا في حساب Cloudflare، ووجّه فيه اسمًا إلى http://127.0.0.1:" + IntValue("TUNNEL_PORT", 18091) +
                " (النظام) واسمًا آخر إلى http://127.0.0.1:" + IntValue("PANEL_PORT", 18092) + " (لوحة التشغيل)، ثم الصق رمزه هنا.");
            tokenBox = new TextBox { Width = Ui.S(300), RightToLeft = RightToLeft.No, Text = Value("TUNNEL_TOKEN", ""), UseSystemPasswordChar = Value("TUNNEL_TOKEN", "").Length > 0 };
            AddField(online, "رمز النفق (Token)", tokenBox, "اتركه فارغًا لاستعمال النفق المجاني التلقائي.");
            siteUrlBox = new TextBox { Width = Ui.S(300), RightToLeft = RightToLeft.No, Text = Value("TUNNEL_SITE_URL", "") };
            AddField(online, "رابط النظام", siteUrlBox, "مثل https://clinic.example.com");
            panelUrlBox = new TextBox { Width = Ui.S(300), RightToLeft = RightToLeft.No, Text = Value("TUNNEL_PANEL_URL", "") };
            AddField(online, "رابط لوحة التشغيل", panelUrlBox, "مثل https://panel.example.com");

            save.Click += (s, e) => Save();
            cancel.Click += (s, e) => { DialogResult = DialogResult.Cancel; };
            defaults.Click += (s, e) =>
            {
                nameBox.Text = "clinic.lan"; ipBox.Text = AutoIp; httpBox.Value = 80; httpsBox.Value = 443;
                workersBox.Value = 16; dnsBox.Checked = true; autoOpenBox.Checked = true; backupBox.Text = Engine.DefaultBackupDir(root);
            };
            AcceptButton = save;
            CancelButton = cancel;
        }

        public void ScrollDown()
        {
            scroll.AutoScrollPosition = new Point(0, scroll.DisplayRectangle.Height);
        }

        Card Section(TableLayoutPanel body, string title, string subtitle)
        {
            var card = new Card();
            card.Title(title, subtitle);
            body.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            body.Controls.Add(card, 0, body.RowCount);
            body.RowCount++;
            var grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Fill, BackColor = Ui.Card, Margin = Padding.Empty };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Ui.S(170)));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            card.Add(grid);
            card.Tag = grid;
            return card;
        }

        string Value(string key, string def)
        {
            string v;
            return cfg.TryGetValue(key, out v) ? v : def;
        }

        int IntValue(string key, int def)
        {
            int v;
            return int.TryParse(Value(key, ""), out v) ? v : def;
        }

        static NumericUpDown Number(int min, int max, int value)
        {
            return new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Max(min, Math.Min(max, value)), Width = Ui.S(120), RightToLeft = RightToLeft.No };
        }

        static void AddField(Card card, string caption, Control input, string hint)
        {
            var grid = (TableLayoutPanel)card.Tag;
            int row = grid.RowCount;
            grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            grid.Controls.Add(new Label { Text = caption, AutoSize = true, Margin = Ui.P(0, 10, 12, 0), Font = Ui.Bold(10f), ForeColor = Ui.Ink }, 0, row);
            var cell = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, Dock = DockStyle.Fill, Margin = Ui.P(0, 6, 0, 4), BackColor = Ui.Card };
            cell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            input.Margin = Ui.P(0, 0, 0, 2);
            cell.Controls.Add(input, 0, 0);
            if (hint.Length > 0) cell.Controls.Add(Ui.Wrap(hint, 8.5f, Ui.Muted), 0, 1);
            grid.Controls.Add(cell, 1, row);
            grid.RowCount++;
        }

        void Save()
        {
            string name = nameBox.Text.Trim().ToLowerInvariant();
            if (!Regex.IsMatch(name, @"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$"))
            {
                error.Text = "اسم النظام غير صالح: أحرف إنجليزية وأرقام ونقاط فقط، مثل clinic.lan";
                return;
            }
            string ip = ipBox.Text.Trim();
            if (ip == AutoIp) ip = "";
            IPAddress parsed;
            if (ip.Length > 0 && (!IPAddress.TryParse(ip, out parsed) || parsed.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork || ip.Split('.').Length != 4))
            {
                error.Text = "عنوان الجهاز غير صالح. اكتب عنوانًا مثل 192.168.68.10 أو اختر «تلقائي».";
                return;
            }
            int http = (int)httpBox.Value, https = (int)httpsBox.Value;
            if (http == https)
            {
                error.Text = "منفذ HTTP ومنفذ HTTPS يجب أن يكونا مختلفين.";
                return;
            }
            var reserved = new[] { Engine.DbPort, 53, IntValue("TUNNEL_PORT", 18091), IntValue("PANEL_PORT", 18092) };
            if (reserved.Contains(http) || reserved.Contains(https) || (http >= 9100 && http < 9200) || (https >= 9100 && https < 9200))
            {
                error.Text = "هذا المنفذ محجوز لخدمة أخرى في النظام. اختر منفذًا آخر مثل 8080.";
                return;
            }
            string backup = backupBox.Text.Trim().TrimEnd('\\');
            if (backup.Length == 0 || !Path.IsPathRooted(backup))
            {
                error.Text = "اكتب مسارًا كاملًا لمجلد النسخ الاحتياطية، مثل C:\\DentalClinicBackups";
                return;
            }
            if ((backup + "\\").StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
            {
                error.Text = "اختر مجلدًا خارج مجلد البرنامج، حتى لا تُحذف النسخ إذا استبدلت البرنامج.";
                return;
            }
            if (string.Equals(backup, Engine.DefaultBackupDir(root), StringComparison.OrdinalIgnoreCase)) backup = "";

            NewPassword = null;
            if (pwRemove.Visible && pwRemove.Checked) NewPassword = "";
            else if (pwBox.Text.Length > 0 || pwConfirm.Text.Length > 0)
            {
                if (pwBox.Text.Length < 6) { error.Text = "كلمة المرور قصيرة: 6 أحرف أو أرقام على الأقل."; return; }
                if (pwBox.Text != pwConfirm.Text) { error.Text = "كلمتا المرور غير متطابقتين."; return; }
                NewPassword = pwBox.Text;
            }

            string token = tokenBox.Text.Trim(), siteUrl = siteUrlBox.Text.Trim().TrimEnd('/'), panelUrl = panelUrlBox.Text.Trim().TrimEnd('/');
            if (token.Length > 0 && !Regex.IsMatch(token, @"^[A-Za-z0-9_\-=+/.]{20,}$"))
            {
                error.Text = "رمز النفق غير صالح. انسخه كاملًا من صفحة النفق في Cloudflare.";
                return;
            }
            foreach (var u in new[] { siteUrl, panelUrl })
            {
                if (u.Length > 0 && !Regex.IsMatch(u, @"^https://[A-Za-z0-9.-]+(:\d+)?$"))
                {
                    error.Text = "الرابط يجب أن يكون مثل https://clinic.example.com";
                    return;
                }
            }
            if (token.Length > 0 && siteUrl.Length == 0)
            {
                error.Text = "مع رمز النفق اكتب رابط النظام الذي أعطيته له في Cloudflare.";
                return;
            }

            Values = new Dictionary<string, string>
            {
                { "SERVER_NAME", name },
                { "SERVER_IP", ip },
                { "HTTP_PORT", http.ToString() },
                { "HTTPS_PORT", https.ToString() },
                { "PHP_WORKERS", ((int)workersBox.Value).ToString() },
                { "DNS", dnsBox.Checked ? "1" : "0" },
                { "AUTO_OPEN", autoOpenBox.Checked ? "1" : "0" },
                { "BACKUP_DIR", backup },
                { "TUNNEL_TOKEN", token },
                { "TUNNEL_SITE_URL", siteUrl },
                { "TUNNEL_PANEL_URL", panelUrl },
            };
            DialogResult = DialogResult.OK;
        }
    }

    // Online access (2026-10-31, by request: reach and control the offline
    // server and the clinic system over the internet). Cloudflare's free
    // tunnel program (cloudflared, bundled in cloudflared\) connects out to
    // Cloudflare, so nothing is opened in the router and no fixed address is
    // needed. Two tunnels: the clinic system (the local web server's site on
    // TUNNEL_PORT, see prepare.ps1) and, only while the panel has a password,
    // the panel's remote control page (PanelWeb on PANEL_PORT). A free tunnel
    // gets a new address on every start, so the addresses are reported to the
    // hosting, whose fixed link /go/{slug} leads to the current one. With a
    // token from a Cloudflare account (TUNNEL_TOKEN) one permanent tunnel
    // serves both, at the addresses given to it there.
    class Tunnel
    {
        const string ReportApi = "https://dental.azoclinic.duckdns.org/api/v1/offline/tunnel";
        static readonly Regex QuickUrl = new Regex(@"https://[a-z0-9-]+\.trycloudflare\.com", RegexOptions.Compiled);

        class Proc
        {
            public string Name, Args;
            public Process P;
            public volatile string Url = "";
            public volatile bool Connected;
            public DateTime NextTry = DateTime.MinValue;
            public int Fails;
        }

        readonly Engine engine;
        readonly Func<string[]> license;
        public Func<bool> PanelReady = () => false;
        readonly Proc site = new Proc { Name = "site" }, panel = new Proc { Name = "panel" };
        readonly object gate = new object();
        System.Threading.Timer timer;
        volatile bool ended;
        string reportedSite, reportedPanel;
        DateTime lastReport = DateTime.MinValue;
        int reporting;

        public volatile string Link = "", PanelLink = "", Error = "", LinkNote = "";

        public Tunnel(Engine engine, Func<string[]> license)
        {
            this.engine = engine;
            this.license = license;
        }

        public string Exe { get { return engine.P(@"cloudflared\cloudflared.exe"); } }
        public bool Installed { get { return File.Exists(Exe); } }
        bool Token { get { return engine.TunnelToken.Length > 0; } }
        public bool Connected { get { return site.Connected; } }
        public string SiteUrl { get { return Token ? engine.TunnelSiteUrl : site.Url; } }
        public string PanelUrl { get { return Token ? engine.TunnelPanelUrl : (panel.Connected ? panel.Url : ""); } }

        public void Begin()
        {
            ended = false;
            if (timer == null) timer = new System.Threading.Timer(_ => Tick(), null, 1500, 3000);
        }

        // Settings changed: act now rather than on the next tick.
        public void Poke()
        {
            if (timer != null) timer.Change(200, 3000);
        }

        public void End()
        {
            ended = true;
            if (timer != null) { timer.Dispose(); timer = null; }
            lock (gate)
            {
                bool was = site.P != null;
                Kill(site);
                Kill(panel);
                if (was) Report(true);
            }
        }

        void Tick()
        {
            if (ended || !Monitor.TryEnter(gate)) return;
            try
            {
                bool on = engine.TunnelOn && !engine.NoTunnel && Installed;
                string siteArgs = Token
                    ? "tunnel --no-autoupdate run --token " + engine.TunnelToken
                    : "tunnel --no-autoupdate --url http://127.0.0.1:" + engine.TunnelPort;
                Ensure(site, on, siteArgs);
                Ensure(panel, on && !Token && PanelReady(), "tunnel --no-autoupdate --url http://127.0.0.1:" + engine.PanelPort);
                if (!on)
                {
                    if (reportedSite != null) Report(true);
                    Link = PanelLink = "";
                    Error = "";
                    return;
                }
                if (site.Connected && (SiteUrl != reportedSite || PanelUrl != reportedPanel || (DateTime.Now - lastReport).TotalMinutes >= 5))
                    Report(false);
            }
            catch (Exception ex) { Error = ex.Message; }
            finally { Monitor.Exit(gate); }
        }

        void Ensure(Proc t, bool want, string args)
        {
            bool alive = false;
            try { alive = t.P != null && !t.P.HasExited; } catch { }
            if (!want || (alive && t.Args != args))
            {
                Kill(t);
                if (!want) return;
                alive = false;
            }
            if (alive) return;
            if (t.P != null)
            {
                // It stopped by itself: try again, waiting longer each time.
                t.P = null;
                t.Url = "";
                t.Connected = false;
                t.Fails++;
                t.NextTry = DateTime.Now.AddSeconds(Math.Min(120, 5 * t.Fails * t.Fails));
                engine.Log("انقطع نفق " + (t.Name == "site" ? "النظام" : "لوحة التشغيل") + "، إعادة المحاولة بعد " + (int)(t.NextTry - DateTime.Now).TotalSeconds + " ثانية.");
            }
            if (DateTime.Now < t.NextTry) return;
            Launch(t, args);
        }

        void Launch(Proc t, string args)
        {
            string log = Path.Combine(engine.LogDir, "tunnel-" + t.Name + ".log");
            var p = new Process();
            p.StartInfo = engine.Info(Exe, args, engine.Root);
            DataReceivedEventHandler h = (s, e) =>
            {
                if (e.Data == null) return;
                try { File.AppendAllText(log, e.Data + Environment.NewLine); } catch { }
                var m = QuickUrl.Match(e.Data);
                if (m.Success && !e.Data.Contains("api.trycloudflare.com")) t.Url = m.Value;
                if (e.Data.Contains("Registered tunnel connection"))
                {
                    if (!t.Connected) engine.Log("الوصول عبر الإنترنت يعمل" + (t.Url.Length > 0 ? ": " + t.Url : "") + (t.Name == "panel" ? " (لوحة التشغيل)" : ""));
                    t.Connected = true;
                    t.Fails = 0;
                    Error = "";
                }
                if (e.Data.Contains("failed to request quick Tunnel") || e.Data.Contains("Unauthorized") || e.Data.Contains("Invalid tunnel secret"))
                    Error = "تعذّر إنشاء النفق: " + Short(e.Data);
                else if (!t.Connected && (e.Data.Contains("no such host") || e.Data.Contains("dial tcp") || e.Data.Contains("i/o timeout")))
                    Error = "لا يوجد اتصال بالإنترنت على هذا الحاسوب، أو أن الشبكة تمنع Cloudflare. يعيد البرنامج المحاولة وحده.";
            };
            p.OutputDataReceived += h;
            p.ErrorDataReceived += h;
            try { File.WriteAllText(log, DateTime.Now.ToString("s") + " cloudflared " + (Token ? "tunnel run (token)" : args) + Environment.NewLine); } catch { }
            t.Args = args;
            t.Url = "";
            t.Connected = false;
            p.Start();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            t.P = p;
        }

        static string Short(string line)
        {
            int i = line.IndexOf("ERR ");
            string s = i >= 0 ? line.Substring(i + 4) : line;
            return s.Length > 160 ? s.Substring(0, 160) : s;
        }

        static void Kill(Proc t)
        {
            try { if (t.P != null && !t.P.HasExited) { t.P.Kill(); t.P.WaitForExit(5000); } } catch { }
            t.P = null;
            t.Url = "";
            t.Connected = false;
            t.Fails = 0;
            t.NextTry = DateTime.MinValue;
        }

        // Tells the hosting where the tunnel is now (and empty when it is off).
        void Report(bool off)
        {
            var lic = license();
            string siteUrl = off ? null : SiteUrl, panelUrl = off ? null : PanelUrl;
            reportedSite = off ? null : siteUrl;
            reportedPanel = off ? null : panelUrl;
            lastReport = DateTime.Now;
            if (lic == null)
            {
                LinkNote = "يظهر الرابط الثابت بعد تفعيل النسخة برمز الجامعة. إلى ذلك الحين استعمل «عنوان النفق الحالي»، وهو يتغير عند كل تشغيل.";
                return;
            }
            if (Interlocked.Exchange(ref reporting, 1) == 1) return;
            Action send = () =>
            {
                try
                {
                    ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // TLS 1.2
                    var body = new JavaScriptSerializer().Serialize(new Dictionary<string, object>
                    {
                        { "code", lic[0] }, { "machine", lic[1] },
                        { "url", string.IsNullOrEmpty(siteUrl) ? null : siteUrl },
                        { "panel_url", string.IsNullOrEmpty(panelUrl) ? null : panelUrl },
                    });
                    var req = (HttpWebRequest)WebRequest.Create(ReportApi);
                    req.Method = "POST";
                    req.ContentType = "application/json";
                    req.Accept = "application/json";
                    req.UserAgent = "DentalClinicPanel";
                    req.Timeout = off ? 5000 : 20000;
                    var bytes = Encoding.UTF8.GetBytes(body);
                    using (var s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
                    string json;
                    using (var resp = req.GetResponse())
                    using (var sr = new StreamReader(resp.GetResponseStream())) json = sr.ReadToEnd();
                    var d = new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string, object>;
                    if (d != null && !off)
                    {
                        Link = d.ContainsKey("link") ? (d["link"] as string ?? "") : "";
                        PanelLink = !string.IsNullOrEmpty(panelUrl) && d.ContainsKey("panel_link") ? (d["panel_link"] as string ?? "") : "";
                        LinkNote = "";
                    }
                }
                catch (Exception ex)
                {
                    // Tried again on the next tick.
                    reportedSite = null;
                    var we = ex as WebException;
                    var r = we == null ? null : we.Response as HttpWebResponse;
                    LinkNote = r != null && r.StatusCode == HttpStatusCode.Forbidden
                        ? "رمز التفعيل لهذا الحاسوب موقوف، فلا يوجد رابط ثابت. استعمل «عنوان النفق الحالي»."
                        : "تعذّر الوصول إلى الاستضافة لحفظ الرابط الثابت، يعيد البرنامج المحاولة. استعمل «عنوان النفق الحالي» الآن.";
                }
                finally { reporting = 0; }
            };
            if (off) send();
            else ThreadPool.QueueUserWorkItem(_ => send());
        }
    }

    // The panel's remote control page (2026-10-31), served on this computer
    // only (127.0.0.1:PANEL_PORT) and reached over the tunnel. Needs the
    // panel's password; a small HTTP server of its own, so it needs no
    // administrator rights and keeps working while the system is stopped.
    class PanelWeb
    {
        readonly int port;
        readonly Settings settings;
        readonly Func<Dictionary<string, object>> status;
        readonly Func<string, string> action;
        readonly Action<string> log;
        TcpListener listener;
        readonly Dictionary<string, DateTime> sessions = new Dictionary<string, DateTime>();
        readonly List<DateTime> failures = new List<DateTime>();
        public volatile bool Listening;

        public PanelWeb(int port, Settings settings, Func<Dictionary<string, object>> status, Func<string, string> action, Action<string> log)
        {
            this.port = port;
            this.settings = settings;
            this.status = status;
            this.action = action;
            this.log = log;
        }

        public void Start()
        {
            if (listener != null) return;
            try
            {
                listener = new TcpListener(IPAddress.Loopback, port);
                listener.Start();
                Listening = true;
            }
            catch (Exception ex)
            {
                listener = null;
                Listening = false;
                log("تعذّر تشغيل صفحة التحكم عن بعد على المنفذ " + port + ": " + ex.Message);
                return;
            }
            var l = listener;
            var t = new Thread(() =>
            {
                while (true)
                {
                    TcpClient c;
                    try { c = l.AcceptTcpClient(); } catch { return; }
                    ThreadPool.QueueUserWorkItem(_ => Serve(c));
                }
            });
            t.IsBackground = true;
            t.Start();
        }

        public void Stop()
        {
            Listening = false;
            try { if (listener != null) listener.Stop(); } catch { }
            listener = null;
        }

        public void ForgetSessions()
        {
            lock (sessions) sessions.Clear();
        }

        class Request
        {
            public string Method, Path, Body = "";
            public Dictionary<string, string> Headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }

        void Serve(TcpClient c)
        {
            using (c)
            {
                try
                {
                    c.ReceiveTimeout = 15000;
                    c.SendTimeout = 15000;
                    var stream = c.GetStream();
                    var req = Read(stream);
                    if (req == null) return;
                    Handle(req, stream);
                }
                catch { }
            }
        }

        static Request Read(NetworkStream stream)
        {
            var buf = new byte[8192];
            var ms = new MemoryStream();
            int headerEnd = -1;
            while (headerEnd < 0)
            {
                int n = stream.Read(buf, 0, buf.Length);
                if (n <= 0) return null;
                ms.Write(buf, 0, n);
                if (ms.Length > 32768) return null;
                headerEnd = Find(ms.GetBuffer(), (int)ms.Length);
            }
            byte[] all = ms.ToArray();
            string head = Encoding.ASCII.GetString(all, 0, headerEnd);
            var lines = head.Split(new[] { "\r\n" }, StringSplitOptions.None);
            var first = lines[0].Split(' ');
            if (first.Length < 2) return null;
            var req = new Request { Method = first[0].ToUpperInvariant(), Path = first[1] };
            for (int i = 1; i < lines.Length; i++)
            {
                int colon = lines[i].IndexOf(':');
                if (colon > 0) req.Headers[lines[i].Substring(0, colon).Trim()] = lines[i].Substring(colon + 1).Trim();
            }
            int length = 0;
            string cl;
            if (req.Headers.TryGetValue("Content-Length", out cl)) int.TryParse(cl, out length);
            if (length < 0 || length > 65536) return null;
            var body = new MemoryStream();
            body.Write(all, headerEnd + 4, all.Length - headerEnd - 4);
            while (body.Length < length)
            {
                int n = stream.Read(buf, 0, buf.Length);
                if (n <= 0) break;
                body.Write(buf, 0, n);
            }
            req.Body = Encoding.UTF8.GetString(body.ToArray(), 0, (int)Math.Min(body.Length, length));
            return req;
        }

        static int Find(byte[] b, int len)
        {
            for (int i = 0; i + 3 < len; i++)
                if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
            return -1;
        }

        string Session(Request req)
        {
            string cookie;
            if (!req.Headers.TryGetValue("Cookie", out cookie)) return null;
            foreach (var part in cookie.Split(';'))
            {
                var kv = part.Trim();
                if (!kv.StartsWith("dcp=")) continue;
                string token = kv.Substring(4);
                lock (sessions)
                {
                    DateTime until;
                    if (sessions.TryGetValue(token, out until) && until > DateTime.Now) return token;
                }
            }
            return null;
        }

        void Handle(Request req, NetworkStream s)
        {
            string path = req.Path.Split('?')[0];
            if (!settings.HasPassword)
            {
                Send(s, 403, "text/html; charset=utf-8", Html.Page("التحكم عن بعد غير مفعّل",
                    "<div class='card'><h1>التحكم عن بعد غير مفعّل</h1><p class='muted'>ضع كلمة مرور للوحة التشغيل من «الإعدادات» على حاسوب الخادم لتفعيله.</p></div>", ""), null);
                return;
            }
            string session = Session(req);

            if (path == "/login" && req.Method == "POST")
            {
                string pw = Form(req.Body, "password");
                lock (failures)
                {
                    failures.RemoveAll(t => (DateTime.Now - t).TotalMinutes > 10);
                    if (failures.Count >= 5)
                    {
                        Send(s, 429, "text/html; charset=utf-8", Html.Login("محاولات كثيرة خاطئة. انتظر 10 دقائق ثم أعد المحاولة."), null);
                        return;
                    }
                }
                if (!settings.CheckPassword(pw))
                {
                    lock (failures) failures.Add(DateTime.Now);
                    log("محاولة دخول خاطئة إلى التحكم عن بعد.");
                    Thread.Sleep(1000);
                    Send(s, 401, "text/html; charset=utf-8", Html.Login("كلمة المرور غير صحيحة."), null);
                    return;
                }
                string token = NewToken();
                lock (sessions)
                {
                    foreach (var k in sessions.Where(kv => kv.Value < DateTime.Now).Select(kv => kv.Key).ToList()) sessions.Remove(k);
                    sessions[token] = DateTime.Now.AddHours(12);
                }
                log("دخول إلى التحكم عن بعد.");
                Send(s, 303, "text/plain", "", new[] { "Location: /", "Set-Cookie: dcp=" + token + "; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=43200" });
                return;
            }
            if (path == "/logout" && req.Method == "POST")
            {
                if (session != null) lock (sessions) sessions.Remove(session);
                Send(s, 303, "text/plain", "", new[] { "Location: /", "Set-Cookie: dcp=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0" });
                return;
            }
            if (session == null)
            {
                if (path.StartsWith("/api/")) { Send(s, 401, "application/json", "{\"message\":\"login\"}", null); return; }
                Send(s, 200, "text/html; charset=utf-8", Html.Login(""), null);
                return;
            }
            // The page's own requests carry its token back (no other site can).
            string csrf = Csrf(session);
            if (path == "/api/status" && req.Method == "GET")
            {
                Send(s, 200, "application/json; charset=utf-8", new JavaScriptSerializer().Serialize(status()), null);
                return;
            }
            if (path == "/api/action" && req.Method == "POST")
            {
                string sent;
                if (!req.Headers.TryGetValue("X-Panel-Token", out sent) || sent != csrf) { Send(s, 403, "application/json", "{\"message\":\"\"}", null); return; }
                string msg = action(Form(req.Body, "action"));
                Send(s, 200, "application/json; charset=utf-8", new JavaScriptSerializer().Serialize(new Dictionary<string, object> { { "message", msg } }), null);
                return;
            }
            if (path == "/" && req.Method == "GET")
            {
                Send(s, 200, "text/html; charset=utf-8", Html.Panel(csrf), null);
                return;
            }
            Send(s, 404, "text/plain; charset=utf-8", "Not found", null);
        }

        static string NewToken()
        {
            var b = new byte[24];
            using (var rng = new RNGCryptoServiceProvider()) rng.GetBytes(b);
            return Convert.ToBase64String(b).Replace('+', '-').Replace('/', '_').TrimEnd('=');
        }

        static string Csrf(string session)
        {
            using (var sha = SHA256.Create())
                return Convert.ToBase64String(sha.ComputeHash(Encoding.UTF8.GetBytes("csrf:" + session))).Substring(0, 24);
        }

        static string Form(string body, string key)
        {
            foreach (var part in (body ?? "").Split('&'))
            {
                int eq = part.IndexOf('=');
                if (eq > 0 && part.Substring(0, eq) == key) return Uri.UnescapeDataString(part.Substring(eq + 1).Replace('+', ' '));
            }
            return "";
        }

        static void Send(NetworkStream s, int code, string type, string body, string[] headers)
        {
            byte[] data = Encoding.UTF8.GetBytes(body);
            var sb = new StringBuilder();
            sb.Append("HTTP/1.1 ").Append(code).Append(code == 200 ? " OK" : code == 303 ? " See Other" : " Error").Append("\r\n");
            sb.Append("Content-Type: ").Append(type).Append("\r\n");
            sb.Append("Content-Length: ").Append(data.Length).Append("\r\n");
            sb.Append("Cache-Control: no-store\r\n");
            sb.Append("X-Frame-Options: DENY\r\n");
            sb.Append("X-Content-Type-Options: nosniff\r\n");
            sb.Append("Referrer-Policy: no-referrer\r\n");
            sb.Append("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'\r\n");
            sb.Append("Connection: close\r\n");
            if (headers != null) foreach (var h in headers) sb.Append(h).Append("\r\n");
            sb.Append("\r\n");
            byte[] head = Encoding.ASCII.GetBytes(sb.ToString());
            s.Write(head, 0, head.Length);
            s.Write(data, 0, data.Length);
            s.Flush();
        }
    }

    // The remote control page itself: one file, Arabic, for phones and computers.
    static class Html
    {
        const string Style = @"
:root{--bg:#f1f5f9;--card:#fff;--ink:#0f172a;--muted:#64748b;--border:#e2e8f0;--primary:#0d9488;--primary-dark:#0f766e;
--green:#16a34a;--green-soft:#dcfce7;--red:#dc2626;--red-soft:#fee2e2;--amber:#d97706;--amber-soft:#fef3c7;--gray:#64748b;--gray-soft:#f1f5f9}
@media (prefers-color-scheme:dark){:root{--bg:#0b1220;--card:#111a2e;--ink:#e2e8f0;--muted:#94a3b8;--border:#1e293b;--gray-soft:#1e293b;
--green-soft:#052e1a;--red-soft:#3b0a0a;--amber-soft:#3a2405}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:'Segoe UI',Tahoma,Arial,sans-serif;font-size:15px}
header{background:#112e34;color:#fff;padding:16px 20px;display:flex;align-items:center;justify-content:space-between;gap:12px}
header b{font-size:18px}header small{display:block;color:#bad6d6;font-size:12px;font-weight:normal}
main{max-width:860px;margin:0 auto;padding:18px 16px 40px}
.card{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:18px 20px;margin-bottom:14px}
h1{font-size:20px;margin:0 0 6px}h2{font-size:16px;margin:0 0 10px}.muted{color:var(--muted)}
.state{display:flex;align-items:center;gap:12px}.dot{width:16px;height:16px;border-radius:50%;background:var(--gray);flex:none}
.btns{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
button{font:inherit;font-weight:600;border:1px solid var(--border);background:var(--card);color:var(--ink);padding:10px 16px;border-radius:10px;cursor:pointer;min-height:42px}
button.primary{background:var(--primary);border-color:var(--primary);color:#fff}button.danger{background:var(--red);border-color:var(--red);color:#fff}
button.success{background:var(--green);border-color:var(--green);color:#fff}button:disabled{opacity:.45;cursor:default}
.row{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:9px 0;border-top:1px solid var(--border)}.row:first-of-type{border-top:0}
.pill{font-size:12.5px;font-weight:600;padding:3px 10px;border-radius:99px;white-space:nowrap}
.green{color:var(--green);background:var(--green-soft)}.red{color:var(--red);background:var(--red-soft)}.amber{color:var(--amber);background:var(--amber-soft)}.gray{color:var(--gray);background:var(--gray-soft)}
pre{direction:rtl;white-space:pre-wrap;word-break:break-word;font:12.5px/1.7 'Segoe UI',Tahoma,sans-serif;margin:0;max-height:320px;overflow:auto;color:var(--muted)}
#msg{position:fixed;bottom:16px;left:16px;right:16px;max-width:520px;margin:auto;background:#0f172a;color:#fff;padding:12px 16px;border-radius:12px;display:none}
input{font:inherit;width:100%;padding:11px 12px;border:1px solid var(--border);border-radius:10px;background:var(--card);color:var(--ink);direction:ltr}
a{color:var(--primary-dark)}.ltr{direction:ltr;unicode-bidi:embed}
.login{max-width:380px;margin:12vh auto 0}
.bar{height:8px;background:var(--gray-soft);border-radius:99px;overflow:hidden;margin-top:10px;display:none}.bar i{display:block;height:100%;background:var(--primary)}
";

        public static string Page(string title, string body, string script)
        {
            return "<!doctype html><html lang='ar' dir='rtl'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>" +
                "<meta name='robots' content='noindex'><title>" + title + "</title><style>" + Style + "</style></head><body>" +
                "<header><div><b>عيادة الأسنان</b><small>لوحة تشغيل الخادم عن بعد</small></div>" + (script.Length > 0 ? "<form method='post' action='/logout'><button>خروج</button></form>" : "") + "</header>" +
                "<main>" + body + "</main><div id='msg'></div>" + (script.Length > 0 ? "<script>" + script + "</script>" : "") + "</body></html>";
        }

        public static string Login(string error)
        {
            return Page("الدخول إلى لوحة التشغيل",
                "<div class='card login'><h1>لوحة تشغيل الخادم</h1><p class='muted'>أدخل كلمة مرور لوحة التشغيل.</p>" +
                "<form method='post' action='/login'><input type='password' name='password' autofocus autocomplete='current-password' required>" +
                (error.Length > 0 ? "<p style='color:var(--red);margin:8px 0 0'>" + WebUtility.HtmlEncode(error) + "</p>" : "") +
                "<div class='btns'><button class='primary' style='width:100%'>دخول</button></div></form></div>", "");
        }

        public static string Panel(string csrf)
        {
            string body =
                "<div class='card'><div class='state'><span class='dot' id='dot'></span><div><h1 id='state'>...</h1><div class='muted' id='hint'></div></div></div>" +
                "<div class='btns'><button id='toggle' class='success'></button><button id='restart'>إعادة التشغيل</button>" +
                "<a id='site' target='_blank' rel='noopener' style='display:none'><button class='primary' type='button'>فتح نظام العيادة</button></a></div></div>" +
                "<div class='card'><h2>الخدمات</h2><div id='services'></div></div>" +
                "<div class='card'><h2>النسخ الاحتياطي</h2><div class='muted' id='backup'></div><div class='btns'><button id='backupBtn'>نسخة احتياطية الآن</button></div></div>" +
                "<div class='card'><h2>التحديثات</h2><div id='build' style='font-weight:600'></div><div class='muted' id='update'></div><div class='bar' id='bar'><i id='barFill'></i></div>" +
                "<div class='btns'><button id='check'>تحقق الآن</button><button id='apply' class='success' style='display:none'>تحديث الآن</button></div></div>" +
                "<div class='card'><h2>السجل</h2><pre id='log'></pre></div>";
            string script = @"
const T='" + csrf + @"';const $=id=>document.getElementById(id);let busy=false,st=null;
function esc(s){return String(s).replace(/[&<>""']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','""':'&quot;',""'"":'&#39;'}[c]))}
function toast(m){const e=$('msg');e.textContent=m;e.style.display='block';clearTimeout(toast.t);toast.t=setTimeout(()=>e.style.display='none',5000)}
async function act(a,ask){if(ask&&!confirm(ask))return;try{const r=await fetch('/api/action',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded','X-Panel-Token':T},body:'action='+a});
const j=await r.json();toast(j.message||'تم');setTimeout(load,800)}catch(e){toast('تعذّر الاتصال بالخادم.')}}
async function load(){try{const r=await fetch('/api/status',{cache:'no-store'});if(r.status==401){location.reload();return}st=await r.json();draw()}catch(e){$('hint').textContent='انقطع الاتصال بالخادم، إعادة المحاولة...'}}
function draw(){const s=st;const tone={green:'var(--green)',red:'var(--red)',amber:'var(--amber)',gray:'var(--gray)'};
$('dot').style.background=tone[s.tone];$('state').textContent=s.stateText;
$('hint').textContent=s.error||(s.state=='running'?'تفتحه أجهزة العيادة على '+s.lan:'');
const run=s.state=='running',wait=s.state=='starting'||s.state=='stopping';
const t=$('toggle');t.textContent=run?'إيقاف النظام':(wait?'انتظر...':'تشغيل النظام');t.className=run?'danger':'success';t.disabled=wait;
$('restart').disabled=!run;$('backupBtn').disabled=!run||s.backupBusy;$('backupBtn').textContent=s.backupBusy?'جارٍ الحفظ...':'نسخة احتياطية الآن';
const site=$('site');if(s.site&&run){site.href=s.site;site.style.display=''}else site.style.display='none';
$('services').innerHTML=s.services.map(x=>""<div class='row'><span>""+esc(x.name)+""</span><span class='pill ""+x.tone+""'>""+esc(x.status)+""</span></div>"").join('');
$('backup').textContent=s.lastBackup?'آخر نسخة: '+s.lastBackup:'لا توجد نسخة بعد.';
$('build').textContent='النسخة الحالية '+s.build;$('update').textContent=s.update;$('apply').style.display=s.updateReady?'':'none';
$('bar').style.display=s.updateProgress>=0?'block':'none';$('barFill').style.width=(Math.max(0,s.updateProgress)/10)+'%';
const lg=$('log');const end=lg.scrollTop+lg.clientHeight>=lg.scrollHeight-10;lg.textContent=s.log.join('\n');if(end)lg.scrollTop=lg.scrollHeight}
$('toggle').onclick=()=>st&&(st.state=='running'?act('stop','سيتوقف النظام على كل أجهزة العيادة. هل تريد الإيقاف؟'):act('start'));
$('restart').onclick=()=>act('restart','سيتوقف النظام لحظات على كل الأجهزة. إعادة التشغيل الآن؟');
$('backupBtn').onclick=()=>act('backup');$('check').onclick=()=>act('check-update');
$('apply').onclick=()=>act('apply-update','سيُحدَّث النظام مع نسخة احتياطية قبلها، ويتوقف دقيقة أو اثنتين. المتابعة؟');
load();setInterval(load,3000);";
            return Page("لوحة تشغيل الخادم", body, script);
        }
    }
}
