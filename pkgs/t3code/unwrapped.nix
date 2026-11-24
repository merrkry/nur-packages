{
  lib,
  stdenv,
  autoPatchelfHook,
  cacert,
  electron_44,
  fetchPnpmDeps,
  jq,
  libsecret,
  node-gyp,
  nodejs_26,
  playwright-driver,
  pkg-config,
  pnpmBuildHook,
  pnpmConfigHook,
  pnpm_12,
  procps,
  python3,
  util-linux,
  vulkan-loader,
  writableTmpDirAsHomeHook,
  src,
  version,
  pnpmDepsHash,
  nativeHelpers,
}:

let
  # Upstream pins Node.js 26 in package.json#engines.
  nodejs = nodejs_26;
  pnpm = pnpm_12;
  # Upstream pins this Electron major in apps/desktop/package.json.
  electron = electron_44;
  inherit (stdenv.hostPlatform.node) arch;
  # The headless shell nixpkgs builds for the same Playwright that T3 drives it with.
  browser = playwright-driver.components.chromium-headless-shell;
  browserExecutable = "${browser}/chrome-headless-shell-linux64/chrome-headless-shell";
in
stdenv.mkDerivation (finalAttrs: {
  __structuredAttrs = true;
  strictDeps = true;

  pname = "t3code-unwrapped";
  inherit version src;

  postPatch = ''
    # Generic Electron runs this installation unpackaged, which would otherwise make
    # the read-only application root the backend's working directory.
    substituteInPlace apps/desktop/src/app/DesktopEnvironment.ts \
      --replace-fail 'backendCwd: input.isPackaged ? homeDirectory : appRoot,' \
                     'backendCwd: homeDirectory,'

    # T3 downloads Chrome's headless shell at runtime, which needs an FHS loader and
    # libraries on NixOS. Use the one from nixpkgs for previews, recording and setup.
    substituteInPlace apps/server/src/preview/PreviewBrowser.ts \
      --replace-fail 'const executable = path.join(installRoot, release.version, executableName);' \
                     'const executable = "${browserExecutable}";'
    substituteInPlace apps/server/src/cli/browser.ts \
      --replace-fail 'const browser = yield* installedBrowser(baseDirPath);' \
                     'const browser = Option.some("${browserExecutable}");'
    # The AppArmor profile setup writes on Ubuntu must attach to that executable.
    substituteInPlace apps/server/src/preview/PreviewBrowserHost.ts \
      --replace-fail '/**/tools/chrome-headless-shell/*/*/chrome-headless-shell' \
                     '${browserExecutable}'

    # The test fixture renames `cat` with `exec -a`, which a multi-call coreutils
    # cannot dispatch.
    substituteInPlace apps/desktop/src/wsl/DesktopWslEnvironment.test.ts \
      --replace-fail 'it("prunes old and markerless caches' 'it.skip("prunes old and markerless caches'

    # Official builds bake these public T3 Connect identifiers into the clients.
    cp .env.example .env
  '';

  nativeBuildInputs = [
    autoPatchelfHook
    cacert
    jq
    node-gyp
    nodejs
    pkg-config
    pnpm
    pnpmBuildHook
    pnpmConfigHook
    python3
  ];

  buildInputs = [
    libsecret
    stdenv.cc.cc.lib
    vulkan-loader
  ];

  pnpmWorkspaces = [
    # `...` also selects the workspace packages these depend on.
    "@t3tools/monorepo"
    "t3..."
    "@t3tools/desktop..."
    "@t3tools/scripts..."
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit pnpm;
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    fetcherVersion = 5;
    hash = pnpmDepsHash;
  };

  preBuild = ''
    # The version update below would otherwise look like dependency drift and
    # trigger another install with lifecycle scripts.
    export pnpm_config_verify_deps_before_run=false

    node scripts/update-release-package-versions.ts ${finalAttrs.version}

    export npm_config_nodedir=${nodejs}
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    # The monorepo's own lifecycle script runs `vp config`, which needs git.
    pnpm rebuild --pending "''${pnpmInstallFlags[@]}" --filter '!@t3tools/monorepo'
  '';

  pnpmBuildScript = "build:desktop";

  postBuild = ''
    # Release builds brand the bundled web client like the desktop app.
    node scripts/apply-web-brand-assets.ts production apps/server/dist/client
  '';

  doCheck = true;
  nativeCheckInputs = [
    procps
    util-linux
    writableTmpDirAsHomeHook
  ];

  # Upstream CI splits the server suite across eight runners; only the desktop
  # suite, which covers the Electron shell this package runs unpackaged, fits a build.
  checkPhase = ''
    runHook preCheck

    # The suite's setup downloads Electron unless the package has a runtime, and
    # marks its binary executable, so the binary itself cannot stay in the store.
    electronDir=$(node -p 'path.dirname(require.resolve("electron/package.json", { paths: ["apps/desktop"] }))')
    mkdir "$electronDir/dist"
    ln -s ${electron.dist}/* "$electronDir/dist/"
    rm "$electronDir/dist/electron"
    install -m755 ${electron.dist}/electron "$electronDir/dist/"
    printf electron > "$electronDir/path.txt"

    pnpm --filter @t3tools/desktop test

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    root="$out/libexec/t3code"
    node ${./stage-runtime.mjs} . "$root"

    mkdir -p "$root/apps/server" "$root/apps/desktop"
    cp -r apps/server/dist "$root/apps/server/"
    cp -r apps/desktop/dist-electron apps/desktop/resources "$root/apps/desktop/"

    # Electron derives the app name, and with it the keyring identity for
    # encrypted data, from package.json. Official builds use `t3code`.
    jq '.name = "t3code" | del(.productName)' apps/desktop/package.json \
      > "$root/apps/desktop/package.json"

    # Unpackaged installations look up their native helpers in the source tree layout.
    install -Dm644 assets/prod/black-universal-1024.png \
      "$root/apps/desktop/prod-resources/icon.png"
    install -Dm755 native/browser-secret/build/${arch}/t3-browser-secret \
      -t "$root/native/browser-secret/build/${arch}"
    install -Dm755 ${lib.getExe nativeHelpers.resource-monitor} \
      -t "$root/apps/server/dist/resource-monitor"
    install -Dm755 ${lib.getExe nativeHelpers.resource-monitor} \
      -t "$root/apps/desktop/prod-resources/resource-monitor"
    # Capture setup installs these helpers itself and rejects symlinks.
    install -Dm755 ${lib.getExe nativeHelpers.kde-snap-shot} \
      -t "$root/native/kde-snap-shot/target/release"
    install -Dm755 ${lib.getExe nativeHelpers.hyprland-snap-shot} \
      -t "$root/native/hyprland-snap-shot/target/release"
    cp -r native/hyprland-snap-shot/protocols "$root/native/hyprland-snap-shot/"
    while IFS= read -r file; do
      install -Dm644 "apps/desktop/gnome-extension/$file" -t "$root/apps/desktop/gnome-extension"
    done < <(jq -r '.files[]' apps/desktop/gnome-extension/bundle.json)

    install -Dm644 assets/prod/black-universal-1024.png \
      "$out/share/icons/hicolor/1024x1024/apps/t3code.png"
    install -Dm644 assets/prod/logo.svg "$out/share/icons/hicolor/scalable/apps/t3code.svg"

    # Release artifacts ship without source maps.
    find "$root/apps" -name '*.map' -delete
    # Package-manager shims and peer links point outside the runtime closure.
    find "$out" -xtype l -delete

    runHook postInstall
  '';

  # The pnpm tree ships static, musl and foreign-platform prebuilds that generic
  # ELF fixups cannot handle; only the host's native modules are patched below.
  dontPatchELF = true;
  dontAutoPatchelf = true;
  noAuditTmpdir = true;
  # Speech backends load their sibling ggml libraries from their own directory.
  autoPatchelfFlags = [ "--preserve-origin" ];

  postFixup = ''
    # Electron's Node runtime provides neither libstdc++ nor the Vulkan loader.
    autoPatchelf \
      "$out"/libexec/t3code/node_modules/.pnpm/node-pty@*/node_modules/node-pty/prebuilds/linux-${arch} \
      "$out"/libexec/t3code/node_modules/.pnpm/@koromix+koffi-linux-${arch}@*/node_modules/@koromix/koffi-linux-${arch}/linux_${arch} \
      "$out"/libexec/t3code/node_modules/.pnpm/@transcribe-cpp+linux-${arch}-cpu-vulkan@*/node_modules/@transcribe-cpp/linux-${arch}-cpu-vulkan
  '';

  passthru = {
    inherit
      nodejs
      pnpm
      electron
      browserExecutable
      ;
  };

  meta = {
    description = "Web and desktop interfaces for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ merrkry ];
    platforms = [ "x86_64-linux" ];
  };
})
