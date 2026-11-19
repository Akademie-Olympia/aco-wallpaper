# Wallpaper switcher

Hyprpaper-CLI und Fuzzel-TUI mit globalem Default, Monitor-Overrides und Hot-Plug-Wiederherstellung.

**[Dokumentation und CLI-Befehle](https://aco-arch-dotfiles.readthedocs.io/en/latest/components/#wallpaper)** ·
[Desktop-Anleitung](https://aco-hypr.readthedocs.io/en/latest/keybindings/) ·
[Installation und Updates](https://aco-arch-dotfiles.readthedocs.io/en/latest/arch-package/)

```bash
curl -fsSL https://raw.githubusercontent.com/Akademie-Olympia/aco-arch-dotfiles/main/install.sh | bash -s -- wallpaper
```

Paket: `aco-arch-dotfiles-wallpaper`. Datei: `~/.config/wallpaper/wallpaper.conf`.
Private Bilder sind kein Paketinhalt; beispielsweise `~/Pictures/Wallpapers` verwenden.
`wallpaper doctor` prüft die Laufzeitumgebung. Befehle und Konfiguration stehen im Handbuch.

Hier auf `main` pushen; nach erfolgreichem Registry-Build mit `sudo pacman -Syu`
aktualisieren. Entwicklung und lokale Builds: [PACKAGING.md](PACKAGING.md).

### Bedienung

`wallpaper list` zeigt verfügbare Bilder; `wallpaper set DATEI` setzt den Standard. Mit `wallpaper set DATEI --monitor DP-1` lässt sich ein Bildschirm getrennt konfigurieren. `wallpaper doctor` prüft die Voraussetzungen.

Eigene Änderungen in der aktivierten Benutzerkopie bleiben bei der Synchronisierung erhalten; neue abweichende Vorgaben erscheinen als `.pacnew`. Siehe [Update und Wiederherstellung](https://aco-arch-dotfiles.readthedocs.io/en/latest/verification/).

[![Package safety](https://github.com/Akademie-Olympia/aco-wallpaper/actions/workflows/package.yml/badge.svg)](https://github.com/Akademie-Olympia/aco-wallpaper/actions/workflows/package.yml)

[MIT-Lizenz](LICENSE).
