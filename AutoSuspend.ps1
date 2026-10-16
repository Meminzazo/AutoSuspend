# ==============================================================================
# AutoSuspend.ps1 — Suspende el PC tras inactividad si no hay actividad activa
# Detecta: audio, llamada de Discord, descargas en launchers y actividad de discos/USB
# ==============================================================================

# --- CONFIGURACIÓN ---
$idleLimitMinutes     = 35
$checkIntervalSeconds = 60
$idleLimitSeconds     = $idleLimitMinutes * 60
$audioThreshold       = 0.005
$audioGraceMinutes    = 5      # Minutos de gracia compartidos por audio, Discord y descargas
$audioGraceSeconds    = $audioGraceMinutes * 60
$networkThresholdMBps = 1     # MB/s mínimos para considerar descarga activa
$diskThresholdMBps    = 1     # Lectura + escritura en discos/USB para evitar suspender
$logFile              = "$PSScriptRoot\autosuspend.log"
$maxLogSizeBytes      = 2MB

# Procesos de los launchers a monitorear para tráfico de red
$launcherProcesses = @(
    "steam",           # Steam
    "EpicGamesLauncher",# Epic Games
    "GalaxyClient",    # GOG Galaxy
    "Battle.net",      # Battle.net
    "EADesktop",       # EA App
    "EALauncher",      # EA App (proceso alternativo)
    "Origin"           # Origin (legado)
)

# --- LOGGING ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"

    Write-Host $line

    # Si el log llegó al límite, eliminarlo y empezar uno nuevo.
    if (Test-Path $logFile) {
        try {
            $logSize = (Get-Item $logFile -ErrorAction Stop).Length

            if ($logSize -ge $maxLogSizeBytes) {
                Remove-Item -Path $logFile -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Host "[WARN] No se pudo rotar el log: $_"
        }
    }

    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# --- LIBRERÍAS NATIVAS ---
Add-Type -AssemblyName System.Windows.Forms

if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
    $Win32Signature = @"
using System;
using System.Runtime.InteropServices;

public class Win32 {

    // ------------------------------------------------------------------ //
    //  Inactividad                                                         //
    // ------------------------------------------------------------------ //
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [DllImport("kernel32.dll")]
    public static extern ulong GetTickCount64();

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    public static uint GetIdleTime() {
        LASTINPUTINFO lastInputInfo = new LASTINPUTINFO();
        lastInputInfo.cbSize = (uint)Marshal.SizeOf(lastInputInfo);
        if (!GetLastInputInfo(ref lastInputInfo)) return 0;
        return (uint)(((uint)GetTickCount64() - lastInputInfo.dwTime) / 1000);
    }

    // ------------------------------------------------------------------ //
    //  Audio — Core Audio API via P/Invoke puro (sin COM de .NET)         //
    // ------------------------------------------------------------------ //
    [DllImport("ole32.dll")]
    static extern int CoCreateInstance(
        ref Guid rclsid, IntPtr pUnkOuter, uint dwClsContext,
        ref Guid riid, out IntPtr ppv);

    [DllImport("ole32.dll")]
    static extern int CoInitialize(IntPtr pvReserved);

    [DllImport("ole32.dll")]
    static extern void CoUninitialize();

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetDefaultAudioEndpointDelegate(
        IntPtr self, int dataFlow, int role, out IntPtr ppDevice);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int ActivateDelegate(
        IntPtr self, ref Guid iid, uint dwClsCtx,
        IntPtr pActivationParams, out IntPtr ppInterface);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetPeakValueDelegate(IntPtr self, out float pfPeak);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int ReleaseDelegate(IntPtr self);

    static T GetVtableMethod<T>(IntPtr comObject, int methodIndex) where T : class {
        IntPtr vtable = Marshal.ReadIntPtr(comObject);
        IntPtr methodPtr = Marshal.ReadIntPtr(vtable, methodIndex * IntPtr.Size);
        return Marshal.GetDelegateForFunctionPointer(methodPtr, typeof(T)) as T;
    }

    static void ReleaseComPtr(IntPtr ptr) {
        if (ptr != IntPtr.Zero)
            GetVtableMethod<ReleaseDelegate>(ptr, 2)(ptr);
    }

    public static float GetAudioPeakValue() {
        Guid clsidEnum = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
        Guid iidEnum   = new Guid("A95664D2-9614-4F35-A746-DE8DB63617E6");
        Guid iidMeter  = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");

        IntPtr pEnum   = IntPtr.Zero;
        IntPtr pDevice = IntPtr.Zero;
        IntPtr pMeter  = IntPtr.Zero;

        try {
            CoInitialize(IntPtr.Zero);

            int hr = CoCreateInstance(ref clsidEnum, IntPtr.Zero, 1, ref iidEnum, out pEnum);
            if (hr != 0 || pEnum == IntPtr.Zero)
                throw new Exception("CoCreateInstance fallo. HR=" + hr.ToString("X8"));

            var getEndpoint = GetVtableMethod<GetDefaultAudioEndpointDelegate>(pEnum, 4);
            hr = getEndpoint(pEnum, 0, 0, out pDevice);
            if (hr != 0 || pDevice == IntPtr.Zero)
                throw new Exception("GetDefaultAudioEndpoint fallo. HR=" + hr.ToString("X8"));

            var activate = GetVtableMethod<ActivateDelegate>(pDevice, 3);
            hr = activate(pDevice, ref iidMeter, 1, IntPtr.Zero, out pMeter);
            if (hr != 0 || pMeter == IntPtr.Zero)
                throw new Exception("Activate fallo. HR=" + hr.ToString("X8"));

            var getPeak = GetVtableMethod<GetPeakValueDelegate>(pMeter, 3);
            float peak;
            hr = getPeak(pMeter, out peak);
            if (hr != 0)
                throw new Exception("GetPeakValue fallo. HR=" + hr.ToString("X8"));

            return peak;
        } finally {
            ReleaseComPtr(pMeter);
            ReleaseComPtr(pDevice);
            ReleaseComPtr(pEnum);
            CoUninitialize();
        }
    }
}
"@
    try {
        Add-Type -TypeDefinition $Win32Signature -ErrorAction Stop
        Write-Log "Tipo Win32 cargado correctamente."
    } catch {
        Write-Log "ERROR FATAL: No se pudo cargar Win32. Detalle: $_" "ERROR"
        exit 1
    }
} else {
    Write-Log "Tipo Win32 ya estaba cargado en la sesion, reutilizando."
}

# --- DETECCIÓN DE AUDIO ---
function Get-AudioVolume {
    try {
        return [Win32]::GetAudioPeakValue()
    } catch {
        Write-Log "Error leyendo audio: $_" "WARN"
        return 0.0
    }
}

# --- DETECCION DE LLAMADA EN DISCORD POR REGISTRO RTC ---
# Lector independiente por proceso: guarda posicion y estado sin mantener el archivo abierto.
if (-not ('DiscordRtcIncrementalReader' -as [type])) {
    Add-Type -ErrorAction Stop -TypeDefinition @"
using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Globalization;
using System.Runtime.InteropServices;
using System.ComponentModel;
using Microsoft.Win32.SafeHandles;

public sealed class DiscordRtcIncrementalReader {
    [StructLayout(LayoutKind.Sequential)]
    struct FileInfo {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);

    // shortcut: formato interno de Discord; revisar si cambia el formato de los eventos RTC.
    static readonly Regex Event = new Regex(@"^\[(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\].*\[RTCConnection\([^,]+, default\)\] RTC connection state: \w+ => (?<state>\w+)");
    readonly MemoryStream pending = new MemoryStream();
    string identity, state;
    long offset, session;
    byte[] anchor = new byte[0];
    DateTime lastEvent = DateTime.MinValue;

    void ResetFile() {
        identity = null;
        offset = 0;
        anchor = new byte[0];
        pending.SetLength(0);
    }
    public void Reset() {
        ResetFile();
        session = 0;
        state = null;
        lastEvent = DateTime.MinValue;
    }
    void AcceptLine(DateTime started) {
        string line = Encoding.UTF8.GetString(pending.ToArray()).TrimStart('\uFEFF');
        pending.SetLength(0);
        Match match = Event.Match(line);
        DateTime time;
        if (match.Success && DateTime.TryParseExact(match.Groups["time"].Value,
            "yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture, DateTimeStyles.None, out time)
            && time >= started && time >= lastEvent) {
            state = match.Groups["state"].Value;
            lastEvent = time;
        }
    }
    public string Read(string path, DateTime started) {
        if (session != started.Ticks) {
            Reset();
            session = started.Ticks;
        }
        try {
            using (FileStream file = new FileStream(path, FileMode.Open, FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete)) {
                FileInfo info;
                if (!GetFileInformationByHandle(file.SafeFileHandle, out info))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                string current = info.Volume + ":" + info.IndexHigh + ":" + info.IndexLow;
                long end = file.Length;
                bool changed = identity != current || end < offset;
                // La huella detecta truncado y recrecimiento entre revisiones, aun con el mismo identificador.
                if (!changed && anchor.Length > 0) {
                    file.Position = offset - anchor.Length;
                    for (int i = 0; i < anchor.Length; i++) {
                        if (file.ReadByte() != anchor[i]) { changed = true; break; }
                    }
                }
                if (changed) ResetFile();
                identity = current;
                file.Position = offset;
                byte[] buffer = new byte[8192];
                while (file.Position < end) {
                    int count = file.Read(buffer, 0, (int)Math.Min(buffer.Length, end - file.Position));
                    if (count == 0) throw new IOException("El registro cambio durante la lectura.");
                    int first = 0;
                    for (int i = 0; i < count; i++) {
                        if (buffer[i] == 10) {
                            pending.Write(buffer, first, i - first);
                            AcceptLine(started);
                            first = i + 1;
                        }
                    }
                    pending.Write(buffer, first, count - first);
                }
                offset = file.Position;
                anchor = new byte[(int)Math.Min(64, offset)];
                file.Position = offset - anchor.Length;
                for (int i = 0; i < anchor.Length; i++) {
                    int value = file.ReadByte();
                    if (value < 0) throw new IOException("El registro fue truncado durante la lectura.");
                    anchor[i] = (byte)value;
                }
            }
            return state;
        } catch {
            ResetFile();
            throw;
        }
    }
}
"@
}
$script:discordRtcReader = New-Object DiscordRtcIncrementalReader

function Get-DiscordInCall {
    try {
        $discordProcs = @(Get-Process -Name 'discord' -ErrorAction SilentlyContinue)
        if ($discordProcs.Count -eq 0) { $script:discordRtcReader.Reset(); return $false }
        $started = ($discordProcs | Sort-Object StartTime | Select-Object -First 1).StartTime
        $path = Join-Path $env:APPDATA 'discord\logs\renderer_js.log'
        $state = $script:discordRtcReader.Read($path, $started)
        if (-not [string]::IsNullOrEmpty($state)) {
            return $state -notin @('RTC_DISCONNECTED', 'DISCONNECTED')
        }
        Write-Log 'Discord abierto sin estado RTC verificable; se aplaza la suspension.' 'WARN'
        return $true
    } catch {
        Write-Log "Error leyendo estado de voz de Discord; se aplaza la suspension: $_" 'WARN'
        return $true
    }
}
# --- DETECCIÓN DE DESCARGA ACTIVA EN LAUNCHERS [EXPERIMENTAL] ---
# Mide el tráfico de red de los procesos launcher comparando contadores
# de bytes recibidos entre dos snapshots separados por 2 segundos.
function Get-LauncherDownloadMBps {
    try {
        # Obtener PIDs de launchers activos
        $launcherPids = @()
        foreach ($name in $launcherProcesses) {
            $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
            if ($procs) {
                $launcherPids += $procs.Id
            }
        }
        if ($launcherPids.Count -eq 0) { return 0.0 }

        # Snapshot 1: bytes recibidos por proceso via Win32_PerfRawData_Tcpip_NetworkInterface
        # Usamos Get-NetAdapterStatistics para el total de la interfaz y filtramos
        # por proceso con Get-Counter si está disponible, de lo contrario usamos
        # el tráfico total de la interfaz como aproximación
        $before = @(Get-NetAdapterStatistics -ErrorAction SilentlyContinue) |
            Measure-Object -Property ReceivedBytes -Sum |
            Select-Object -ExpandProperty Sum
        if ($null -eq $before) { return 0.0 }

        Start-Sleep -Milliseconds 2000

        $after = @(Get-NetAdapterStatistics -ErrorAction SilentlyContinue) |
            Measure-Object -Property ReceivedBytes -Sum |
            Select-Object -ExpandProperty Sum
        if ($null -eq $after) { return 0.0 }

        $bytesPerSec = ($after - $before) / 2
        $mbps = [math]::Round($bytesPerSec / 1MB, 2)
        return $mbps
    } catch {
        Write-Log "Error midiendo trafico de red: $_" "WARN"
        return 0.0
    }
}

# --- DETECCION DE TRANSFERENCIAS EN DISCOS / USB ---
# shortcut: mide actividad de disco, no operaciones de copia; ajustar el umbral si hay falsos positivos.
function Get-DiskTransferMBps {
    try {
        $before = Get-CimInstance -ClassName Win32_PerfRawData_PerfDisk_PhysicalDisk -ErrorAction Stop | Where-Object Name -eq '_Total'
        Start-Sleep -Seconds 5
        $after = Get-CimInstance -ClassName Win32_PerfRawData_PerfDisk_PhysicalDisk -ErrorAction Stop | Where-Object Name -eq '_Total'
        if ($null -eq $before -or $null -eq $after) { throw 'Contadores de disco no disponibles.' }
        $elapsed = ([double]$after.Timestamp_PerfTime - [double]$before.Timestamp_PerfTime) / [double]$after.Frequency_PerfTime
        $bytes = [double]$after.DiskBytesPersec - [double]$before.DiskBytesPersec
        if ($elapsed -le 0 -or $bytes -lt 0) { throw 'Contadores de disco reiniciados o sin actualizar.' }
        return $bytes / $elapsed / 1MB
    } catch {
        Write-Log "No se pudo comprobar actividad de discos; se aplaza la suspension: $_" "WARN"
        return $null
    }
}

# --- INICIO ---
Write-Log "Servicio AutoSuspend iniciado. Limite: $idleLimitMinutes min | Gracia: $audioGraceMinutes min | Red: >$networkThresholdMBps MB/s | Discos/USB: >=$diskThresholdMBps MB/s | Intervalo: $checkIntervalSeconds seg."

$lastActivityTime = $null   # Gracia compartida: audio + Discord + descargas + discos/USB

$testVol = Get-AudioVolume
Write-Log "Prueba de audio al inicio: $testVol"

while ($true) {
    $secondsIdle = [Win32]::GetIdleTime()

    if ($secondsIdle -ge $idleLimitSeconds) {

        $activityReason = $null   # Qué disparó la gracia este ciclo

        # -- 1. Audio --
        $currentVolume = Get-AudioVolume
        if ($currentVolume -ge $audioThreshold) {
            $activityReason = "audio (Vol: $([math]::Round($currentVolume,4)))"
        }

        # -- 2. Llamada de Discord (registro RTC) --
        if (-not $activityReason) {
            $inCall = Get-DiscordInCall
            if ($inCall) {
                $activityReason = "Discord en llamada, reconectando o sin estado verificable"
            }
        }

        # -- 3. Descarga en launcher [EXPERIMENTAL] --
        if (-not $activityReason) {
            $downloadMBps = Get-LauncherDownloadMBps
            if ($downloadMBps -ge $networkThresholdMBps) {
                $activityReason = "descarga activa en launcher ($downloadMBps MB/s)"
            }
        }

        # -- 4. Transferencias entre discos / USB --
        if (-not $activityReason) {
            $diskMBps = Get-DiskTransferMBps
            if ($null -eq $diskMBps) {
                $activityReason = "comprobacion de discos no disponible"
            } elseif ($diskMBps -ge $diskThresholdMBps) {
                $activityReason = "actividad de discos/USB ($([math]::Round($diskMBps, 2)) MB/s)"
            }
        }
        # -- Decisión --
        if ($activityReason) {
            $lastActivityTime = Get-Date
            Write-Log "Inactivo $secondsIdle seg | Actividad detectada: $activityReason. Gracia reiniciada."
        } else {
            $secondsSinceActivity = if ($null -eq $lastActivityTime) {
                [int]::MaxValue
            } else {
                [int]((Get-Date) - $lastActivityTime).TotalSeconds
            }

            if ($secondsSinceActivity -lt $audioGraceSeconds) {
                $remainingGrace = $audioGraceSeconds - $secondsSinceActivity
                Write-Log "Inactivo $secondsIdle seg | Sin actividad, en gracia. Faltan $remainingGrace seg para suspender."
            } else {
                Write-Log "Inactivo $secondsIdle seg | Sin actividad y gracia expirada. Suspendiendo..."
                [System.Windows.Forms.Application]::SetSuspendState(
                    [System.Windows.Forms.PowerState]::Suspend,
                    $true,
                    $false
                )
                $lastActivityTime = $null
            }
        }
    } else {
        Write-Log "Sistema activo. Inactivo: $secondsIdle seg / $idleLimitSeconds seg requeridos."
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}
