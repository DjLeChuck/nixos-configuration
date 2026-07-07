# Fetches prebuilt CLI binaries from the company's private GitLab (Package
# Registry / release assets). Auth goes through `netrcImpureEnvVars`, so the
# token is only ever an impure env var during the sandboxed fetch - it never
# becomes a derivation input, so it never ends up in the store or a .drv.
# See modules/private-tools.nix for how GITLAB_TOOLS_TOKEN reaches the build.
{ pkgs, variables }:

let
  fetchPrivateBinary =
    { name, url, sha256 }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = name;
      version = "latest";

      src = pkgs.fetchurl {
        inherit url sha256;
        netrcPhase = ''
          cat > netrc <<EOF
          machine ${variables.privateTools.gitlabHost}
          login PRIVATE-TOKEN
          password $GITLAB_TOOLS_TOKEN
          EOF
        '';
        netrcImpureEnvVars = [ "GITLAB_TOOLS_TOKEN" ];
      };

      dontUnpack = true;

      installPhase = ''
        install -Dm755 $src $out/bin/${name}
      '';
    };
in
{
  lock-excel = fetchPrivateBinary {
    name = "lock-excel";
    inherit (variables.privateTools.lockExcel) url sha256;
  };
  excel2jsonl = fetchPrivateBinary {
    name = "excel2jsonl";
    inherit (variables.privateTools.excel2jsonl) url sha256;
  };
}
