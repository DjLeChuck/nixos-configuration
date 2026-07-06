{ pkgs }:

let
  uuid = "openvpn3-switcher@djlechuck";
  domain = "openvpn3-switcher";
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-openvpn3-switcher";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.gettext ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    targetDir=$out/share/gnome-shell/extensions/${uuid}
    mkdir -p "$targetDir"
    install -Dm444 metadata.json "$targetDir/metadata.json"
    install -Dm444 extension.js  "$targetDir/extension.js"

    for po in po/*.po; do
      lang=$(basename "$po" .po)
      mkdir -p "$targetDir/locale/$lang/LC_MESSAGES"
      msgfmt "$po" -o "$targetDir/locale/$lang/LC_MESSAGES/${domain}.mo"
    done

    runHook postInstall
  '';

  passthru.extensionUuid = uuid;

  meta.platforms = pkgs.lib.platforms.linux;
}
