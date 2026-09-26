using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

internal static class DshLauncher {
    static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
    static string Protect(string value) {
        value = Regex.Replace(value, @"(?i)([?&]token=)[^\s&""<>]+", "$1[REDACTED]");
        value = Regex.Replace(value, @"(?i)((?:api[_-]?key|authorization|password|secret|access[_-]?token|refresh[_-]?token)\s*[=:]\s*[""']?)[^\s,""'}]+", "$1[REDACTED]");
        return Regex.Replace(value, @"\bsk-[A-Za-z0-9_-]{12,}", "[REDACTED]");
    }
    static void Log(string message) {
        using (var mutex = new Mutex(false, @"Local\DSH-Windowless-Launcher-Log")) {
            bool owned = false;
            try {
                try { owned = mutex.WaitOne(10000); } catch (AbandonedMutexException) { owned = true; }
                if (!owned) return;
                string path = Path.Combine(Root, "logs", "launcher.log");
                if (File.Exists(path) && new FileInfo(path).Length >= 10485760) {
                    for (int i = 5; i >= 1; --i) {
                        string source = i == 1 ? path : path + "." + (i - 1);
                        string target = path + "." + i;
                        if (File.Exists(source)) { if (File.Exists(target)) File.Delete(target); File.Move(source, target); }
                    }
                }
                File.AppendAllText(path, DateTimeOffset.Now.ToString("o") + " " + Protect(message) + Environment.NewLine, new UTF8Encoding(false));
            } finally { if (owned) mutex.ReleaseMutex(); }
        }
    }
    [STAThread]
    static int Main(string[] args) {
        try {
            string action = args.Length == 0 ? "start" : args[0];
            if (args.Length > 1 || (action != "host" && action != "start" && action != "stop" && action != "restart"))
                throw new ArgumentException("Allowed actions: host, start, stop, restart");
            string script = Path.Combine(Root, action == "host" ? "DSH-Host.ps1" : "DSH-Manager.ps1");
            var info = new ProcessStartInfo {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\"" + (action == "host" ? "" : " " + action),
                WorkingDirectory = Path.GetDirectoryName(Root.TrimEnd(Path.DirectorySeparatorChar)),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var process = new Process { StartInfo = info }) {
                process.OutputDataReceived += (sender, e) => { if (e.Data != null) { try { Log(action + " stdout: " + e.Data); } catch {} } };
                process.ErrorDataReceived += (sender, e) => { if (e.Data != null) { try { Log(action + " stderr: " + e.Data); } catch {} } };
                if (!process.Start()) throw new InvalidOperationException("Process creation failed");
                process.StandardInput.Close();
                Log("action=" + action + " childPID=" + process.Id + " CreateNoWindow=True UseShellExecute=False");
                process.BeginOutputReadLine(); process.BeginErrorReadLine();
                process.WaitForExit();
                Log("action=" + action + " exit=" + process.ExitCode);
                return process.ExitCode;
            }
        } catch (Exception error) {
            try { Log(error.ToString()); } catch {}
            return 1;
        }
    }
}
