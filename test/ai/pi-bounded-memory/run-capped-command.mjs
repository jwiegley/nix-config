#!/usr/bin/env node
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  closeSync,
  constants as fsConstants,
  existsSync,
  fsyncSync,
  ftruncateSync,
  lstatSync,
  openSync,
  writeSync,
} from "node:fs";
import { constants as osConstants } from "node:os";
import { dirname, resolve } from "node:path";
import {
  check,
  hashFile,
  parseArgs,
  planAtomicOutputs,
  publishNoClobber,
  sha256,
  sortedJsonValue,
  structuredSha256,
  tempFileIdentity,
  unlinkOwnedTemp,
} from "./common.mjs";

const FROZEN_MAX_BYTES = 16777216;
const MAX_ARGUMENT_COUNT = 64;
const MAX_ARGUMENT_BYTES = 65536;
const MAX_ARGUMENT_BYTES_PER_ARGUMENT = 4096;
const SIGNAL_GRACE_MILLISECONDS = 1000;

const separator = process.argv.indexOf("--", 2);
check(separator >= 0, "missing -- before command");
const args = parseArgs(process.argv.slice(2, separator), ["stdout", "stderr", "run-result", "max-bytes"]);
const command = process.argv.slice(separator + 1);
check(command.length > 0 && command[0].length > 0, "missing command");
check(command.length <= MAX_ARGUMENT_COUNT, `command exceeds ${MAX_ARGUMENT_COUNT} arguments`);
let argvBytes = 0;
for (const value of command) {
  check(typeof value === "string" && !value.includes("\0"), "command contains an invalid argument");
  const encodedBytes = Buffer.byteLength(value, "utf8") + 1;
  check(encodedBytes <= MAX_ARGUMENT_BYTES_PER_ARGUMENT, "encoded command argument exceeds 4,096 bytes");
  argvBytes += encodedBytes;
}
check(argvBytes <= MAX_ARGUMENT_BYTES, "encoded command arguments exceed 65,536 bytes");
check(args["max-bytes"] === String(FROZEN_MAX_BYTES), "--max-bytes must equal the frozen 16 MiB cap");
const maxBytes = FROZEN_MAX_BYTES;
check(process.platform !== "win32", "capped command requires POSIX process groups");
const outputPlan = planAtomicOutputs([args.stdout, args.stderr, args["run-result"]]);

function errorName(error) {
  return typeof error?.code === "string" ? error.code : error?.name ?? "Error";
}

function writeAll(fd, bytes) {
  let offset = 0;
  while (offset < bytes.length) {
    const count = writeSync(fd, bytes, offset, bytes.length - offset);
    check(count > 0, "output write made no progress");
    offset += count;
  }
}

function cleanupFailure(error, cleanupErrors, message) {
  if (cleanupErrors.length === 0) return error;
  return new AggregateError([error, ...cleanupErrors], message);
}

function cleanupOwned(resource) {
  const errors = [];
  if (resource.fd !== undefined) {
    const fd = resource.fd;
    resource.fd = undefined;
    try {
      closeSync(fd);
    } catch (error) {
      errors.push(error);
    }
  }
  if (resource.identity !== undefined) {
    try {
      unlinkOwnedTemp(resource.temp, resource.identity);
    } catch (error) {
      errors.push(error);
    }
  }
  return errors;
}

function createOwnedTemp(temp) {
  const resource = { temp, fd: undefined, identity: undefined };
  try {
    resource.fd = openSync(temp, "wx", 0o600);
    resource.identity = tempFileIdentity(resource.fd);
    return resource;
  } catch (error) {
    throw cleanupFailure(error, cleanupOwned(resource), `temporary output cleanup failed: ${temp}`);
  }
}

function closeOwned(resource) {
  check(resource.fd !== undefined, `temporary output is not open: ${resource.temp}`);
  const fd = resource.fd;
  resource.fd = undefined;
  closeSync(fd);
}

function validateOutputPlan() {
  for (const { target, temp } of outputPlan) {
    const parent = dirname(target);
    const parentInfo = lstatSync(parent);
    check(parentInfo.isDirectory() && !parentInfo.isSymbolicLink(), `invalid output directory: ${parent}`);
    check(!existsSync(target), `refusing to replace output: ${target}`);
    check(!existsSync(temp), `refusing to replace temporary output: ${temp}`);
  }
}

function reserveJsonOutput(plan) {
  const resource = createOwnedTemp(plan.temp);
  try {
    closeOwned(resource);
  } catch (error) {
    throw cleanupFailure(error, cleanupOwned(resource), `run-result reservation cleanup failed: ${plan.target}`);
  }
  let finalized = false;
  return {
    publish(value) {
      check(!finalized, "run-result output finalized twice");
      try {
        const noFollow = fsConstants.O_NOFOLLOW ?? 0;
        resource.fd = openSync(resource.temp, fsConstants.O_WRONLY | noFollow);
        const reopened = tempFileIdentity(resource.fd);
        check(
          reopened.dev === resource.identity.dev && reopened.ino === resource.identity.ino,
          `run-result reservation was replaced: ${resource.temp}`,
        );
        ftruncateSync(resource.fd, 0);
        const bytes = Buffer.from(`${JSON.stringify(sortedJsonValue(value), null, 2)}\n`, "utf8");
        writeAll(resource.fd, bytes);
        fsyncSync(resource.fd);
        closeOwned(resource);
        chmodSync(resource.temp, 0o444);
        publishNoClobber(resource.temp, plan.target, resource.identity);
        finalized = true;
        return { bytes: bytes.length, sha256: sha256(bytes) };
      } catch (error) {
        finalized = true;
        throw cleanupFailure(error, cleanupOwned(resource), `run-result publication cleanup failed: ${plan.target}`);
      }
    },
    abort() {
      if (finalized) return;
      finalized = true;
      const errors = cleanupOwned(resource);
      if (errors.length > 0) throw new AggregateError(errors, `run-result reservation cleanup failed: ${plan.target}`);
    },
  };
}

function makeSink(plan) {
  const resource = createOwnedTemp(plan.temp);
  const hash = createHash("sha256");
  let bytes = 0;
  let overflow = false;
  let finalized = false;

  return {
    push(chunk) {
      check(!finalized && resource.fd !== undefined, "write to finalized capped sink");
      const available = Math.max(0, maxBytes - bytes);
      const retained = chunk.subarray(0, available);
      let offset = 0;
      while (offset < retained.length) {
        const count = writeSync(resource.fd, retained, offset, retained.length - offset);
        check(count > 0, "capped sink made no write progress");
        hash.update(retained.subarray(offset, offset + count));
        bytes += count;
        offset += count;
      }
      if (retained.length < chunk.length) overflow = true;
      return overflow;
    },
    finish() {
      check(!finalized, "capped sink finalized twice");
      finalized = true;
      let failure = null;
      let published = false;
      try {
        fsyncSync(resource.fd);
        closeOwned(resource);
        chmodSync(resource.temp, 0o444);
        publishNoClobber(resource.temp, plan.target, resource.identity);
        published = true;
      } catch (error) {
        failure = cleanupFailure(error, cleanupOwned(resource), `capped sink cleanup failed: ${plan.target}`);
      }
      return {
        path: plan.target,
        bytes,
        sha256: hash.digest("hex"),
        overflow,
        published,
        error: failure === null ? null : errorName(failure),
      };
    },
    abort() {
      if (finalized) return;
      finalized = true;
      const errors = cleanupOwned(resource);
      if (errors.length > 0) throw new AggregateError(errors, `capped sink cleanup failed: ${plan.target}`);
    },
  };
}

let child;
let childGroup = null;
let childClosed = false;
let closePromise;
let spawnError = null;
let ioError = null;
let parentSignal = null;
let terminationReason = null;
let fallbackTimer = null;
let pipeCloseTimer = null;
const signalHandlers = new Map();

function recordIoError(stream, error) {
  if (ioError === null) ioError = { stream, error };
}

function signalChildGroup(signal) {
  if (childGroup === null) return;
  try {
    process.kill(-childGroup, signal);
  } catch (error) {
    if (error?.code !== "ESRCH") recordIoError("process-group", errorName(error));
  }
}

function requestTermination(reason, signal = "SIGKILL") {
  if (terminationReason === null) terminationReason = reason;
  signalChildGroup(signal);
}

function installSignalHandlers() {
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    const handler = () => {
      if (parentSignal === null) {
        parentSignal = signal;
        requestTermination("parent-signal", signal);
        fallbackTimer = setTimeout(
          () => requestTermination("parent-signal-timeout", "SIGKILL"),
          SIGNAL_GRACE_MILLISECONDS,
        );
        fallbackTimer.unref();
      } else {
        requestTermination("repeated-parent-signal", "SIGKILL");
      }
    };
    signalHandlers.set(signal, handler);
    process.on(signal, handler);
  }
}

function removeSignalHandlers() {
  for (const [signal, handler] of signalHandlers) process.off(signal, handler);
  signalHandlers.clear();
  if (fallbackTimer !== null) clearTimeout(fallbackTimer);
  if (pipeCloseTimer !== null) clearTimeout(pipeCloseTimer);
}

function observeStream(name, stream, sink) {
  const state = { accepting: true, closed: false };
  stream.on("data", (chunk) => {
    if (!state.accepting) return;
    try {
      if (sink.push(chunk)) {
        state.accepting = false;
        requestTermination(`${name}-overflow`);
      }
    } catch (error) {
      state.accepting = false;
      recordIoError(name, errorName(error));
      requestTermination(`${name}-sink-error`);
    }
  });
  stream.once("error", (error) => {
    state.accepting = false;
    recordIoError(name, errorName(error));
    requestTermination(`${name}-stream-error`);
  });
  stream.once("close", () => {
    state.closed = true;
  });
  return state;
}

let stdoutSink;
let stderrSink;
let runResultOutput;
let finalExitCode;
installSignalHandlers();
try {
  validateOutputPlan();
  runResultOutput = reserveJsonOutput(outputPlan[2]);
  stdoutSink = makeSink(outputPlan[0]);
  stderrSink = makeSink(outputPlan[1]);

  child = spawn(command[0], command.slice(1), {
    detached: true,
    shell: false,
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (Number.isSafeInteger(child.pid) && child.pid > 0) childGroup = child.pid;
  check(child.stdout !== null && child.stderr !== null, "child pipes were not created");
  const streamStates = {
    stdout: observeStream("stdout", child.stdout, stdoutSink),
    stderr: observeStream("stderr", child.stderr, stderrSink),
  };
  closePromise = new Promise((resolveOutcome) => {
    child.once("error", (error) => {
      spawnError = errorName(error);
      requestTermination("spawn-error");
    });
    child.once("exit", () => {
      signalChildGroup("SIGKILL");
      pipeCloseTimer = setTimeout(() => {
        recordIoError("process-group", "pipe-close-timeout");
        if (terminationReason === null) terminationReason = "descendant-pipe-timeout";
        child.stdout.destroy();
        child.stderr.destroy();
      }, SIGNAL_GRACE_MILLISECONDS);
      pipeCloseTimer.unref();
    });
    child.once("close", (exitCode, signal) => {
      childClosed = true;
      childGroup = null;
      if (pipeCloseTimer !== null) clearTimeout(pipeCloseTimer);
      resolveOutcome({ exitCode, signal });
    });
  });
  if (parentSignal !== null) requestTermination("parent-signal", parentSignal);
  const outcome = await closePromise;
  for (const [name, state] of Object.entries(streamStates)) {
    if (!state.closed) recordIoError(name, "stream-did-not-close");
  }

  const stdout = stdoutSink.finish();
  const stderr = stderrSink.finish();
  if (!stdout.published) recordIoError("stdout", stdout.error);
  if (!stderr.published) recordIoError("stderr", stderr.error);
  const overflow = stdout.overflow || stderr.overflow;
  const selfIdentity = hashFile(process.argv[1], 65536, FROZEN_MAX_BYTES);
  runResultOutput.publish({
    schema: 1,
    kind: "pi-b1-capped-command-result",
    qualification: "descriptive-b1-only",
    exitCode: outcome.exitCode,
    signal: outcome.signal,
    parentSignal,
    spawnError,
    ioError,
    terminationReason,
    argv: command,
    argvSha256: structuredSha256(command),
    argvCount: command.length,
    argvBytes,
    environmentSha256: structuredSha256(process.env),
    environmentKeyCount: Object.keys(process.env).length,
    maxBytes,
    stdout,
    stderr,
    tool: { path: resolve(process.argv[1]), ...selfIdentity },
  });
  await new Promise((resolveTimer) => setTimeout(resolveTimer, 0));

  if (parentSignal !== null) {
    finalExitCode = 128 + (osConstants.signals[parentSignal] ?? 1);
  } else if (overflow) {
    finalExitCode = 125;
  } else if (ioError !== null) {
    finalExitCode = 126;
  } else if (spawnError !== null) {
    finalExitCode = 127;
  } else if (outcome.signal !== null) {
    finalExitCode = 128 + (osConstants.signals[outcome.signal] ?? 1);
  } else {
    finalExitCode = outcome.exitCode ?? 1;
  }
} catch (error) {
  const cleanupErrors = [];
  requestTermination("runner-error");
  if (closePromise !== undefined && !childClosed) {
    try {
      await closePromise;
    } catch (cleanupError) {
      cleanupErrors.push(cleanupError);
    }
  }
  for (const resource of [stdoutSink, stderrSink, runResultOutput]) {
    try {
      resource?.abort();
    } catch (cleanupError) {
      cleanupErrors.push(cleanupError);
    }
  }
  throw cleanupFailure(error, cleanupErrors, "capped command cleanup failed");
} finally {
  removeSignalHandlers();
}

process.exitCode = finalExitCode;
