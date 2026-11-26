// Stage the pnpm dependencies that the server and desktop bundles load at runtime.
//
// Upstream release builds install the runtime externals selected by
// scripts/lib/{cli,desktop}-external-packages.ts into a fresh hoisted tree.
// That install needs the registry, so this copies the same packages and their
// transitive closure from the offline build tree instead, keeping pnpm's
// virtual-store layout so every package still sees its own dependency versions.
//
// Usage: node stage-runtime.mjs <build tree> <output root>

import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const [source, destination] = process.argv.slice(2).map((argument) => path.resolve(argument));
const store = path.join(source, "node_modules/.pnpm");

const importSource = (relative) => import(pathToFileURL(path.join(source, relative)).href);
const readManifest = (relative) =>
  JSON.parse(fs.readFileSync(path.join(source, relative, "package.json"), "utf8"));

const { selectCliRuntimeExternalDependencies } = await importSource(
  "scripts/lib/cli-external-packages.ts",
);
const { selectDesktopRuntimeExternalDependencies } = await importSource(
  "scripts/lib/desktop-external-packages.ts",
);

const workspaceRoots = {
  "apps/server": selectCliRuntimeExternalDependencies(readManifest("apps/server").dependencies),
  "apps/desktop": selectDesktopRuntimeExternalDependencies(readManifest("apps/desktop").dependencies),
};

/** Map a package directory inside the virtual store to its `.pnpm/<entry>` directory. */
function storeEntry(packageDirectory) {
  const relative = path.relative(store, packageDirectory);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`${packageDirectory} is outside the pnpm virtual store`);
  }
  return path.join(store, relative.split(path.sep)[0]);
}

// Upstream installs one hoisted tree for both bundles, so a name must resolve to one version.
const roots = new Map();
for (const [workspace, dependencies] of Object.entries(workspaceRoots)) {
  for (const name of Object.keys(dependencies)) {
    const target = fs.realpathSync(path.join(source, workspace, "node_modules", name));
    const existing = roots.get(name);
    if (existing !== undefined && existing !== target) {
      throw new Error(`${name} resolves to both ${existing} and ${target}`);
    }
    roots.set(name, target);
  }
}

function packageNames(nodeModules) {
  return fs
    .readdirSync(nodeModules)
    .filter((name) => !name.startsWith("."))
    .flatMap((name) =>
      name.startsWith("@")
        ? fs.readdirSync(path.join(nodeModules, name)).map((child) => `${name}/${child}`)
        : [name],
    );
}

const required = new Set();
const pending = [...roots.values()].map(storeEntry);
while (pending.length > 0) {
  const entry = pending.pop();
  if (required.has(entry)) continue;
  required.add(entry);

  // Each entry holds its package as a directory and its dependencies as symlinks.
  const nodeModules = path.join(entry, "node_modules");
  const names = packageNames(nodeModules);
  const links = names.filter((name) => fs.lstatSync(path.join(nodeModules, name)).isSymbolicLink());
  // Like upstream's production install, leave peers to the packages that depend on them.
  const peers = new Set(
    names
      .filter((name) => !links.includes(name))
      .flatMap((name) => {
        const manifest = readManifest(path.relative(source, path.join(nodeModules, name)));
        const provided = { ...manifest.dependencies, ...manifest.optionalDependencies };
        return Object.keys(manifest.peerDependencies ?? {}).filter((peer) => !(peer in provided));
      }),
  );
  for (const name of links) {
    if (!peers.has(name)) pending.push(storeEntry(fs.realpathSync(path.join(nodeModules, name))));
  }
}

// pnpm's publicHoistPattern links some packages into the root node_modules, where
// runtime lookups that walk up from the entry script expect them (e.g. @cursor/sdk-*).
const rootManifest = readManifest(".");
const rootDependencies = new Set(
  Object.keys({ ...rootManifest.dependencies, ...rootManifest.devDependencies }),
);
for (const name of packageNames(path.join(source, "node_modules"))) {
  if (rootDependencies.has(name) || roots.has(name)) continue;
  const target = fs.realpathSync(path.join(source, "node_modules", name));
  if (required.has(storeEntry(target))) roots.set(name, target);
}

for (const entry of required) {
  fs.cpSync(entry, path.join(destination, path.relative(source, entry)), {
    recursive: true,
    verbatimSymlinks: true,
  });
}

for (const [name, target] of roots) {
  const link = path.join(destination, "node_modules", name);
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(
    path.relative(path.dirname(link), path.join(destination, path.relative(source, target))),
    link,
  );
}

console.log(`Staged ${roots.size} runtime packages from ${required.size} store entries`);
