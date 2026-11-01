# 📺 Optimizador de Android TV / Google TV

Script para **limpiar el bloatware, acelerar y darle un diseño minimalista** a una
Android TV usando ADB. No necesita root y **todo se puede deshacer**.

## Qué hace

| Opción | Qué hace | ¿Se puede deshacer? |
|---|---|---|
| 1. Quitar bloatware | Desactiva apps inútiles de Google y del fabricante ([lista](listas/basura-segura.txt)) | ✅ Opción 6 |
| 2. Apps opcionales | Te pregunta una por una por Netflix, YouTube, Asistente, Chromecast, etc. | ✅ Opción 6 |
| 3. Acelerar | Animaciones a 0.5x, limpia caché y opcionalmente optimiza todas las apps | ✅ Opción 6 |
| 4. Diseño minimalista | Pone **Projectivy Launcher** o **FLauncher** como inicio y desactiva el de fábrica (con publicidad) | ✅ Opción 6 |
| 5. Auditar | Lista las apps de sistema del fabricante para revisarlas a mano | (solo lectura) |
| 6. Restaurar | Reactiva todo lo que el script desactivó y vuelve las animaciones a 1x | — |

Las apps se **desactivan** (`pm disable-user`), no se borran: no ocupan RAM ni
aparecen, pero siguen en el sistema. Un reseteo de fábrica también las devuelve.
Hay una [lista de paquetes críticos](listas/nunca-tocar.txt) que el script se niega a tocar.

## Paso a paso

### 1. En la TV
- *Configuración → Sistema → Acerca de* → presioná **7 veces** "Compilación del SO" (ya lo hiciste ✅).
- *Configuración → Sistema → Opciones de desarrollador* → activá **Depuración USB**
  y, si aparece, **Depuración de red / ADB por red**.
- Anotá la IP de la TV: *Configuración → Red e Internet → (tu Wi-Fi)*.

> 💡 La mayoría de las TVs **no** se conectan a la PC por cable USB (sus puertos USB son
> para pendrives). Lo normal es conectarse **por Wi-Fi** con la IP. Si tu TV o
> Chromecast sí admite cable, también funciona.

### 2a. Desde el celular (Android + Termux)
1. Instalá **Termux** desde [F-Droid](https://f-droid.org/packages/com.termux/) (la del Play Store está desactualizada).
2. En Termux:
   ```bash
   pkg install android-tools git
   git clone https://github.com/EliseyAgustin/android-tv-optimizer
   cd android-tv-optimizer
   ```
3. Conectá el celu a la TV (mismo Wi-Fi):
   - **Con "Depuración inalámbrica"** (Google TV moderno): en la TV tocá *Vincular con código* →
     `adb pair IP:PUERTO` → después `adb connect IP:PUERTO` (el puerto de la pantalla principal, no el de vinculación).
   - **Con "Depuración de red"**: `adb connect IP_DE_LA_TV`.

### 2b. Desde la computadora
1. Descargá **Android Platform Tools**: https://developer.android.com/tools/releases/platform-tools
2. Cloná o descargá este repo (*Code → Download ZIP*).
3. Abrí una terminal en la carpeta:
   - **Linux / macOS**: Terminal.
   - **Windows**: instalá [Git for Windows](https://git-scm.com/download/win) y usá **Git Bash**
     (copiá `adb.exe` y sus `.dll` dentro de esta carpeta, o agregalos al PATH).

### 3. Correr el script
```bash
# Primero en modo simulación: muestra qué haría sin cambiar nada
DRY_RUN=1 ./tv-optimizer.sh 192.168.1.50

# De verdad (cambiá por la IP de tu TV; sin IP usa el cable USB o la conexión ya hecha con adb connect)
./tv-optimizer.sh 192.168.1.50
```
La primera vez la TV muestra **"¿Permitir depuración?"** → marcá *Permitir siempre* y aceptá.

**Orden recomendado:** `1` → `3` → instalar Projectivy desde el Play Store de la TV → `4` → `2` → `7` (reiniciar).

## Diseño minimalista recomendado (Projectivy Launcher)
Una vez activo, en sus ajustes:
- **Tema:** oscuro, fondo liso o un wallpaper sutil (sin carrusel de pósters).
- **Filas:** dejá una sola fila con tus 6-8 apps reales; ocultá "Recomendados" y "Canales".
- **Reloj y clima** arriba, chiquitos; tarjetas en tamaño pequeño con esquinas redondeadas.
- **Ocultá** del cajón de apps lo que nunca abrís.

## Si algo sale mal
- **Pantalla negra al apretar Home:** corré la opción `6`, o directamente:
  `adb shell pm enable com.google.android.apps.tv.launcherx`
- **Reactivar una app puntual:** `adb shell pm enable <paquete>`
- **Deshacer todo de golpe:** opción `6`, o como último recurso un reseteo de fábrica.

Los respaldos de qué estaba activo antes quedan en `respaldos/` (no se suben a git).

## Agregar más apps a la lista
Corré la opción `5`, buscá en Google el nombre del paquete que te parezca basura
(ej. publicidad o "tienda" de la marca) y agregalo a `listas/basura-segura.txt`.
