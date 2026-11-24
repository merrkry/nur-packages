{
  lib,
  stdenvNoCC,
  copyDesktopItems,
  makeDesktopItem,
  makeShellWrapper,
  xdg-utils,
  unwrapped,
  runtimeWrapperArgs,
  commandLineArgs,
}:

let
  inherit (unwrapped) electron;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "t3code-desktop";
  inherit (unwrapped) version;

  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [
    copyDesktopItems
    makeShellWrapper
  ];

  installPhase = ''
    runHook preInstall

    # The URL handler entry the app writes must launch this wrapper rather
    # than the shared Electron.
    makeShellWrapper ${lib.getExe electron} "$out/bin/t3code-desktop" \
      --add-flags ${unwrapped}/libexec/t3code/apps/desktop \
      --set-default T3CODE_DESKTOP_LAUNCHER_PATH "$out/bin/t3code-desktop" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      ${runtimeWrapperArgs} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-wayland-ime=true}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs} \
      --inherit-argv0

    mkdir -p "$out/share"
    ln -s ${unwrapped}/share/icons "$out/share/icons"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "t3code";
      desktopName = "T3 Code (Beta)";
      comment = finalAttrs.meta.description;
      exec = "t3code-desktop %U";
      icon = "t3code";
      startupWMClass = "com.t3tools.T3Code";
      mimeTypes = [ "x-scheme-handler/t3code" ];
      categories = [ "Development" ];
    })
  ];

  passthru = {
    inherit electron unwrapped;
  };

  meta = unwrapped.meta // {
    description = "Desktop interface for coding agents";
    mainProgram = "t3code-desktop";
  };
})
