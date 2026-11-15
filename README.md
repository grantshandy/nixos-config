# a humble nixos config

![screenshot](./screenshot.png)

This is my [NixOS](https://nixos.org) 26.05 configuration for my laptop, desktop, and homelab.

It includes a near-stock [GNOME](https://gnome.org) desktop environment with a few tweaks to make it a bit more cohesive.

Features:

 - Personal info config file for user-specific items
 - Adwaita GTK3/QT theme, blurred GNOME Shell
 - Minimal & secure Firefox w/GNOME theme & select extensions
 - Zed w/Adwaita Theme
 - Tailscale w/automatic SSH aliases & file manager bookmarks
 - University of Utah VPN helper
 - Headscale & Headplane on Radon, w/Caddy HTTPS & DuckDNS
 - Encrypted secrets w/agenix
 - Optional Navidrome/Beets music & Immich photo modules
 - Local Ollama inference & Tailscale-only Open WebUI on Xenon

## Repository layout

Simplified from `tree -a -I '.git|.direnv|result|node_modules'`, with hidden tooling
files omitted and wallpaper images and encrypted secrets grouped together.

```text
.
├── flake.nix
├── flake.lock
├── flake-modules/
│   ├── dev.nix                        # Development shell and Nix formatter
│   └── nixos.nix                      # Builds host configurations from the registry
├── identity.example.nix               # Template for personal and homelab settings
├── identity.nix                       # Local identity, domain, and SSH settings
├── hosts/
│   ├── registry.nix                   # Host metadata and public/private web services
│   ├── helium/                        # Personal Laptop
│   ├── xenon/                         # Desktop PC
│   └── radon/
│   │   ├── default.nix                # Server setup, media root, and endpoint imports
│   │   ├── hardware-configuration.nix # Radon's hardware, storage, and media permissions
│   │   ├── gitlab-runner.nix          # GitLab runner with isolated university VPN access
│   │   └── endpoints/
│   │       ├── auth.nix               # Authelia authentication, access rules, and OIDC
│   │       ├── cockpit.nix            # Cockpit administration and authenticated proxy
│   │       ├── directory.nix          # Registry-generated service landing page
│   │       ├── headscale.nix          # Headscale, Headplane, DuckDNS, and proxy routes
│   │       ├── music.nix              # Navidrome, Lidarr, slskd, and shared music storage
│   │       └── photos.nix             # Immich photo library and proxy routes
├── modules/
│   ├── options.nix                    # Shared identity, desktop, and registry options
│   ├── home/                          # User-level Home Manager modules
│   │   ├── home-manager-base.nix      # Connects NixOS users, identity, and Home Manager
│   │   ├── base.nix                   # CLI tools, shell, tmux, Git, and direnv
│   │   ├── desktop.nix                # Desktop applications, VPN helpers, and favorites
│   │   ├── beeper.nix                 # Beeper messaging client
│   │   ├── globalprotect-vpn.nix      # GlobalProtect VPN service and commands
│   │   ├── gitlab-runner-vpn.nix      # Periodic checks of Radon's VPN-backed runner
│   │   ├── firefox/                   # Firefox profile, extensions, theme, and bookmarks
│   │   └── zed/                       # Zed editor configuration
│   └── nixos/                         # System-level NixOS modules
│       ├── base.nix                   # Common packages, users, locale, and module imports
│       ├── bootloader-systemd.nix     # systemd-boot configuration
│       ├── network-base.nix           # SSH, Tailscale, Avahi, and firewall defaults
│       ├── nix-cache-mesh.nix         # Nix binary caches shared between hosts
│       ├── slskd-notify.nix           # Soulseek upload notifications across the tailnet
│       └── desktop/
│           ├── default.nix            # Desktop system and Home Manager module imports
│           ├── flatpak.nix            # Flatpak support and application management
│           ├── korean.nix             # Korean language input configuration
│           ├── tailscale-bookmarks.nix # SSH aliases and GTK/Firefox homelab bookmarks
│           └── gnome/
│               ├── default.nix        # GNOME, GDM, desktop packages, and system services
│               └── wallpapers/        # Wallpaper rotation and display-aware rendering
├── secrets/                           # Encrypted service credentials and private keys
├── README.md
└── screenshot.png
```
