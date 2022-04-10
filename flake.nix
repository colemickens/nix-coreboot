{
  description = "nix-coreboot";

  inputs = {
    nixpkgs = { url = "github:nixos/nixpkgs/nixos-unstable"; };
  };

  outputs = inputs:
    with builtins;
    let
      nameValuePair = name: value: { inherit name value; };
      genAttrs = names: f: builtins.listToAttrs (map (n: nameValuePair n (f n)) names);
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = genAttrs supportedSystems;
      pkgsFor = pkgs: system: overlays:
        import pkgs {
          inherit system overlays;
          config.allowUnfree = true;
          config.allowAliases = false;
        };
    in
    {
      # TODO: should we go ahead and use the pkgs in default.nix for the shell?
      devShell = forAllSystems (sys: 
      let
        pkgs = pkgsFor inputs.nixpkgs sys [];
      in pkgs.mkShellNoCC {
        buildInputs = with pkgs; [
          gnat11 ncurses m4 flex bison zlib
          pkg-config
        ];
        shellHook = ''
          # TODO REMOVE?
          NIX_LDFLAGS="$NIX_LDFLAGS -lncurses"
        '';
      });
            
      lib = forAllSystems (sys:
        let
          pkgs = import inputs.nixpkgs { system=sys; };
          builder = import ./default.nix {
            inherit pkgs;
          };
        in
      {
        buildCoreboot = builder.buildCoreboot;
      });
    };
}
