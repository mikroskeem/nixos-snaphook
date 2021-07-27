{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.system.nixsnap;
in
{
  options = {
    system.nixsnap = {
      enable = mkEnableOption "nixsnap";
      fileSystems = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.enable -> (cfg.fileSystems != [ ]);
        message = "Must specify at least one file system to snapshot";
      }
      {
        assertion = lib.all (f: lib.trace "checking '${f}' (${config.fileSystems.${f}.fsType})" (config.fileSystems ? ${f})) cfg.fileSystems;
        message = "One or more file system is not configured";
      }
    ];

    #  fileSystems."/nix" =
    #    { device = "/dev/disk/by-uuid/891a6ff1-9a75-4817-96c0-dd1eaacaba70";
    #      fsType = "btrfs";
    #      options = [ "noatime"  "subvol=@nix" ];
    #      neededForBoot = true;
    #    };

    environment.systemPackages =
      let
        supportedFilesystems = {
          "zfs" = {
            extraArgs = fs: [];
          };
          "btrfs" = {
            extraArgs = fs: [(lib.removePrefix "subvol=" (lib.findFirst (lib.hasPrefix "subvol=") "none" fs.options))];
          };
        };

        mapSnapshotCommand = f:
          let
            fs = config.fileSystems.${f};
            inherit (fs) device fsType;
          in
          if (supportedFilesystems ? ${fsType}) then
            "  makeSnapshot ${fsType} ${device} ${f} ${lib.concatStringsSep " " (supportedFilesystems.${fsType}.extraArgs fs)}"
          else
            "  : # Unsupported fs '${fsType}' (${device})";

        unshareBtrfsDelegateScript = pkgs.writeShellScript "nixsnap-btrfs-unshare" ''
          set -euo pipefail

          type="$1"
          device="$2"
          mountpoint="$3"
          snapname="$4"
          subvolname="$5"

          # mount tmpfs to store our temporary mounts
          mount -t tmpfs tmpfs /tmp

          # mount the device
          mkdir /tmp/btrfsdev
          mount -o subvolid=0 "$device" /tmp/btrfsdev

          # make a read-only snapshot
          btrfs subvolume snapshot -r "/tmp/btrfsdev/$subvolname" "/tmp/btrfsdev/$subvolname.$snapname"
        '';

        rebuildScript = pkgs.writeShellScriptBin "nixsnap-rebuild" ''
          set -euo pipefail

          : "''${NIXOS_CONFIG:=/etc/nixos/configuration.nix}"

          # Reset envvars to known good value
          export PATH=/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin
          export NIX_PATH="${lib.concatStringsSep ":" config.nix.nixPath}"

          # Get current system version
          sysver="$(readlink /nix/var/nix/profiles/system | cut -d- -f2)"

          makeSnapshot () {
            type="$1"
            device="$2"
            mountpoint="$3"
            shift 3

            snapname="nixos-generation-$sysver"

            case "$type" in
              zfs)
                echo "SNAPSHOT '$mountpoint' ($type) -> '$device@$snapname'"
                zfs snapshot -r "$device@snapname"
                ;;
              btrfs)
                echo "SNAPSHOT '$mountpoint' ($type) -> '$1.$snapname'"
                unshare --mount --fork "${unshareBtrfsDelegateScript}" "$type" "$device" "$mountpoint" "$snapname" "$@"
                ;;
            esac
          }

          # Make a snapshot
          {
          ${lib.concatMapStringsSep "\n" mapSnapshotCommand cfg.fileSystems}
            :
          } || {
            echo ">>> Failed to take all required snapshots, bailing out"
            exit 1
          }
          exit 0

          # Start rebuild task
          systemd-run --setenv=NIX_PATH="$NIX_PATH" --setenv=PATH="$PATH" --setenv=NIXOS_CONFIG="$NIXOS_CONFIG" --wait nixos-rebuild switch
        '';
      in
      lib.optional cfg.enable rebuildScript;
  };
}
