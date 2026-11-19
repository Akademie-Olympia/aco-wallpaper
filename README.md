# Wallpaper switcher configuration

hyprpaper CLI and Fuzzel menu with a global default, per-monitor overrides and hot-plug restore.

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

`wallpaper list` shows available images; `wallpaper set FILE` sets the default and `wallpaper set FILE --monitor DP-1` configures one screen separately. `wallpaper doctor` checks the prerequisites. Private images are not part of the package – use for example `~/Pictures/Wallpapers`.

Your own changes in the activated user copy survive synchronisation; new differing defaults appear as `.pacnew`.
See [update and recovery](https://aco-arch-dotfiles.readthedocs.io/en/latest/verification/).

[![Package safety](https://github.com/Akademie-Olympia/aco-wallpaper/actions/workflows/package.yml/badge.svg)](https://github.com/Akademie-Olympia/aco-wallpaper/actions/workflows/package.yml)

[MIT licence](LICENSE).
