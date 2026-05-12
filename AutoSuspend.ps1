# ==============================================================================
# AutoSuspend.ps1 — Suspende el PC tras inactividad si no hay audio activo
# ==============================================================================

# --- CONFIGURACIÓN ---
$idleLimitMinutes     = 25
$checkIntervalSeconds = 60
$idleLimitSeconds     = $idleLimitMinutes * 60
$audioThreshold       = 0.005   # Umbral mínimo para considerar que hay audio
$logFile              = "$PSScriptRoot\autosuspend.log"

# --- LOGGING ---
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# --- LIBRERÍAS NATIVAS ---
# Se cargan una sola vez al inicio del script
Add-Type -AssemblyName System.Windows.Forms

if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
    $Win32Signature = @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    // GetTickCount64 es compatible con .NET Framework y no desborda cada ~49 dias
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
}
"@
    try {
        Add-Type -TypeDefinition $Win32Signature -ErrorAction Stop
        Write-Log "Tipo Win32 cargado correctamente."
    } catch {
        Write-Log "ERROR FATAL: No se pudo cargar Win32. El script no puede continuar. Detalle: $_" "ERROR"
        exit 1
    }
} else {
    Write-Log "Tipo Win32 ya estaba cargado en la sesion, reutilizando."
}

# --- DETECCIÓN DE AUDIO ---
function Get-AudioVolume {
    $enumerator = $null
    $device     = $null
    try {
        $enumerator = New-Object -ComObject MMDeviceEnumerator
        # eDataFlow = 0 (Render/salida), eRole = 0 (Console)
        $device = $enumerator.GetDefaultAudioEndpoint(0, 0)
        return $device.AudioMeterInformation.MasterPeakValue
    }
    catch {
        # Sin dispositivo de audio disponible: se asume silencio pero se registra
        Write-Log "No se pudo leer el dispositivo de audio: $_" "WARN"
        return 0.0
    }
    finally {
        # Liberar objetos COM siempre para evitar memory leaks
        if ($null -ne $device)     { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($device)     | Out-Null }
        if ($null -ne $enumerator) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($enumerator) | Out-Null }
    }
}

# --- INICIO ---
Write-Log "Servicio AutoSuspend iniciado. Límite de inactividad: $idleLimitMinutes min. Intervalo de revisión: $checkIntervalSeconds seg."

while ($true) {
    $secondsIdle = [Win32]::GetIdleTime()

    if ($secondsIdle -ge $idleLimitSeconds) {
        $currentVolume = Get-AudioVolume

        if ($currentVolume -lt $audioThreshold) {
            Write-Log "Inactividad de $secondsIdle seg detectada y silencio total (Vol: $currentVolume). Suspendiendo..."
            # Suspend: modo suspensión | Force: forzar cierre de apps | DisableWakeEvent: no despertar por timers
            [System.Windows.Forms.Application]::SetSuspendState(
                [System.Windows.Forms.PowerState]::Suspend,
                $true,
                $false
            )
        }
        else {
            Write-Log "Inactivo por $secondsIdle seg, pero hay audio detectado (Vol: $([math]::Round($currentVolume, 4))). Manteniendo encendido."
        }
    }
    else {
        Write-Log "Sistema activo. Tiempo inactivo: $secondsIdle seg / $idleLimitSeconds seg requeridos."
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}