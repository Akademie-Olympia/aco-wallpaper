# Wallpaper switcher configuration

Wallpaper CLI (swaybg) and a menu with a preview grid: global default, per-monitor overrides and hot-plug restore.
The default is the generated, licence-free ACO background that follows light/dark and the accent.

**[Documentation](https://aco-docs.readthedocs.io/en/latest/wallpaper/)** ·
[Guide](https://aco-docs.readthedocs.io/en/latest/wallpaper/guide/) ·
[Design & dependencies](https://aco-docs.readthedocs.io/en/latest/wallpaper/design/) ·
[Installation and updates](https://aco-arch-dotfiles.readthedocs.io/en/latest/arch-package/)

```bash
curl -fsSL https://raw.githubusercontent.com/Akademie-Olympia/aco-arch-dotfiles/main/install.sh | bash -s -- wallpaper
```

Package: `aco-arch-dotfiles-wallpaper`. This standalone repository holds the development sources and the package recipe in
`packaging/arch/PKGBUILD`. The documentation of this component lives in the shared
[aco-docs](https://github.com/Akademie-Olympia/aco-docs) repository (one Read the Docs project for all small components).
Push to `main`; after a successful registry build update with `sudo pacman -Syu`. Details and local builds: [PACKAGING.md](PACKAGING.md).

### Customisation

`wallpaper list` shows available images; `wallpaper set FILE` sets the default and `wallpaper set FILE --monitor DP-1` configures one screen separately. `wallpaper doctor` checks the prerequisites. Private images are not part of the package – put them into `~/Pictures/Wallpapers` (searched recursively) and pick them in
*Einstellungen > Hintergrundbild* or with `wallpaper set FILE`. A chosen image always wins; theme switches only re-render the
generated ACO background (`~/.cache/aco/wallpaper/generated/aco.png`, from `aco-theme/aco.svg.tpl`).

swaybg draws through shared memory, so it works on every GPU and in virtual machines; one small process runs per monitor.

Your own changes in the activated user copy survive synchronisation; new differing defaults appear as `.pacnew`.
See [update and recovery](https://aco-arch-dotfiles.readthedocs.io/en/latest/verification/).

[![Package safety](https://github.com/Akademie-Olympia/aco-wallpaper/actions/workflows/package.yml/badge.svg)](https://github.com/Akademie-Olympia/aco-wallpaper/actions/workflows/package.yml)

[MIT licence](LICENSE).

### Default background

The generated ACO background (`aco-theme/aco.svg.tpl`) is a set of layered waves in the accent and palette colours
over a calm gradient; it follows light/dark and the accent and is always the first and default wallpaper. Your own
images go into `~/Pictures/Wallpapers`.

### Bar and lock screen

After setting a wallpaper, `wallpaper.sh` measures the brightness of the top edge of the first monitor's image (ImageMagick)
and tells aco-theme (`aco-theme bar tone light|dark`), so an automatic bar uses dark text
on light wallpapers and light text on dark ones. It also links that image to `~/.cache/aco/wallpaper/current`,
which the lock screen shows.

