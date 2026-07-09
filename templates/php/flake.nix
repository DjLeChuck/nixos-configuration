{
  description = "PHP project dev shell (auto-detects PHP from .php-version)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f system);

      defaultPhpAttr = "php84";

      # This flake lives in nixos-config and is shared by every PHP project
      # via `use flake $NIXOS_CONFIG_DIR/templates/php --impure` in each
      # project's own .envrc — so it never needs a flake.nix/.envrc copied
      # (or git-tracked) inside the project itself. `./.` would resolve to
      # this flake's own source dir, not the calling project, hence PWD.
      projectDir =
        let pwd = builtins.getEnv "PWD"; in
        if pwd != "" then pwd else toString ./.;

      phpVersionFile = projectDir + "/.php-version";

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

      # Default extension panel for every project, on top of nixpkgs' own
      # sane defaults (openssl, pdo, session, sockets, ctype, fileinfo, xml, ...).
      extraPhpExtensions = with_all: with with_all; [
        amqp
        bcmath
        curl
        gd
        igbinary
        imagick
        imap
        intl
        ldap
        mbstring
        memcached
        msgpack
        mysqli
        opentelemetry
        pdo_mysql
        pdo_pgsql
        pgsql
        ssh2
        sysvmsg
        sysvshm
        xdebug
        xsl
        zip
      ];

      # Default php.ini directives for every project.
      extraPhpIni = ''
        date.timezone = Europe/Paris
        memory_limit = 512M

        ; xdebug stays installed but inactive (near-zero overhead) unless
        ; explicitly requested, e.g. `XDEBUG_MODE=debug php ...` or per-IDE run config.
        xdebug.mode = off
      '';
    in
    {
      devShells = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          phpAttr = phpAttrName pkgs;
          php = pkgs.${phpAttr}.buildEnv {
            extensions = ({ enabled, all }: enabled ++ (extraPhpExtensions all));
            extraConfig = extraPhpIni;
          };
          composer = pkgs.${phpAttr + "Packages"}.composer;
        in
        {
          default = pkgs.mkShell {
            packages = [ php composer ];

            # Exported explicitly (not left to php-with-extensions' `--set-default` wrapper) so
            # tools that themselves set PHP_INI_SCAN_DIR (e.g. Symfony CLI, to support a
            # project-root php.ini) append to this instead of silently losing every extension
            env.PHP_INI_SCAN_DIR = "${php}/lib";

            # nixpkgs' composer binary is a compiled wrapper (makeBinaryWrapper), not a plain
            # PHAR/PHP script, so Symfony CLI's own file sniffing rejects it and silently
            # downloads/manages its own copy instead. SYMFONY_COMPOSER_PATH (symfony-cli#581)
            # points it at this one directly, keeping composer pinned to the project's nixpkgs.
            env.SYMFONY_COMPOSER_PATH = "${composer}/bin/composer";

            shellHook = ''
              echo "PHP:      ${php.version} (${phpAttr}${if builtins.pathExists phpVersionFile then "" else ", default"})"
              echo "Composer: ${composer.version}"
            '';
          };
        });
    };
}
