{
  description = "PHP project dev shell (auto-detects PHP from .php-version, Node/Yarn from package.json volta config)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f system);

      defaultPhpAttr = "php84";
      phpVersionFile = ./. + "/.php-version";

      phpAttrName = pkgs:
        if builtins.pathExists phpVersionFile then
          let
            raw = nixpkgs.lib.strings.trim (builtins.readFile phpVersionFile);
            m = builtins.match "^([0-9]+)\\.([0-9]+).*" raw;
          in
          if m == null then
            builtins.throw "flake.nix: could not parse PHP version from .php-version ('${raw}'); expected e.g. '8.4' or '8.4.22'"
          else
            let
              major = builtins.elemAt m 0;
              minor = builtins.elemAt m 1;
              attr = "php" + major + minor;
            in
            if pkgs ? ${attr} then attr
            else builtins.throw ''
              flake.nix: .php-version requests PHP ${major}.${minor} ("${attr}"),
              but that attribute does not exist in the pinned nixpkgs (nixos-26.05).
              Either update .php-version, or bump the nixpkgs input in this flake.
            ''
        else
          defaultPhpAttr;

      packageJsonFile = ./. + "/package.json";
      hasPackageJson = builtins.pathExists packageJsonFile;
      packageJson = if hasPackageJson then builtins.fromJSON (builtins.readFile packageJsonFile) else { };
      volta = packageJson.volta or { };

      # tryEval catches both a missing attribute and an attribute that exists
      # but throws on evaluation (e.g. nixpkgs marking an EOL Node major insecure).
      isUsable = pkgs: attr: pkgs ? ${attr} && (builtins.tryEval pkgs.${attr}.outPath).success;

      nodeAttrName = pkgs:
        if volta ? node then
          let m = builtins.match "^([0-9]+)\\..*" volta.node; in
          if m == null then "nodejs"
          else
            let attr = "nodejs_" + builtins.elemAt m 0; in
            if isUsable pkgs attr then attr else "nodejs"
        else "nodejs";

      # nixpkgs only ships classic Yarn 1.x. For Berry (2+), delegate to
      # corepack pinned to the exact volta.yarn version, so `yarn` in the
      # shell transparently matches what the team already uses.
      yarnIsClassic = !(volta ? yarn) || nixpkgs.lib.strings.hasPrefix "1." volta.yarn;

      # Default extension panel for every project, on top of nixpkgs' own
      # sane defaults (openssl, pdo, session, sockets, ctype, fileinfo, xml, ...).
      extraPhpExtensions = with_all: with with_all; [
        amqp
        bcmath
        curl
        gd
        imagick
        intl
        ldap
        mbstring
        mysqli
        pdo_mysql
        pdo_pgsql
        pgsql
        xdebug
        zip
      ];
    in
    {
      devShells = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          phpAttr = phpAttrName pkgs;
          php = pkgs.${phpAttr}.withExtensions ({ enabled, all }: enabled ++ (extraPhpExtensions all));
          composer = pkgs.${phpAttr + "Packages"}.composer;
          nodeAttr = nodeAttrName pkgs;
          node = pkgs.${nodeAttr};

          yarn =
            if yarnIsClassic then
              pkgs.yarn
            else
              pkgs.writeShellScriptBin "yarn" ''
                exec ${pkgs.corepack}/bin/corepack yarn@${volta.yarn} "$@"
              '';
          yarnLabel = if yarnIsClassic then "${pkgs.yarn.version} (classic)" else "${volta.yarn} (via corepack)";
        in
        {
          default = pkgs.mkShell {
            packages = [ php composer ]
              ++ nixpkgs.lib.optionals hasPackageJson [ node yarn ];

            shellHook = ''
              echo "PHP:      ${php.version} (${phpAttr}${if builtins.pathExists phpVersionFile then "" else ", default"})"
              echo "Composer: ${composer.version}"
            '' + nixpkgs.lib.optionalString hasPackageJson ''
              echo "Node:     ${node.version} (${nodeAttr}${if volta ? node then "" else ", default"})"
              echo "Yarn:     ${yarnLabel}"
            '';
          };
        });
    };
}
