{
  description = "A Nix Flake for an xfce-based system with hardware token setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    mkSystem = system:
      nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/profiles/all-hardware.nix"
          "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
          (
            {
              lib,
              pkgs,
              config,
              ...
            }: let
              gpgAgentConf = pkgs.runCommand "gpg-agent.conf" {} ''
                sed '/pinentry-program/d' ${self}/../config/gpg-agent.conf > $out
                echo "pinentry-program ${pkgs.pinentry.curses}/bin/pinentry" >> $out
              '';
              hardwareTokenGuide = pkgs.writeShellScriptBin "view-guide" ''
                viewer="$(type -P xdg-open || true)"
                if [ -z "$viewer" ]; then
                  viewer="${pkgs.glow}/bin/glow -p"
                fi
                exec $viewer "${self}/../README.md"
              '';
            in {
              isoImage = {
                isoName = "token-setup-env.iso";
                # As of writing, zstd-based iso is 1542M, takes ~2mins to
                # compress. If you prefer a smaller image and are happy to
                # wait, delete the line below, it will default to a
                # slower-but-smaller xz (1375M in 8mins as of writing).
                squashfsCompression = "zstd";

                appendToMenuLabel = " Hardware Token Setup Live ${self.lastModifiedDate}";
                makeEfiBootable = true; # EFI booting
                makeUsbBootable = true; # USB booting
              };

              swapDevices = [];

              boot = {
                tmp.cleanOnBoot = true;
                kernel.sysctl = {"kernel.unprivileged_bpf_disabled" = 1;};
              };

              services = {
                pcscd.enable = true;
                # Automatically log in at the virtual consoles.
                getty.autologinUser = "nixos";
              };

              programs = {
                ssh.startAgent = false;
                gnupg = {
                  dirmngr.enable = true;
                  agent = {
                    enable = true;
                    enableSSHSupport = true;
                  };
                };
              };

              # Use less privileged nixos user
              users.users = {
                nixos = {
                  isNormalUser = true;
                  extraGroups = ["wheel" "video"];
                  initialHashedPassword = "";
                };
                root.initialHashedPassword = "";
              };

              security = {
                pam.services.lightdm.text = ''
                  auth sufficient pam_succeed_if.so user ingroup wheel
                '';
                sudo = {
                  enable = true;
                  wheelNeedsPassword = false;
                };
              };

              environment.systemPackages = with pkgs; [
                # Tools for backing up keys
                paperkey
                pgpdump
                parted
                cryptsetup

                # Testing
                ent

                # Password generation tools
                diceware
                pwgen
                rng-tools

                # Might be useful beyond the scope of the guide
                cfssl
                pcsctools
                tmux
                htop

                # This guide itself (run `view-guide` on the terminal
                # to open it in a non-graphical environment).
                hardwareTokenGuide
              ];

              # Disable networking so the system is air-gapped
              # Comment all of these lines out if you'll need internet access
              boot.initrd.network.enable = false;
              networking = {
                resolvconf.enable = false;
                dhcpcd.enable = false;
                dhcpcd.allowInterfaces = [];
                interfaces = {};
                firewall.enable = true;
                useDHCP = false;
                useNetworkd = false;
                wireless.enable = false;
                networkmanager.enable = lib.mkForce false;
              };

              # Unset history so it's never stored Set GNUPGHOME to an
              # ephemeral location and configure GPG with the guide

              environment.interactiveShellInit = ''
                unset HISTFILE
                export GNUPGHOME="/run/user/$(id -u)/gnupg"
                if [ ! -d "$GNUPGHOME" ]; then
                  echo "Creating \$GNUPGHOME…"
                  install --verbose -m=0700 --directory="$GNUPGHOME"
                fi
                [ ! -f "$GNUPGHOME/gpg.conf" ] && cp --verbose "${self}/../config/gpg.conf" "$GNUPGHOME/gpg.conf"
                [ ! -f "$GNUPGHOME/gpg-agent.conf" ] && cp --verbose ${gpgAgentConf} "$GNUPGHOME/gpg-agent.conf"
                echo "\$GNUPGHOME is \"$GNUPGHOME\""
              '';

              # Copy the contents of contrib to the home directory, add a
              # shortcut to the guide on the desktop, and link to the whole
              # repo in the documents folder.
              system.activationScripts.yubikeyGuide = let
                homeDir = "/home/nixos/";
                desktopDir = homeDir + "Desktop/";
                documentsDir = homeDir + "Documents/";
              in ''
                mkdir -p ${desktopDir} ${documentsDir}
                chown nixos ${homeDir} ${desktopDir} ${documentsDir}

                cp -R ${self}/contrib/* ${homeDir}
                ln -sfT ${self} ${documentsDir}/YubiKey-Guide
              '';
              system.stateVersion = "25.05";
            }
          )
        ];
      };
  in {
    nixosConfigurations.yubikeyLive.x86_64-linux = mkSystem "x86_64-linux";
    nixosConfigurations.yubikeyLive.aarch64-linux = mkSystem "aarch64-linux";
    formatter.x86_64-linux = (import nixpkgs {system = "x86_64-linux";}).alejandra;
    formatter.aarch64-linux = (import nixpkgs {system = "aarch64-linux";}).alejandra;
  };
}
