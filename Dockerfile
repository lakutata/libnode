# syntax=docker/dockerfile:1
# libnode, the shared library of Node.js, and its headers for Android and HarmonyOS, built from the sources for one
# architecture. scripts/build.mjs runs it with the versions of versions.env:
#   docker buildx build --platform linux/amd64 --target <android|harmony> --build-arg ARCH=<arch> \
#     --build-arg NODE_VERSION=... (every version of versions.env) --output type=local,dest=<dir> .
# Each target exports its files only (FROM scratch): lib/libnode.so, include (the headers of the native addons) and the
# LICENSE of Node.js. The build directories are removed in the step making them (the build cache keeps no gigabytes of
# objects); the output of configure and make goes to files (BuildKit clips the output of a step at 2 MiB), their ends
# printed when they fail.

# The jobs of make: V8 takes over a gigabyte per job
ARG JOBS=4

# ---------------------------------------------------------------------------------------------------------------------
# HarmonyOS: the LLVM 19 of OpenHarmony (Linux x86_64 only), a shared library (dlopened: PIE breaks its thread-local
# storage), the native thread-local storage (-fno-emulated-tls), named libnode.so (the addons link it by that name)
FROM node:22-bookworm AS harmony-build
ARG ARCH
ARG JOBS
ARG NODE_VERSION
ARG OHOS_LLVM_URL
ARG OHOS_LLVM_SHA256
ARG OHOS_LLVM_MIRROR
RUN apt-get update && apt-get install -y --no-install-recommends patchelf && rm -rf /var/lib/apt/lists/*
WORKDIR /build
# The copy of this repository first, the URL of OpenHarmony else; checked by its sha256 either way
RUN test -n "$OHOS_LLVM_SHA256" || { echo "OHOS_LLVM_SHA256 missing: build with scripts/build.mjs" >&2; exit 1; }; \
    fetch() { curl -fsSL -o llvm.tar.gz "$1" && echo "$OHOS_LLVM_SHA256  llvm.tar.gz" | sha256sum -c -; }; \
    { [ -n "$OHOS_LLVM_MIRROR" ] && fetch "$OHOS_LLVM_MIRROR"; } || fetch "$OHOS_LLVM_URL" || exit 1; \
    tar -xzf llvm.tar.gz llvm-linux-x86_64.tar.gz ohos-sysroot.tar.gz \
 && tar -xzf llvm-linux-x86_64.tar.gz && tar -xzf ohos-sysroot.tar.gz \
 && rm -f llvm.tar.gz llvm-linux-x86_64.tar.gz ohos-sysroot.tar.gz
RUN test -n "$NODE_VERSION" || { echo "NODE_VERSION missing: build with scripts/build.mjs" >&2; exit 1; }; \
    curl -fsSLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.xz" \
 && curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" | grep " node-v$NODE_VERSION.tar.xz\$" | sha256sum -c - \
 && tar -xJf "node-v$NODE_VERSION.tar.xz" && mv "node-v$NODE_VERSION" node && rm "node-v$NODE_VERSION.tar.xz"
RUN case "$ARCH" in \
      arm64) triple=aarch64-unknown-linux-ohos; cpu=arm64 ;; \
      x64) triple=x86_64-unknown-linux-ohos; cpu=x64 ;; \
      *) echo "unknown architecture of HarmonyOS: $ARCH (arm64, x64)" >&2; exit 1 ;; \
    esac; \
    cd node \
 && export CC="/build/llvm/bin/$triple-clang -fno-emulated-tls" CXX="/build/llvm/bin/$triple-clang++ -fno-emulated-tls" \
           AR=/build/llvm/bin/llvm-ar AR_target=/build/llvm/bin/llvm-ar AR_host=ar \
           CC_host=gcc CXX_host=g++ LINK_host=g++ CFLAGS=-DNDEBUG CXXFLAGS=-DNDEBUG \
 && ./configure --dest-cpu="$cpu" --dest-os=openharmony --cross-compiling --openssl-no-asm --shared --prefix=/build/install > /tmp/configure.log 2>&1 || { tail -40 /tmp/configure.log; exit 1; }; \
    echo "Building libnode.so for HarmonyOS ($ARCH)"; \
    make -j"$JOBS" > /tmp/make.log 2>&1 || { tail -60 /tmp/make.log; exit 1; }; \
    make install > /tmp/install.log 2>&1 || { tail -40 /tmp/install.log; exit 1; }; \
    cp LICENSE /build/install/LICENSE && cd /build && rm -rf node
COPY scripts/check-elf.sh /build/check-elf.sh
RUN case "$ARCH" in arm64) machine=AArch64 ;; x64) machine=X86-64 ;; esac; \
    mkdir -p /export/lib \
 && /build/llvm/bin/llvm-strip -o /export/lib/libnode.so "$(ls /build/install/lib/libnode.so.* | head -1)" \
 && patchelf --set-soname libnode.so /export/lib/libnode.so \
 && sh /build/check-elf.sh /build/llvm/bin/llvm-readelf /export/lib/libnode.so "$machine" \
 && cp -R /build/install/include /export/include && cp /build/install/LICENSE /export/LICENSE

FROM scratch AS harmony
COPY --from=harmony-build /export/ /

# ---------------------------------------------------------------------------------------------------------------------
# The source tree of nodejs-mobile, made by its recipe (scripts/prepare.sh checks the tree it makes)
FROM node:22-bookworm AS recipe
ARG RECIPE_COMMIT
RUN test -n "$RECIPE_COMMIT" || { echo "RECIPE_COMMIT missing: build with scripts/build.mjs" >&2; exit 1; }; \
    git clone --filter=blob:none https://github.com/digidem/nodejs-mobile.git /recipe \
 && git -C /recipe checkout -q "$RECIPE_COMMIT" \
 && /recipe/scripts/prepare.sh /build/node && rm -rf /recipe

# ---------------------------------------------------------------------------------------------------------------------
# Android: the NDK (Linux only: node's gyp archives thin archives and links its host tools with --start-group), the
# library aligned to pages of 16 KB (Android 15 and later, Google Play), as the CI of the recipe builds it: on Ubuntu
# 24.04, whose clang builds the host tools (the recipe takes the clang of the PATH; the clang of the NDK does not find
# the 32-bit libatomic of the system the host tools of arm link)
FROM ubuntu:24.04 AS android-build
ARG ARCH
ARG JOBS
ARG ANDROID_NDK_VERSION
ARG ANDROID_API
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl unzip git make \
      python3 python3-setuptools rsync clang gcc-multilib g++-multilib \
 && rm -rf /var/lib/apt/lists/*
RUN test -n "$ANDROID_NDK_VERSION" || { echo "ANDROID_NDK_VERSION missing: build with scripts/build.mjs" >&2; exit 1; }; \
    curl -fsSL -o /tmp/ndk.zip "https://dl.google.com/android/repository/android-ndk-$ANDROID_NDK_VERSION-linux.zip" \
 && unzip -q /tmp/ndk.zip -d /opt && rm /tmp/ndk.zip && mv "/opt/android-ndk-$ANDROID_NDK_VERSION" /opt/ndk
COPY --from=recipe /build/node /build/node
RUN case "$ARCH" in \
      arm64) arch=arm64 ;; \
      arm) arch=arm ;; \
      x64) arch=x86_64 ;; \
      *) echo "unknown architecture of Android: $ARCH (arm64, arm, x64)" >&2; exit 1 ;; \
    esac; \
    cd /build/node && export LDFLAGS=-Wl,-z,max-page-size=16384; \
    ./android-configure /opt/ndk "$ANDROID_API" "$arch" > /tmp/configure.log 2>&1 || { tail -40 /tmp/configure.log; exit 1; }; \
    echo "Building libnode.so for Android ($ARCH)"; \
    make -j"$JOBS" > /tmp/make.log 2>&1 || { tail -60 /tmp/make.log; exit 1; }; \
    mkdir -p /export/lib \
 && cp "$(ls out/Release/lib.target/libnode.so out/Release/obj.target/libnode.so 2>/dev/null | head -1)" /export/lib/libnode.so \
 && bash tools/copy_libnode_headers.sh android > /dev/null \
 && cp common.gypi config.gypi out_android/libnode/include/node/ \
 && cp -R out_android/libnode/include /export/include && cp LICENSE /export/LICENSE \
 && cd / && rm -rf /build/node
COPY scripts/check-elf.sh /build/check-elf.sh
RUN case "$ARCH" in arm64) machine=AArch64 ;; arm) machine=ARM ;; x64) machine=X86-64 ;; esac; \
    sh /build/check-elf.sh /opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf /export/lib/libnode.so "$machine" 0x4000

FROM scratch AS android
COPY --from=android-build /export/ /
