// The files of a release, next to its archives in dist: SHA256SUMS, manifest.json (the archives with their systems,
// architectures, sizes and sha256) and notes.md (the notes of the release):
//   node scripts/manifest.mjs [dist] [--tag <tag>]
// Every system and architecture must have its archive; the tag of a release must be v<version>
import {createHash} from 'node:crypto'
import {readFileSync, readdirSync, statSync, writeFileSync} from 'node:fs'
import path from 'node:path'
import {parseArgs} from 'node:util'
import {ROOT, TARGETS, assetName, readVersions, releaseVersion} from './versions.mjs'

const {positionals, values} = parseArgs({allowPositionals: true, options: {tag: {type: 'string'}}})
const dist = path.resolve(positionals[0] ?? path.join(ROOT, 'dist'))
const versions = readVersions()
const version = releaseVersion(versions)
if (values.tag !== undefined && values.tag !== `v${version}`) {
    console.error(`The tag ${values.tag} is not the version of versions.env (v${version})`)
    process.exit(1)
}
const archives = new Set(readdirSync(dist).filter((file) => file.endsWith('.tar.gz')))
const assets = []
for (const [platform, archs] of Object.entries(TARGETS)) {
    for (const [arch, target] of Object.entries(archs)) {
        const file = `${assetName(platform, arch)}.tar.gz`
        if (!archives.delete(file)) {
            console.error(`${file} is missing in ${dist}`)
            process.exit(1)
        }
        const data = readFileSync(path.join(dist, file))
        assets.push({name: file, platform: platform, arch: arch, ...target, size: statSync(path.join(dist, file)).size, sha256: createHash('sha256').update(data).digest('hex')})
    }
}
if (archives.size) {
    console.error(`Archives of no known system: ${[...archives].join(', ')}`)
    process.exit(1)
}
writeFileSync(path.join(dist, 'SHA256SUMS'), assets.map((asset) => `${asset.sha256}  ${asset.name}\n`).join(''))
writeFileSync(path.join(dist, 'manifest.json'), `${JSON.stringify({
    version: version,
    node: versions.NODE_VERSION,
    recipe: versions.RECIPE_COMMIT,
    android: {ndk: versions.ANDROID_NDK_VERSION, minSdkVersion: Number(versions.ANDROID_API)},
    harmony: {llvm: path.basename(versions.OHOS_LLVM_MIRROR)},
    assets: assets
}, null, 2)}\n`)
const megabytes = (size) => `${(size / 2 ** 20).toFixed(1)} MB`
writeFileSync(path.join(dist, 'notes.md'), [
    `libnode ${version}: Node.js ${versions.NODE_VERSION} as a library for Android, iOS and HarmonyOS.`,
    '',
    `- Android and iOS: the patches of [nodejs-mobile](https://github.com/digidem/nodejs-mobile) (recipe ${versions.RECIPE_COMMIT.slice(0, 8)}); Android built with the NDK ${versions.ANDROID_NDK_VERSION} for API ${versions.ANDROID_API} and later, its segments aligned to pages of 16 KB.`,
    '- HarmonyOS: the sources of Node.js, built with the LLVM 19 of OpenHarmony. The x64 library is checked by its build only.',
    '',
    '| Archive | System | Architecture | Size |',
    '|---|---|---|---|',
    ...assets.map((asset) => `| \`${asset.name}\` | ${asset.platform} | ${asset.arch}${asset.abi ? ` (${asset.abi})` : ''} | ${megabytes(asset.size)} |`),
    '',
    'Their sha256 are in `SHA256SUMS`, and `manifest.json` describes them.',
    ''
].join('\n'))
console.log(`${assets.length} archives of libnode ${version}: SHA256SUMS, manifest.json, notes.md`)
