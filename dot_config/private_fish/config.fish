if status is-interactive
    set -g EDITOR helix
    set fish_greeting

    alias hx="helix"

    if set -q "$DISPLAY"
        exec sway
    end
end
