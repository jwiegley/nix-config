#!/usr/bin/env node
import { chmodSync, closeSync, existsSync, fsyncSync, lstatSync, openSync, opendirSync, unlinkSync, writeSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { check, compareUtf8, hashFile, parseArgs, publishNoClobber } from "./common.mjs";

const LIMITS = Object.freeze({
  hashChunkBytes: 65536,
  maxEntries: 512,
  maxFiles: 256,
  maxOpenDirectories: 9,
  maxDepth: 8,
  maxRelativePathBytes: 1024,
  maxTotalPathBytes: 65536,
  maxChecksumBytes: 131072,
});

const args = parseArgs(process.argv.slice(2), ["root"]);
const root = resolve(args.root);
const rootInfo = lstatSync(root);
check(rootInfo.isDirectory() && !rootInfo.isSymbolicLink(), "bundle root must be a real directory");
const sumsPath = join(root, "SHA256SUMS");
check(!existsSync(sumsPath), "refusing to replace SHA256SUMS");
const files = [];
let entries = 0;
let totalPathBytes = 0;

function validatePath(rel) {
  check(rel.length > 0 && !rel.includes("\n") && !rel.includes("\r") && !rel.includes("\\"), "bundle path is unsafe for SHA256SUMS");
  const pathBytes = Buffer.byteLength(rel, "utf8");
  check(pathBytes <= LIMITS.maxRelativePathBytes, `bundle path exceeds ${LIMITS.maxRelativePathBytes} bytes: ${rel}`);
  totalPathBytes += pathBytes;
  check(totalPathBytes <= LIMITS.maxTotalPathBytes, "bundle paths exceed aggregate byte cap");
  check(rel.split("/").length <= LIMITS.maxDepth, `bundle path exceeds depth ${LIMITS.maxDepth}: ${rel}`);
}

function walk(directory, openDirectories = 1) {
  check(openDirectories <= LIMITS.maxOpenDirectories, "bundle traversal exceeds open-directory cap");
  const handle = opendirSync(directory);
  try {
    for (;;) {
      const dirent = handle.readSync();
      if (dirent === null) break;
      entries += 1;
      check(entries <= LIMITS.maxEntries, `bundle exceeds ${LIMITS.maxEntries} directory entries`);
      const path = join(directory, dirent.name);
      const rel = relative(root, path);
      validatePath(rel);
      const info = lstatSync(path);
      check(!info.isSymbolicLink(), `bundle contains symlink: ${rel}`);
      if (info.isDirectory()) {
        walk(path, openDirectories + 1);
      } else if (info.isFile()) {
        if (rel !== "SHA256SUMS") {
          files.push(rel);
          check(files.length <= LIMITS.maxFiles, `bundle exceeds ${LIMITS.maxFiles} files`);
        }
      } else {
        throw new Error(`bundle contains non-regular entry: ${rel}`);
      }
    }
  } finally {
    handle.closeSync();
  }
}

walk(root);
files.sort(compareUtf8);
check(files.length > 0, "cannot seal an empty bundle");
const lines = [];
let checksumBytes = 0;
for (const rel of files) {
  const line = `${hashFile(join(root, rel), LIMITS.hashChunkBytes).sha256}  ${rel}\n`;
  checksumBytes += Buffer.byteLength(line, "utf8");
  check(checksumBytes <= LIMITS.maxChecksumBytes, "SHA256SUMS exceeds checksum byte cap");
  lines.push(line);
}
const bytes = Buffer.from(lines.join(""), "utf8");
check(bytes.length === checksumBytes && bytes.at(-1) === 10, "invalid checksum encoding");
const temp = `${sumsPath}.tmp-${process.pid}`;
let fd;
let tempOwned = false;
try {
  fd = openSync(temp, "wx", 0o600);
  tempOwned = true;
  let offset = 0;
  while (offset < bytes.length) {
    const count = writeSync(fd, bytes, offset, bytes.length - offset);
    check(count > 0, "checksum write made no progress");
    offset += count;
  }
  fsyncSync(fd);
  closeSync(fd);
  fd = undefined;
  chmodSync(temp, 0o444);
  publishNoClobber(temp, sumsPath);
  tempOwned = false;
} catch (error) {
  if (fd !== undefined) closeSync(fd);
  if (tempOwned && existsSync(temp)) unlinkSync(temp);
  throw error;
}
