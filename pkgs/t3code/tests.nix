{
  lib,
  runCommand,
  bash,
  coreutils,
  curl,
  jq,
  t3code,
}:

let
  root = "${t3code.unwrapped}/libexec/t3code";
in
{
  # The desktop backend loads native modules in Electron's Node runtime, which
  # provides fewer libraries than the standalone Node CLI.
  native-modules = runCommand "t3code-native-modules-smoke" { } ''
    ${coreutils}/bin/timeout 60s env ELECTRON_RUN_AS_NODE=1 \
      ${lib.getExe t3code.desktop.electron} --input-type=module -e '
        import assert from "node:assert/strict";
        import { createRequire } from "node:module";

        const speech = await import("${root}/node_modules/transcribe-cpp/dist/index.js");
        assert.ok(speech.getAvailableBackends().some((backend) => backend.kind === "cpu"));

        const pty = createRequire("${root}/apps/server/dist/")("node-pty");
        const terminal = pty.spawn("${lib.getExe bash}", ["--noprofile", "--norc", "-c", "printf pty-ok"]);
        let output = "";
        terminal.onData((data) => { output += data; });
        terminal.onExit(({ exitCode }) => {
          assert.equal(exitCode, 0);
          assert.equal(output, "pty-ok");
        });
      '
    touch "$out"
  '';

  # nixpkgs pins the headless shell to its own Playwright release, which can drift
  # from the playwright-core T3 bundles. Exercise both ways the server drives it.
  browser = runCommand "t3code-browser-smoke" { } ''
    export HOME="$TMPDIR"
    ${coreutils}/bin/timeout 120s ${lib.getExe t3code.unwrapped.nodejs} --input-type=module -e '
      import assert from "node:assert/strict";
      import { spawn } from "node:child_process";
      import { createRequire } from "node:module";

      const executable = "${t3code.unwrapped.browserExecutable}";
      // Chrome cannot nest its sandbox inside the build sandbox.
      const sandboxArgs = ["--no-sandbox"];
      const html = "data:text/html,<h1>browser-ok</h1>";

      // Previews and recording: Playwright with a CDP screencast.
      const { chromium } = createRequire("${root}/apps/server/dist/")("playwright-core");
      const browser = await chromium.launch({ executablePath: executable, headless: true, args: sandboxArgs });
      const page = await browser.newPage();
      await page.goto(html);
      assert.equal(await page.textContent("h1"), "browser-ok");
      assert.ok((await page.screenshot()).length > 0);
      const cdp = await page.context().newCDPSession(page);
      const frame = new Promise((resolve) => cdp.once("Page.screencastFrame", resolve));
      await cdp.send("Page.startScreencast", { format: "jpeg" });
      await page.evaluate(() => { document.body.style.background = "blue"; });
      assert.ok((await frame).data.length > 0);
      await browser.close();

      // HTML rendering: a direct spawn speaking CDP over fds 3 and 4.
      const child = spawn(executable, [
        "--headless=new", "--remote-debugging-pipe", "--user-data-dir=" + process.env.TMPDIR + "/pipe",
        ...sandboxArgs, "about:blank",
      ], { stdio: ["ignore", "ignore", "inherit", "pipe", "pipe"] });
      const reply = await new Promise((resolve, reject) => {
        let buffer = "";
        child.stdio[4].on("data", (chunk) => {
          buffer += chunk;
          if (buffer.includes("\0")) resolve(JSON.parse(buffer.slice(0, buffer.indexOf("\0"))));
        });
        child.on("exit", (code) => reject(new Error("browser exited with " + code)));
        child.stdio[3].write(JSON.stringify({ id: 1, method: "Browser.getVersion" }) + "\0");
      });
      assert.match(reply.result.product, /HeadlessChrome/);
      child.kill();
    '
    touch "$out"
  '';

  web =
    runCommand "t3code-web-smoke"
      {
        nativeBuildInputs = [
          curl
          jq
        ];
        T3CODE_TELEMETRY_ENABLED = "false";
      }
      ''
        export HOME="$TMPDIR"
        url=http://127.0.0.1:37730

        ${lib.getExe t3code} serve --host 127.0.0.1 --port 37730 --base-dir "$HOME/.t3" &> server.log &
        trap 'kill %1; cat server.log' EXIT

        # The server accepts connections before its HTTP routes are attached.
        curl --fail --silent --retry 60 --retry-delay 1 --retry-all-errors \
          "$url/.well-known/t3/environment" | jq --exit-status .environmentId
        curl --fail --silent "$url" | grep --quiet '<html'

        touch "$out"
      '';
}
