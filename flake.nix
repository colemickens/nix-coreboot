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

      # coreboot source
      corebootVersion = "4.16";
      corebootSource = builtins.fetchTarball {
        url = "https://coreboot.org/releases/coreboot-${corebootVersion}.tar.xz";
        sha256 = "0id1s2awm1r1pr9igplg87prq00n8psiddxisdad58a2fiwrqiqc";
      };
    in
    {
      # TODO: should we go ahead and use the pkgs in default.nix for the shell?
      devShell = forAllSystems (sys:
        let
          pkgs = pkgsFor inputs.nixpkgs sys [ ];
        in
        pkgs.mkShellNoCC {
          buildInputs = with pkgs; [ gnat11 ncurses m4 flex bison zlib pkg-config ];
          shellHook = ''
            # TODO REMOVE?
            NIX_LDFLAGS="$NIX_LDFLAGS -lncurses"
          '';
        });

      lib = {
        buildCoreboot = ({ name, configText, system, crossSystem }:
          let
            configFile = builtins.toFile "config" configText;

            # option1
            # binutils fails:
            # binutils-i686-unknown-linux-gnu> /nix/store/31i662dl3xirp3mnz2wpn362yjd5rqsy
            #   -i686-unknown-linux-gnu-binutils-2.35.2/bin/i686-unknown-linux-gnu-ld: cannot find -lz
            cbpkgs1 = (import inputs.nixpkgs {
              system = system;
            }).pkgsCross.gnu32;

            # option2
            # (same error as #1, which is actually reassuring...)
            cbpkgs2 = import inputs.nixpkgs {
              system = system;
              crossSystem = crossSystem;
            };

            # option3
            # (big failure, not even close...)
            cbpkgs3 = (import inputs.nixpkgs {
              system = system;
            }).pkgsi686Linux;

            cbpkgs = cbpkgs1;
            # cbpkgs = cbpkgs2;
            # cbpkgs = cbpkgs3;


            ######## impl

            _gcc = cbpkgs.gcc11;
            gnatWithCxx = cbpkgs.wrapCC (_gcc.cc.override {
              name = "gnat";
              langC = true;
              langCC = true;
              langAda = true;
              profiledCompiler = false;
              gnatboot = cbpkgs.gnat11;
            });
            toolchainEnv = {
              nativeBuildInputs = with cbpkgs; [
                gnatWithCxx
                gmp
                mpfr
                libmpc
                _gcc
                nasm
                acpica-tools
              ];
            };
          in
          cbpkgs.stdenv.mkDerivation {
            pname = name;
            version = corebootVersion;

            src = corebootSource;

            # nativeBuildInputs = [ corebootNativeToolchain ];
            nativeBuildInputs = toolchainEnv.nativeBuildInputs;
            buildInputs = toolchainEnv.nativeBuildInputs;

            # TODO: patch @localversion@ in the config
            postPatch = ''
              patchShebangs util/xcompile/xcompile

              cp ${configFile} .config

              make olddefconfig
            '';

            # buildFlags = [ "-Wno-error=unused-result" ];
            # makeFlags = [ "CC=${cpkgs.stdenv.cc.targetPrefix}cc" "LD=${cpkgs.stdenv.cc.targetPrefix}cc" ];

            installPhase = ''
              prefix=$out/share/coreboot

              mkdir -p $prefix
              install -m 0444 build/coreboot.rom $prefix
            '';
          });
      };
    };
}
