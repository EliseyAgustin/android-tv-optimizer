#!/usr/bin/env bash
# tv-optimizer.sh: limpia, acelera y "minimaliza" una Android TV / Google TV por ADB.
#
# No hace falta root. Todo lo que hace se puede deshacer:
#   - Las apps se DESACTIVAN para tu usuario (pm disable-user), no se borran del sistema.
#   - Antes de tocar nada guarda un respaldo en ./respaldos/
#   - La opción "Restaurar" vuelve a activar todo lo que el script desactivó.
#
# Uso:
#   ./tv-optimizer.sh                 # TV conectada por USB
#   ./tv-optimizer.sh 192.168.1.50    # TV por Wi-Fi (depuración de red activada)
#   DRY_RUN=1 ./tv-optimizer.sh       # Muestra lo que haría, sin cambiar nada

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTAS="$DIR/listas"
RESPALDOS="$DIR/respaldos"
DRY_RUN="${DRY_RUN:-0}"
TV_IP="${1:-}"

verde()   { printf '\033[32m%s\033[0m\n' "$*"; }
amarillo(){ printf '\033[33m%s\033[0m\n' "$*"; }
rojo()    { printf '\033[31m%s\033[0m\n' "$*"; }
titulo()  { printf '\n\033[1;35m== %s ==\033[0m\n' "$*"; }

preguntar() { # preguntar "texto" -> 0 si responde s/si
  local r
  read -r -p "$1 [s/N] " r
  [[ "$r" =~ ^([sS]|[sS][iI]|[yY])$ ]]
}

# </dev/null: sin esto adb se "come" la entrada de los bucles while-read.
sh_tv() { adb shell "$@" </dev/null 2>/dev/null | tr -d '\r'; }

ejecutar() { # Corre un comando en la TV, o solo lo muestra si DRY_RUN=1
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [simulación] adb shell $*"
    return 0
  fi
  sh_tv "$@"
}

leer_lista() { # Devuelve los paquetes de un archivo de lista, sin comentarios
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' || true
}

# ---------------------------------------------------------------- conexión

conectar() {
  titulo "Conexión"
  if ! command -v adb >/dev/null 2>&1; then
    rojo "No encuentro 'adb'. Instalá Android Platform Tools:"
    echo "  https://developer.android.com/tools/releases/platform-tools"
    echo "  (Windows: descomprimí la carpeta y agregala al PATH, o copiá este script adentro)"
    exit 1
  fi

  if [[ -n "$TV_IP" ]]; then
    [[ "$TV_IP" == *:* ]] || TV_IP="$TV_IP:5555"
    echo "Conectando a $TV_IP ..."
    adb connect "$TV_IP" >/dev/null
  fi

  adb start-server >/dev/null 2>&1
  local estado
  estado="$(adb get-state 2>&1 || true)"
  if [[ "$estado" != "device" ]]; then
    rojo "La TV no aparece como conectada (estado: ${estado:-ninguno})."
    echo "  - Si es 'unauthorized': aceptá el cartel \"¿Permitir depuración?\" en la TV."
    echo "  - Si no aparece: revisá el cable o pasá la IP de la TV como argumento."
    echo "  - Dispositivos detectados:"
    adb devices -l | sed 's/^/      /'
    exit 1
  fi

  local modelo marca android
  modelo="$(sh_tv getprop ro.product.model)"
  marca="$(sh_tv getprop ro.product.manufacturer)"
  android="$(sh_tv getprop ro.build.version.release)"
  verde "Conectado: $marca $modelo (Android $android)"
  [[ "$DRY_RUN" == "1" ]] && amarillo "Modo simulación: no se va a cambiar nada."
}

instalados() { sh_tv pm list packages | sed 's/^package://' | sort; }

respaldar() {
  mkdir -p "$RESPALDOS"
  local f
  f="$RESPALDOS/activos-$(date +%Y%m%d-%H%M%S).txt"
  sh_tv pm list packages -e | sed 's/^package://' | sort > "$f"
  {
    echo "window_animation_scale=$(sh_tv settings get global window_animation_scale)"
    echo "transition_animation_scale=$(sh_tv settings get global transition_animation_scale)"
    echo "animator_duration_scale=$(sh_tv settings get global animator_duration_scale)"
  } > "${f%.txt}.ajustes"
  verde "Respaldo guardado en: $f"
}

es_critico() { grep -qxF "$1" <(leer_lista "$LISTAS/nunca-tocar.txt"); }

desactivar() { # desactivar <paquete>
  local p="$1" salida
  if es_critico "$p"; then
    amarillo "  Salteado (crítico): $p"
    return
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [simulación] adb shell pm disable-user --user 0 $p"
    return
  fi
  salida="$(sh_tv pm disable-user --user 0 "$p")"
  if grep -qi 'disabled' <<<"$salida"; then
    verde "  Desactivado: $p"
    echo "$p" >> "$RESPALDOS/desactivados-por-script.txt"
  else
    amarillo "  No se pudo desactivar: $p (algunas marcas lo bloquean)"
  fi
}

# ---------------------------------------------------------------- acciones

limpiar_basura() {
  titulo "1. Quitar bloatware seguro"
  local todos encontrados=()
  todos="$(instalados)"
  while read -r p; do
    grep -qxF "$p" <<<"$todos" && encontrados+=("$p")
  done < <(leer_lista "$LISTAS/basura-segura.txt")

  if [[ ${#encontrados[@]} -eq 0 ]]; then
    verde "No se encontró nada de la lista en esta TV."
    return
  fi
  echo "Encontré ${#encontrados[@]} apps para desactivar:"
  printf '  - %s\n' "${encontrados[@]}"
  preguntar "¿Desactivarlas todas?" || return
  respaldar
  for p in "${encontrados[@]}"; do desactivar "$p"; done
}

limpiar_opcional() {
  titulo "2. Revisar apps opcionales (una por una)"
  local todos launcher_alt
  todos="$(instalados)"
  launcher_alt="$(launcher_actual)"
  respaldar
  local lineas linea p desc
  mapfile -t lineas < "$LISTAS/opcional.txt"
  for linea in "${lineas[@]}"; do
    p="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' <<<"$linea")"
    [[ -z "$p" ]] && continue
    grep -qxF "$p" <<<"$todos" || continue
    desc="$(sed -n 's/^[^#]*#[[:space:]]*//p' <<<"$linea")"
    if [[ "$p" =~ launcher && ( "$launcher_alt" == "$p" || "$launcher_alt" == "android" || -z "$launcher_alt" ) ]]; then
      amarillo "  $p es tu inicio actual. Primero instalá otro launcher (opción 4)."
      continue
    fi
    preguntar "  ¿Desactivar $p ($desc)?" && desactivar "$p"
  done
}

acelerar() {
  titulo "3. Acelerar la TV"
  respaldar
  echo "- Animaciones a 0.5x (la interfaz se siente el doble de rápida)"
  ejecutar settings put global window_animation_scale 0.5
  ejecutar settings put global transition_animation_scale 0.5
  ejecutar settings put global animator_duration_scale 0.5

  echo "- Limpiando caché de todas las apps"
  ejecutar pm trim-caches 999G >/dev/null

  if preguntar "- ¿Optimizar (compilar) todas las apps? Tarda 5-20 min, la TV puede ir lenta mientras."; then
    ejecutar cmd package compile -m speed-profile -a
  fi
  verde "Listo. Reiniciá la TV al terminar para notar el cambio (opción 7)."
}

launcher_actual() {
  sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN \
    -c android.intent.category.HOME | tail -1 | cut -d/ -f1
}

poner_launcher() {
  titulo "4. Diseño minimalista (launcher nuevo)"
  cat <<'EOF'
El "diseño" de la pantalla de inicio lo define el launcher. Recomendados, sin publicidad:

  a) Projectivy Launcher  - moderno, muy personalizable, el más popular (Play Store)
  b) FLauncher            - ultra minimalista y de código abierto (Play Store)

Instalá uno desde el Play Store de la TV (o pasá un .apk con: adb install archivo.apk)
y volvé a esta opción.
EOF
  local actual candidatos=() todos
  actual="$(launcher_actual)"
  echo "Inicio actual: ${actual:-desconocido}"
  todos="$(instalados)"
  for p in com.spocky.projengmenu me.efesser.flauncher; do
    grep -qxF "$p" <<<"$todos" && candidatos+=("$p")
  done
  if [[ ${#candidatos[@]} -eq 0 ]]; then
    amarillo "Todavía no hay ninguno de los dos instalado."
    return
  fi

  local elegido="${candidatos[0]}"
  [[ "$actual" == "$elegido" ]] && verde "$elegido ya es tu inicio predeterminado."
  preguntar "¿Usar $elegido como pantalla de inicio?" || return

  local comp
  comp="$(sh_tv cmd package resolve-activity --brief -a android.intent.action.MAIN \
           -c android.intent.category.HOME "$elegido" | tail -1)"
  if [[ "$comp" != */* ]]; then
    rojo "No encontré la actividad de inicio de $elegido."
    return
  fi
  respaldar
  ejecutar cmd package set-home-activity "$comp"

  # IMPORTANTE: NO desactivamos el inicio original de Google/TCL. En una TCL 32S5K
  # hacerlo dejó la TV trabada en el logo de Google TV y sin acceso a ADB.
  amarillo "Aviso: en Google TV el botón Home puede seguir abriendo el inicio original."
  echo "  Si pasa, en los ajustes de Projectivy buscá la opción para reemplazar el botón Home."
  echo "  Este script NO desactiva el inicio original porque puede dejar la TV sin arrancar."
  verde "Apretá el botón Home del control para ver el nuevo inicio."
}

auditar() {
  titulo "5. Ver todas las apps del fabricante (para revisar a mano)"
  echo "Apps de sistema que no son de Google ni de Android:"
  sh_tv pm list packages -s -e | sed 's/^package://' | sort \
    | grep -v -E '^(android|com\.android\.|com\.google\.)' | sed 's/^/  /'
  echo
  echo "Si encontrás alguna que sea publicidad o \"tienda\" de la marca, agregala"
  echo "a listas/basura-segura.txt y corré la opción 1. Buscala en Google antes."
}

restaurar() {
  titulo "6. Restaurar"
  local f="$RESPALDOS/desactivados-por-script.txt"
  if [[ -f "$f" ]]; then
    echo "Reactivando $(sort -u "$f" | wc -l | tr -d ' ') apps..."
    local p
    # shellcheck disable=SC2013  # los nombres de paquete no tienen espacios
    for p in $(sort -u "$f"); do
      ejecutar pm enable --user 0 "$p" >/dev/null && verde "  Activado: $p"
    done
    [[ "$DRY_RUN" == "1" ]] || mv "$f" "$f.restaurado-$(date +%s)"
  else
    echo "No hay apps desactivadas por este script."
  fi
  if preguntar "¿Volver las animaciones a velocidad normal (1x)?"; then
    ejecutar settings put global window_animation_scale 1
    ejecutar settings put global transition_animation_scale 1
    ejecutar settings put global animator_duration_scale 1
  fi
  verde "Restauración terminada. Reiniciá la TV."
}

# ---------------------------------------------------------------- menú

main() {
  conectar
  mkdir -p "$RESPALDOS"
  while true; do
    titulo "Optimizador de Android TV"
    cat <<'EOF'
  1) Quitar bloatware seguro (recomendado)
  2) Revisar apps opcionales una por una (Netflix, YouTube, asistente...)
  3) Acelerar: animaciones, caché y optimización de apps
  4) Diseño minimalista: instalar/activar un launcher nuevo
  5) Ver apps del fabricante para revisar a mano
  6) Restaurar todo lo que hizo este script
  7) Reiniciar la TV
  0) Salir
EOF
    local op
    read -r -p "Opción: " op
    case "$op" in
      1) limpiar_basura ;;
      2) limpiar_opcional ;;
      3) acelerar ;;
      4) poner_launcher ;;
      5) auditar ;;
      6) restaurar ;;
      7) if preguntar "¿Reiniciar ahora?"; then
           if [[ "$DRY_RUN" == "1" ]]; then echo "  [simulación] adb reboot"; else adb reboot; fi
         fi ;;
      0) exit 0 ;;
      *) amarillo "Opción inválida" ;;
    esac
  done
}

main
