{ pkgs, ... }: {
  # Enable networking
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.	
  networking.networkmanager.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.excludePackages = [ pkgs.xterm ];
  services.xserver.desktopManager.xterm.enable = false;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages =
    (with pkgs; [ gnome-photos gnome-tour gnome-connections ])
    ++ (with pkgs.gnome; [
      gnome-music
      geary
      gnome-contacts
      gnome-calendar
      gnome-maps
      yelp
      totem
    ]);

  environment.systemPackages = [ pkgs.clapper ];
  fonts.packages = with pkgs; [ noto-fonts noto-fonts-cjk ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.webInterface = false;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    #jack.enable = true;
  };

}
