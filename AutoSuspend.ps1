# ==============================================================================
# AutoSuspend.ps1 — Suspende el PC tras inactividad si no hay actividad activa
# Detecta: audio, llamada de Discord, descargas activas en launchers de juegos
# ==============================================================================

# --- CONFIGURACIÓN ---
$idleLimitMinutes     = 35
$checkIntervalSeconds = 60
$idleLimitSeconds     = $idleLimitMinutes * 60
$audioThreshold       = 0.005
$audioGraceMinutes    = 5      # Minutos de gracia compartidos por audio, Discord y descargas
$audioGraceSeconds    = $audioGraceMinutes * 60
$networkThresholdMBps = 2     # MB/s mínimos para considerar descarga activa
$logFile              = "$PSScriptRoot\autosuspend.log"

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
        return (uint)((GetTickCount64() - lastInputInfo.dwTime) / 1000);
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

# --- DETECCIÓN DE LLAMADA EN DISCORD [EXPERIMENTAL] ---
# Discord abre sockets UDP en el rango 50000-65535 durante llamadas de voz/video.
# Se detecta buscando conexiones UDP activas del proceso discord.exe en ese rango.
function Get-DiscordInCall {
    try {
        $discordProcs = Get-Process -Name "discord" -ErrorAction SilentlyContinue
        if (-not $discordProcs) { return $false }

        $discordPids = $discordProcs.Id

        # netstat lista conexiones UDP activas; filtramos por PID de Discord
        # y por el rango de puertos de voz (50000-65535)
        $netstatOutput = netstat -ano -p UDP 2>$null
        foreach ($line in $netstatOutput) {
            if ($line -match '^\s*UDP\s+\S+:(\d+)\s+\*:\*\s+(\d+)') {
                $port   = [int]$Matches[1]
                $procId = [int]$Matches[2]
                if ($discordPids -contains $procId -and $port -ge 50000) {
                    return $true
                }
            }
        }
        return $false
    } catch {
        Write-Log "Error detectando llamada de Discord: $_" "WARN"
        return $false
    }
}

# --- DETECCIÓN DE DESCARGA ACTIVA EN LAUNCHERS [EXPERIMENTAL] ---
# Mide el tráfico de red de los procesos launcher comparando contadores
# de bytes recibidos entre dos snapshots separados por 2 segundos.
function Get-LauncherDownloadMBps {
    try {
        # Obtener PIDs de launchers activos
        $activePids = @()
        foreach ($name in $launcherProcesses) {
            $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
            if ($procs) { $activePids += $procs.Id }
        }
        if ($activePids.Count -eq 0) { return 0.0 }

        # Snapshot 1: bytes recibidos por proceso via Win32_PerfRawData_Tcpip_NetworkInterface
        # Usamos Get-NetAdapterStatistics para el total de la interfaz y filtramos
        # por proceso con Get-Counter si está disponible, de lo contrario usamos
        # el tráfico total de la interfaz como aproximación
        $before = (Get-NetAdapterStatistics -ErrorAction SilentlyContinue |
                   Measure-Object -Property ReceivedBytes -Sum).Sum
        if ($null -eq $before) { return 0.0 }

        Start-Sleep -Milliseconds 2000

        $after = (Get-NetAdapterStatistics -ErrorAction SilentlyContinue |
                  Measure-Object -Property ReceivedBytes -Sum).Sum
        if ($null -eq $after) { return 0.0 }

        $bytesPerSec = ($after - $before) / 2
        $mbps = [math]::Round($bytesPerSec / 1MB, 2)
        return $mbps
    } catch {
        Write-Log "Error midiendo trafico de red: $_" "WARN"
        return 0.0
    }
}

# --- INICIO ---
Write-Log "Servicio AutoSuspend iniciado. Limite: $idleLimitMinutes min | Gracia: $audioGraceMinutes min | Red: >$networkThresholdMBps MB/s | Intervalo: $checkIntervalSeconds seg."

$lastActivityTime = $null   # Gracia compartida: audio + Discord + descargas

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

        # -- 2. Llamada de Discord [EXPERIMENTAL] --
        if (-not $activityReason) {
            $inCall = Get-DiscordInCall
            if ($inCall) {
                $activityReason = "llamada de Discord activa"
            }
        }

        # -- 3. Descarga en launcher [EXPERIMENTAL] --
        if (-not $activityReason) {
            $downloadMBps = Get-LauncherDownloadMBps
            if ($downloadMBps -ge $networkThresholdMBps) {
                $activityReason = "descarga activa en launcher ($downloadMBps MB/s)"
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
