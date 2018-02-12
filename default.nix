{
  haskell-version ? "ghc7103",
  nixpkgs-version ? "nixpkgs1709"  # Use "unstable" for <nixpkgs>
}:

with builtins;
with rec {
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
};
{ inherit pkgs hsPkgs; }
