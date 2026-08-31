{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  coreutils,
  findutils,
  fontconfig,
  gawk,
  gnugrep,
  gnused,
  jq,
  inotify-tools,
  libxkbcommon,
  niri,
  noctalia-qs,
  pipewire,
  pulseaudio,
  procps,
  systemd,
  util-linux,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "omarchy-shell";
  version = "unstable-2026-08-23";

  src = fetchFromGitHub {
    owner = "basecamp";
    repo = "omarchy";
    rev = "43bfe9b9d82ba650b5b80eef79e94776790801c9";
    hash = "sha256-GP4bBX5iFqye8gw4BDFChbJXwBo3BtBlR8FXqnuN+BU=";
  };

  patches = [ ./niri.patch ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -d $out/share/omarchy/config/omarchy $out/share/omarchy/theme $out/bin
    cp -r shell $out/share/omarchy/
    install -Dm644 ${./shell.json} $out/share/omarchy/config/omarchy/shell.json
    cp ${./theme}/* $out/share/omarchy/theme/

    install -Dm755 \
      bin/omarchy-audio-input-set-default \
      bin/omarchy-audio-output-set-default \
      bin/omarchy-audio-output-sink \
      bin/omarchy-audio-sink-availability \
      bin/omarchy-hyprland-focus-app \
      bin/omarchy-launch-shell \
      bin/omarchy-shell \
      $out/bin/
    install -Dm755 ${./omarchy-focus-app} $out/bin/omarchy-focus-app
    install -Dm755 ${./omarchy-system-lock} $out/bin/omarchy-system-lock
    install -Dm755 ${./omarchy-system-wake} $out/bin/omarchy-system-wake

    runHook postInstall
  '';

  postFixup =
    let
      runtimePath = lib.makeBinPath [
        bash
        coreutils
        findutils
        fontconfig
        gawk
        gnugrep
        gnused
        jq
        inotify-tools
        libxkbcommon
        niri
        noctalia-qs
        pipewire
        pulseaudio
        procps
        systemd
        util-linux
      ];
    in
    ''
      for program in $out/bin/*; do
        wrapProgram "$program" \
          --set OMARCHY_PATH $out/share/omarchy \
          --prefix PATH : "$out/bin:${runtimePath}"
      done
    '';

  passthru = {
    config = "${finalAttrs.finalPackage}/share/omarchy/config/omarchy/shell.json";
    theme = "${finalAttrs.finalPackage}/share/omarchy/theme";
  };

  meta = {
    description = "Omarchy Quickshell bar, notifications, idle service, and lock screen with niri support";
    homepage = "https://github.com/basecamp/omarchy";
    license = lib.licenses.mit;
    mainProgram = "omarchy-launch-shell";
    platforms = lib.platforms.linux;
  };
})
