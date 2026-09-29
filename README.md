# 🖥️ AutoSuspend

Script de PowerShell que suspende automáticamente el PC tras un periodo de inactividad, siempre que no haya actividad activa detectada: audio, llamada de Discord o descarga en un launcher de juegos.

---

## ¿Cómo funciona?

Cada 60 segundos el script revisa el tiempo de inactividad. Al alcanzar **35 minutos**, comprueba tres fuentes de actividad. Cualquiera de ellas reinicia un **periodo de gracia compartido** de 5 minutos: mientras la gracia no expire, el PC no se suspende.

```
┌────────────────────────────────────────────────────────┐
│  Cada 60 segundos                                      │
│                                                        │
│  ¿Inactivo >= 35 min?                                   │
│       │                                                │
│      SÍ ──► ¿Audio / Discord en llamada / Descarga?   │
│       │                    │                           │
│       │                   SÍ ──► 🔄 Reiniciar gracia  │
│       │                    │                           │
│       │                   NO ──► ¿Gracia expirada?    │
│       │                               │               │
│       │                              SÍ ──► 💤 Suspender
│       │                               │               │
│       │                              NO ──► ⏳ Esperar │
│       │                                                │
│      NO ──► ⏳ Esperar                                 │
└────────────────────────────────────────────────────────┘
```

### Fuentes de actividad detectadas

**Audio** — Lee el nivel de volumen pico del dispositivo de salida predeterminado via Core Audio API. Cualquier sonido por encima del umbral configurable reinicia la gracia.

**Actividad UDP de Discord** *(experimental)* — Busca en la salida de `netstat` entradas UDP asociadas al proceso `discord.exe` cuyo puerto local sea igual o superior a `50000`. Es un indicador indirecto de actividad de voz/video, no una confirmación fiable de que haya una llamada activa; puede haber falsos positivos o negativos.

**Tráfico de red con launchers abiertos** *(experimental)* — Si detecta abierto al menos uno de los launchers compatibles, mide el total de bytes recibidos por los adaptadores de red durante un intervalo de 2 segundos. Si la tasa supera el umbral configurado, se considera actividad. La medición **no está asociada al proceso del launcher**: también puede contar tráfico de Windows u otras aplicaciones. Launchers comprobados: Steam, Epic Games, GOG Galaxy, Battle.net, EA App y Origin.

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

**Ubicación recomendada:** guarda el proyecto en `Documentos\Scripts\AutoSuspend`. Si aún no existe, crea primero la carpeta `Documentos\Scripts` y dentro de ella `AutoSuspend`. Puedes hacerlo desde el Explorador de archivos (File Explorer).

1. Descarga `AutoSuspend.ps1` e `Instalar-AutoSuspend.ps1` desde el repositorio y coloca ambos archivos dentro de `Documentos\Scripts\AutoSuspend` (deben estar en la misma carpeta).
2. Abre el menú **Inicio (Start)**, busca **PowerShell** o **Windows PowerShell** y selecciona **Ejecutar como administrador (Run as administrator)**.
3. En la ventana de PowerShell, ejecuta el instalador con esta ruta:

   ```powershell
   & "$env:USERPROFILE\Documents\Scripts\AutoSuspend\Instalar-AutoSuspend.ps1"
   ```

   Si guardaste los archivos en otra ubicación, ajusta la ruta.
4. Confirma el aviso de Control de cuentas de usuario (UAC) con **Sí (Yes)**, si aparece.
5. El instalador configura la tarea en el Programador de tareas y se elimina automáticamente al finalizar.


**Si no aparece la opción «Ejecutar con PowerShell como administrador»:**

1. Abre el menú **Inicio (Start)** y busca **PowerShell** o **Windows PowerShell**.
2. Haz clic derecho en el resultado y selecciona **Ejecutar como administrador (Run as administrator)**. También puedes seleccionar la opción desde el panel derecho del menú Inicio.
3. En la ventana de PowerShell, ejecuta el instalador usando su ruta completa. Por ejemplo:

   ```powershell
   & "$env:USERPROFILE\Downloads\AutoSuspend\Instalar-AutoSuspend.ps1"
   ```

   Ajusta la ruta si guardaste los archivos en otra carpeta.
4. Si aparece el aviso de Control de cuentas de usuario (UAC), confirma con **Sí (Yes)**.


El script se ejecutará de forma automática:
- Al iniciar sesión en Windows.
- Al volver de suspensión (con o sin contraseña de bloqueo configurada).

---

## Configuración

Abre `AutoSuspend.ps1` y edita las variables al inicio del archivo:

```powershell
$idleLimitMinutes     = 35      # Minutos de inactividad antes de evaluar suspensión
$checkIntervalSeconds = 60     # Frecuencia de revisión en segundos
$audioThreshold       = 0.005  # Nivel mínimo de volumen para considerar que hay audio
$audioGraceMinutes    = 5      # Minutos de gracia compartidos por las tres fuentes
$networkThresholdMBps = 1      # MB/s mínimos para considerar descarga activa (1 MB/s = 8 Mbps)
$maxLogSizeBytes      = 2MB    # Tamaño en MB del archivo .log
```

### Sobre la gracia de actividad

`$audioGraceMinutes` es un temporizador compartido. Cualquiera de las tres fuentes (audio, Discord, descarga) puede reiniciarlo. El PC no se suspenderá mientras haya pasado menos de ese tiempo desde la última actividad detectada, sin importar cuál fue.

- Si tus llamadas tienen silencios largos, sube este valor (ej. `10`).
- Si quieres que el PC suspenda más rápido tras cerrar el audio, bájalo (ej. `2`).

### Sobre el umbral de red

`$networkThresholdMBps` se expresa en **MB/s** (megabytes por segundo). Referencia rápida:

| `$networkThresholdMBps` | Equivalente |
|---|---|
| `1` | 8 Mbps |
| `5` | 40 Mbps |
| `10` | 80 Mbps |
| `12.5` | 100 Mbps |

El valor predeterminado del script es `1` MB/s. Puedes aumentarlo para reducir detecciones causadas por tráfico de otras aplicaciones, o disminuirlo si quieres detectar transferencias más lentas. Como la medición es del tráfico total recibido, un umbral menor también puede aumentar los falsos positivos.

---

## Registro (log)

El script genera `autosuspend.log` en la misma carpeta, con un tamaño máximo de 2 MB (configurable mediante `$maxLogSizeBytes`). Al alcanzar el límite, el archivo se elimina y se vuelve a crear; no se conserva un historial anterior. El log indica qué fuente reinició la gracia en cada ciclo:

```
[2026-05-24 21:00:00][INFO] Servicio AutoSuspend iniciado. Limite: 35 min | Gracia: 5 min | Red: >1 MB/s | Intervalo: 60 seg.
[2026-05-24 21:04:00][INFO] Inactivo 2100 seg | Actividad detectada: audio (Vol: 0.3421). Gracia reiniciada.
[2026-05-24 21:06:00][INFO] Inactivo 2220 seg | Sin actividad, en gracia. Faltan 240 seg para suspender.
[2026-05-24 21:08:00][INFO] Inactivo 2340 seg | Actividad detectada: actividad UDP de Discord. Gracia reiniciada.
[2026-05-24 21:10:00][INFO] Inactivo 2460 seg | Actividad detectada: tráfico de red con launcher abierto (45.3 MB/s). Gracia reiniciada.
[2026-05-24 21:20:00][INFO] Inactivo 3060 seg | Sin actividad y gracia expirada. Suspendiendo...
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

## Licencia

MIT — consulta el archivo [LICENSE](LICENSE) para más detalles.
