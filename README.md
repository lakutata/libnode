# libnode

[简体中文](README.zh-CN.md)

Node.js as a library (libnode) for Android, iOS and HarmonyOS, built from its sources by GitHub Actions and released
here. [lakutata](https://github.com/lakutata/lakutata) embeds it in the mobile applications of its `mobile-react`
template, and any native application embedding Node.js can use it.

## The archives

Each release, tagged with its version (`v24.20.0`: the version of Node.js), has an archive per system and
architecture, named `libnode_<platform>_<arch>.tar.gz`. The architectures are named as Node.js names them
(`process.arch`):

| Archive | System | Architecture | Library |
|---|---|---|---|
| `libnode_android_arm64.tar.gz` | Android | arm64-v8a | `lib/libnode.so` |
| `libnode_android_arm.tar.gz` | Android | armeabi-v7a | `lib/libnode.so` |
| `libnode_android_x64.tar.gz` | Android | x86_64 | `lib/libnode.so` |
| `libnode_ios_arm64.tar.gz` | iOS | arm64, devices and simulators | `NodeMobile.xcframework` |
| `libnode_harmony_arm64.tar.gz` | HarmonyOS | arm64-v8a | `lib/libnode.so` |
| `libnode_harmony_x64.tar.gz` | HarmonyOS | x86_64 | `lib/libnode.so` |

An archive holds a directory of the same name: the library, the headers for native addons (`include/node`, with the
`common.gypi` and `config.gypi` of the build), the LICENSE of Node.js, and `libnode.json`, which describes the archive
(its version, system and architecture). Each release also has `SHA256SUMS`, with the sha256 of the archives, and
`manifest.json`, which describes all of them for the tools that download them. The archives of the latest release
are at `https://github.com/lakutata/libnode/releases/latest/download/<archive>`.

- Android and iOS: Node.js with the patches of [nodejs-mobile](https://github.com/digidem/nodejs-mobile), built the same
  way as its own releases. On Android, it is built with the NDK r27d for API level 24 and later, its segments aligned to
  16 KB pages (Android 15 and later). On iOS, it is a dynamic framework, without JIT: WebAssembly is served by the
  polyfill of nodejs-mobile.
- HarmonyOS: Node.js from its sources (`--dest-os=openharmony --shared`), built with the LLVM 19 of OpenHarmony.
  `libnode.so` needs the `libc++_shared.so` of the system. The x64 library has only been build-checked: it has not run
  on an x86_64 emulator of HarmonyOS yet.

## Versions

`versions.env` holds the versions every build uses: Node.js, the commit of the nodejs-mobile recipe (which patches the
same version of Node.js), the NDK and the LLVM of OpenHarmony. They are upgraded together. To build the same version
of Node.js again (other patches, other toolchains), set `REVISION`: the release is then `v<version>-<revision>`.

## Releasing

1. Update `versions.env` and push it: the Build workflow builds every archive (a few hours) and checks the release
   files.
2. Push the tag `v<version>`, which must match `versions.env`: the workflow builds the archives again and publishes the
   release.

The LLVM of OpenHarmony comes from a daily build of its CI, which is removed after some time. When `versions.env` takes
a new one, run the Toolchains workflow: it copies the LLVM into the `toolchains` release of this repository, which the
builds download first (checked by its sha256).

## Building locally

```bash
node scripts/build.mjs <platform> <arch>    # dist/libnode_<platform>_<arch>.tar.gz
```

Android and HarmonyOS are built by the `Dockerfile` with Docker (linux/amd64, emulated on Apple silicon: several
hours), iOS on macOS with Xcode (`ios/build.sh`). The scripts need Node.js 20 or later.

## License

The scripts of this repository are under the MIT license. The archives are under the licenses of Node.js and its
dependencies (their `LICENSE`); the patches of nodejs-mobile are under the MIT license.
