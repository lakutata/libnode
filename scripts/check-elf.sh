#!/bin/sh
# Check a libnode.so built for Android or HarmonyOS: its machine, its name (SONAME libnode.so: the native addons link
# it by that name) and, given an alignment, the one of its loaded segments (Android: pages of 16 KB)
# Usage: check-elf.sh <readelf> <file> <machine> [alignment]
set -e
readelf=$1
file=$2
machine=$3
alignment=$4
if ! "$readelf" -h "$file" | grep -Eq "Machine:.*$machine\$"; then
    echo "$file is not built for $machine:" >&2
    "$readelf" -h "$file" | grep Machine: >&2
    exit 1
fi
if ! "$readelf" -d "$file" | grep -q 'SONAME.*\[libnode\.so\]'; then
    echo "$file is not named libnode.so (its SONAME):" >&2
    "$readelf" -d "$file" | grep SONAME >&2
    exit 1
fi
if [ -n "$alignment" ] && ! "$readelf" -lW "$file" | awk -v alignment="$alignment" '$1 == "LOAD" { loads++; if ($NF != alignment) misaligned++ } END { exit !(loads && !misaligned) }'; then
    echo "The segments of $file are not aligned to $alignment:" >&2
    "$readelf" -lW "$file" | grep LOAD >&2
    exit 1
fi
echo "$file: $machine, SONAME libnode.so${alignment:+, segments aligned to $alignment}"
