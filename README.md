# 🖥️ AutoSuspend

Script de PowerShell que suspende automáticamente el PC tras un periodo de inactividad, siempre que no haya actividad activa detectada: audio, llamada de Discord o descarga en un launcher de juegos.

---

## ¿Cómo funciona?

Cada minuto el script verifica que el usuario esté inactivo y luego comprueba tres fuentes de actividad. Cualquiera de ellas reinicia un **periodo de gracia compartido** de 5 minutos: mientras la gracia no expire, el PC no se suspende.

```
┌────────────────────────────────────────────────────────┐
│  Cada 60 segundos                                      │
│                                                        │
│  ¿Inactivo >= 2 min?                                   │
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

**Llamada de Discord** *(experimental)* — Detecta conexiones UDP activas de `discord.exe` en el rango de puertos 50000-65535, que Discord usa exclusivamente para voz y video. Si Discord está abierto pero no en llamada, no activa la gracia.

**Descarga en launchers** *(experimental)* — Mide el tráfico de red recibido en intervalos de 2 segundos. Si supera el umbral configurado, se considera que hay una descarga activa. Launchers soportados: Steam, Epic Games, GOG Galaxy, Battle.net, EA App y Origin.

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
3. Listo. El instalador configura la tarea y se elimina automáticamente.

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
$networkThresholdMBps = 3      # MB/s mínimos para considerar descarga activa (1 MB/s = 8 Mbps)
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

Se recomienda dejarlo en `3` para que detecte también descargas en segundo plano o con ancho de banda limitado.

---

## Registro (log)

El script genera `autosuspend.log` en la misma carpeta (limitado a 2MB{configurable} de espacio). El log indica qué fuente reinició la gracia en cada ciclo:

```
[2026-05-24 21:00:00][INFO] Servicio AutoSuspend iniciado. Limite: 2 min | Gracia: 5 min | Red: >1 MB/s | Intervalo: 60 seg.
[2026-05-24 21:04:00][INFO] Inactivo 130 seg | Actividad detectada: audio (Vol: 0.3421). Gracia reiniciada.
[2026-05-24 21:06:00][INFO] Inactivo 250 seg | Sin actividad, en gracia. Faltan 240 seg para suspender.
[2026-05-24 21:08:00][INFO] Inactivo 370 seg | Actividad detectada: llamada de Discord activa. Gracia reiniciada.
[2026-05-24 21:10:00][INFO] Inactivo 490 seg | Actividad detectada: descarga activa en launcher (45.3 MB/s). Gracia reiniciada.
[2026-05-24 21:20:00][INFO] Inactivo 1090 seg | Sin actividad y gracia expirada. Suspendiendo...
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
