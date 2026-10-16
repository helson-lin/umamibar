"""Headless Finder layout for the release installer (coordinates are points)."""
from pathlib import Path

# package-release.sh always runs from the repository root. dmgbuild executes
# settings without defining __file__.
root = Path.cwd()
format = "UDZO"
filesystem = "HFS+"
files = [str(root / "dist/UmamiBar.app")]
symlinks = {"Applications": "/Applications"}
background = str(root / "assets/dmg-background.png")
icon = str(root / "assets/AppIcon.icns")
window_rect = ((160, 120), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
icon_size = 96
text_size = 13
icon_locations = {"UmamiBar.app": (170, 200), "Applications": (470, 200)}
