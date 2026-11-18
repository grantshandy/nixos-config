{
  lib,
  pkgs,
  ...
}: let
  vmUser = "windows-xp";
  vmStateDir = "/var/lib/windows-xp";
  vmDisk = "${vmStateDir}/system.qcow2";
  installIso = "${vmStateDir}/install.iso";

  # QEMU includes SDL_syswm.h while compiling its SDL frontend. Build the SDL2
  # compatibility headers without X11 so they match this Wayland-only kiosk and
  # do not require Xlib just to compile QEMU.
  sdl2Wayland =
    (pkgs.sdl2-compat.override {
      x11Support = false;
    }).overrideAttrs (old: {
      doCheck = false;
      cmakeFlags =
        (old.cmakeFlags or [])
        ++ [
          (lib.cmakeBool "SDL2COMPAT_X11" false)
        ];
    });
  sdl2ImageWayland = pkgs.SDL2_image.override {SDL2 = sdl2Wayland;};

  qemu =
    (pkgs.qemu_kvm.override {
      SDL2 = sdl2Wayland;
      SDL2_image = sdl2ImageWayland;
      alsaSupport = true;
      pulseSupport = false;
      pipewireSupport = false;
      sdlSupport = true;
      jackSupport = false;
      gtkSupport = false;
      vncSupport = false;
      smartcardSupport = false;
      spiceSupport = false;
      ncursesSupport = false;
      openGLSupport = false;
      libiscsiSupport = false;
      tpmSupport = false;
      fuseSupport = false;
      numaSupport = false;
      guestAgentSupport = false;
      capstoneSupport = false;
      pluginsSupport = false;
      enableDocs = false;
    }).overrideAttrs (old: {
      # Cage initially configures its primary view as maximized. Keep QEMU's
      # fullscreen SDL window resizable so SDL accepts Cage's output-sized
      # configure, while suppressing later guest-driven physical resizes.
      patches = (old.patches or []) ++ [./qemu-sdl-preserve-fullscreen-size.patch];

      # This is a scheduling hint upstream, not a functional requirement. The
      # currently deployed builder list predates Xenon's feature declaration.
      requiredSystemFeatures = [];
    });

  launchWindowsXp = pkgs.writeShellApplication {
    name = "windows-xp-vm";
    runtimeInputs = [pkgs.coreutils qemu];
    text = ''
      if [[ ! -e ${lib.escapeShellArg vmDisk} ]]; then
        qemu-img create -f qcow2 ${lib.escapeShellArg vmDisk} 6G
      fi

      cd ${lib.escapeShellArg vmStateDir}

      cdrom_args=()
      if [[ -r ${lib.escapeShellArg installIso} ]]; then
        cdrom_args=(
          -drive "file=${installIso},if=ide,index=2,media=cdrom,readonly=on"
        )
      fi

      exec qemu-system-x86_64 \
        -name "Windows XP" \
        -enable-kvm \
        -machine pc,accel=kvm \
        -cpu host \
        -smp 2,sockets=1,cores=2,threads=1 \
        -m 1024 \
        -drive file=${lib.escapeShellArg vmDisk},if=ide,index=0,media=disk,format=qcow2,cache=writeback \
        "''${cdrom_args[@]}" \
        -boot order=cd,menu=on \
        -vga std \
        -audiodev alsa,id=audio0 \
        -device AC97,audiodev=audio0 \
        -device rtl8139,netdev=net0 \
        -netdev user,id=net0 \
        -display sdl,gl=off \
        -full-screen
    '';
  };

  kioskSession = pkgs.writeShellScript "windows-xp-kiosk" ''
    export SDL_AUDIODRIVER=alsa
    export SDL_VIDEODRIVER=wayland
    exec ${lib.getExe pkgs.cage} -- ${lib.getExe launchWindowsXp}
  '';
in {
  hardware.graphics.enable = true;

  users.users.${vmUser} = {
    isSystemUser = true;
    group = vmUser;
    home = vmStateDir;
    createHome = false;
    extraGroups = ["audio" "input" "kvm" "render" "video"];
  };
  users.groups.${vmUser} = {};

  systemd.tmpfiles.rules = [
    "d ${vmStateDir} 0750 ${vmUser} ${vmUser} -"
  ];

  # greetd creates a proper logind session; Cage owns the seat and exposes only
  # a single Wayland surface containing QEMU's SDL display.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = kioskSession;
        user = vmUser;
      };
      default_session = {
        command = kioskSession;
        user = vmUser;
      };
    };
  };

  boot = {
    kernelParams = ["quiet" "loglevel=3" "systemd.show_status=auto" "udev.log_level=3" "vt.global_cursor_default=0"];
    loader.timeout = 0;
    plymouth.enable = true;
  };
}
