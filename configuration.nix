{ config, pkgs, lib, ... }:

{
  imports = [
    ./module.nix
  ];

  system.nixsnap = {
    enable = true;
    fileSystems = [
      "/home"
      "/persist"
    ];
  };
}
