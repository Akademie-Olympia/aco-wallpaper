# Befehle

Desktop backgrounds are managed through `hyprpaper` and the custom `wallpaper` script (`~/.config/wallpaper/wallpaper.sh`, linked to `~/.local/bin/wallpaper` and aliased to `wp`):

```bash
# Open interactive Fuzzel picker (choose All/Default or specific monitor, then image):
wallpaper

# List all wallpapers (★ = Default, ● = Monitor Override):
wallpaper list

# Set global default wallpaper (for all monitors without an override):
wallpaper set forest.png

# Set an independent override wallpaper on a specific monitor:
wallpaper set ocean.png --monitor DP-1

# Set the same wallpaper everywhere and clear all overrides:
wallpaper set city.png --all

# Clear a monitor's override so it reverts to the global default:
wallpaper monitor DP-1 default

# Add a new wallpaper image to the user library and apply it:
wallpaper add ~/Downloads/mountain.jpg --set
```

- Wallpapers can reside in `~/Pictures/Wallpapers` or the user library under
  `~/.local/share/arch-dotfiles/config/pictures`. Private images are not included
  in the package; back them up separately.
- Persistent monitor state is stored in `~/.local/state/wallpaper/state` (outside the Git worktree) and automatically restored on login and monitor hot-plug.
