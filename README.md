# Optional platform binaries get scope required

Reproducer for the last point in https://github.com/cdxgen/cdxgen/discussions/4070.

The project depends on `@napi-rs/nice` and imports it from `src/index.js`. `@napi-rs/nice` lists 16 platform packages under `optionalDependencies`, and every one of them has `"optional": true` plus `os` and `cpu` in `package-lock.json`. npm installs the ones whose `os` and `cpu` match the host, which on linux x64 is both the gnu and the musl build, and at runtime only one of them is loaded.

cdxgen gives every platform package it lists `scope: required`, while the same components have `cdx:npm:package:optional=true`.

## Run it

```
npm ci
./run.sh
```

`run.sh` calls `cdxgen` from `PATH`. Set `CDXGEN` to use something else, for example `CDXGEN="node /path/to/cdxgen/bin/cdxgen.js" ./run.sh`. It runs three scans and prints scope, the optional property and the occurrence count for each component:

1. `lockfile-only`: a copy of the project without `node_modules`, default options.
2. `lockfile-only-evidence`: the same copy with `--evidence`.
3. `installed-evidence`: this directory with `node_modules`, with `--evidence`.

Output with cdxgen at eb67227a5d3bae0f3c5ee0a289f7ae08fc1837ca on linux x64 (glibc):

```
== lockfile-only
required  @napi-rs/nice                        npmOptional=false occurrences=2
required  @napi-rs/nice-android-arm-eabi       npmOptional=true occurrences=0
required  @napi-rs/nice-android-arm64          npmOptional=true occurrences=0
...                                            (all 16 platform packages)
required  @napi-rs/nice-win32-x64-msvc         npmOptional=true occurrences=0

== lockfile-only-evidence
(same as above)

== installed-evidence
required  @napi-rs/nice                        npmOptional=false occurrences=2
required  @napi-rs/nice-linux-x64-gnu          npmOptional=true occurrences=1
required  @napi-rs/nice-linux-x64-musl         npmOptional=true occurrences=1
```

## Why

There are two separate paths to `required`.

Scans 1 and 2 go through the npm scope. When the analyzer records an import of `@napi-rs/nice` it also stores the first path segment, `@napi-rs`, as an import key ([analyzer.js#L291](https://github.com/cdxgen/cdxgen/blob/eb67227a5d3bae0f3c5ee0a289f7ae08fc1837ca/lib/inventory/analyzer.js#L291)). `addComponent` then treats a component as imported when its group is one of the keys ([bomAssembly.js#L1093-L1094](https://github.com/cdxgen/cdxgen/blob/eb67227a5d3bae0f3c5ee0a289f7ae08fc1837ca/lib/cli/bomAssembly.js#L1093-L1094)), so importing one package makes every package in the same scope required. None of the 16 platform packages has an occurrence in these two scans. With those two lines removed, the 16 platform packages come out `optional` in both scans and `@napi-rs/nice` stays `required`.

Scan 3 goes through real imports. `--evidence` turns on `deep` ([cliOptions.js#L231](https://github.com/cdxgen/cdxgen/blob/eb67227a5d3bae0f3c5ee0a289f7ae08fc1837ca/lib/cli/cliOptions.js#L231)), so the tree is read from `node_modules` ([parsers-js.js#L1476](https://github.com/cdxgen/cdxgen/blob/eb67227a5d3bae0f3c5ee0a289f7ae08fc1837ca/lib/ecosystems/parsers-js.js#L1476)) and only the two installed platform packages are listed. The analyzer also reads `node_modules/@napi-rs/nice/index.js`, which requires each platform package by name inside a platform switch (lines 217 and 229 for the two linux x64 ones), and that exact name match makes them required. This path stays after removing the scope match above. On a glibc host `node -e 'require("@napi-rs/nice")'` loads only `nice-linux-x64-gnu`, yet the musl package is also reported as required.

In both paths the scope is set at [bomAssembly.js#L1104](https://github.com/cdxgen/cdxgen/blob/eb67227a5d3bae0f3c5ee0a289f7ae08fc1837ca/lib/cli/bomAssembly.js#L1104) without looking at `cdx:npm:package:optional`, which is already on these components when that line runs.
