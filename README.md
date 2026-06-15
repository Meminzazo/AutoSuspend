# 🖥️ AutoSuspend

Script de PowerShell que suspende automáticamente el PC tras un periodo de inactividad, **siempre que no haya audio reproduciéndose**.

---

## ¿Cómo funciona?

Cada minuto el script verifica dos condiciones:

1. **Inactividad del usuario** — usa la API nativa de Windows (`GetLastInputInfo`) para medir cuántos segundos han pasado desde la última interacción con teclado o ratón.
2. **Ausencia de audio** — usa la Core Audio API de Windows via P/Invoke para leer el nivel de volumen pico del dispositivo de salida en tiempo real.

Para evitar suspensiones falsas durante silencios cortos (pausas en una llamada de Discord, cambio de canción, etc.), el script implementa un **periodo de gracia de audio**: si se detecta audio, se guarda la hora. Aunque el siguiente check no detecte audio, el script esperará 5 minutos desde la última detección antes de considerar que realmente hay silencio. Cualquier nueva detección de audio reinicia el contador de gracia desde cero.

```
┌──────────────────────────────────────────────────┐
│  Cada 60 segundos                                │
│                                                  │
│  ¿Inactivo >= 35 min?                            │
│       │                                          │
│      SÍ ──► ¿Hay audio?                          │
│       │          │                               │
│       │         SÍ ──► 🔄 Reiniciar gracia       │
│       │          │                               │
│       │         NO ──► ¿Gracia expirada (5 min)? │
│       │                     │                    │
│       │                    SÍ ──► 💤 Suspender   │
│       │                     │                    │
│       │                    NO ──► ⏳ Esperar     │
│       │                                          │
│      NO ──► ⏳ Esperar                           │
└──────────────────────────────────────────────────┘
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
3. Listo. El instalador configura la tarea y se elimina automáticamente.

El script se ejecutará de forma automática:
- Al iniciar sesión en Windows.
- Al volver de suspensión (con o sin contraseña de bloqueo configurada).

---

## Configuración

Abre `AutoSuspend.ps1` y edita las variables al inicio del archivo:

```powershell
$idleLimitMinutes     = 35     # Minutos de inactividad antes de suspender
$checkIntervalSeconds = 60     # Frecuencia de revisión en segundos
$audioThreshold       = 0.005  # Nivel mínimo de volumen para considerar que hay audio
$audioGraceMinutes    = 5      # Minutos de gracia tras el último audio detectado
```

### Sobre la gracia de audio

`$audioGraceMinutes` controla cuánto tiempo espera el script tras detectar audio por última vez antes de atreverse a suspender. Útil para evitar suspensiones durante silencios normales en llamadas de voz o entre canciones.

- Si tus llamadas tienen silencios largos, sube este valor (ej. `10`).
- Si quieres que el PC suspenda más rápido tras cerrar el audio, bájalo (ej. `2`).
- Cualquier detección de audio reinicia el contador desde cero, sin importar en qué punto de la gracia estés.

---

## Registro (log)

El script genera un archivo `autosuspend.log` en la misma carpeta con el historial de eventos:

```
[2026-05-24 21:00:00][INFO] Servicio AutoSuspend iniciado. Limite inactividad: 2 min. Gracia de audio: 5 min. Intervalo: 60 seg.
[2026-05-24 21:00:00][INFO] Prueba de audio al inicio: 0.1823
[2026-05-24 21:04:00][INFO] Inactivo 130 seg, hay audio (Vol: 0.3421). Gracia reiniciada.
[2026-05-24 21:06:00][INFO] Inactivo 250 seg, sin audio pero en gracia. Faltan 299 seg para poder suspender.
[2026-05-24 21:08:00][INFO] Inactivo 370 seg, hay audio (Vol: 0.1205). Gracia reiniciada.
[2026-05-24 21:14:00][INFO] Inactividad de 730 seg y silencio confirmado (gracia expirada). Suspendiendo...
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
