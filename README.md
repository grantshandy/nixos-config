# a humble nixos config

![screenshot](./screenshot.png)

This is my [NixOS](https://nixos.org) 26.05 configuration for my laptop, desktop, and homelab.

It includes a near-stock [GNOME](https://gnome.org) desktop environment with a few tweaks to make it a bit more cohesive.

Desktop features:

- Personal information configuration for user-specific settings
- Adwaita GTK3 and Qt theming with a blurred GNOME Shell
- Minimal, secure Firefox with a GNOME theme and selected extensions
- Zed with an Adwaita theme
- English and Korean input methods
- Tailscale SSH aliases and file manager bookmarks
- University of Utah VPN helper

## Devices

| Host | Device | Primary role |
| --- | --- | --- |
| Helium | Laptop | Personal laptop |
| Xenon | Desktop PC | Personal desktop workstation |
| Krypton | Edge server | HTTPS ingress and tailnet control plane |
| Radon | Home server | Application server, storage, and always-on build worker |
