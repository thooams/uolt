{
  description = "UOLT - 34 Unix command-line tools hand-written in x86_64 assembly (no libc, no heap)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # The sources are x86_64 assembly; arm64 (and a Nix darwin build, which
      # needs the macOS SDK) are out of scope for now.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.stdenv.mkDerivation {
            pname = "uolt";
            version = "0.1.0";
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
