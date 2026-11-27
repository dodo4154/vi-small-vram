# Sets the volume (0.0 - 1.0) of the audio session of a process, by name.
# Usage: powershell -ExecutionPolicy Bypass -File set-game-volume.ps1 -Process victory -Volume 0.2
param(
    [string]$Process = "victory",
    [double]$Volume = 0.2
)

$code = @'
using System;
using System.Runtime.InteropServices;

namespace AudioCtl
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumeratorComObject { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    public interface IMMDeviceEnumerator
    {
        int NotImpl1();
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    public interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")]
    public interface IAudioSessionManager2
    {
        int NotImpl1();
        int NotImpl2();
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")]
    public interface IAudioSessionEnumerator
    {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl session);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")]
    public interface IAudioSessionControl
    {
        int GetState(out int state);
        int GetDisplayName(out IntPtr name);
        int SetDisplayName(string name, ref Guid eventContext);
        int GetIconPath(out IntPtr path);
        int SetIconPath(string path, ref Guid eventContext);
        int GetGroupingParam(out Guid groupingParam);
        int SetGroupingParam(ref Guid groupingParam, ref Guid eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D")]
    public interface IAudioSessionControl2
    {
        int NotImpl1();
        int NotImpl2();
        int NotImpl3();
        int NotImpl4();
        int NotImpl5();
        int NotImpl6();
        int NotImpl7();
        int NotImpl8();
        int NotImpl9();
        int NotImpl10();
        int NotImpl11();
        int GetProcessId(out int pid);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8")]
    public interface ISimpleAudioVolume
    {
        int SetMasterVolume(float level, ref Guid eventContext);
        int GetMasterVolume(out float level);
    }

    public static class Api
    {
        public static int SetProcessVolume(int pid, float level)
        {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice device;
            enumerator.GetDefaultAudioEndpoint(0 /*eRender*/, 1 /*eMultimedia*/, out device);
            Guid iid = typeof(IAudioSessionManager2).GUID;
            object obj;
            device.Activate(ref iid, 23 /*CLSCTX_ALL*/, IntPtr.Zero, out obj);
            var manager = (IAudioSessionManager2)obj;
            IAudioSessionEnumerator sessions;
            manager.GetSessionEnumerator(out sessions);
            int count;
            sessions.GetCount(out count);
            int changed = 0;
            for (int i = 0; i < count; i++)
            {
                IAudioSessionControl control;
                sessions.GetSession(i, out control);
                var control2 = control as IAudioSessionControl2;
                if (control2 == null) continue;
                int spid;
                control2.GetProcessId(out spid);
                if (spid != pid) continue;
                var volume = control as ISimpleAudioVolume;
                if (volume == null) continue;
                Guid ctx = Guid.Empty;
                if (volume.SetMasterVolume(level, ref ctx) >= 0) changed++;
            }
            return changed;
        }
    }
}
'@

Add-Type -TypeDefinition $code -Language CSharp | Out-Null

$targets = Get-Process -Name $Process -ErrorAction SilentlyContinue
if (-not $targets) { Write-Output "no process named $Process"; exit 1 }
$total = 0
foreach ($p in $targets) {
    $n = [AudioCtl.Api]::SetProcessVolume($p.Id, [float]$Volume)
    $total += $n
}
Write-Output ("sessions set to {0:P0}: {1}" -f $Volume, $total)
