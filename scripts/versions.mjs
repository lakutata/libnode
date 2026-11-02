import {readFileSync} from 'node:fs'
import path from 'node:path'
import {fileURLToPath} from 'node:url'

/**
 * The directory of the repository
 */
export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

/**
 * The systems and their architectures, named as Node.js names them (process.arch): abi is the directory of the
 * libraries of the applications (the jniLibs of Android, the libs of a HAP), slices the libraries of the xcframework
 */
export const TARGETS = {
    android: {
        arm64: {abi: 'arm64-v8a'},
        arm: {abi: 'armeabi-v7a'},
        x64: {abi: 'x86_64'}
    },
    ios: {
        arm64: {slices: ['ios-arm64', 'ios-arm64-simulator']}
    },
    harmony: {
        arm64: {abi: 'arm64-v8a'},
        x64: {abi: 'x86_64'}
    }
}

/**
 * The versions of versions.env
 * @returns {Record<string, string>}
 */
export function readVersions() {
    const versions = {}
    for (const line of readFileSync(path.join(ROOT, 'versions.env'), 'utf8').split('\n')) {
        const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim())
        if (match) versions[match[1]] = match[2]
    }
    return versions
}

/**
 * The version of the release: the one of Node.js, then the revision of its build when it is built again
 * @param {Record<string, string>} versions
 */
export function releaseVersion(versions = readVersions()) {
    return versions.REVISION ? `${versions.NODE_VERSION}-${versions.REVISION}` : versions.NODE_VERSION
}

/**
 * The name of the archive of a system and an architecture, libnode_<platform>_<arch> (the version is the one of its
 * release, given in its libnode.json)
 * @param {string} platform
 * @param {string} arch
 */
export function assetName(platform, arch) {
    return `libnode_${platform}_${arch}`
}
