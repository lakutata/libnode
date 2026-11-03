#!/bin/sh
# Check a libnode.so built for Android or HarmonyOS: its machine, its name (SONAME libnode.so: the native addons link
# it by that name), the order of its program headers (each note after the loaded segment holding it: the loader of
# HarmonyOS finds none of the symbols of a library listing the note first, as patchelf 0.18 laid out one it renamed)
# and, given an alignment, the one of its loaded segments (Android: pages of 16 KB)
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
if ! "$readelf" -lW "$file" | awk '$1 == "LOAD" || $1 == "NOTE" { print $1, $2, $5 }' | {
    loads=
    while read -r type offset size; do
        if [ "$type" = LOAD ]; then
            loads="$loads $(($offset)):$(($offset + $size))"
            continue
        fi
        held=
        for load in $loads; do
            if [ $(($offset)) -ge "${load%:*}" ] && [ $(($offset + $size)) -le "${load#*:}" ]; then held=1; fi
        done
        [ -n "$held" ] || exit 1
    done
}; then
    echo "The program headers of $file list a note before the loaded segment holding it:" >&2
    "$readelf" -lW "$file" | grep -E '^ +(LOAD|NOTE) ' >&2
    exit 1
fi
if [ -n "$alignment" ] && ! "$readelf" -lW "$file" | awk -v alignment="$alignment" '$1 == "LOAD" { loads++; if ($NF != alignment) misaligned++ } END { exit !(loads && !misaligned) }'; then
    echo "The segments of $file are not aligned to $alignment:" >&2
    "$readelf" -lW "$file" | grep LOAD >&2
    exit 1
fi
echo "$file: $machine, SONAME libnode.so, notes after their segments${alignment:+, segments aligned to $alignment}"
