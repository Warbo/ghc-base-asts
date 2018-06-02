{
  haskell-version ? "ghc7103",
  nixpkgs-version ? "nixpkgs1709"  # Use "unstable" for <nixpkgs>
}:

with builtins;
with rec {
  inherit (pkgs) gmp;

  rawPkgs = import <nixpkgs> { config = {}; };

  config =
    with tryEval <nix-config>;
    if success
       then import "${value}/unstable.nix"
       else import "${rawPkgs.fetchgit {
              url    = http://chriswarbo.net/git/nix-config.git;
              rev    = "07ad493";
              sha256 = "03cmgb53lxxdhvk1zdiq0ly80lhfrbpkmbbxcragmdm29gyn77q2";
            }}/stable.nix";

  pkgs = getAttr nixpkgs-version
                 (import <nixpkgs> { inherit config; }).customised;

  hsPkgs = getAttr haskell-version pkgs.haskell.packages;

  # The ghc.bootPkgs set contains those packages used to build GHC, including
  # the version of GHC used to bootstrap the compiler.
  bootGhc = hsPkgs.ghc.bootPkgs.ghc;

  ghcWrapper = pkgs.wrap {
    name   = "wrapped-ghc";
    vars   = { real = "${bootGhc}/bin/ghc"; };
    script = ''
      #!/usr/bin/env bash
      exec "$real" -package-db="$GHC_PKG" -package AstPlugin \
           -fplugin=AstPlugin.Plugin "$@"
    '';
  };

  # Copy the bootstrap compiler and replace the 'ghc' command with our augmented
  # script.
  augmentGhc = ghc: pkgs.runCommand "augmented-ghc"
    {
      buildInputs = [ pkgs.replace ];
      real        = ghc;
      newGhc      = pkgs.wrap {
        name   = "augmented-ghc";
        script = ''
          #!/usr/bin/env bash
          echo -e "GHC called with: $*" 1>&2
          "REPLACE_ME/bin/ghc.real" "$@"
        '';
      };
    }
    ''
      echo "Duplicating GHC package" 1>&2
      cp -r "$real" "$out"
      chmod +w -R "$out"

      echo "Updating internal references to use our duplicate" 1>&2
      while read -r F
      do
        replace "$real" "$out" -- "$F"
      done < <(find "$out" -type f)

      echo "Wrapping bin/ghc command" 1>&2
      mv "$out/bin/ghc" "$out/bin/ghc.real"
      cp "$newGhc" "$out/bin/ghc"
      chmod +w "$out/bin/ghc"
      replace "REPLACE_ME" "$out" -- "$out/bin/ghc"
    '';

  go = ghc:
    with pkgs.lib;
    with rec {
      augmentedGhc = augmentGhc ghc;
      depsSansGhc  = filter (x: !(hasPrefix "ghc-" x.name)) ghc.buildInputs;
      ghcsrc       = pkgs.unpack ghc.src;
    };
    with pkgs;
    runCommand "x"
      {
        inherit ghcsrc;
        buildInputs = depsSansGhc ++ [
          augmentedGhc
          cabal-install
          gcc
          ncurses.dev
        ];
        hackage = stableHackageDb;
      }
      ''
        export HOME="$PWD/cache"
        mkdir -p "$HOME"/.cabal/packages/hackage.haskell.org
        ln -s "$hackage"/.cabal/packages/hackage.haskell.org/00-index.tar \
                 "$HOME"/.cabal/packages/hackage.haskell.org/

        cp -r "$ghcsrc" ./ghc
        chmod +w -R ./ghc
        cd ./ghc

        ./configure
        make all_libraries/base_dist-boot

      #cabal sandbox init
      #cabal sandbox add-source "$ghcsrc/libraries/integer-gmp"
      #cabal configure -f integer-gmp
      #cabal build
    '';
};
go pkgs.ghc
