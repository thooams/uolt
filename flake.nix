{
  description = "UOLT - 34 Unix command-line tools hand-written in assembly (x86_64 and aarch64; no libc, no heap)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # Linux x86_64 and aarch64 build natively (make auto-selects the arch from
      # uname -m). A Nix darwin build needs the macOS SDK and stays out of scope.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.stdenv.mkDerivation {
            pname = "uolt";
            version = "0.2.0";
            src = self;

            # The build is one clang integrated-assembler invocation per tool,
            # plus strip; no libc, so disable the wrapper's default hardening
            # (-fPIE/-pie etc.) that fights -static -nostdlib and the link script.
            nativeBuildInputs = [ pkgs.clang pkgs.binutils ];
            hardeningDisable = [ "all" ];

            buildPhase = ''
              runHook preBuild
              make
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              for f in build/uolt-*; do
                install -m755 "$f" "$out/bin/$(basename "$f")"
              done
              # `[` is the same binary as `test`.
              ln -s uolt-test "$out/bin/uolt-["
              runHook postInstall
            '';

            doCheck = false;

            meta = with pkgs.lib; {
              description = "34 Unix tools in x86_64 assembly: no libc, no heap, direct syscalls";
              homepage = "https://github.com/thooams/uolt";
              license = licenses.mit;
              platforms = [ "x86_64-linux" ];
              mainProgram = "uolt-true";
            };
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/uolt-true";
        };
      });
    };
}
