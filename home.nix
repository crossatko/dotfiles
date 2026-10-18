{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  user = "kreejzak";
  dotfiles = "${config.home.homeDirectory}/dotfiles/config";
  create_symlink = path: config.lib.file.mkOutOfStoreSymlink path;
  configs = {
    hypr = "hypr";
    zellij = "zellij";
    nvim = "nvim";
    tofi = "tofi";
    opencode = "opencode";
    wivrn = "wivrn";
  };
in
{
  home = {
    username = "${user}";
    homeDirectory = "/home/${user}";

    sessionPath = [
      "$HOME/.local/bin"
    ];

    sessionVariables = {
      XDG_DATA_DIRS = "$XDG_DATA_DIRS:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share";
      GTK_USE_PORTAL = "1";
    };

    stateVersion = "25.11";

    packages = with pkgs; [
      nerd-fonts.comic-shanns-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      zellij
      wl-clipboard
      gnumake
      gcc
      binutils
      desktop-file-utils
      thunderbird
      mpv
      swappy
      imv
      pavucontrol
      networkmanagerapplet
      yazi
      nautilus
      gvfs
      glib
      tldr
      trezor-suite
      gnome-disk-utility
      kdePackages.ktorrent
      libreoffice
      adwaita-icon-theme
      yaru-theme
      ubuntu-themes
      catppuccin-gtk
      catppuccin-kvantum
      vue-language-server
      vtsls
      typescript-language-server
      prettier
      lazygit
      nodePackages.typescript
      statix
      kdePackages.ark
      zip
      unzip
      rar
      p7zip
      _7zz
      gzip
      playerctl
      python3
      nodejs
      yarn
      appimage-run
      opencode
      jellyfin-mpv-shim
      jellyfin-media-player
      anki-bin
      memento
      epiphany
      discord
    ];
  };

  imports = [
    ./modules/home/nvim.nix
    ./modules/home/kitty.nix
    ./modules/home/tableplus.nix
    ./modules/home/browsers.nix
    ./modules/home/shell.nix
    ./modules/home/themes.nix
    ./modules/home/desktop-entries.nix
  ];

  programs = {
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
      };
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks = {
        "*" = {
          extraOptions = {
            IdentityAgent = "~/.1password/agent.sock";
          };
        };
      };
    };

    home-manager.enable = true;

    git = {
      enable = true;
      settings = {
        pull.rebase = true;
        user = {
          name = "Paul Cross";
          email = "me@paulcross.cz";
        };
      };
    };
  };

  xdg = {
    portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-gnome # Added for Pika Backup background support
      ];
      config = {
        common = {
          default = [ "gtk" ];
          "org.freedesktop.impl.portal.Background" = [ "gnome" ]; # Fallback routing
        };
        hyprland = {
          default = [
            "hyprland"
            "gtk"
          ];
          "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
          "org.freedesktop.impl.portal.Background" = [ "gnome" ]; # Explicitly route Background to GNOME
        };
      };
    };

    configFile =
      (builtins.mapAttrs (name: subpath: {
        source = create_symlink "${dotfiles}/${subpath}";
        recursive = true;
      }) configs)
      // {
        "brave-flags.conf".source = create_symlink "${dotfiles}/brave-flags.conf";
        "gtk-3.0/bookmarks".text = ''
          file:///home/${user}/Documents
          file:///home/${user}/Downloads
          file:///home/${user}/Music
          file:///home/${user}/Pictures
          file:///home/${user}/Videos
          file:///home/${user}/code
        '';
      };

    userDirs = {
      enable = true;
      createDirectories = true;
      download = "$HOME/Downloads";
      documents = "$HOME/Documents";
      music = "$HOME/Music";
      pictures = "$HOME/Pictures";
      videos = "$HOME/Videos";
    };
  };

  services.blueman-applet.enable = true;
}
