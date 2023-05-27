if status is-interactive
    set fish_greeting
    alias hx="helix"
end

set -gx EDITOR helix
set -gx GRIM_DEFAULT_PATH ~/pics/screenshots/
set -gx XDG_SCREENSHOTS_DIR ~/pics/screenshots/

fish_add_path -a ~/.cargo/bin
fish_add_path -a /usr/lib/emscripten
