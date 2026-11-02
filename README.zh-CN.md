# libnode

[English](README.md)

把 Node.js 编译成库（libnode），供 Android、iOS 和鸿蒙使用。由 GitHub Actions 从源码编译，在这里发布。[lakutata](https://github.com/lakutata/lakutata) 的 `mobile-react` 模板把它内嵌进手机应用，其他内嵌 Node.js 的原生应用也可以使用。

## 发布的压缩包

每次发布都带一个版本 tag（例如 `v24.20.0`，即 Node.js 的版本），每个系统和架构各有一个压缩包，命名为 `libnode_<平台>_<架构>.tar.gz`。架构沿用 Node.js 的叫法（`process.arch`）：

| 压缩包 | 系统 | 架构 | 库 |
|---|---|---|---|
| `libnode_android_arm64.tar.gz` | Android | arm64-v8a | `lib/libnode.so` |
| `libnode_android_arm.tar.gz` | Android | armeabi-v7a | `lib/libnode.so` |
| `libnode_android_x64.tar.gz` | Android | x86_64 | `lib/libnode.so` |
| `libnode_ios_arm64.tar.gz` | iOS | arm64，真机和模拟器 | `NodeMobile.xcframework` |
| `libnode_harmony_arm64.tar.gz` | 鸿蒙 | arm64-v8a | `lib/libnode.so` |
| `libnode_harmony_x64.tar.gz` | 鸿蒙 | x86_64 | `lib/libnode.so` |

每个压缩包里是一个同名目录，包含库文件、原生插件用的头文件（`include/node`，附带编译时的 `common.gypi` 和 `config.gypi`）、Node.js 的 LICENSE，以及描述这个压缩包的 `libnode.json`（版本、系统、架构等）。每次发布还附带 `SHA256SUMS`（各压缩包的 sha256）和 `manifest.json`（描述所有压缩包，供下载它们的工具读取）。最新一次发布的压缩包可以从 `https://github.com/lakutata/libnode/releases/latest/download/<压缩包>` 下载。

- Android 和 iOS：打上 [nodejs-mobile](https://github.com/digidem/nodejs-mobile) 补丁的 Node.js，编译方式与它的发布版相同。Android 版用 NDK r27d 编译，支持 API 24 及以上，段按 16 KB 页对齐（Android 15 及以上需要）。iOS 版是动态 framework，没有 JIT，WebAssembly 由 nodejs-mobile 的 polyfill 提供。
- 鸿蒙：从 Node.js 源码编译（`--dest-os=openharmony --shared`），使用 OpenHarmony 的 LLVM 19。`libnode.so` 依赖系统的 `libc++_shared.so`。x64 版目前只通过了编译检查，还没有在鸿蒙的 x86_64 模拟器上运行过。

## 版本

`versions.env` 记录每次编译使用的版本：Node.js、nodejs-mobile 配方的提交（它给同一个 Node.js 版本打补丁）、NDK 和 OpenHarmony 的 LLVM。它们一起升级。同一个 Node.js 版本需要重新编译时（补丁或工具链有变化），设置 `REVISION`，发布的 tag 就是 `v<版本>-<修订号>`。

## 发布

1. 修改 `versions.env` 并推送：Build 工作流会编译所有压缩包（需要几个小时），并检查发布用的文件。
2. 推送 tag `v<版本>`，它必须与 `versions.env` 一致：工作流会重新编译，并发布这个版本。

OpenHarmony 的 LLVM 来自它 CI 的每日构建，过一段时间就会被删除。`versions.env` 换用新的 LLVM 时，运行一次 Toolchains 工作流，它会把 LLVM 复制到本仓库的 `toolchains` 发布中。编译时优先从那里下载，并用 sha256 校验。

## 在本地编译

```bash
node scripts/build.mjs <平台> <架构>    # 生成 dist/libnode_<平台>_<架构>.tar.gz
```

Android 和鸿蒙由 `Dockerfile` 在 Docker 中编译（linux/amd64，在 Apple 芯片的 Mac 上靠模拟运行，需要几个小时）；iOS 在 macOS 上用 Xcode 编译（`ios/build.sh`）。脚本需要 Node.js 20 或更高版本。

## 许可

本仓库的脚本采用 MIT 许可。压缩包遵循 Node.js 及其依赖的许可（见压缩包里的 `LICENSE`），nodejs-mobile 的补丁采用 MIT 许可。
