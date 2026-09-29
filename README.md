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

Hay dos formas de instalar el proyecto:

- **Instalación automática (recomendada):** ejecuta `Instalar-AutoSuspend.bat`. El archivo BAT solicita permisos de administrador, copia los archivos necesarios a la carpeta de Documentos, ejecuta el instalador de PowerShell, registra la tarea y la inicia inmediatamente.
- **Instalación manual:** descarga los archivos y ejecuta directamente el instalador de PowerShell desde una consola elevada. Esta opción permite elegir la ubicación y controlar cada paso.

### Opción 1: instalación automática con `Instalar-AutoSuspend.bat`

1. Descarga el repositorio como ZIP desde GitHub (**Code → Download ZIP**) o descarga los archivos de instalación.
2. Si descargaste un ZIP, extráelo primero. No ejecutes el BAT directamente dentro del archivo comprimido.
3. Asegúrate de que estos tres archivos estén juntos en la misma carpeta:
   - `Instalar-AutoSuspend.bat`
   - `Instalar-AutoSuspend.ps1`
   - `AutoSuspend.ps1`
4. Haz doble clic en `Instalar-AutoSuspend.bat`.
5. Si Windows muestra el aviso de Control de cuentas de usuario (**User Account Control / Control de cuentas de usuario**, UAC), acepta con **Sí (Yes)** para permitir la instalación. El BAT solicita elevación automáticamente; no es necesario abrir PowerShell como administrador.
6. El instalador copia los dos archivos de PowerShell a:
   
   `Documentos\\Scripts\\AutoSuspend`

   La ruta de Documentos se obtiene desde Windows, por lo que también funciona si la carpeta está redirigida a otra ubicación (por ejemplo, OneDrive).
7. El instalador registra la tarea programada **AutoSuspend** y, si todo termina correctamente, el BAT comprueba que la tarea exista y la inicia de inmediato, sin esperar al siguiente inicio de sesión.
8. Se genera en la carpeta de destino un archivo `Desinstalar-AutoSuspend.bat`. Puedes usarlo más adelante para quitar la tarea y, opcionalmente, los archivos del programa.
9. Cuando la instalación termina correctamente, el BAT elimina los instaladores de PowerShell de la carpeta de origen y se elimina a sí mismo. Los archivos de la carpeta de destino permanecen.

**Importante:** no elimines `Documentos\\Scripts\\AutoSuspend`; contiene el script que se ejecuta en segundo plano y los archivos de configuración o registro que correspondan. Si la instalación falla, el BAT muestra un error y conserva los archivos originales para que puedas volver a intentarlo. Si cancelas el aviso de administrador, la instalación no se realiza.

### Opción 2: instalación manual con PowerShell

Usa este método si prefieres instalar en una ruta distinta o no quieres utilizar el BAT.

1. Descarga y extrae el repositorio, o descarga los archivos necesarios.
2. Coloca `AutoSuspend.ps1` y `Instalar-AutoSuspend.ps1` juntos en la carpeta donde quieras mantener el programa. El instalador de PowerShell busca el script principal en su propia carpeta.
3. Abre **Start / Inicio**, busca **PowerShell** o **Windows PowerShell**, haz clic derecho y selecciona **Run as administrator / Ejecutar como administrador**. Si no aparece esa opción en el menú contextual, selecciónala desde el panel derecho del menú Inicio.
4. Ejecuta el instalador usando su ruta completa. Por ejemplo, si elegiste la ubicación recomendada:

   ```powershell
   & "$env:USERPROFILE\\Documents\\Scripts\\AutoSuspend\\Instalar-AutoSuspend.ps1"
   ```

   Si lo guardaste en otra ubicación, sustituye la ruta por la carpeta que elegiste.
5. Confirma el aviso UAC si aparece. El instalador verifica que el script principal esté presente y que PowerShell se esté ejecutando como administrador.
6. Al finalizar, se registra la tarea **AutoSuspend**, configurada para ejecutarse al iniciar sesión y al volver de suspensión. El instalador de PowerShell se elimina automáticamente.

En la instalación manual, el BAT no se ejecuta, por lo que **no se crea automáticamente** el archivo `Desinstalar-AutoSuspend.bat`. Para iniciar la tarea sin cerrar sesión, ejecuta:

```powershell
Start-ScheduledTask -TaskName "AutoSuspend"
```


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
