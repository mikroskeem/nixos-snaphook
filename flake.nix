{
  description = "NixOS snaphook";

  outputs = { self, nixpkgs }:
    let
      currentHostname = nixpkgs.lib.fileContents /etc/hostname;
    in
    {
      nixosConfigurations.${currentHostname} = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
        ];
      };
    };
}
