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
// see Updater).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.NetworkInformation;
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
                engine.StopLeftovers();
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
        public event Action<string> Logged;
        public List<Service> Services = new List<Service>();

        Dictionary<string, string> cfg;
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

        ProcessStartInfo Info(string file, string args, string dir)
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

        static bool TcpInUse(int port)
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
            StopLeftovers();
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
                "-NoProfile -ExecutionPolicy Bypass -File \"{0}\" -Root \"{1}\" -ServerName \"{2}\" -Workers {3} -ServerIp \"{4}\" -HttpPort {5} -HttpsPort {6} -AutoOpen {7}",
                P("prepare.ps1"), Root, ServerName, Workers, Get("SERVER_IP", ""), HttpPort, HttpsPort, DnsOn ? GetInt("AUTO_OPEN", 1) : 0);
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
            StopLeftovers(); // shuts the database down cleanly, then sweeps the rest
            foreach (var s in Services) s.Failed = false;
        }

        // Stops every process this folder started, including ones left by an
        // earlier panel or by the old Start.bat: supervisors first so nothing
        // respawns, then a clean database shutdown, then the rest.
        public void StopLeftovers()
        {
            var found = FindOwn();
            var supervisors = found.Where(f => f.Item2 == "dentalclinic.exe" || f.Item2 == "cmd.exe" || f.Item2 == "powershell.exe").ToList();
            foreach (var f in supervisors) Kill(f.Item1, false);

            if (found.Any(f => f.Item2 == "mariadbd.exe" || f.Item2 == "mysqld.exe"))
            {
                Run(P(@"mariadb\bin\mariadb-admin.exe"), "--user=root --host=127.0.0.1 --port=" + DbPort + " shutdown", Root, 30000);
                for (int i = 0; i < 30; i++)
                {
                    if (!FindOwn().Any(f => f.Item2 == "mariadbd.exe" || f.Item2 == "mysqld.exe")) break;
                    Thread.Sleep(1000);
                }
            }
            // Sweep until nothing is left: the scheduler can spawn its
            // minute's `schedule:run` (cmd + php) just as it is being
            // stopped, and that child would otherwise outlive the panel.
            for (int i = 0; i < 10; i++)
            {
                var left = FindOwn();
                if (left.Count == 0) break;
                foreach (var f in left) Kill(f.Item1, true);
                Thread.Sleep(500);
            }
        }

        List<Tuple<int, string>> FindOwn()
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
        string[] ReadLicense()
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
                engine.Stop();
                engine.StopLeftovers();

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
                    throw;
                }
                DeleteDir(staging);
                engine.Log("استُبدلت الملفات، تشغيل النسخة الجديدة...");
                Launch(headless ? "--headless --after-update" : "--after-update");
            }
            catch
            {
                State = previous;
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
            engine.Stop();
            engine.StopLeftovers();
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
    class Settings
    {
        readonly string file;
        public bool Exists;
        public bool AutoStartServices = true;

        public Settings(string root)
        {
            file = Path.Combine(root, "panel.ini");
            Exists = File.Exists(file);
            if (!Exists) return;
            foreach (var line in File.ReadAllLines(file))
            {
                if (line.StartsWith("AutoStartServices=")) AutoStartServices = line.EndsWith("1");
            }
        }

        public void Save()
        {
            try { File.WriteAllText(file, "AutoStartServices=" + (AutoStartServices ? "1" : "0") + Environment.NewLine); Exists = true; } catch { }
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
        static readonly Color Teal = Color.FromArgb(15, 118, 110);
        static readonly Color Green = Color.FromArgb(22, 163, 74);
        static readonly Color Red = Color.FromArgb(220, 38, 38);
        static readonly Color Amber = Color.FromArgb(217, 119, 6);
        static readonly Color Gray = Color.FromArgb(107, 114, 128);

        readonly Engine engine;
        readonly Updater updater;
        readonly Settings settings;
        bool startHidden;
        bool exiting;
        bool balloonShown;
        bool firewallOk = true;
        DateTime lastFirewallCheck = DateTime.MinValue;

        Label stateDot, stateText, errorText, addrLocal, addrNet, addrIp, addrDns, macEth, macWifi;
        DateTime lastMacCheck = DateTime.MinValue;
        string macIp;
        Button toggleBtn, openBtn, setupBtn, clientBtn, firewallBtn, backupBtn, restoreBtn;
        bool backupBusy;
        ListView list;
        TextBox logBox;
        CheckBox bootBox, servicesBox;
        NotifyIcon tray;
        ToolStripMenuItem trayToggle;
        System.Windows.Forms.Timer uiTimer, updateTimer;
        Label updateText;
        ProgressBar updateBar;
        Button updateBtn;
        bool updateBusy;
        readonly bool afterUpdate, rolledBack;

        public MainForm(Engine engine, Updater updater, bool autostart, bool afterUpdate, bool rolledBack)
        {
            this.engine = engine;
            this.updater = updater;
            this.afterUpdate = afterUpdate;
            this.rolledBack = rolledBack;
            settings = new Settings(engine.Root);
            startHidden = autostart;

            if (!settings.Exists)
            {
                // First launch: start with Windows and start the system by default.
                try { WindowsStartup.Set(true); } catch { }
                settings.Save();
            }
            try { WindowsStartup.Refresh(); } catch { }

            BuildUi();
            engine.Logged += line =>
            {
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

            this.autostart = autostart;
            Load += (s, e) => Init();
        }

        readonly bool autostart;
        bool initialized;

        void Init()
        {
            if (initialized) return;
            initialized = true;
            RefreshUi();
            RefreshUpdate();
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
        }

        protected override void SetVisibleCore(bool value)
        {
            if (startHidden)
            {
                // Started with Windows: stay in the tray.
                startHidden = false;
                if (!IsHandleCreated) CreateHandle();
                value = false;
                Init();
            }
            base.SetVisibleCore(value);
        }

        void BuildUi()
        {
            Text = "عيادة الأسنان - لوحة التشغيل";
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Font = new Font("Segoe UI", 10f);
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96f, 96f);
            ClientSize = new Size(780, 800);
            MinimumSize = new Size(700, 720);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(248, 250, 252);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, Padding = new Padding(0) };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            Controls.Add(grid);

            // Header
            var header = new FlowLayoutPanel { Dock = DockStyle.Fill, BackColor = Teal, Margin = new Padding(0), Padding = new Padding(14, 6, 14, 6), FlowDirection = FlowDirection.TopDown, WrapContents = false };
            var title = new Label { Text = "عيادة الأسنان", ForeColor = Color.White, Font = new Font("Segoe UI", 18f, FontStyle.Bold), AutoSize = true, Margin = new Padding(0) };
            var sub = new Label { Text = "لوحة تشغيل النسخة المحلية (بدون إنترنت)", ForeColor = Color.FromArgb(204, 251, 241), AutoSize = true, Margin = new Padding(2, 0, 2, 0) };
            header.Controls.Add(title);
            header.Controls.Add(sub);
            AddRow(grid, header, SizeType.Absolute, 72);

            // State and main buttons
            var bar = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoSize = true, Padding = new Padding(12, 10, 12, 4) };
            bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            var statePanel = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false };
            var stateLine = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0) };
            stateDot = new Label { Text = "●", AutoSize = true, Font = new Font("Segoe UI", 20f), Margin = new Padding(0, 0, 0, 0) };
            stateText = new Label { Text = "متوقف", AutoSize = true, Font = new Font("Segoe UI", 15f, FontStyle.Bold), Margin = new Padding(4, 6, 0, 0) };
            stateLine.Controls.Add(stateDot);
            stateLine.Controls.Add(stateText);
            errorText = new Label { AutoSize = true, ForeColor = Red, MaximumSize = new Size(440, 0), Margin = new Padding(4, 0, 0, 0) };
            statePanel.Controls.Add(stateLine);
            statePanel.Controls.Add(errorText);
            bar.Controls.Add(statePanel, 0, 0);

            var buttons = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Anchor = AnchorStyles.Top };
            toggleBtn = MakeButton("تشغيل", Green, 120);
            toggleBtn.Font = new Font("Segoe UI", 11f, FontStyle.Bold);
            toggleBtn.Click += (s, e) => { if (engine.CurrentState == State.Running) StopSystem(); else StartSystem(); };
            openBtn = MakeButton("فتح النظام", Teal, 120);
            openBtn.Click += (s, e) => OpenUrl(engine.LocalUrl);
            buttons.Controls.Add(toggleBtn);
            buttons.Controls.Add(openBtn);
            bar.Controls.Add(buttons, 1, 0);
            AddRow(grid, bar, SizeType.AutoSize, 0);

            // Services
            list = new ListView
            {
                View = View.Details, FullRowSelect = true, HeaderStyle = ColumnHeaderStyle.Nonclickable,
                Dock = DockStyle.Fill, Height = 150, MultiSelect = false, RightToLeftLayout = true,
                Margin = new Padding(12, 6, 12, 6), BorderStyle = BorderStyle.FixedSingle
            };
            list.Columns.Add("الخدمة", 320);
            list.Columns.Add("الحالة", 200);
            list.Columns.Add("المنفذ", 150);
            AddRow(grid, list, SizeType.Absolute, 186);

            // Addresses
            var addr = new GroupBox { Text = "العناوين", Dock = DockStyle.Fill, Margin = new Padding(12, 0, 12, 6), Padding = new Padding(10, 6, 10, 6), AutoSize = true };
            var addrGrid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, AutoSize = true };
            addrGrid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            addrGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            addrGrid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            addrLocal = AddAddress(addrGrid, "على هذا الجهاز:");
            addrNet = AddAddress(addrGrid, "على كل الأجهزة:");
            addrIp = AddAddress(addrGrid, "بالرقم:");
            addrDns = AddAddress(addrGrid, "DNS في راوتر Deco:");
            macEth = AddAddress(addrGrid, "ماك الإيثرنت (MAC):");
            macWifi = AddAddress(addrGrid, "ماك الواي فاي (MAC):");
            addr.Controls.Add(addrGrid);
            AddRow(grid, addr, SizeType.AutoSize, 0);

            // Options and tools
            var tools = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(8, 0, 8, 0) };
            bootBox = new CheckBox { Text = "التشغيل تلقائيًا مع ويندوز", AutoSize = true, Margin = new Padding(6, 8, 12, 4) };
            try { bootBox.Checked = WindowsStartup.IsOn(); } catch { }
            bootBox.CheckedChanged += (s, e) => { try { WindowsStartup.Set(bootBox.Checked); } catch (Exception ex) { AppendLog(ex.Message); } };
            servicesBox = new CheckBox { Text = "بدء النظام عند فتح اللوحة", AutoSize = true, Checked = settings.AutoStartServices, Margin = new Padding(6, 8, 12, 4) };
            servicesBox.CheckedChanged += (s, e) => { settings.AutoStartServices = servicesBox.Checked; settings.Save(); };
            tools.Controls.Add(bootBox);
            tools.Controls.Add(servicesBox);
            AddRow(grid, tools, SizeType.AutoSize, 0);

            var tools2 = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(8, 0, 8, 4) };
            firewallBtn = MakeButton("السماح لأجهزة الشبكة", Gray, 0);
            firewallBtn.Click += (s, e) => SetupFirewall();
            setupBtn = MakeButton("صفحة تجهيز الأجهزة", Gray, 0);
            setupBtn.Click += (s, e) => OpenUrl(engine.LocalUrl.Replace("localhost", "127.0.0.1") + "/setup");
            // The program for the other computers (2026-10-17), served from client\.
            clientBtn = MakeButton("برنامج الحواسيب الأخرى", Gray, 0);
            clientBtn.Click += (s, e) => OpenUrl(engine.LocalUrl.Replace("localhost", "127.0.0.1") + "/client/");
            var cfgBtn = MakeButton("الإعدادات", Gray, 0);
            cfgBtn.Click += (s, e) => OpenSettings();
            var logsBtn = MakeButton("مجلد السجلات", Gray, 0);
            logsBtn.Click += (s, e) => { try { Process.Start("explorer.exe", "\"" + engine.LogDir + "\""); } catch { } };
            var exitBtn = MakeButton("إيقاف وخروج", Gray, 0);
            exitBtn.Click += (s, e) => ExitApp();
            foreach (var b in new[] { firewallBtn, setupBtn, clientBtn, cfgBtn, logsBtn, exitBtn }) tools2.Controls.Add(b);
            AddRow(grid, tools2, SizeType.AutoSize, 0);

            // Backups (2026-10-13): daily and before every update by themselves.
            var tools3 = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, Padding = new Padding(8, 0, 8, 4) };
            var backupCaption = new Label { Text = "النسخ الاحتياطي (يوميًا وقبل كل تحديث):", AutoSize = true, ForeColor = Gray, Margin = new Padding(6, 12, 6, 4) };
            backupBtn = MakeButton("نسخة احتياطية الآن", Teal, 0);
            backupBtn.Click += (s, e) => BackupNow();
            restoreBtn = MakeButton("استعادة نسخة", Gray, 0);
            restoreBtn.Click += (s, e) => RestoreBackup();
            var backupDirBtn = MakeButton("مجلد النسخ", Gray, 0);
            backupDirBtn.Click += (s, e) =>
            {
                try { Directory.CreateDirectory(engine.BackupDir); Process.Start("explorer.exe", "\"" + engine.BackupDir + "\""); }
                catch (Exception ex) { AppendLog(ex.Message); }
            };
            tools3.Controls.Add(backupCaption);
            foreach (var b in new[] { backupBtn, restoreBtn, backupDirBtn }) tools3.Controls.Add(b);
            AddRow(grid, tools3, SizeType.AutoSize, 0);

            // Updates (2026-10-14): downloaded in the background, applied on request.
            var upd = new GroupBox { Text = "التحديثات", Dock = DockStyle.Fill, Margin = new Padding(12, 0, 12, 6), Padding = new Padding(10, 4, 10, 6), AutoSize = true };
            var updGrid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, AutoSize = true };
            updGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            updGrid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            updateText = new Label { Text = "النسخة الحالية " + updater.CurrentBuild, AutoSize = true, Margin = new Padding(3, 6, 3, 2), MaximumSize = new Size(520, 0) };
            updateBar = new ProgressBar { Dock = DockStyle.Fill, Height = 14, Minimum = 0, Maximum = 1000, Margin = new Padding(3, 2, 3, 4), Visible = false, RightToLeftLayout = true };
            updateBtn = MakeButton("تحقق الآن", Gray, 0);
            updateBtn.Click += (s, e) => UpdateAction();
            updGrid.Controls.Add(updateText, 0, 0);
            updGrid.Controls.Add(updateBtn, 1, 0);
            updGrid.Controls.Add(updateBar, 0, 1);
            updGrid.SetColumnSpan(updateBar, 2);
            upd.Controls.Add(updGrid);
            AddRow(grid, upd, SizeType.AutoSize, 0);

            // Event log
            logBox = new TextBox
            {
                Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
                BackColor = Color.White, Font = new Font("Segoe UI", 9f), Margin = new Padding(12, 4, 12, 12),
                RightToLeft = RightToLeft.Yes
            };
            AddRow(grid, logBox, SizeType.Percent, 100);

            // Tray
            var menu = new ContextMenuStrip { RightToLeft = RightToLeft.Yes };
            menu.Items.Add("فتح اللوحة", null, (s, e) => ShowPanel());
            menu.Items.Add("فتح النظام", null, (s, e) => OpenUrl(engine.LocalUrl));
            trayToggle = new ToolStripMenuItem("تشغيل", null, (s, e) => { if (engine.CurrentState == State.Running) StopSystem(); else StartSystem(); });
            menu.Items.Add(trayToggle);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("إيقاف وخروج", null, (s, e) => ExitApp());
            tray = new NotifyIcon { Icon = Icon ?? SystemIcons.Application, Text = "عيادة الأسنان", Visible = true, ContextMenuStrip = menu };
            tray.DoubleClick += (s, e) => ShowPanel();
        }

        static void AddRow(TableLayoutPanel grid, Control c, SizeType type, float size)
        {
            grid.RowStyles.Add(type == SizeType.AutoSize ? new RowStyle(SizeType.AutoSize) : new RowStyle(type, size));
            grid.Controls.Add(c, 0, grid.RowCount);
            grid.RowCount++;
        }

        Label AddAddress(TableLayoutPanel g, string caption)
        {
            var cap = new Label { Text = caption, AutoSize = true, ForeColor = Gray, Margin = new Padding(3, 4, 8, 4) };
            var val = new Label { Text = "-", AutoSize = true, Margin = new Padding(3, 4, 3, 4), RightToLeft = RightToLeft.No, Font = new Font("Segoe UI", 10f, FontStyle.Bold) };
            int row = g.RowCount;
            g.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            g.Controls.Add(cap, 0, row);
            g.Controls.Add(val, 1, row);
            var copy = new Button
            {
                Text = "نسخ", FlatStyle = FlatStyle.Flat, AutoSize = true, Height = 26, Margin = new Padding(3, 1, 3, 1),
                Padding = new Padding(6, 0, 6, 0), Cursor = Cursors.Hand, Font = new Font("Segoe UI", 8.5f), ForeColor = Teal
            };
            copy.FlatAppearance.BorderColor = Color.FromArgb(203, 213, 225);
            copy.Click += (s, e) => CopyText(val.Text, copy);
            g.Controls.Add(copy, 2, row);
            g.RowCount++;
            return val;
        }

        void CopyText(string text, Button btn)
        {
            if (text.Length == 0 || text == "-") return;
            try { Clipboard.SetText(text); }
            catch (Exception ex) { AppendLog("تعذّر النسخ: " + ex.Message); return; }
            btn.Text = "تم ✓";
            var t = new System.Windows.Forms.Timer { Interval = 1500 };
            t.Tick += (s, e) => { t.Dispose(); btn.Text = "نسخ"; };
            t.Start();
        }

        static Button MakeButton(string text, Color color, int width)
        {
            var b = new Button
            {
                Text = text, FlatStyle = FlatStyle.Flat, BackColor = color, ForeColor = Color.White,
                AutoSize = width == 0, Height = 36, Margin = new Padding(4), Cursor = Cursors.Hand,
                Padding = new Padding(8, 0, 8, 0)
            };
            if (width > 0) b.Width = width;
            b.FlatAppearance.BorderSize = 0;
            return b;
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

        void BackupNow()
        {
            if (backupBusy || engine.CurrentState != State.Running) return;
            backupBusy = true;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                string msg;
                bool ok = engine.BackupNow(out msg);
                backupBusy = false;
                try { BeginInvoke(new Action(() => Notify(msg, ok))); } catch { }
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
                ClientSize = new Size(520, 560),
                Font = Font,
            })
            {
                var title = new Label { Text = "النسخة: " + fileName, Dock = DockStyle.Top, Height = 28, Padding = new Padding(8, 8, 8, 0) };
                var mergeRb = new RadioButton { Text = "إضافة البيانات غير الموجودة فقط (لا يُحذف أو يتغيّر شيء من البيانات الحالية)", Checked = true, Dock = DockStyle.Top, Height = 44, Padding = new Padding(8, 0, 8, 0) };
                var replaceRb = new RadioButton { Text = "استبدال كل البيانات الحالية بالنسخة", Dock = DockStyle.Top, Height = 30, Padding = new Padding(8, 0, 8, 0) };
                var hint = new Label { Text = "اختر الأقسام التي تؤخذ من النسخة:", Dock = DockStyle.Top, Height = 24, Padding = new Padding(8, 4, 8, 0) };
                var list = new CheckedListBox { Dock = DockStyle.Fill, CheckOnClick = true, IntegralHeight = false, RightToLeft = RightToLeft.Yes };
                foreach (var sct in sections)
                    list.Items.Add((sct.Label ?? sct.Table) + (sct.Label != sct.Table ? "  (" + sct.Table + ")" : "") + (sct.Rows ? "" : "  — فارغ"), sct.Rows);

                var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(8) };
                var ok = new Button { Text = "استعادة", DialogResult = DialogResult.OK, Width = 100, Height = 30 };
                var cancel = new Button { Text = "إلغاء", DialogResult = DialogResult.Cancel, Width = 90, Height = 30 };
                var all = new Button { Text = "تحديد الكل", Width = 100, Height = 30 };
                var none = new Button { Text = "إلغاء التحديد", Width = 100, Height = 30 };
                all.Click += (s, e) => { for (int i = 0; i < list.Items.Count; i++) list.SetItemChecked(i, true); };
                none.Click += (s, e) => { for (int i = 0; i < list.Items.Count; i++) list.SetItemChecked(i, false); };
                EventHandler sync = (s, e) => { list.Enabled = all.Enabled = none.Enabled = hint.Enabled = mergeRb.Checked; };
                mergeRb.CheckedChanged += sync;
                replaceRb.CheckedChanged += sync;
                buttons.Controls.AddRange(new Control[] { ok, cancel, all, none });

                // Docked in reverse: the last added sits on top.
                dlg.Controls.Add(list);
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

        void RefreshUpdate()
        {
            var st = updater.State;
            var info = updater.Available;
            string text, btn = null;
            Color btnColor = Gray;
            int progress = -1;
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
                    btnColor = Green;
                    break;
                case UpdateState.Applying:
                    text = "جارٍ التحديث، لا تطفئ الحاسوب...";
                    break;
                case UpdateState.Error:
                    text = "تعذّر التحقق من التحديثات أو تنزيلها: " + updater.Error + " (يُعاد تلقائيًا)";
                    btn = "إعادة المحاولة";
                    break;
                case UpdateState.UpToDate:
                    text = "النسخة الحالية " + updater.CurrentBuild + "، لا يوجد تحديث.";
                    btn = "تحقق الآن";
                    break;
                default:
                    text = "النسخة الحالية " + updater.CurrentBuild + ".";
                    btn = "تحقق الآن";
                    break;
            }
            if (st != UpdateState.Ready && st != UpdateState.Applying && updater.FailedBuild > 0 && updater.FailedBuild >= updater.CurrentBuild)
                text += Environment.NewLine + "آخر تحديث (النسخة " + updater.FailedBuild + ") لم يعمل فرجع النظام للنسخة السابقة.";
            if (updateText.Text != text) updateText.Text = text;
            updateText.ForeColor = st == UpdateState.Error ? Red : (st == UpdateState.Ready ? Green : Color.Black);

            bool marquee = st == UpdateState.Applying || st == UpdateState.Checking;
            updateBar.Visible = marquee || progress >= 0;
            updateBar.Style = marquee ? ProgressBarStyle.Marquee : ProgressBarStyle.Continuous;
            if (!marquee && progress >= 0 && updateBar.Value != progress) updateBar.Value = progress;

            updateBtn.Visible = btn != null && !updateBusy;
            if (btn != null && updateBtn.Text != btn) updateBtn.Text = btn;
            updateBtn.BackColor = btnColor;
        }

        void UpdateAction()
        {
            switch (updater.State)
            {
                case UpdateState.Downloading: updater.Pause(); break;
                case UpdateState.Ready: ApplyUpdate(); break;
                case UpdateState.Applying: case UpdateState.Checking: break;
                default: updater.CheckNow(); break;
            }
            RefreshUpdate();
        }

        void ApplyUpdate()
        {
            if (updateBusy || updater.Available == null) return;
            var r = MessageBox.Show(this,
                "سيُحدَّث النظام إلى النسخة " + updater.Available.Build + "." + Environment.NewLine +
                "تُحفظ نسخة احتياطية من البيانات أولًا، ثم يتوقف النظام على كل الأجهزة دقيقة أو اثنتين ويعود وحده." + Environment.NewLine +
                "إذا لم تعمل النسخة الجديدة يرجع النظام تلقائيًا للنسخة السابقة وبياناتها." + Environment.NewLine + Environment.NewLine +
                "هل تريد التحديث الآن؟",
                "عيادة الأسنان", MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2,
                MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
            if (r != DialogResult.Yes) return;
            updateBusy = true;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                try
                {
                    updater.Apply(false);
                    // The new version is starting; this one steps aside.
                    try { BeginInvoke(new Action(() => { exiting = true; tray.Visible = false; Application.Exit(); })); } catch { }
                }
                catch (Exception ex)
                {
                    updateBusy = false;
                    string msg = "لم يتم التحديث، والنظام على النسخة الحالية دون تغيير: " + ex.Message;
                    engine.Log(msg);
                    if (engine.CurrentState != State.Running) StartAgain();
                    try { BeginInvoke(new Action(() => Notify(msg, false))); } catch { }
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

        void RefreshUi()
        {
            var st = engine.CurrentState;
            Color c; string text;
            switch (st)
            {
                case State.Running: c = Green; text = "النظام يعمل"; break;
                case State.Starting: c = Amber; text = "جارٍ التشغيل..."; break;
                case State.Stopping: c = Amber; text = "جارٍ الإيقاف..."; break;
                case State.Error: c = Red; text = "تعذّر التشغيل"; break;
                default: c = Gray; text = "النظام متوقف"; break;
            }
            stateDot.ForeColor = c;
            stateText.Text = text;
            stateText.ForeColor = c;
            errorText.Text = st == State.Error ? engine.LastError : "";
            errorText.Visible = errorText.Text.Length > 0;

            bool busy = st == State.Starting || st == State.Stopping;
            toggleBtn.Enabled = !busy;
            toggleBtn.Text = st == State.Running ? "إيقاف" : (busy ? "انتظر..." : "تشغيل");
            toggleBtn.BackColor = st == State.Running ? Red : (busy ? Gray : Green);
            openBtn.Enabled = st == State.Running;
            setupBtn.Enabled = st == State.Running;
            clientBtn.Enabled = st == State.Running;
            openBtn.BackColor = openBtn.Enabled ? Teal : Color.FromArgb(156, 163, 175);
            backupBtn.Enabled = restoreBtn.Enabled = st == State.Running && !backupBusy;
            backupBtn.Text = backupBusy ? "انتظر..." : "نسخة احتياطية الآن";
            backupBtn.BackColor = backupBtn.Enabled ? Teal : Color.FromArgb(156, 163, 175);
            trayToggle.Text = st == State.Running ? "إيقاف النظام" : "تشغيل النظام";
            trayToggle.Enabled = !busy;
            tray.Text = st == State.Running ? "عيادة الأسنان - يعمل" : "عيادة الأسنان - " + text;

            if ((DateTime.Now - lastFirewallCheck).TotalSeconds > 60) CheckFirewallAsync();
            firewallBtn.Text = firewallOk ? "الجدار الناري: مسموح ✓" : "السماح لأجهزة الشبكة (مطلوب مرة واحدة)";
            firewallBtn.BackColor = firewallOk ? Gray : Amber;

            bool hasIp = engine.LanIp.Length > 0;
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

            var services = engine.Services;
            list.BeginUpdate();
            while (list.Items.Count < services.Count) list.Items.Add(new ListViewItem(new[] { "", "", "" }) { UseItemStyleForSubItems = true });
            while (list.Items.Count > services.Count) list.Items.RemoveAt(list.Items.Count - 1);
            for (int i = 0; i < services.Count; i++)
            {
                var s = services[i];
                int alive = s.Alive;
                string status; Color color;
                if (s.Failed) { status = "خطأ - راجع السجلات"; color = Red; }
                else if (s.Count == 0) { status = "معطّل من الإعدادات"; color = Gray; }
                else if (alive == s.Count) { status = s.Count > 1 ? "يعمل (" + alive + ")" : "يعمل"; color = Green; }
                else if (alive > 0) { status = "يعمل جزئيًا (" + alive + " من " + s.Count + ")"; color = Amber; }
                else if (st == State.Starting) { status = "بانتظار التشغيل"; color = Amber; }
                else if (st == State.Running && s.Key == "dns" && engine.DnsBusy) { status = "المنفذ 53 مشغول"; color = Amber; }
                else { status = "متوقف"; color = Gray; }
                var item = list.Items[i];
                if (item.SubItems[0].Text != "● " + s.Name) item.SubItems[0].Text = "● " + s.Name;
                if (item.SubItems[1].Text != status) item.SubItems[1].Text = status;
                if (item.SubItems[2].Text != s.Port) item.SubItems[2].Text = s.Port;
                if (item.ForeColor != color) item.ForeColor = color;
            }
            list.EndUpdate();
        }

        void OpenSettings()
        {
            using (var dlg = new SettingsForm(engine.ReadConfig(), engine.Root))
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                try { engine.WriteConfig(dlg.Values); }
                catch (Exception ex)
                {
                    MessageBox.Show(this, "تعذّر حفظ الإعدادات: " + ex.Message, "عيادة الأسنان", MessageBoxButtons.OK, MessageBoxIcon.Error,
                        MessageBoxDefaultButton.Button1, MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
                    return;
                }
                CheckFirewallAsync();
                if (engine.CurrentState == State.Running)
                {
                    var r = MessageBox.Show(this, "حُفظت الإعدادات. تُطبَّق بعد إعادة تشغيل النظام (يتوقف لحظات على كل الأجهزة). إعادة التشغيل الآن؟",
                        "عيادة الأسنان", MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button1,
                        MessageBoxOptions.RightAlign | MessageBoxOptions.RtlReading);
                    if (r == DialogResult.Yes) ThreadPool.QueueUserWorkItem(_ => engine.Restart());
                }
                RefreshUi();
            }
        }

        void ShowPanel()
        {
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
                engine.Stop();
                try { BeginInvoke(new Action(() => { tray.Visible = false; Application.Exit(); })); } catch { }
            });
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing && !exiting)
            {
                // The close button only hides the panel; the system keeps running.
                e.Cancel = true;
                Hide();
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
                engine.Stop();
            }
            tray.Visible = false;
            base.OnFormClosing(e);
        }
    }

    // Edits config.txt through a form instead of a text editor.
    class SettingsForm : Form
    {
        const string AutoIp = "تلقائي";
        public Dictionary<string, string> Values = new Dictionary<string, string>();

        readonly TextBox nameBox;
        readonly ComboBox ipBox;
        readonly NumericUpDown httpBox, httpsBox, workersBox;
        readonly CheckBox autoOpenBox, dnsBox;
        readonly TextBox backupBox;
        readonly string root;
        readonly Label error;

        public SettingsForm(Dictionary<string, string> cfg, string root)
        {
            this.root = root;
            Text = "الإعدادات";
            RightToLeft = RightToLeft.Yes;
            RightToLeftLayout = true;
            Font = new Font("Segoe UI", 10f);
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96f, 96f);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterParent;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            BackColor = Color.FromArgb(248, 250, 252);

            var grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Padding = new Padding(16, 12, 16, 8), Dock = DockStyle.Fill };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 320));
            Controls.Add(grid);

            nameBox = new TextBox { Width = 300, RightToLeft = RightToLeft.No, Text = Value(cfg, "SERVER_NAME", "clinic.lan") };
            AddField(grid, "اسم النظام على الشبكة", nameBox, "الاسم الذي تفتح به الأجهزة النظام. الافتراضي clinic.lan");

            ipBox = new ComboBox { Width = 300, RightToLeft = RightToLeft.No, DropDownStyle = ComboBoxStyle.DropDown };
            ipBox.Items.Add(AutoIp);
            foreach (var ip in Engine.LocalAddresses()) ipBox.Items.Add(ip);
            string savedIp = Value(cfg, "SERVER_IP", "");
            ipBox.Text = savedIp.Length == 0 ? AutoIp : savedIp;
            AddField(grid, "عنوان هذا الجهاز", ipBox, "اتركه «تلقائي» إلا إذا ثبّتّ للجهاز عنوانًا في راوتر Deco.");

            httpBox = Number(1, 65535, IntValue(cfg, "HTTP_PORT", 80));
            AddField(grid, "منفذ HTTP", httpBox, "80 افتراضيًا. غيّره فقط إذا كان برنامج آخر (مثل XAMPP) يستخدمه.");

            httpsBox = Number(1, 65535, IntValue(cfg, "HTTPS_PORT", 443));
            AddField(grid, "منفذ HTTPS", httpsBox, "443 افتراضيًا.");

            workersBox = Number(2, 64, IntValue(cfg, "PHP_WORKERS", 16));
            AddField(grid, "عدد الطلبات المتزامنة", workersBox, "16 مناسب لأغلب العيادات، و24 أو 32 مع ذاكرة 16 غيغابايت.");

            dnsBox = new CheckBox { Text = "تشغيل خادم الأسماء (DNS)", AutoSize = true, Checked = Value(cfg, "DNS", "1") != "0" };
            AddField(grid, "", dnsBox, "اختياري. بدونه تدخل الأجهزة بعنوان IP هذا الجهاز، وهو الأسرع والأثبت. يلزم فقط لاسم " + Value(cfg, "SERVER_NAME", "clinic.lan") + " وللفتح التلقائي.");

            autoOpenBox = new CheckBox { Text = "فتح النظام تلقائيًا عند الاتصال بالواي فاي", AutoSize = true, Checked = Value(cfg, "AUTO_OPEN", "1") != "0" };
            AddField(grid, "", autoOpenBox, "يحتاج أن يكون هذا الجهاز خادم DNS في راوتر Deco، ومنفذ HTTP هو 80.");

            var backupRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0) };
            backupBox = new TextBox { Width = 220, RightToLeft = RightToLeft.No, Text = Value(cfg, "BACKUP_DIR", "") };
            if (backupBox.Text.Length == 0) backupBox.Text = Engine.DefaultBackupDir(root);
            var browse = Btn("اختيار...", Color.FromArgb(107, 114, 128));
            browse.Click += (s, e) =>
            {
                using (var dlg = new FolderBrowserDialog { Description = "مجلد النسخ الاحتياطية", SelectedPath = backupBox.Text })
                    if (dlg.ShowDialog(this) == DialogResult.OK) backupBox.Text = dlg.SelectedPath;
            };
            backupRow.Controls.Add(backupBox);
            backupRow.Controls.Add(browse);
            AddField(grid, "مجلد النسخ الاحتياطية", backupRow, "خارج مجلد البرنامج حتى لا يُحذف معه. يمكن اختيار قرص آخر أو فلاشة تبقى موصولة.");

            error = new Label { AutoSize = true, ForeColor = Color.FromArgb(220, 38, 38), MaximumSize = new Size(560, 0), Margin = new Padding(3, 6, 3, 0) };
            grid.Controls.Add(error, 0, grid.RowCount);
            grid.SetColumnSpan(error, 2);
            grid.RowCount++;

            var buttons = new FlowLayoutPanel { AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 10, 0, 4) };
            var save = Btn("حفظ", Color.FromArgb(15, 118, 110));
            var cancel = Btn("إلغاء", Color.FromArgb(107, 114, 128));
            var defaults = Btn("القيم الافتراضية", Color.FromArgb(107, 114, 128));
            save.Click += (s, e) => Save();
            cancel.Click += (s, e) => { DialogResult = DialogResult.Cancel; };
            defaults.Click += (s, e) =>
            {
                nameBox.Text = "clinic.lan"; ipBox.Text = AutoIp; httpBox.Value = 80; httpsBox.Value = 443;
                workersBox.Value = 16; dnsBox.Checked = true; autoOpenBox.Checked = true; backupBox.Text = Engine.DefaultBackupDir(root);
            };
            buttons.Controls.Add(save);
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(defaults);
            grid.Controls.Add(buttons, 0, grid.RowCount);
            grid.SetColumnSpan(buttons, 2);
            grid.RowCount++;

            AcceptButton = save;
            CancelButton = cancel;
        }

        static string Value(Dictionary<string, string> cfg, string key, string def)
        {
            string v;
            return cfg.TryGetValue(key, out v) ? v : def;
        }

        static int IntValue(Dictionary<string, string> cfg, string key, int def)
        {
            int v;
            return int.TryParse(Value(cfg, key, ""), out v) ? v : def;
        }

        static NumericUpDown Number(int min, int max, int value)
        {
            return new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Max(min, Math.Min(max, value)), Width = 120, RightToLeft = RightToLeft.No };
        }

        static Button Btn(string text, Color color)
        {
            var b = new Button { Text = text, FlatStyle = FlatStyle.Flat, BackColor = color, ForeColor = Color.White, AutoSize = true, Height = 34, Margin = new Padding(4), Padding = new Padding(10, 0, 10, 0), Cursor = Cursors.Hand };
            b.FlatAppearance.BorderSize = 0;
            return b;
        }

        static void AddField(TableLayoutPanel grid, string caption, Control input, string hint)
        {
            int row = grid.RowCount;
            grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            grid.Controls.Add(new Label { Text = caption, AutoSize = true, Margin = new Padding(3, 12, 12, 0), Font = new Font("Segoe UI", 10f, FontStyle.Bold) }, 0, row);
            var cell = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, Margin = new Padding(0, 8, 0, 0) };
            cell.Controls.Add(input);
            cell.Controls.Add(new Label { Text = hint, AutoSize = true, MaximumSize = new Size(310, 0), ForeColor = Color.FromArgb(107, 114, 128), Font = new Font("Segoe UI", 8.5f) });
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
            if (http == Engine.DbPort || https == Engine.DbPort || http == 53 || https == 53 || (http >= 9100 && http < 9200) || (https >= 9100 && https < 9200))
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
            };
            DialogResult = DialogResult.OK;
        }
    }
}
