// Pack the libnode a build exported (lib/libnode.so or NodeMobile.xcframework, include, LICENSE) into
// <dist>/libnode_<platform>_<arch>.tar.gz, with its description, libnode.json (its version among others):
//   node scripts/package.mjs <platform> <arch> <export> [dist]
import {spawnSync} from 'node:child_process'
import {cpSync, existsSync, mkdirSync, rmSync, writeFileSync} from 'node:fs'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
import {ROOT, TARGETS, assetName, readVersions, releaseVersion} from './versions.mjs'

/**
 * Pack an export into the archive of its system and its architecture
 * @param {string} platform
 * @param {string} arch
 * @param {string} exported
 * @param {string} dist
 * @returns {string} the archive
 */
export function packLibnode(platform, arch, exported, dist = path.join(ROOT, 'dist')) {
    const target = TARGETS[platform]?.[arch]
    if (!target) throw new Error(`Unknown system and architecture: ${platform} ${arch}`)
    const library = platform === 'ios' ? 'NodeMobile.xcframework' : 'lib/libnode.so'
    for (const file of [library, 'include/node/node.h', 'LICENSE']) {
        if (!existsSync(path.join(exported, file))) throw new Error(`${file} is missing in ${exported}`)
    }
    const versions = readVersions()
    const version = releaseVersion(versions)
    const name = assetName(platform, arch)
    const stage = path.join(dist, name)
    rmSync(stage, {recursive: true, force: true})
    mkdirSync(stage, {recursive: true})
    cpSync(exported, stage, {recursive: true, verbatimSymlinks: true})
    const description = {
        name: name,
        version: version,
        node: versions.NODE_VERSION,
        platform: platform,
        arch: arch,
        ...target,
        library: library,
        headers: 'include/node',
        //Android and iOS: the patches of nodejs-mobile; HarmonyOS: the sources of Node.js
        ...platform === 'harmony' ? {} : {recipe: versions.RECIPE_COMMIT},
        ...platform === 'android' ? {minSdkVersion: Number(versions.ANDROID_API)} : {}
    }
    writeFileSync(path.join(stage, 'libnode.json'), `${JSON.stringify(description, null, 2)}\n`)
    const archive = path.join(dist, `${name}.tar.gz`)
    rmSync(archive, {force: true})
    //Without the metadata of macOS (its ._ files, its extended attributes)
    const metadata = process.platform === 'darwin' ? ['--no-mac-metadata'] : []
    const packed = spawnSync('tar', [...metadata, '-czf', path.basename(archive), name], {cwd: dist, stdio: 'inherit', env: {...process.env, COPYFILE_DISABLE: '1'}})
    rmSync(stage, {recursive: true, force: true})
    if (packed.status !== 0) throw new Error(`tar failed packing ${name}`)
    return archive
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const [platform, arch, exported, dist] = process.argv.slice(2)
    if (!exported) {
        console.error('Usage: node scripts/package.mjs <platform> <arch> <export> [dist]')
        process.exit(1)
    }
    console.log(packLibnode(platform, arch, path.resolve(exported), dist ? path.resolve(dist) : undefined))
}
