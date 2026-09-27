{
  identity.homelab = {
    dns = "summerhillnet.duckdns.org";
  };

  identity.user = {
    name = "grant";
    description = "Grant Handy";
  };

  identity.ssh = {
    userKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE/3ShunvZsf43FQUOBrZfquVTR1VEWrI6KbdfCoh71U grant@xenon"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP59990ax7Hh7lz8nEKrSj5ka7XJLRGeBN1i7yo66Ztd grant@helium"
    ];
    hostKeys.radon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDskTTcyiRpEPJoKOAi7L8Bxv+BQBKjjDW6hz5ctWXOB";
  };

  identity.git = {
    name = "grantshandy";
    email = "granthandy@proton.me";
  };

  identity.firefox = {
    defaultEngine = "ddg";

    extensions = [
      "ublock-origin"
      "darkreader"
      "proton-pass"
      "youtube-shorts-block"
      "return-youtube-dislikes"
    ];

    bookmarks = {
      Mail = "https://mail.proton.me";
      Calendar = "https://calendar.proton.me";
      Spotify = "https://open.spotify.com";
      GitHub = "https://github.com";
      "NixOS Wiki" = "https://wiki.nixos.org/wiki/NixOS_Wiki";
      Papago = "https://papago.naver.com";
      Canvas = "https://utah.instructure.com";
      Thesaurus = "https://www.powerthesaurus.org/";
    };

    searchEngines = {
      homemanager = "https://home-manager-options.extranix.com/?query={s}&release=master";
      hanjadict = "https://koreanhanja.app/{s}";
      koverb = "https://koreanverb.app/?search={s}";
    };
  };
}
