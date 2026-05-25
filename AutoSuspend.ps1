# ==============================================================================
# AutoSuspend.ps1 — Suspende el PC tras inactividad si no hay audio activo
# ==============================================================================

# --- CONFIGURACIÓN ---
$idleLimitMinutes     = 25
$checkIntervalSeconds = 60
$idleLimitSeconds     = $idleLimitMinutes * 60
$audioThreshold       = 0.005
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
    //  Audio — Core Audio API completamente via P/Invoke                   //
    //  Sin interfaces COM de .NET; todo via punteros nativos               //
    // ------------------------------------------------------------------ //
    [DllImport("ole32.dll")]
    static extern int CoCreateInstance(
        ref Guid rclsid, IntPtr pUnkOuter, uint dwClsContext,
        ref Guid riid, out IntPtr ppv);

    [DllImport("ole32.dll")]
    static extern int CoInitialize(IntPtr pvReserved);

    [DllImport("ole32.dll")]
    static extern void CoUninitialize();

    // vtable offsets para IMMDeviceEnumerator::GetDefaultAudioEndpoint (metodo #4, indice 3)
    // vtable: 0=QI, 1=AddRef, 2=Release, 3=EnumAudioEndpoints, 4=GetDefaultAudioEndpoint
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetDefaultAudioEndpointDelegate(
        IntPtr self, int dataFlow, int role, out IntPtr ppDevice);

    // vtable offset para IMMDevice::Activate (metodo #4, indice 3)
    // vtable: 0=QI, 1=AddRef, 2=Release, 3=Activate
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int ActivateDelegate(
        IntPtr self, ref Guid iid, uint dwClsCtx,
        IntPtr pActivationParams, out IntPtr ppInterface);

    // vtable para IAudioMeterInformation::GetPeakValue (metodo #4, indice 3)
    // vtable: 0=QI, 1=AddRef, 2=Release, 3=GetPeakValue
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetPeakValueDelegate(IntPtr self, out float pfPeak);

    // vtable: 0=QI, 1=AddRef, 2=Release
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
        // CLSID MMDeviceEnumerator
        Guid clsidEnum = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
        // IID IMMDeviceEnumerator
        Guid iidEnum   = new Guid("A95664D2-9614-4F35-A746-DE8DB63617E6");
        // IID IAudioMeterInformation
        Guid iidMeter  = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");

        IntPtr pEnum   = IntPtr.Zero;
        IntPtr pDevice = IntPtr.Zero;
        IntPtr pMeter  = IntPtr.Zero;

        try {
            CoInitialize(IntPtr.Zero);

            // 1. Crear MMDeviceEnumerator
            int hr = CoCreateInstance(ref clsidEnum, IntPtr.Zero, 1, ref iidEnum, out pEnum);
            if (hr != 0 || pEnum == IntPtr.Zero)
                throw new Exception("CoCreateInstance fallo. HR=" + hr.ToString("X8"));

            // 2. GetDefaultAudioEndpoint
            var getEndpoint = GetVtableMethod<GetDefaultAudioEndpointDelegate>(pEnum, 4);
            hr = getEndpoint(pEnum, 0, 0, out pDevice); // eRender=0, eConsole=0
            if (hr != 0 || pDevice == IntPtr.Zero)
                throw new Exception("GetDefaultAudioEndpoint fallo. HR=" + hr.ToString("X8"));

            // 3. IMMDevice::Activate -> IAudioMeterInformation
            var activate = GetVtableMethod<ActivateDelegate>(pDevice, 3);
            hr = activate(pDevice, ref iidMeter, 1, IntPtr.Zero, out pMeter);
            if (hr != 0 || pMeter == IntPtr.Zero)
                throw new Exception("Activate fallo. HR=" + hr.ToString("X8"));

            // 4. GetPeakValue
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

# --- INICIO ---
Write-Log "Servicio AutoSuspend iniciado. Limite: $idleLimitMinutes min. Intervalo: $checkIntervalSeconds seg."

$testVol = Get-AudioVolume
Write-Log "Prueba de audio al inicio: $testVol"

while ($true) {
    $secondsIdle = [Win32]::GetIdleTime()

    if ($secondsIdle -ge $idleLimitSeconds) {
        $currentVolume = Get-AudioVolume

        if ($currentVolume -lt $audioThreshold) {
            Write-Log "Inactividad de $secondsIdle seg y silencio (Vol: $currentVolume). Suspendiendo..."
            [System.Windows.Forms.Application]::SetSuspendState(
                [System.Windows.Forms.PowerState]::Suspend,
                $true,
                $false
            )
        } else {
            Write-Log "Inactivo $secondsIdle seg, hay audio (Vol: $([math]::Round($currentVolume,4))). Manteniendo encendido."
        }
    } else {
        Write-Log "Sistema activo. Inactivo: $secondsIdle seg / $idleLimitSeconds seg requeridos."
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}
