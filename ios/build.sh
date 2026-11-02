#!/bin/bash
# libnode of iOS, built on macOS with Xcode as the CI of the recipe of digidem/nodejs-mobile builds it (the script
# tools/ios_framework_prepare.sh of its tree): NodeMobile.xcframework, with the slices of the device and of the
# simulator (arm64), and its headers.
# Usage:
#   ios/build.sh <work> slice <arm64|arm64-simulator>   a slice, in <work>/node/out_ios_<slice>
#   ios/build.sh <work> combine <out>                    the xcframework of both slices and the headers, in <out>
#   ios/build.sh <work> all <out>                        both slices, then combine
#   ios/build.sh <work> tree                             the source tree only (the slices built elsewhere copied in it)
# <work> holds the source tree the recipe makes (node) and a Python environment (python), made once; PYTHON gives the
# Python making it (3.9 to 3.13)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$1
command=$2
set -a
. "$here/versions.env"
set +a
mkdir -p "$work"
work=$(cd "$work" && pwd)
target=${3:-}
case "$command" in
    combine | all) mkdir -p "$target" && target=$(cd "$target" && pwd) ;;
esac

if [ ! -d "$work/node" ]; then
    echo "Making the source tree of nodejs-mobile (recipe $RECIPE_COMMIT)"
    rm -rf "$work/recipe"
    git clone -q --filter=blob:none https://github.com/digidem/nodejs-mobile.git "$work/recipe"
    git -C "$work/recipe" checkout -q "$RECIPE_COMMIT"
    "$work/recipe/scripts/prepare.sh" "$work/node" > "$work/prepare.log" 2>&1 || { tail -40 "$work/prepare.log"; exit 1; }
    rm -rf "$work/recipe"
fi
# gyp needs setuptools from Python 3.12 on (distutils removed)
if [ ! -x "$work/python/bin/python3" ]; then
    "${PYTHON:-python3}" -m venv "$work/python"
    "$work/python/bin/python3" -m pip install -q setuptools
fi
export PATH="$work/python/bin:$PATH"
cd "$work/node"

# A slice: the framework of the recipe's Xcode project, and the configuration of Node.js it was built with (the
# config.gypi of the headers)
slice() {
    echo "Building libnode for iOS ($1)"
    ./tools/ios_framework_prepare.sh "$1" > "$work/$1.log" 2>&1 || { tail -60 "$work/$1.log"; exit 1; }
    cp config.gypi "out_ios_$1/config.gypi"
}

# The symbols of node the native modules embedding it call (node.h), exported by every slice
check() {
    local framework=$1 platform=$2 symbols
    symbols=$(nm -gU "$framework/NodeMobile" | c++filt)
    for symbol in 'node::InitializeOncePerProcess(' 'node::CommonEnvironmentSetup::CommonEnvironmentSetup(' \
        'node::LoadEnvironment(' 'node::SetProcessExitHandler(' 'node::SpinEventLoop(' 'node::Stop(' 'napi_create_function'; do
        grep -qF "$symbol" <<< "$symbols" || { echo "$framework does not export $symbol" >&2; exit 1; }
    done
    [ "$(lipo -archs "$framework/NodeMobile")" = arm64 ] || { echo "$framework is not built for arm64 only" >&2; exit 1; }
    vtool -show-build "$framework/NodeMobile" | grep -q "platform $platform\$" || { echo "$framework is not built for $platform" >&2; exit 1; }
    echo "$framework: arm64, $platform, minimum iOS $(vtool -show-build "$framework/NodeMobile" | awk '$1 == "minos" { print $2; exit }'), the symbols of node.h exported"
}

combine() {
    local slice
    rm -rf out_ios
    mkdir -p out_ios
    for slice in arm64 arm64-simulator; do
        [ -d "out_ios_$slice" ] || { echo "The slice $slice is missing (out_ios_$slice)" >&2; exit 1; }
        cp -R "out_ios_$slice/." out_ios/
    done
    ./tools/ios_framework_prepare.sh combine_frameworks > "$work/combine.log" 2>&1 || { tail -40 "$work/combine.log"; exit 1; }
    check out_ios/NodeMobile.xcframework/ios-arm64/NodeMobile.framework IOS
    check out_ios/NodeMobile.xcframework/ios-arm64-simulator/NodeMobile.framework IOSSIMULATOR
    # The headers with the configuration of the device
    cp out_ios_arm64/config.gypi config.gypi
    bash tools/copy_libnode_headers.sh ios > /dev/null
    cp common.gypi config.gypi out_ios/libnode/include/node/
    rm -rf "${target:?}"/*
    cp -R out_ios/NodeMobile.xcframework "$target/NodeMobile.xcframework"
    cp -R out_ios/libnode/include "$target/include"
    cp LICENSE "$target/LICENSE"
}

case "$command" in
    slice) slice "$target" ;;
    combine) combine ;;
    all) slice arm64 && slice arm64-simulator && combine ;;
    tree) ;;
    *) echo "Usage: ios/build.sh <work> slice <arm64|arm64-simulator> | combine <out> | all <out> | tree" >&2; exit 1 ;;
esac
