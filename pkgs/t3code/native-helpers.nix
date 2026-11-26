{
  lib,
  rustPlatform,
  dbus,
  pkg-config,
  wayland,
  src,
  version,
  cargoHashes,
}:

lib.mapAttrs (
  name: cargoHash:
  rustPlatform.buildRustPackage {
    __structuredAttrs = true;
    strictDeps = true;

    pname = "t3code-${name}";
    inherit src version cargoHash;

    sourceRoot = "${src.name}/native/${name}";

    nativeBuildInputs = lib.optionals (name == "hyprland-snap-shot") [ pkg-config ];
    buildInputs = lib.optionals (name == "hyprland-snap-shot") [ wayland ];
    nativeCheckInputs = lib.optionals (name == "kde-snap-shot") [ dbus ];

    postPatch = lib.optionalString (name == "kde-snap-shot") ''
      # The tests start a private bus; /etc/dbus-1 is absent in the sandbox.
      substituteInPlace src/transport_tests.rs \
        --replace-fail '"--session"' '"--config-file=${dbus}/share/dbus-1/session.conf"'
    '';

    meta = {
      description = "Native ${name} helper for T3 Code";
      homepage = "https://github.com/pingdotgg/t3code";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [ merrkry ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "t3-${name}";
    };
  }
) cargoHashes
