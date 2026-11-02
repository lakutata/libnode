// Build the libnode of a system for an architecture and pack it into dist (scripts/package.mjs):
//   node scripts/build.mjs <android|ios|harmony> <arch> [--jobs <n>] [--dist <dir>] [--work <dir>]
// Android and HarmonyOS are built by the Dockerfile (Docker, linux/amd64: emulated on other machines), iOS by
// ios/build.sh (macOS, Xcode). --work keeps the directory of the build (by default a temporary one, removed after)
import {execFileSync, spawnSync} from 'node:child_process'
import {mkdirSync, mkdtempSync, rmSync} from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {parseArgs} from 'node:util'
import {packLibnode} from './package.mjs'
import {ROOT, TARGETS, readVersions} from './versions.mjs'

const {positionals, values} = parseArgs({
    allowPositionals: true,
    options: {
        jobs: {type: 'string'},
        dist: {type: 'string', default: path.join(ROOT, 'dist')},
        work: {type: 'string'}
    }
})
const [platform, arch] = positionals
if (!TARGETS[platform]?.[arch]) {
    const targets = Object.entries(TARGETS).flatMap(([platform, archs]) => Object.keys(archs).map((arch) => `${platform} ${arch}`))
    console.error(`Usage: node scripts/build.mjs <platform> <arch> [--jobs <n>] [--dist <dir>] [--work <dir>]\nThe systems and architectures: ${targets.join(', ')}`)
    process.exit(1)
}

/**
 * The jobs of make in Docker: about 2 GB of memory each (V8), no more than its processors
 */
function dockerJobs() {
    const [processors, memory] = execFileSync('docker', ['info', '--format', '{{.NCPU}} {{.MemTotal}}'], {encoding: 'utf8'}).trim().split(' ').map(Number)
    return Math.max(1, Math.min(processors, Math.floor(memory / 2 ** 31)))
}

/**
 * Run a command, its output shown; exit with it when it fails
 * @param {string} command
 * @param {string[]} args
 * @param {Record<string, string>} env
 */
function run(command, args, env = {}) {
    const result = spawnSync(command, args, {stdio: 'inherit', cwd: ROOT, env: {...process.env, ...env}})
    if (result.status !== 0) {
        console.error(`${command} failed (${result.status ?? result.signal})`)
        process.exit(1)
    }
}

const versions = readVersions()
const work = values.work ? path.resolve(values.work) : mkdtempSync(path.join(os.tmpdir(), 'libnode-'))
const exported = path.join(work, 'export')
rmSync(exported, {recursive: true, force: true})
mkdirSync(exported, {recursive: true})
if (platform === 'ios') {
    if (process.platform !== 'darwin') {
        console.error('The libnode of iOS is built on macOS, with Xcode')
        process.exit(1)
    }
    run(path.join(ROOT, 'ios', 'build.sh'), [path.join(work, 'ios'), 'all', exported])
} else {
    const jobs = values.jobs ?? String(dockerJobs())
    const args = Object.entries({...versions, ARCH: arch, JOBS: jobs}).flatMap(([name, value]) => ['--build-arg', `${name}=${value}`])
    run('docker', ['buildx', 'build', '--platform', 'linux/amd64', '--target', platform, ...args, '--progress', 'plain', '--output', `type=local,dest=${exported}`, ROOT])
}
console.log(packLibnode(platform, arch, exported, path.resolve(values.dist)))
if (!values.work) rmSync(work, {recursive: true, force: true})
