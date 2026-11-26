#!/usr/bin/env bash
# ============================================================================
# wallpaper.sh - Wallpaper-Switcher für Hyprland (swaybg)
# ============================================================================
# - Default-Wallpaper für alle Bildschirme
# - Pro-Monitor-Overrides (z. B. für Zweit-/Drittschirme)
# - Wallpaper-Ordner werden automatisch eingelesen (neue Bilder einfach ablegen)
# - Menü (aco-menu) bei Aufruf ohne Argumente, Bildauswahl als Vorschau-Raster,
#   vollständige CLI mit Parametern
#
# Beispiele:
#   wallpaper                                  TUI öffnen
#   wallpaper list                             verfügbare Wallpapers anzeigen
#   wallpaper set forest.png                   Default setzen (alle ohne Override)
#   wallpaper set ocean.png --monitor eDP-1    Override für einen Monitor
#   wallpaper set city.png --all               überall setzen + Overrides löschen
#   wallpaper default forest.png               nur den Default setzen
#   wallpaper monitor DP-1 ocean.png           Monitor-Override setzen
#   wallpaper monitor DP-1 default             Override entfernen
#   wallpaper next | prev | random             durchwechseln
#   wallpaper current                          aktuelle Belegung anzeigen
#   wallpaper dirs                             Wallpaper-Ordner anzeigen
#   wallpaper add ~/Downloads/bild.jpg --set   Bild in die Bibliothek übernehmen
# ============================================================================
set -euo pipefail

# Symlink-Kette auflösen: ~/.local/bin/wallpaper -> ~/.config/wallpaper/wallpaper.sh
# -> ~/git/dotfiles/wallpaper/wallpaper.sh
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_FILE="${WALLPAPER_CONFIG:-$CONFIG_HOME/wallpaper/wallpaper.conf}"
STATE_DIR="$STATE_HOME/wallpaper"
STATE_FILE="$STATE_DIR/state"
# Laufende swaybg-Instanzen (eine pro Monitor): PID und Bild, nur für diese Sitzung.
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/wallpaper"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/aco/wallpaper"
# Das mitgelieferte ACO-Hintergrundbild: aco-theme rendert das SVG passend zu
# Hell/Dunkel und Akzent, hier wird es in ein PNG für swaybg umgewandelt.
GENERATED_SVG="$CONFIG_HOME/aco/theme/wallpaper/aco.svg"
GENERATED_DIR="$CACHE_DIR/generated"
THUMB_DIR="$CACHE_DIR/thumbnails"
# Link to the wallpaper of the first monitor; the lock screen (hyprlock) shows it.
CURRENT_LINK="$CACHE_DIR/current"

# Direkt aus dem Repository gestartet? Dann die Repo-Konfiguration verwenden.
if [[ ! -r "$CONFIG_FILE" && -r "$SCRIPT_DIR/wallpaper.conf" ]]; then
    CONFIG_FILE="$SCRIPT_DIR/wallpaper.conf"
fi

QUIET=0

# ----------------------------------------------------------------------------
# Ausgaben
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    BLUE='\033[1;34m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    RED='\033[1;31m'
    RESET='\033[0m'
else
    BLUE='' GREEN='' YELLOW='' RED='' RESET=''
fi

info()  { (( QUIET )) || printf "${BLUE}[INFO]${RESET}  %s\n" "$*"; }
ok()    { (( QUIET )) || printf "${GREEN}[OK]${RESET}    %s\n" "$*"; }
warn()  { (( QUIET )) || printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; }
die()   { error "$*"; exit 1; }

notify() {
    case "${WALLPAPER_NOTIFY:-1}" in
        0|false|no|off) return 0 ;;
    esac
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a Hintergrund -i preferences-desktop-wallpaper "Hintergrund" "$*" >/dev/null 2>&1 || true
}

# ----------------------------------------------------------------------------
# Konfiguration & Status
# ----------------------------------------------------------------------------
load_config() {
    WALLPAPER_DIRS=()
    WALLPAPER_FIT="cover"
    WALLPAPER_NOTIFY=1

    if [[ -r "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi

    if (( ${#WALLPAPER_DIRS[@]} == 0 )); then
        WALLPAPER_DIRS=("$DOTFILES_ROOT/pictures")
    fi
    # Das generierte ACO-Bild steht immer zuerst und ist damit der Default,
    # solange niemand ein eigenes Bild gewählt hat.
    ensure_generated
    WALLPAPER_DIRS=("$GENERATED_DIR" "${WALLPAPER_DIRS[@]}")

    # Mit "wallpaper dirs add" ergänzte Ordner (Status, nicht Konfiguration)
    local extra
    while IFS= read -r extra; do
        [[ -n "$extra" ]] && WALLPAPER_DIRS+=("$extra")
    done < <([[ -f "$STATE_FILE" ]] && awk -F '\t' '$1 == "dir" { print $2 }' "$STATE_FILE" || true)

    case "$WALLPAPER_FIT" in
        contain|cover|tile|fill) ;;
        *)
            warn "Ungültiger WALLPAPER_FIT '$WALLPAPER_FIT' – verwende 'cover'."
            WALLPAPER_FIT="cover"
            ;;
    esac
}

# Größte Pixelfläche der angeschlossenen Monitore (Fallback 3840x2160 ohne Hyprland).
largest_monitor_size() {
    hyprctl monitors -j 2>/dev/null \
        | jq -r 'max_by(.width * .height) | "\(.width)x\(.height)"' 2>/dev/null \
        || echo 3840x2160
}

# SVG -> PNG in Monitorgröße, nur wenn sich SVG (Theme-Wechsel) oder Größe geändert haben.
ensure_generated() {
    local png="$GENERATED_DIR/aco.png" size_file="$GENERATED_DIR/aco.size" size
    [[ -r "$GENERATED_SVG" ]] || return 0
    size="$(largest_monitor_size)"
    [[ "$size" =~ ^[0-9]+x[0-9]+$ ]] || size=3840x2160
    if [[ -f "$png" && "$png" -nt "$GENERATED_SVG" && "$(cat "$size_file" 2>/dev/null)" == "$size" ]]; then
        return 0
    fi
    command -v rsvg-convert >/dev/null 2>&1 || { warn "rsvg-convert fehlt – ACO-Hintergrund nicht verfügbar."; return 0; }
    mkdir -p "$GENERATED_DIR"
    if rsvg-convert --width "${size%x*}" --height "${size#*x}" --output "$png.tmp" "$GENERATED_SVG"; then
        mv -f "$png.tmp" "$png"
        printf '%s\n' "$size" > "$size_file"
    else
        rm -f "$png.tmp"
        warn "ACO-Hintergrund konnte nicht erzeugt werden."
    fi
}

state_init() {
    mkdir -p "$STATE_DIR"
    [[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"
}

state_default_get() {
    state_init
    awk -F '\t' '$1 == "default" { print $2; exit }' "$STATE_FILE"
}

state_monitor_get() {
    state_init
    awk -F '\t' -v m="$1" '$1 == "monitor" && $2 == m { print $3; exit }' "$STATE_FILE"
}

state_set_default() {
    state_init
    local value="$1" tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    awk -F '\t' -v OFS='\t' -v val="$value" '
        $1 != "default" { print }
        END { print "default", val }
    ' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

state_set_monitor() {
    state_init
    local monitor="$1" value="$2" tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    awk -F '\t' -v OFS='\t' -v mon="$monitor" -v val="$value" '
        !($1 == "monitor" && $2 == mon) { print }
        END { print "monitor", mon, val }
    ' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

state_clear_monitor() {
    state_init
    local monitor="$1" tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    awk -F '\t' -v mon="$monitor" '!($1 == "monitor" && $2 == mon)' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

state_clear_monitors() {
    state_init
    local tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    awk -F '\t' '$1 != "monitor"' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Darstellung (Fit) und zusätzliche Ordner liegen ebenfalls im Status, damit die
# Konfigurationsdatei nie vom Skript verändert wird:
#   fit<TAB>MODE                  globaler Fit-Modus
#   monitorfit<TAB>MON<TAB>MODE   Fit-Modus eines Monitors
#   dir<TAB>PFAD                  zusätzlicher Wallpaper-Ordner
state_fit_get() {
    state_init
    awk -F '\t' '$1 == "fit" { print $2; exit }' "$STATE_FILE"
}

state_monitor_fit_get() {
    state_init
    awk -F '\t' -v m="$1" '$1 == "monitorfit" && $2 == m { print $3; exit }' "$STATE_FILE"
}

state_set_fit() {
    state_init
    local tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    awk -F '\t' -v OFS='\t' -v val="$1" '$1 != "fit" { print } END { print "fit", val }' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

state_set_monitor_fit() {
    state_init
    local tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    awk -F '\t' -v OFS='\t' -v mon="$1" -v val="$2" \
        '!($1 == "monitorfit" && $2 == mon) { print } END { print "monitorfit", mon, val }' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

state_clear_fit() {  # $1 = Monitor oder leer (alle Overrides + globaler Wert)
    state_init
    local tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    if [[ -n "${1:-}" ]]; then
        awk -F '\t' -v mon="$1" '!($1 == "monitorfit" && $2 == mon)' "$STATE_FILE" > "$tmp"
    else
        awk -F '\t' '$1 != "fit" && $1 != "monitorfit"' "$STATE_FILE" > "$tmp"
    fi
    mv "$tmp" "$STATE_FILE"
}

valid_fit() { [[ "${1:-}" =~ ^(cover|contain|tile|fill)$ ]]; }

# Wirksamer Fit: Monitor-Override > globaler Status > wallpaper.conf
effective_fit() {
    local fit=""
    [[ -n "${1:-}" ]] && fit="$(state_monitor_fit_get "$1")"
    [[ -z "$fit" ]] && fit="$(state_fit_get)"
    valid_fit "$fit" || fit="$WALLPAPER_FIT"
    printf '%s' "$fit"
}

state_dirs_get() {
    state_init
    awk -F '\t' '$1 == "dir" { print $2 }' "$STATE_FILE"
}

state_dir_add() {
    state_init
    state_dirs_get | grep -qxF -- "$1" && return 0
    printf 'dir\t%s\n' "$1" >> "$STATE_FILE"
}

state_dir_remove() {
    state_init
    local tmp
    tmp="$(mktemp "$STATE_DIR/.state.XXXXXX")"
    awk -F '\t' -v d="$1" '!($1 == "dir" && $2 == d)' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# ----------------------------------------------------------------------------
# Wallpaper-Bibliothek
# ----------------------------------------------------------------------------
list_wallpapers() {
    local entry f root rel abs id parent
    local -A seen_abs=()
    local -A seen_id=()

    for entry in "${WALLPAPER_DIRS[@]}"; do
        entry="${entry/#\~/$HOME}"
        local -a matches=()

        if [[ -d "$entry" ]]; then
            root="$(readlink -f -- "$entry" 2>/dev/null || printf '%s' "$entry")"
            while IFS= read -r -d '' f; do
                matches+=("$f")
            done < <(find "$root" \( -type f -o -type l \) \( \
                -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o \
                -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' -o \
                -iname '*.avif' -o -iname '*.jxl' -o -iname '*.tif' -o \
                -iname '*.tiff' \) -print0 2>/dev/null)
        elif [[ -f "$entry" ]]; then
            matches=("$entry")
            root=""
        else
            # Dateimuster wie /usr/share/hypr/wall*.png unterstützen
            while IFS= read -r f; do
                [[ -f "$f" ]] && matches+=("$f")
            done < <(compgen -G "$entry" || true)
            root=""
        fi

        for f in "${matches[@]}"; do
            abs="$(readlink -f -- "$f" 2>/dev/null)" || continue
            [[ -f "$abs" ]] || continue
            [[ -n "${seen_abs[$abs]:-}" ]] && continue
            seen_abs[$abs]=1

            if [[ -n "$root" && "$abs" == "$root"/* ]]; then
                rel="${abs#"$root"/}"
            else
                rel="$(basename -- "$abs")"
            fi

            # Doppelte Anzeigenamen eindeutig machen
            id="$rel"
            if [[ -n "${seen_id[$id]:-}" ]]; then
                parent="$(basename -- "$(dirname -- "$abs")")"
                id="$parent/$rel"
                [[ -n "${seen_id[$id]:-}" ]] && id="$abs"
            fi

            # Tabs/Zeilenumbrüche würden das Zustandsformat zerstören
            [[ "$id" == *$'\t'* || "$id" == *$'\n'* ]] && continue
            seen_id[$id]=1

            printf '%s\t%s\n' "$id" "$abs"
        done
    done | LC_ALL=C sort -t $'\t' -k1,1
}

first_wallpaper_id() {
    list_wallpapers | awk -F '\t' 'NR == 1 { print $1; exit }'
}

resolve_wallpaper() {
    local query="${1-}"
    [[ -n "$query" ]] || return 1

    local expanded="${query/#\~/$HOME}"
    if [[ -f "$expanded" ]]; then
        readlink -f -- "$expanded"
        return 0
    fi

    local -a exact=() base=() substr=()
    local id abs b

    while IFS=$'\t' read -r id abs; do
        [[ -z "$id" ]] && continue

        if [[ "$id" == "$query" ]]; then
            exact+=("$abs")
            continue
        fi

        b="$(basename -- "$id")"
        [[ "$b" == "$query" ]] && base+=("$abs")
        [[ "${id,,}" == *"${query,,}"* ]] && substr+=("$abs")
    done < <(list_wallpapers)

    if (( ${#exact[@]} == 1 )); then
        printf '%s\n' "${exact[0]}"
        return 0
    fi

    if (( ${#base[@]} == 1 )); then
        printf '%s\n' "${base[0]}"
        return 0
    fi

    if (( ${#base[@]} > 1 )); then
        error "Mehrere Wallpapers heißen '$query':"
        printf '  %s\n' "${base[@]}" >&2
        return 2
    fi

    if (( ${#substr[@]} == 1 )); then
        printf '%s\n' "${substr[0]}"
        return 0
    fi

    if (( ${#substr[@]} > 1 )); then
        error "Mehrdeutige Suche '$query'. Bitte präzisieren:"
        printf '  %s\n' "${substr[@]}" >&2
        return 2
    fi

    error "Wallpaper '$query' nicht gefunden."
    return 1
}

id_for_path() {
    local target id abs
    target="$(readlink -f -- "$1" 2>/dev/null || printf '%s' "$1")"

    while IFS=$'\t' read -r id abs; do
        if [[ "$abs" == "$target" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    done < <(list_wallpapers)

    printf '%s\n' "$target"
}

ensure_default() {
    local id
    id="$(state_default_get)"

    if [[ -n "$id" ]] && resolve_wallpaper "$id" >/dev/null 2>&1; then
        printf '%s\n' "$id"
        return 0
    fi

    if [[ -n "$id" ]]; then
        warn "Default-Wallpaper '$id' wurde nicht gefunden – wähle das erste verfügbare."
    fi

    id="$(first_wallpaper_id)"
    if [[ -z "$id" ]]; then
        die "Keine Wallpapers gefunden. Lege Bilder in einem dieser Ordner ab: ${WALLPAPER_DIRS[*]}"
    fi

    state_set_default "$id"
    printf '%s\n' "$id"
}

# ----------------------------------------------------------------------------
# Hyprpaper / Monitore
# ----------------------------------------------------------------------------
get_monitors() {
    command -v hyprctl >/dev/null 2>&1 || die "hyprctl nicht gefunden – läuft Hyprland?"
    hyprctl monitors -j 2>/dev/null | jq -r '.[].name' \
        || die "Monitore konnten nicht über hyprctl ermittelt werden."
}

monitor_exists() {
    local monitor="$1"
    get_monitors | grep -Fxq -- "$monitor"
}

# swaybg-Darstellung zum Fit-Modus
swaybg_mode() {
    case "$1" in
        cover) echo fill ;;
        contain) echo fit ;;
        fill) echo stretch ;;
        tile) echo tile ;;
    esac
}

# Neues Bild auf einem Monitor: erst die neue swaybg-Instanz starten, dann die
# alte beenden, damit nie ein leerer Hintergrund aufblitzt.
wallpaper_set() {
    local monitor="$1" path="$2" old_pid="" pid lock
    command -v swaybg >/dev/null 2>&1 || die "swaybg ist nicht installiert: sudo pacman -S swaybg"
    mkdir -p "$RUN_DIR"
    # Hyprland-Start und monitor.added rufen "apply" gleichzeitig auf: pro Monitor
    # darf nur einer die Instanz tauschen, sonst laufen zwei swaybg nebeneinander.
    exec {lock}>"$RUN_DIR/$monitor.lock"
    flock "$lock"
    [[ -f "$RUN_DIR/$monitor.pid" ]] && old_pid="$(<"$RUN_DIR/$monitor.pid")"
    # swaybg must not inherit the lock, or it would hold it for its whole lifetime.
    setsid swaybg -o "$monitor" -i "$path" -m "$(swaybg_mode "$(effective_fit "$monitor")")" >/dev/null 2>&1 < /dev/null {lock}>&- &
    pid=$!
    # Die alte Instanz erst beenden, wenn die neue sicher läuft.
    sleep 0.5
    if ! kill -0 "$pid" 2>/dev/null; then
        warn "swaybg konnte auf $monitor nicht starten – altes Bild bleibt."
        exec {lock}>&-
        return 1
    fi
    printf '%s\n' "$pid" > "$RUN_DIR/$monitor.pid"
    printf '%s\n' "$path" > "$RUN_DIR/$monitor.path"
    [[ "$monitor" == "$(get_monitors | head -n 1)" ]] && record_primary "$path"
    if [[ -n "$old_pid" && "$old_pid" != "$pid" ]]; then
        kill "$old_pid" 2>/dev/null || true
    fi
    exec {lock}>&-
}

# The first monitor's wallpaper decides the bar style (light or dark text, see
# `aco-theme bar`) and is what the lock screen shows. The tone is the mean
# brightness of the top edge, where the bar sits.
record_primary() {
    local path="$1" mean tone
    mkdir -p "$CACHE_DIR"
    ln -sfn "$path" "$CURRENT_LINK"
    command -v magick >/dev/null 2>&1 && command -v aco-theme >/dev/null 2>&1 || return 0
    mean="$(magick "$path" -resize 256x -gravity North -crop 100%x5%+0+0 +repage \
        -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null)" || return 0
    tone="$(awk -v m="$mean" 'BEGIN { print (m > 0.55) ? "light" : "dark" }')"
    aco-theme --quiet bar tone "$tone" || true
}

apply_monitor() {
    local monitor="$1" default_id="$2"
    local id abs

    id="$(state_monitor_get "$monitor")"
    [[ -z "$id" ]] && id="$default_id"

    if ! abs="$(resolve_wallpaper "$id" 2>/dev/null)"; then
        warn "Wallpaper '$id' für $monitor nicht gefunden – verwende Default '$default_id'."
        abs="$(resolve_wallpaper "$default_id" 2>/dev/null)" \
            || die "Auch das Default-Wallpaper '$default_id' ist nicht mehr verfügbar."
    fi

    if ! wallpaper_set "$monitor" "$abs"; then
        warn "Konnte das Wallpaper für $monitor nicht setzen (Monitor noch nicht bereit?)."
        return 0
    fi
    ok "$monitor: $(basename -- "$abs")"
}

apply_all() {
    local default_id
    default_id="$(ensure_default)"
    resolve_wallpaper "$default_id" >/dev/null 2>&1 \
        || die "Default-Wallpaper '$default_id' ist nicht mehr verfügbar."

    local -a monitors=()
    mapfile -t monitors < <(get_monitors)
    (( ${#monitors[@]} > 0 )) || die "Keine Monitore gefunden."

    local m
    for m in "${monitors[@]}"; do
        apply_monitor "$m" "$default_id"
    done
}

apply_monitor_only() {
    local monitor="$1"
    monitor_exists "$monitor" || die "Monitor '$monitor' nicht gefunden. Verfügbar: $(get_monitors | paste -sd ', ' -)"

    local default_id
    default_id="$(ensure_default)"
    apply_monitor "$monitor" "$default_id"
}

# ----------------------------------------------------------------------------
# Aktionen
# ----------------------------------------------------------------------------
apply_choice() {
    local query="$1" target="$2"
    local abs id

    if [[ "$query" == "__reset__" ]]; then
        [[ "$target" == "__all__" || "$target" == "all" || "$target" == "__default__" ]] \
            && die "Für dieses Ziel gibt es keinen Monitor-Override zum Entfernen."
        monitor_exists "$target" || die "Monitor '$target' nicht gefunden."
        state_clear_monitor "$target"
        apply_monitor_only "$target"
        notify "$target: Default"
        return 0
    fi

    abs="$(resolve_wallpaper "$query")" || exit 1
    id="$(id_for_path "$abs")"

    case "$target" in
        __all__|all)
            state_set_default "$id"
            state_clear_monitors
            apply_all
            notify "Wallpaper überall: $(basename -- "$abs")"
            ;;
        __default__|default)
            state_set_default "$id"
            apply_all
            notify "Default-Wallpaper: $(basename -- "$abs")"
            ;;
        *)
            monitor_exists "$target" || die "Monitor '$target' nicht gefunden. Verfügbar: $(get_monitors | paste -sd ', ' -)"
            state_set_monitor "$target" "$id"
            apply_monitor_only "$target"
            notify "$target: $(basename -- "$abs")"
            ;;
    esac
}

cmd_set() {
    local target="default" query=""

    while (( $# > 0 )); do
        case "$1" in
            --monitor|-m)
                [[ $# -ge 2 ]] || die "Option $1 benötigt einen Monitor-Namen."
                target="$2"
                shift 2
                ;;
            --all|-a)
                target="all"
                shift
                ;;
            --)
                shift
                query="${1-}"
                shift || true
                ;;
            -*)
                die "Unbekannte Option: $1"
                ;;
            *)
                [[ -z "$query" ]] || die "Es wurde mehr als ein Wallpaper angegeben."
                query="$1"
                shift
                ;;
        esac
    done

    [[ -n "$query" ]] || die "Verwendung: wallpaper set <name|pfad> [--monitor MON | --all]"
    apply_choice "$query" "$target"
}

cmd_default() {
    if (( $# == 0 )); then
        local id abs
        id="$(ensure_default)"
        abs="$(resolve_wallpaper "$id" 2>/dev/null || true)"
        printf 'Default: %s\n' "$id"
        printf 'Pfad:    %s\n' "${abs:-nicht gefunden}"
        return 0
    fi

    [[ $# == 1 ]] || die "Verwendung: wallpaper default [<name|pfad>]"
    apply_choice "$1" "default"
}

cmd_monitor() {
    local monitor="${1-}" query="${2-}"

    [[ -n "$monitor" ]] || die "Verwendung: wallpaper monitor <MON> [<name|pfad>|default]"
    monitor_exists "$monitor" || die "Monitor '$monitor' nicht gefunden. Verfügbar: $(get_monitors | paste -sd ', ' -)"

    if [[ -z "$query" ]]; then
        local default_id override effective
        default_id="$(ensure_default)"
        override="$(state_monitor_get "$monitor")"
        effective="${override:-$default_id}"
        printf 'Monitor:  %s\n' "$monitor"
        printf 'Eigenes:  %s\n' "${override:-– (nutzt Default)}"
        printf 'Effektiv: %s\n' "$effective"
        return 0
    fi

    case "$query" in
        default|clear|-)
            state_clear_monitor "$monitor"
            apply_monitor_only "$monitor"
            notify "$monitor: Default"
            ;;
        *)
            apply_choice "$query" "$monitor"
            ;;
    esac
}

cmd_clear() {
    local target="${1-}"

    [[ -n "$target" ]] || die "Verwendung: wallpaper clear <MON> | --all"

    if [[ "$target" == "--all" || "$target" == "all" ]]; then
        state_clear_monitors
        apply_all
        notify "Monitor-Overrides entfernt"
        return 0
    fi

    monitor_exists "$target" || die "Monitor '$target' nicht gefunden."
    state_clear_monitor "$target"
    apply_monitor_only "$target"
    notify "$target: Default"
}

cmd_apply() {
    local only=""

    while (( $# > 0 )); do
        case "$1" in
            --quiet|-q)
                QUIET=1
                shift
                ;;
            --monitor|-m)
                [[ $# -ge 2 ]] || die "Option $1 benötigt einen Monitor-Namen."
                only="$2"
                shift 2
                ;;
            *)
                die "Unbekannte Option: $1"
                ;;
        esac
    done

    if [[ -n "$only" ]]; then
        apply_monitor_only "$only"
    else
        apply_all
    fi
}

cmd_current() {
    local default_id m override effective active source
    default_id="$(ensure_default)"

    printf 'Default: %s\n\n' "$default_id"
    printf '%-14s %-9s %s\n' "MONITOR" "QUELLE" "AKTIV"
    printf '%-14s %-9s %s\n' "-------" "------" "-----"

    while IFS= read -r m; do
        override="$(state_monitor_get "$m")"
        effective="${override:-$default_id}"
        source="Default"
        [[ -n "$override" ]] && source="Eigenes"

        active=""
        if [[ -f "$RUN_DIR/$m.pid" ]] && kill -0 "$(<"$RUN_DIR/$m.pid")" 2>/dev/null; then
            active="$(<"$RUN_DIR/$m.path")"
        fi

        printf '%-14s %-9s %s\n' "$m" "$source" "${active:-– (swaybg nicht aktiv)}"
        [[ -n "$active" ]] || printf '%-14s %-9s %s\n' "" "" "gespeichert: $effective"
    done < <(get_monitors)
}

cmd_list() {
    local monitor="" plain=0

    while (( $# > 0 )); do
        case "$1" in
            --monitor|-m)
                [[ $# -ge 2 ]] || die "Option $1 benötigt einen Monitor-Namen."
                monitor="$2"
                shift 2
                ;;
            --plain|-p)
                plain=1
                shift
                ;;
            *)
                die "Unbekannte Option: $1"
                ;;
        esac
    done

    local default_id
    default_id="$(ensure_default)"
    if [[ -n "$monitor" ]]; then
        monitor_exists "$monitor" || die "Monitor '$monitor' nicht gefunden. Verfügbar: $(get_monitors | paste -sd ', ' -)"
    fi

    state_init
    local -A overrides=()
    local kind mon val
    while IFS=$'\t' read -r kind mon val; do
        [[ "$kind" == "monitor" ]] || continue
        [[ -n "$monitor" && "$mon" != "$monitor" ]] && continue
        if [[ -n "${overrides[$val]:-}" ]]; then
            overrides[$val]+=", $mon"
        else
            overrides[$val]="$mon"
        fi
    done < "$STATE_FILE"

    local id abs found=0 marks
    while IFS=$'\t' read -r id abs; do
        found=1
        if (( plain )); then
            printf '%s\n' "$id"
            continue
        fi

        marks=""
        [[ "$id" == "$default_id" ]] && marks+="★"
        [[ -n "${overrides[$id]:-}" ]] && marks+="●"
        [[ -z "$marks" ]] && marks=" "

        printf '%s %s' "$marks" "$id"
        if [[ -n "${overrides[$id]:-}" ]]; then
            printf '  (%s)' "${overrides[$id]}"
        fi
        printf '\n'
    done < <(list_wallpapers)

    if (( ! found )); then
        error "Keine Wallpapers gefunden. Durchsuchte Ordner: ${WALLPAPER_DIRS[*]}"
        return 1
    fi
}

current_id_for_target() {
    local target="$1" id
    case "$target" in
        __all__|all|default|__default__)
            ensure_default
            ;;
        *)
            id="$(state_monitor_get "$target")"
            [[ -n "$id" ]] || id="$(ensure_default)"
            printf '%s\n' "$id"
            ;;
    esac
}

cmd_cycle() {
    local direction="$1" target="default"
    shift

    while (( $# > 0 )); do
        case "$1" in
            --monitor|-m)
                [[ $# -ge 2 ]] || die "Option $1 benötigt einen Monitor-Namen."
                target="$2"
                shift 2
                ;;
            --all|-a)
                target="all"
                shift
                ;;
            *)
                die "Unbekannte Option: $1"
                ;;
        esac
    done

    local -a ids=()
    mapfile -t ids < <(list_wallpapers | cut -f1)
    (( ${#ids[@]} > 0 )) || die "Keine Wallpapers gefunden."

    local current idx=-1 i
    current="$(current_id_for_target "$target")"
    for i in "${!ids[@]}"; do
        if [[ "${ids[$i]}" == "$current" ]]; then
            idx="$i"
            break
        fi
    done

    if (( idx < 0 )); then
        idx=0
    elif [[ "$direction" == "next" ]]; then
        idx=$(( (idx + 1) % ${#ids[@]} ))
    else
        idx=$(( (idx - 1 + ${#ids[@]}) % ${#ids[@]} ))
    fi

    apply_choice "${ids[$idx]}" "$target"
}

cmd_random() {
    local target="default"

    while (( $# > 0 )); do
        case "$1" in
            --monitor|-m)
                [[ $# -ge 2 ]] || die "Option $1 benötigt einen Monitor-Namen."
                target="$2"
                shift 2
                ;;
            --all|-a)
                target="all"
                shift
                ;;
            *)
                die "Unbekannte Option: $1"
                ;;
        esac
    done

    local -a ids=()
    mapfile -t ids < <(list_wallpapers | cut -f1)
    (( ${#ids[@]} > 0 )) || die "Keine Wallpapers gefunden."

    local idx=$(( RANDOM % ${#ids[@]} ))
    apply_choice "${ids[$idx]}" "$target"
}

cmd_dirs() {
    case "${1:-list}" in
        add)
            [[ -n "${2:-}" ]] || die "Verwendung: wallpaper dirs add <ordner>"
            local dir="${2/#\~/$HOME}"
            [[ -d "$dir" ]] || die "Ordner '$dir' existiert nicht."
            dir="$(readlink -f -- "$dir")"
            state_dir_add "$dir"
            ok "Ordner hinzugefügt: $dir"
            return 0
            ;;
        remove|rm)
            [[ -n "${2:-}" ]] || die "Verwendung: wallpaper dirs remove <ordner>"
            local dir="${2/#\~/$HOME}"
            dir="$(readlink -f -- "$dir" 2>/dev/null || printf '%s' "$dir")"
            state_dir_remove "$dir"
            ok "Ordner entfernt (nur aus der Liste, nichts gelöscht): $dir"
            return 0
            ;;
        list|"") ;;
        *) die "Verwendung: wallpaper dirs [list | add <ordner> | remove <ordner>]" ;;
    esac

    printf 'Konfiguration: %s\n' "$CONFIG_FILE"
    printf 'Status:        %s\n' "$STATE_FILE"
    printf 'Fit-Modus:     %s (Konfiguration: %s)\n\n' "$(effective_fit "")" "$WALLPAPER_FIT"
    printf 'Wallpaper-Quellen:\n'

    local entry
    for entry in "${WALLPAPER_DIRS[@]}"; do
        entry="${entry/#\~/$HOME}"
        if [[ -d "$entry" ]]; then
            printf '  ✓ %s\n' "$entry"
        elif compgen -G "$entry" >/dev/null 2>&1; then
            printf '  ✓ %s (Dateimuster)\n' "$entry"
        else
            printf '  ✗ %s (fehlt)\n' "$entry"
        fi
    done
}

# wallpaper fit                         Darstellung anzeigen
# wallpaper fit MODE                    globalen Modus setzen (cover|contain|tile|fill)
# wallpaper fit MODE --monitor MON      Modus nur für einen Monitor
# wallpaper fit default [--monitor MON] Override bzw. alle Anpassungen entfernen
cmd_fit() {
    local mode="" monitor=""
    while (( $# > 0 )); do
        case "$1" in
            --monitor|-m)
                [[ $# -ge 2 ]] || die "Option $1 benötigt einen Monitor-Namen."
                monitor="$2"; shift 2 ;;
            *) [[ -z "$mode" ]] || die "Unbekannte Option: $1"; mode="$1"; shift ;;
        esac
    done

    if [[ -z "$mode" ]]; then
        printf 'Global: %s\n' "$(effective_fit "")"
        local m own
        while IFS= read -r m; do
            own="$(state_monitor_fit_get "$m")"
            printf '%-14s %s%s\n' "$m" "$(effective_fit "$m")" "${own:+  (eigener Modus)}"
        done < <(get_monitors)
        return 0
    fi

    [[ -z "$monitor" ]] || monitor_exists "$monitor" || die "Monitor '$monitor' nicht gefunden. Verfügbar: $(get_monitors | paste -sd ', ' -)"
    if [[ "$mode" == "default" ]]; then
        state_clear_fit "$monitor"
    else
        valid_fit "$mode" || die "Ungültiger Modus '$mode'. Erlaubt: cover, contain, tile, fill, default."
        if [[ -n "$monitor" ]]; then state_set_monitor_fit "$monitor" "$mode"; else state_set_fit "$mode"; fi
    fi
    if [[ -n "$monitor" ]]; then apply_monitor_only "$monitor"; else apply_all; fi
    notify "Darstellung: ${monitor:-alle} → $mode"
}

cmd_add() {
    local move=0 set_after=0
    local -a files=()

    while (( $# > 0 )); do
        case "$1" in
            --move|-m)
                move=1
                shift
                ;;
            --set|-s)
                set_after=1
                shift
                ;;
            -*)
                die "Unbekannte Option: $1"
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done

    (( ${#files[@]} > 0 )) || die "Verwendung: wallpaper add <datei>... [--move] [--set]"

    local default_dir="$DOTFILES_ROOT/pictures"
    local dest="${WALLPAPER_DIRS[0]:-$default_dir}"
    dest="${dest/#\~/$HOME}"
    if [[ -f "$dest" || "$dest" == *'*'* || "$dest" == *'?'* || "$dest" == *'['* ]]; then
        dest="$default_dir"
    fi
    mkdir -p "$dest"

    local f target name base ext i
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || { warn "Überspringe '$f' (keine Datei)."; continue; }

        target="$dest/$(basename -- "$f")"
        if [[ -e "$target" ]]; then
            name="$(basename -- "$target")"
            if [[ "$name" == *.* && "$name" != .* ]]; then
                base="${target%.*}"
                ext=".${target##*.}"
            else
                base="$target"
                ext=""
            fi
            i=1
            while [[ -e "${base}-${i}${ext}" ]]; do
                i=$(( i + 1 ))
            done
            target="${base}-${i}${ext}"
        fi

        if (( move )); then
            mv -- "$f" "$target"
        else
            cp -- "$f" "$target"
        fi
        ok "Hinzugefügt: $target"

        if (( set_after )); then
            apply_choice "$target" "default"
        fi
    done
}

cmd_open() {
    local default_dir="$DOTFILES_ROOT/pictures"
    local dir="${WALLPAPER_DIRS[0]:-$default_dir}"
    dir="${dir/#\~/$HOME}"
    [[ -d "$dir" ]] || dir="$default_dir"
    mkdir -p "$dir"

    if command -v pcmanfm >/dev/null 2>&1; then
        setsid pcmanfm "$dir" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
        setsid xdg-open "$dir" >/dev/null 2>&1 &
    else
        die "Kein Dateimanager gefunden (pcmanfm/xdg-open)."
    fi
}

cmd_reload() {
    info "Starte swaybg neu..."
    pkill -x swaybg >/dev/null 2>&1 || true
    rm -f "$RUN_DIR"/*.pid "$RUN_DIR"/*.path
    apply_all
}

cmd_doctor() {
    printf 'Wallpaper-Switcher\n'
    printf '  Konfiguration: %s\n' "$CONFIG_FILE"
    printf '  Status:        %s\n' "$STATE_FILE"
    printf '  Fit-Modus:     %s\n' "$WALLPAPER_FIT"
    printf '  Wallpapers:    %s\n' "$(list_wallpapers | wc -l)"
    printf '\nProgramme:\n'

    local c
    for c in hyprctl swaybg rsvg-convert magick jq aco-menu; do
        if command -v "$c" >/dev/null 2>&1; then
            printf '  ✓ %-10s %s\n' "$c" "$(command -v "$c")"
        else
            printf '  ✗ %-10s fehlt\n' "$c"
        fi
    done

    printf '\nLaufzeit:\n'
    if pgrep -x swaybg >/dev/null 2>&1; then
        printf '  ✓ swaybg läuft (PID %s)\n' "$(pgrep -x swaybg | paste -sd ',' -)"
    else
        printf '  ✗ swaybg läuft nicht\n'
    fi

    if command -v hyprctl >/dev/null 2>&1; then
        printf '\nMonitore:\n'
        get_monitors | sed 's/^/  - /' || true
    fi
}

# ----------------------------------------------------------------------------
# Menüs (aco-menu)
# ----------------------------------------------------------------------------
# Kleine 16:9-Vorschau für das Raster, im Cache nach Pfad und Änderungszeit.
thumbnail() {
    local src="$1" key thumb
    key="$(printf '%s %s' "$src" "$(stat -c %Y -- "$src")" | md5sum | cut -c1-16)"
    thumb="$THUMB_DIR/$key.png"
    if [[ ! -f "$thumb" ]]; then
        mkdir -p "$THUMB_DIR"
        magick "${src}[0]" -thumbnail 384x216^ -gravity center -extent 384x216 "$thumb" 2>/dev/null \
            || { printf '%s' "$src"; return; }
    fi
    printf '%s' "$thumb"
}

choose_from_menu() {
    local prompt="$1" placeholder="$2" data="$3" width="$4" lines="$5"
    local display chosen

    display="$(printf '%s' "$data" | cut -f2-)"
    [[ -n "$display" ]] || return 1

    chosen="$(printf '%s\n' "$display" | aco-menu \
        --prompt "$prompt" \
        --placeholder "$placeholder" \
        --width "$width" \
        --lines "$lines")" || return 1

    [[ -n "$chosen" ]] || return 1
    awk -F '\t' -v sel="$chosen" '$2 == sel { print $1; exit }' <<< "$data"
}

# Menü: Darstellung (Fit) für alle Bildschirme oder einen Monitor wählen
tui_fit() {
    local mode_data fit_mode fit_target m
    mode_data="cover"$'\t'"cover    – füllt den Bildschirm, beschneidet bei Bedarf"$'\n'
    mode_data+="contain"$'\t'"contain  – zeigt das ganze Bild, mit Rändern"$'\n'
    mode_data+="fill"$'\t'"fill     – streckt auf die Bildschirmgröße"$'\n'
    mode_data+="tile"$'\t'"tile     – kachelt das Bild"$'\n'
    mode_data+="default"$'\t'"↺  Zurück zur Konfiguration"$'\n'
    fit_mode="$(choose_from_menu "Darstellung: " "Modus wählen..." "$mode_data" 40 6)" || return 0
    [[ -n "$fit_mode" ]] || return 0

    local target_data="__all__"$'\t'"󰍹  Alle Bildschirme"$'\n'
    while IFS= read -r m; do
        target_data+="$m"$'\t'"󰍹  $m  ·  jetzt: $(effective_fit "$m")"$'\n'
    done < <(get_monitors)
    fit_target="$(choose_from_menu "Darstellung $fit_mode für: " "Ziel wählen..." "$target_data" 40 6)" || return 0
    [[ -n "$fit_target" ]] || return 0

    if [[ "$fit_target" == "__all__" ]]; then
        cmd_fit "$fit_mode"
    else
        cmd_fit "$fit_mode" --monitor "$fit_target"
    fi
}

cmd_tui() {
    command -v aco-menu >/dev/null 2>&1 || die "aco-menu ist nicht installiert (Paket aco-arch-dotfiles-rofi)."
    [[ -n "${WAYLAND_DISPLAY:-}" || -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] \
        || die "Die TUI benötigt eine laufende Hyprland-Session (oder nutze die CLI, z. B. 'wallpaper list')."

    local only_monitor=""
    while (( $# > 0 )); do
        case "$1" in
            --monitor|-m)
                [[ $# -ge 2 ]] || die "Option $1 benötigt einen Monitor-Namen."
                only_monitor="$2"
                shift 2
                ;;
            *)
                die "Unbekannte Option: $1"
                ;;
        esac
    done

    local default_id target data m override
    default_id="$(ensure_default)"

    if [[ -n "$only_monitor" ]]; then
        monitor_exists "$only_monitor" || die "Monitor '$only_monitor' nicht gefunden."
        target="$only_monitor"
    elif (( $(get_monitors | wc -l) == 1 )); then
        # Nur ein Bildschirm: keine Zielfrage, direkt zum Raster.
        target="__all__"
    else
        data="__all__"$'\t'"󰍹  Alle Bildschirme (einheitlich)  ·  $default_id"$'\n'
        data+="__default__"$'\t'"★  Nur Default (Overrides behalten)  ·  $default_id"$'\n'
        while IFS= read -r m; do
            override="$(state_monitor_get "$m")"
            if [[ -n "$override" ]]; then
                data+="$m"$'\t'"󰍹  $m  ·  Eigenes: $override"$'\n'
            else
                data+="$m"$'\t'"󰍹  $m  ·  Default: $default_id"$'\n'
            fi
        done < <(get_monitors)

        data+="__fit__"$'\t'"󰹑  Darstellung ändern (Fit)…"$'\n'

        target="$(choose_from_menu "Ziel wählen: " "Bildschirm oder alle..." "$data" 40 8)" || exit 0
        [[ -n "$target" ]] || exit 0

        if [[ "$target" == "__fit__" ]]; then
            tui_fit
            return
        fi
    fi

    local -a ids=()
    mapfile -t ids < <(list_wallpapers | cut -f1)
    (( ${#ids[@]} > 0 )) || die "Keine Wallpapers gefunden. Lege Bilder in ${WALLPAPER_DIRS[*]} ab."

    local current
    if [[ "$target" == "__all__" || "$target" == "all" || "$target" == "__default__" ]]; then
        current="$default_id"
    else
        current="$(state_monitor_get "$target")"
        [[ -n "$current" ]] || current="$default_id"
    fi

    local target_label="$target"
    [[ "$target" == "__all__" || "$target" == "all" ]] && target_label="alle Bildschirme"
    [[ "$target" == "__default__" ]] && target_label="Default"

    # Raster: Sonderaktionen zuerst, dann jedes Bild mit Vorschau (★ = aktuell).
    local -a choices=() labels=() icons=()
    if [[ "$target" != "__all__" && "$target" != "all" && "$target" != "__default__" ]]; then
        choices+=(__reset__) labels+=("Default verwenden") icons+=(edit-undo-symbolic)
    fi
    choices+=(__random__) labels+=("Zufällig") icons+=(media-playlist-shuffle-symbolic)
    choices+=(__fit__) labels+=("Darstellung") icons+=(zoom-fit-best-symbolic)
    local id abs label
    while IFS=$'\t' read -r id abs; do
        label="$(basename -- "${id%.*}")"
        [[ "$id" == "$current" ]] && label="★ $label"
        choices+=("$id") labels+=("$label") icons+=("$(thumbnail "$abs")")
    done < <(list_wallpapers)

    local index i choice
    index="$(for i in "${!labels[@]}"; do printf '%s\0icon\x1f%s\n' "${labels[$i]}" "${icons[$i]}"; done |
        aco-menu --grid --index --prompt "󰸉" --placeholder "Hintergrund für $target_label")" || exit 0
    [[ "$index" =~ ^[0-9]+$ ]] || exit 0
    choice="${choices[$index]}"

    if [[ "$choice" == "__fit__" ]]; then
        tui_fit
        return
    fi

    if [[ "$choice" == "__random__" ]]; then
        local idx=$(( RANDOM % ${#ids[@]} ))
        choice="${ids[$idx]}"
    fi

    apply_choice "$choice" "$target"
}

# ----------------------------------------------------------------------------
# Hilfe
# ----------------------------------------------------------------------------
usage() {
    cat <<EOF
Wallpaper-Switcher für Hyprland (swaybg)

Verwendung: $(basename "$0") [BEFEHL] [OPTIONEN]

Ohne Befehl wird das Menü geöffnet (Ziel wählen, dann Bild aus dem Vorschau-Raster).

Befehle:
  tui [--monitor MON]        Interaktive Auswahl (Ziel + Wallpaper)
  list [--monitor MON]       Verfügbare Wallpapers anzeigen (★ Default, ● Override)
  set <name|pfad> [--monitor MON | --all]
                             Default setzen (ohne Ziel) bzw. Monitor-Override
  default [<name|pfad>]      Default anzeigen oder setzen
  monitor <MON> [<name|pfad>|default]
                             Monitor-Override setzen, anzeigen oder entfernen
  clear <MON> | --all        Override(s) entfernen (zurück zum Default)
  current                    Aktuelle Belegung pro Monitor anzeigen
  next | prev [--monitor MON | --all]
                             Nächstes/vorheriges Wallpaper
  random [--monitor MON | --all]
                             Zufälliges Wallpaper
  apply [--quiet] [--monitor MON]
                             Gespeicherte Belegung (erneut) anwenden
  reload                     swaybg neu starten und Belegung anwenden
  dirs                       Wallpaper-Ordner und Konfiguration anzeigen
  add <datei>... [--move] [--set]
                             Bilder in die Bibliothek kopieren/verschieben
  open                       Wallpaper-Ordner im Dateimanager öffnen
  doctor                     Installation, Monitore und Status prüfen
  help                       Diese Hilfe anzeigen

Wallpapers hinzufügen:
  Bilder in die private Bibliothek ~/git/dotfiles/pictures legen
  (Unterordner werden rekursiv gelesen). Das Verzeichnis ist per .gitignore
  aus dem öffentlichen Dotfiles-Repo ausgeschlossen (Urheberrecht).
  Einrichtung des privaten Repos: ~/git/dotfiles/scripts/install-wallpapers.sh <git-url>

Beispiele:
  wallpaper
  wallpaper set forest.png
  wallpaper set ocean.png --monitor eDP-1
  wallpaper set city.png --all
  wallpaper default forest.png
  wallpaper monitor DP-1 ocean.png
  wallpaper monitor DP-1 default
  wallpaper next
  wallpaper random --all
  wallpaper add ~/Downloads/bild.jpg --set

Dateien:
  Konfiguration: $CONFIG_FILE
  Status:        $STATE_FILE
EOF
}

# ----------------------------------------------------------------------------
# Hauptprogramm
# ----------------------------------------------------------------------------
main() {
    load_config

    local cmd="${1:-tui}"
    shift || true

    case "$cmd" in
        tui|menu)
            cmd_tui "$@"
            ;;
        list|ls)
            cmd_list "$@"
            ;;
        set)
            cmd_set "$@"
            ;;
        default|def)
            cmd_default "$@"
            ;;
        monitor|mon)
            cmd_monitor "$@"
            ;;
        clear|unset)
            cmd_clear "$@"
            ;;
        current|status)
            cmd_current "$@"
            ;;
        next)
            cmd_cycle next "$@"
            ;;
        prev|previous)
            cmd_cycle prev "$@"
            ;;
        random|rand)
            cmd_random "$@"
            ;;
        apply)
            cmd_apply "$@"
            ;;
        reload|restart)
            cmd_reload "$@"
            ;;
        dirs|dir)
            cmd_dirs "$@"
            ;;
        fit|scale)
            cmd_fit "$@"
            ;;
        add)
            cmd_add "$@"
            ;;
        open)
            cmd_open "$@"
            ;;
        doctor|check)
            cmd_doctor "$@"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            error "Unbekannter Befehl: $cmd"
            usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
