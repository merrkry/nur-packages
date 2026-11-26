{
  lib,
  stdenv,
  stdenvNoCC,
  callPackage,
  callPackages,
  fetchFromGitHub,
  installShellFiles,
  makeShellWrapper,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  git,
  gh,
  githubReleaseUpdater ? callPackage ../../lib/github-release-updater.nix { },
  providerPackages ? [ ],
  commandLineArgs ? "",
}:

let
  version = "0.1.11";
  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${version}";
    hash = "sha256-oI8gyTWFgtTmVK+0cVQaEcfO8EzxUUOW5s8JFG/z/U8=";
  };

  nativeHelpers = callPackages ./native-helpers.nix {
    inherit src version;
    cargoHashes = {
      resource-monitor = "sha256-5cmG2daM1bVOA23gjjoalbx0fEL1hmqV6WZov0sUZp8=";
      kde-snap-shot = "sha256-ZbetrRAvnNLLS51IwR9xLb1NhnpFQB4J1ahn4CthJy0=";
      hyprland-snap-shot = "sha256-oki1DAzUJ/8YIFhaJlw2wOukiQMcAaexdJqxDcFXFW4=";
    };
  };

  unwrapped = callPackage ./unwrapped.nix {
    inherit src version nativeHelpers;
    pnpmDepsHash = "sha256-s/vm8Ox4o/AYpNC/amYP1KFWwh7SY5bCmVBuIJn9f/c=";
  };

  # Both the CLI and the desktop app run the server, which launches these tools.
  runtimeWrapperArgs = "--prefix PATH : ${
    lib.escapeShellArg (
      lib.makeBinPath (
        [
          git
          gh
        ]
        ++ providerPackages
      )
    )
  }";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "t3code";
  inherit version;

  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [
    installShellFiles
    makeShellWrapper
  ];

  installPhase = ''
    runHook preInstall

    makeShellWrapper ${lib.getExe unwrapped.nodejs} "$out/bin/t3" \
      --add-flags ${unwrapped}/libexec/t3code/apps/server/dist/bin.mjs \
      ${runtimeWrapperArgs}

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    for shell in bash fish zsh; do
      installShellCompletion --cmd t3 --"$shell" <(
        HOME="$(mktemp -d)" T3CODE_TELEMETRY_ENABLED=false "$out/bin/t3" --completions "$shell"
      )
    done
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];

  passthru = {
    inherit unwrapped nativeHelpers;
    inherit (unwrapped) src pnpmDeps;
    desktop = callPackage ./desktop.nix {
      inherit unwrapped runtimeWrapperArgs commandLineArgs;
    };
    tests = callPackages ./tests.nix { t3code = finalAttrs.finalPackage; };
    updateScript = [
      (lib.getExe githubReleaseUpdater)
      "--owner"
      "pingdotgg"
      "--repo"
      "t3code"
      "--attribute"
      "t3code"
      "--tag-pattern"
      "v(\\d+\\.\\d+\\.\\d+)"
      "--"
      "--override-filename=pkgs/t3code/default.nix"
    ]
    ++ map (name: "--subpackage=nativeHelpers.${name}") (lib.attrNames nativeHelpers);
  };

  meta = unwrapped.meta // {
    description = "Web interface for coding agents";
    mainProgram = "t3";
  };
})
