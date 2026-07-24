'use strict'

// This test-only preload observes the actual bundled proxy without ever
// persisting the credential. It fails if header-only mode touches mutable
// OAuth state, starts a callback server, or spawns another process.
const childProcess = require('node:child_process')
const fs = require('node:fs')
const fsPromises = require('node:fs/promises')
const moduleBuiltin = require('node:module')
const net = require('node:net')
const path = require('node:path')
const { URL, fileURLToPath } = require('node:url')

const eventFile = process.env.TASK3_ORACLE_EVENT_FILE
const secretEnvName = process.env.TASK3_ORACLE_SECRET_ENV_NAME
const expectedArgsJson = process.env.TASK3_ORACLE_EXPECTED_ARGS
const expectedParentPid = Number(process.env.TASK3_ORACLE_PARENT_PID)
const expectedUrl = process.env.TASK3_ORACLE_URL
const forbiddenConfig = process.env.MCP_REMOTE_CONFIG_DIR

if (
  !eventFile ||
  !secretEnvName ||
  !expectedArgsJson ||
  !Number.isInteger(expectedParentPid) ||
  !expectedUrl ||
  !forbiddenConfig
) {
  throw new Error('task3 bridge oracle guard is incomplete')
}

const originalAppendFileSync = fs.appendFileSync.bind(fs)

function record(event) {
  originalAppendFileSync(eventFile, `${JSON.stringify(event)}\n`, {
    encoding: 'utf8',
    mode: 0o600,
  })
}

function reject(event) {
  record(event)
  throw new Error('task3 bridge oracle rejected runtime behavior')
}

const expectedArgs = JSON.parse(expectedArgsJson)
const actualArgs = process.argv.slice(2)
const argvExact = JSON.stringify(actualArgs) === JSON.stringify(expectedArgs)
const directExec = process.ppid === expectedParentPid

record({ event: 'argv', argvExact, directExec })
if (!argvExact || !directExec) {
  throw new Error('task3 bridge oracle rejected process startup')
}

const forbiddenRoot = path.resolve(forbiddenConfig)

function normalizedPath(value) {
  try {
    if (value instanceof URL && value.protocol === 'file:') {
      return path.resolve(fileURLToPath(value))
    }
    if (Buffer.isBuffer(value)) return path.resolve(value.toString())
    if (typeof value === 'string') return path.resolve(value)
  } catch {
    return null
  }
  return null
}

function touchesForbiddenConfig(args) {
  return args.some((value) => {
    const candidate = normalizedPath(value)
    return (
      candidate === forbiddenRoot || candidate?.startsWith(`${forbiddenRoot}${path.sep}`)
    )
  })
}

function guardFileMethods(target, names) {
  for (const name of names) {
    const original = target[name]
    if (typeof original !== 'function') continue
    target[name] = function guardedFileMethod(...args) {
      if (touchesForbiddenConfig(args)) {
        reject({ event: 'config-access', operation: name })
      }
      return Reflect.apply(original, this, args)
    }
  }
}

const guardedFileOperations = [
  'access',
  'accessSync',
  'appendFile',
  'appendFileSync',
  'chmod',
  'chmodSync',
  'copyFile',
  'copyFileSync',
  'cp',
  'cpSync',
  'existsSync',
  'lstat',
  'lstatSync',
  'mkdir',
  'mkdirSync',
  'mkdtemp',
  'mkdtempSync',
  'open',
  'openSync',
  'opendir',
  'opendirSync',
  'readFile',
  'readFileSync',
  'readdir',
  'readdirSync',
  'readlink',
  'readlinkSync',
  'realpath',
  'realpathSync',
  'rename',
  'renameSync',
  'rm',
  'rmSync',
  'rmdir',
  'rmdirSync',
  'stat',
  'statSync',
  'symlink',
  'symlinkSync',
  'truncate',
  'truncateSync',
  'unlink',
  'unlinkSync',
  'utimes',
  'utimesSync',
  'writeFile',
  'writeFileSync',
]

guardFileMethods(fs, guardedFileOperations)
guardFileMethods(fsPromises, guardedFileOperations)

for (const name of ['exec', 'execFile', 'execFileSync', 'execSync', 'fork', 'spawn', 'spawnSync']) {
  if (typeof childProcess[name] !== 'function') continue
  childProcess[name] = function rejectedChildProcess() {
    reject({
      event: 'child-process',
      operation: name,
      credentialStillPresent: Object.hasOwn(process.env, secretEnvName),
    })
  }
}

net.Server.prototype.listen = function rejectedListener() {
  reject({ event: 'local-listener' })
}

moduleBuiltin.syncBuiltinESMExports()

const originalFetch = globalThis.fetch
if (typeof originalFetch !== 'function') {
  throw new Error('task3 bridge oracle requires global fetch')
}

globalThis.fetch = async function guardedFetch(input, init) {
  const target =
    typeof input === 'string' || input instanceof URL ? String(input) : input.url
  const allowedUrl = target === expectedUrl
  const environmentDeleted = !Object.hasOwn(process.env, secretEnvName)
  const redirectIsError = (init?.redirect ?? input?.redirect) === 'error'
  const method = String(init?.method ?? input?.method ?? 'GET').toUpperCase()

  let safePath = '<redacted>'
  if (allowedUrl) {
    try {
      safePath = new URL(target).pathname
    } catch {
      safePath = '<invalid>'
    }
  }

  record({
    event: 'fetch',
    path: safePath,
    method,
    allowedUrl,
    environmentDeleted,
    redirectIsError,
  })

  if (!allowedUrl || !environmentDeleted || !redirectIsError) {
    throw new Error('task3 bridge oracle rejected outbound request')
  }
  return Reflect.apply(originalFetch, this, [input, init])
}
