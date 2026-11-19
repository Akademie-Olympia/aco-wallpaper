# Wallpaper im Alltag

Das Paket besteht aus einem Befehl – `wallpaper` (Kurzform `wp`) – und einer Konfigurationsdatei. Der Befehl steuert
**hyprpaper**, den Hintergrund-Daemon von Hyprland, und merkt sich pro Bildschirm, welches Bild gilt.

## Wie es zusammenspielt

```text
wallpaper  ──liest──►  wallpaper.conf (Ordner, Darstellung)
    │      ──speichert► ~/.local/state/wallpaper/state (Default + Overrides)
    ├──hyprctl hyprpaper …──►  hyprpaper  (zeichnet die Bilder)
    ├──hyprctl monitors -j──►  welche Bildschirme gibt es (jq wertet aus)
    └──fuzzel --dmenu───────►  Auswahlmenü ({kbd}`Super + Shift + W`)
```

- **hyprpaper** läuft mit `ipc = true` (siehe `hyprpaper.conf` im Hyprland-Paket). Bilder stehen **nicht** in dessen Konfiguration,
  der Befehl setzt sie zur Laufzeit; startet hyprpaper nicht, startet ihn `wallpaper` selbst.
- Der **Zustand** liegt in `~/.local/state/wallpaper/state`, außerhalb der Konfiguration. Ein Paket-Update überschreibt ihn nie.
- Beim **Hyprland-Start** (`wallpaper apply --quiet`) und beim **Anstecken eines Monitors** (Ereignis `monitor.added`)
  stellt Hyprland die gemerkte Belegung wieder her. Auch das [Bildschirm-Werkzeug](https://aco-hypr.readthedocs.io/en/latest/configuration/)
  ruft nach einem Layoutwechsel `wallpaper apply` auf.

## Default und Overrides

- **Default** – das Bild für alle Monitore ohne eigene Einstellung. Auch neue, unbekannte Monitore bekommen es.
- **Override** – ein eigenes Bild für einen bestimmten Monitor (z. B. Hochformat-Zweitschirm).

In `wallpaper list` steht ★ für den Default, ● für Overrides. `wallpaper current` zeigt die aktuelle Belegung je Monitor.

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `wallpaper` | Auswahlmenü (Fuzzel): erst Ziel (Alle/Default oder Monitor), dann Bild |
| `wallpaper list` | Alle gefundenen Bilder |
| `wallpaper current` | Belegung je Monitor |
| `wallpaper set <bild>` | Default setzen |
| `wallpaper set <bild> --monitor DP-1` | Override für einen Monitor |
| `wallpaper set <bild> --all` | Überall dasselbe Bild, Overrides löschen |
| `wallpaper default <bild>` | Nur den Default ändern |
| `wallpaper monitor DP-1 <bild\|default>` | Override setzen oder entfernen |
| `wallpaper clear DP-1` / `clear --all` | Override(s) löschen |
| `wallpaper next` / `prev` / `random` | Durchwechseln |
| `wallpaper add <datei> [--set] [--move]` | Bild in die Bibliothek übernehmen |
| `wallpaper dirs` | Durchsuchte Ordner |
| `wallpaper apply [--quiet]` | Gemerkte Belegung neu anwenden |
| `wallpaper reload` | hyprpaper neu starten und Belegung anwenden |
| `wallpaper doctor` | Prüft Abhängigkeiten (`hyprctl`, `hyprpaper`, `jq`, `fuzzel`) und Einrichtung |

`<bild>` ist ein Dateiname aus der Bibliothek oder ein Pfad. Namen müssen eindeutig sein; sonst nimmt man den Pfad.

## Konfiguration (`wallpaper.conf`)

| Variable | Standard | Wirkung |
| --- | --- | --- |
| `WALLPAPER_DIRS` | `~/.local/share/arch-dotfiles/config/pictures`, `~/Pictures/Wallpapers`, `/usr/share/hypr/wall*.png` | Durchsuchte Ordner (rekursiv) und Dateimuster |
| `WALLPAPER_FIT` | `cover` | `cover` füllt und beschneidet, `contain` zeigt komplett mit Rändern, `tile` kachelt, `fill` streckt |
| `WALLPAPER_NOTIFY` | `1` | Meldung nach dem Wechsel (`0` = aus) |

Neue Bilder einfach in einen der Ordner legen – sie erscheinen sofort in Menü und Liste. Die Datei ist ein Bash-Skript,
sie wird eingelesen („source"); halte sie deshalb frei von Befehlen außer Variablenzuweisungen.

:::{note}
**Bilder gehören nicht ins Paket.** Aus Urheberrechtsgründen liefert `aco-arch-dotfiles-wallpaper` nur das Werkzeug. Deine Bilder liegen
in `~/Pictures/Wallpapers` oder im Bibliotheksordner und sollten separat gesichert werden.
:::

## Tasten

| Taste | Aktion |
| --- | --- |
| {kbd}`Super + Shift + W` | Auswahlmenü öffnen (zweiter Druck schließt es) |

## Fehlersuche

- **„hyprpaper nicht aktiv":** `wallpaper current` zeigt das. Mit `wallpaper apply` startet der Daemon neu; sonst prüfen, dass `hyprpaper` installiert ist.
- **„hyprctl nicht gefunden":** Der Befehl läuft nur in einer Hyprland-Sitzung.
- **Neuer Monitor bleibt schwarz:** Kurz warten (Hyprland wendet die Belegung mit ein bis zwei Sekunden Verzögerung an) oder `wallpaper apply`.
- **Bild nicht gefunden:** `wallpaper dirs` und `wallpaper list` prüfen; Erkannt werden png, jpg, jpeg, webp, gif, bmp, avif, jxl und tif/tiff.
- **Unscharf oder beschnitten:** `WALLPAPER_FIT=contain` zeigt das ganze Bild.
