# 🖥️ AutoSuspend

Script de PowerShell que suspende automáticamente el PC tras un periodo de inactividad, **siempre que no haya audio reproduciéndose**.

---

## ¿Cómo funciona?

Cada minuto el script verifica dos condiciones:

1. **Inactividad del usuario** — usa la API nativa de Windows (`GetLastInputInfo`) para medir cuántos segundos han pasado desde la última interacción con teclado o ratón.
2. **Ausencia de audio** — usa `MMDeviceEnumerator` para leer el nivel de volumen pico del dispositivo de salida de audio en tiempo real.

Si ambas condiciones se cumplen (inactividad ≥ límite configurado **y** volumen < 0.005), el sistema se suspende.

```
┌─────────────────────────────────────────┐
│  Cada 60 segundos                       │
│                                         │
│  ¿Inactivo >= 25 min?                    │
│       │                                 │
│      SÍ ──► ¿Hay audio?                 │
│       │          │                      │
│       │         NO ──► 💤 Suspender     │
│       │          │                      │
│       │         SÍ ──► ⏳ Esperar       │
│       │                                 │
│      NO ──► ⏳ Esperar                  │
└─────────────────────────────────────────┘
```

---

## Archivos

| Archivo | Descripción |
|---|---|
| `AutoSuspend.ps1` | Script principal, corre en segundo plano |
| `Instalar-AutoSuspend.ps1` | Registra la tarea en el Programador de Tareas y se elimina solo |

---

## Requisitos

- Windows 10 / 11
- PowerShell 5.1 o superior
- Dispositivo de audio configurado como salida predeterminada

---

## Instalación

1. Descarga ambos archivos en la misma carpeta.
2. Click derecho en `Instalar-AutoSuspend.ps1` → **Ejecutar con PowerShell como administrador**.
   2.1. En caso de que no aparezca la opcion de **Ejecutar con PoweShell como administrador"" y/o mande error:
         Abrir powershell como adminstrador y ejecutar los siguientes comandos:
         cd "direccion de los scripts" (ejemplo: cd D:\Documentos\Scripts)
         powershell -ExecutionPolicy Bypass -File .\Instalar-AutoSuspend.ps1   
4. Listo. El instalador configura la tarea y se elimina automáticamente.

El script se ejecutará de forma automática:
- Al iniciar sesión en Windows.
- Al volver de suspensión (con o sin contraseña de bloqueo configurada).

---

## Configuración

Abre `AutoSuspend.ps1` y edita las variables al inicio del archivo:

```powershell
$idleLimitMinutes     = 25      # Minutos de inactividad antes de suspender
$checkIntervalSeconds = 60     # Frecuencia de revisión en segundos
$audioThreshold       = 0.005  # Nivel mínimo de volumen para considerar que hay audio
```

---

## Registro (log)

El script genera un archivo `autosuspend.log` en la misma carpeta con el historial de eventos:

```
[2026-05-12 00:27:55][INFO] Servicio AutoSuspend iniciado. Límite: 2 min.
[2026-05-12 00:28:55][INFO] Sistema activo. Tiempo inactivo: 45 seg / 120 seg requeridos.
[2026-05-12 00:30:55][INFO] Inactivo por 165 seg, pero hay audio (Vol: 0.3421). Manteniendo encendido.
[2026-05-12 00:31:55][INFO] Inactividad de 225 seg y silencio total. Suspendiendo...
```

---

## Desinstalar

Abre PowerShell como administrador y ejecuta:

```powershell
Stop-ScheduledTask -TaskName "AutoSuspend"
Unregister-ScheduledTask -TaskName "AutoSuspend" -Confirm:$false
```

Luego elimina manualmente la carpeta con los scripts.

---
