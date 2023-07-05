{

  description = "Agda Language Server";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.stacklock2nix.url = "github:cdepillabout/stacklock2nix/main";

  outputs = { self, nixpkgs, flake-utils, stacklock2nix }:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      overlay = final: prev: {
        agda-lsp-stacklock = final.stacklock2nix {
          stackYaml = ./stack.yaml;

          # The Haskell package set to use as a base.  You should change this
          # based on the compiler version from the resolver in your stack.yaml.
          baseHaskellPkgSet = final.haskell.packages.ghc96;
        };
         

        # One of our local packages.
        agda-lsp-app = final.agda-lsp-stacklock.pkgSet;
        stacklock = final.agda-lsp-stacklock;

        # You can also easily create a development shell for hacking on your local
        # packages with `cabal`.
        agda-lsp-dev-shell = final.agda-lsp-stacklock.devShell;
      };
    in
      flake-utils.lib.eachSystem supportedSystems (system:
      let
        overlays = [ stacklock2nix.overlay overlay ];
        
      pkgs = import nixpkgs { inherit system overlays; };
      agda-lsp = builtins.elemAt (pkgs.stacklock.localPkgsSelector pkgs.stacklock.newPkgSet) 0;
      in {
        overlay = overlay;
        packages = {inherit agda-lsp;};
        defaultPackage = agda-lsp;
        devShell = pkgs.agda-lsp-dev-shell;
      
      });

}
 # Any additional Haskell package overrides you may want to add.
          # additionalHaskellPkgSetOverrides = hfinal: hprev: {
          #   # The servant-cassava.cabal file is malformed on GitHub:
          #   # https://github.com/haskell-servant/servant-cassava/pull/29
          #   servant-cassava =
          #     final.haskell.lib.compose.overrideCabal
          #       { editedCabalFile = null; revision = null; }
          #       hprev.servant-cassava;
          # };

          # Additional packages that should be available for development.
          # additionalDevShellNativeBuildInputs = stacklockHaskellPkgSet: [
          #   # Some Haskell tools (like cabal-install and ghcid) can be taken from the
          #   # top-level of Nixpkgs.
          #   final.ghcid
          #   final.stack
          #   # Some Haskell tools need to have been compiled with the same compiler
          #   # you used to define your stacklock2nix Haskell package set.  Be
          #   # careful not to pull these packages from your stacklock2nix Haskell
          #   # package set, since transitive dependency versions may have been
          #   # carefully setup in Nixpkgs so that the tool will compile, and your
          #   # stacklock2nix Haskell package set will likely contain different
          #   # versions.
          #   final.haskell.packages.ghc1824.haskell-language-server
          #   # Other Haskell tools may need to be taken from the stacklock2nix
          #   # Haskell package set, and compiled with the example same dependency
          #   # versions your project depends on.
          #   #stacklockHaskellPkgSet.some-haskell-lib
          # ];

        #   # When creating your own Haskell package set from the stacklock2nix
        #   # output, you may need to specify a newer all-cabal-hashes.
        #   #
        #   # This is necessary when you are using a Stackage snapshot/resolver or
        #   # `extraDeps` in your `stack.yaml` file that is _newer_ than the
        #   # `all-cabal-hashes` derivation from the Nixpkgs you are using.
        #   #
        #   # If you are using the latest nixpkgs-unstable and an old Stackage
        #   # resolver, then it is usually not necessary to override
        #   # `all-cabal-hashes`.
        #   #
        #   # If you are using a very recent Stackage resolver and an old Nixpkgs,
        #   # it is almost always necessary to override `all-cabal-hashes`.
        #   #
        #   # WARNING: If you're on a case-insensitive filesystem (like some OSX
        #   # filesystems), you may get a hash mismatch when using fetchFromGitHub
        #   # to fetch all-cabal-hashes.  As a workaround in that case, you may
        #   # want to use fetchurl:
        #   #
        #   # ```
        #   # all-cabal-hashes = final.fetchurl {
        #   #   url = "https://github.com/commercialhaskell/all-cabal-hashes/archive/f3f41d1f11f40be4a0eb6d9fcc3fe5ff62c0f840.tar.gz";
        #   #   sha256 = "sha256-vYFfZ77fOcOQpAef6VGXlAZBzTe3rjBSS2dDWQQSPUw=";
        #   # };
        #   # ```
        #   #
        #   # You can find more information in:
        #   # https://github.com/NixOS/nixpkgs/issues/39308
        #   all-cabal-hashes = final.fetchFromGitHub {
        #     owner = "commercialhaskell";
        #     repo = "all-cabal-hashes";
        #     rev = "f3f41d1f11f40be4a0eb6d9fcc3fe5ff62c0f840";
        #     sha256 = "sha256-MLF0Vv2RHai3n7b04JeUchQortm+ikuwSjAzAHWvZJs=";
        #   };
        # };