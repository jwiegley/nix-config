{
  bun,
  coreutils,
  fetchurl,
  git,
  jq,
  lib,
  nodejs_24,
  piPackage,
  piPackages,
  python3,
  runCommand,
  sourceForChecks,
  stdenv,
  upstreamPiPackage,
}:

let
  root = package: name: "${package}/share/pi-packages/${name}";
  canonicalPiPackage = piPackages.pi;
  manifest = piPackages.pi-gallery.manifest;
  catalogSourceIds = builtins.attrNames manifest.sourceCatalog;
  declaredSourceIds =
    map (record: record.sourceName) (builtins.attrValues (manifest.members // manifest.supportSources))
    ++ builtins.attrNames manifest.externalSourceConsumers;
  sourceCatalogComplete = lib.sort builtins.lessThan declaredSourceIds == catalogSourceIds;
  orphanedCatalogRejected =
    lib.sort builtins.lessThan declaredSourceIds
    != builtins.attrNames (manifest.sourceCatalog // { synthetic-orphan = { }; });
  roots = lib.mapAttrs (_: member: root member.package member.attrName) manifest.members;
  manifestPackagesMatch = builtins.all (
    id:
    let
      member = manifest.members.${id};
    in
    piPackages.${member.attrName} == member.package && member.package.version == member.version
  ) manifest.order;
  gallery = "${piPackages.pi-gallery}/share/pi-gallery";
  localModelMemberIds = [
    "llama-swap-provider"
    "omlx-provider"
    "router"
  ];
  activeOrder = lib.subtractLists [ "lens" "mem" ] (
    if stdenv.hostPlatform.isDarwin then
      manifest.order
    else
      lib.subtractLists localModelMemberIds manifest.order
  );
  quiet = "${piPackages.agent-resources}/share/agent-resources/pi-extensions/pi-quiet/src/index.ts";
  packageRoots = lib.escapeShellArgs (builtins.attrValues roots);
  memberVersionChecks = lib.concatMapStringsSep "\n" (
    id: "expect_version ${roots.${id}}/package.json ${manifest.members.${id}.version}"
  ) manifest.order;
  supportVersionChecks =
    lib.concatMapStringsSep "\n"
      (
        id:
        "expect_version ${
          root manifest.supportSources.${id}.package manifest.supportSources.${id}.attrName
        }/package.json ${manifest.supportSources.${id}.version}"
      )
      (
        builtins.attrNames (
          builtins.removeAttrs manifest.supportSources [
            "agent-browser"
            "cymbal"
            "rtk"
          ]
        )
      );
  normalizationPolicy = builtins.fromJSON (
    builtins.readFile ../../packages/pi-gallery/normalization-policy.json
  );
  normalizationTargets = builtins.attrNames normalizationPolicy.targets;
  normalizationMemberFor =
    target:
    let
      matches = lib.filter (id: manifest.members.${id}.attrName == target) manifest.order;
    in
    assert builtins.length matches == 1;
    manifest.members.${builtins.head matches};
  normalizationParityChecks = lib.concatMapStringsSep "\n" (
    target:
    let
      member = normalizationMemberFor target;
      rawTarball = fetchurl member.source.args;
    in
    ''
      normalization_dir="$TMPDIR/pi-normalization/${target}"
      mkdir -p "$normalization_dir/raw"
      tar -xzf ${rawTarball} -C "$normalization_dir/raw"
      ${jq}/bin/jq \
        --arg target ${lib.escapeShellArg target} \
        --arg expectedName ${lib.escapeShellArg member.update.package} \
        --arg expectedVersion ${lib.escapeShellArg member.version} \
        --slurpfile policy ${../../packages/pi-gallery/normalization-policy.json} \
        -f ${../../packages/pi-gallery/normalize-manifest.jq} \
        "$normalization_dir/raw/package/package.json" \
        > "$normalization_dir/updater-package.json"
      cmp -s \
        "$normalization_dir/updater-package.json" \
        ${member.package.src}/package.json \
        || fail "shared normalizer drifted for ${target}"
    ''
  ) normalizationTargets;
  expectedPublicNames = map (id: manifest.members.${id}.publicName) manifest.order;
  expectedSkillCount = builtins.length (
    lib.concatMap (id: manifest.members.${id}.skills or [ ]) manifest.order
  );
  expectedPromptCount = builtins.length (
    lib.concatMap (id: manifest.members.${id}.prompts or [ ]) manifest.order
  );
  galleryIdentifier = id: lib.replaceStrings [ "-" ] [ "_" ] id;
  expectedStaticImportRecords = map (
    id: "${galleryIdentifier id}|${roots.${id}}/${manifest.members.${id}.extension}"
  ) activeOrder;
  expectedActiveImportRecords = map (
    id: "${id}|${galleryIdentifier id}|${roots.${id}}/${manifest.members.${id}.extension}"
  ) activeOrder;
  expectedActiveRegistrationRecords = map (id: "${id}|${galleryIdentifier id}") activeOrder;
  expectedGalleryTimingRecords =
    map (id: "${id}|module import") activeOrder ++ map (id: "${id}|factory") activeOrder;
  routingExtension =
    if stdenv.hostPlatform.isDarwin then
      "${gallery}/index.ts"
    else
      "${roots.router}/extensions/index.ts";
in
assert builtins.length (builtins.attrNames manifest.members) == builtins.length manifest.order;
assert sourceCatalogComplete;
assert orphanedCatalogRejected;
assert manifestPackagesMatch;
assert !(manifest.members ? artifacts);
assert !(builtins.hasAttr "pi-artifacts" piPackages);
assert piPackage.drvPath == canonicalPiPackage.drvPath;
assert piPackage.outPath == canonicalPiPackage.outPath;
assert (piPackage.src or null) == (upstreamPiPackage.src or null);
assert (piPackage.toolRendererWrapperAbi or null) == 1;
runCommand "pi-gallery-check"
  {
    __darwinAllowLocalNetworking = true;
    nativeBuildInputs = [
      bun
      coreutils
      git
      jq
      nodejs_24
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "Pi gallery check: $*" >&2
      exit 1
    }

    expect_version() {
      manifest=$1
      expected=$2
      actual=$(jq -r .version "$manifest")
      [ "$actual" = "$expected" ] || fail "$manifest: expected $expected, got $actual"
    }

    rpc_sequence="$TMPDIR/pi-rpc-sequence.py"
    cat > "$rpc_sequence" <<'PY'
    import json
    from pathlib import Path
    import subprocess
    import sys

    input_path, output_path, error_path, *command = sys.argv[1:]
    with (
        Path(input_path).open() as requests,
        Path(output_path).open("w") as output,
        Path(error_path).open("w") as errors,
    ):
        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=errors,
            text=True,
            bufsize=1,
        )
        assert process.stdin is not None
        assert process.stdout is not None
        try:
            for request_line in requests:
                request = json.loads(request_line)
                request_id = request["id"]
                process.stdin.write(request_line)
                process.stdin.flush()
                while True:
                    response_line = process.stdout.readline()
                    if not response_line:
                        raise RuntimeError(f"Pi exited before responding to {request_id}")
                    output.write(response_line)
                    output.flush()
                    response = json.loads(response_line)
                    if response.get("type") == "response" and response.get("id") == request_id:
                        break
            process.stdin.close()
            for response_line in process.stdout:
                output.write(response_line)
            status = process.wait(timeout=15)
        except BaseException:
            process.kill()
            process.wait()
            raise
    raise SystemExit(status)
    PY

    echo "Pi gallery check: member versions"
    ${memberVersionChecks}
    [ "$(jq -r .type ${roots.usage}/package.json)" = module ] \
      || fail "Pi Usage package must declare ESM module type"
    echo "Pi gallery check: support versions"
    ${supportVersionChecks}
    echo "Pi gallery check: normalization parity"
    ${normalizationParityChecks}
    echo "Pi gallery check: packaged roots"

    for package_root in ${packageRoots}; do
      [ -f "$package_root/package.json" ] || fail "missing package manifest: $package_root"
      patch_artifacts=$(
        find "$package_root" -path '*/node_modules' -prune -o \
          -type f \( -name '*.orig' -o -name '*.rej' \) -print
      )
      [ -z "$patch_artifacts" ] \
        || fail "package contains patch backup or reject artifacts: $patch_artifacts"
      if [ -d "$package_root/node_modules" ]; then
        if find "$package_root/node_modules" -type d \
          \( -path '*/@earendil-works/*' \
            -o -path '*/@mariozechner/pi-*' \
            -o -path '*/@sinclair/typebox' \
            -o -path '*/typebox' \) -print -quit | grep -q .; then
          fail "package bundles a Pi-provided peer runtime: $package_root"
        fi
      fi
    done

    echo "Pi gallery check: bounded session-history consumers"
    for package_root in ${packageRoots} ${piPackages.pi-loop}/share/pi-packages/pi-loop; do
      offenders=$(
        find "$package_root" -path '*/node_modules' -prune -o \
          -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.mjs' \) \
          -exec grep -l -E 'sessionManager\.get(Entries|Branch)\(' {} + || true
      )
      [ -z "$offenders" ] \
        || fail "automatic full-history API remains in $package_root: $offenders"
    done
    ! grep -E 'sessionManager\.get(Entries|Branch)\(' ${quiet} >/dev/null \
      || fail "Pi Quiet still consumes full session history"

    [ -f ${roots.btw}/extensions/btw.ts ]
    [ -f ${roots.btw}/skills/btw/SKILL.md ]
    (
      cd ${sourceForChecks}
      PI_BTW_EXTENSION=${roots.btw}/extensions/btw.ts \
        bun test ./test/ai/pi-btw-escape.check.ts
    )
    [ -f ${roots.insights}/index.ts ]
    [ -f ${roots.insights}/dist/index.html ]
    [ -d ${roots.insights}/node_modules/react ]
    [ -d ${roots.insights}/node_modules/recharts ]
    [ -f ${roots.mem}/index.ts ]
    [ -f ${roots.mem}/lib.ts ]
    [ -f ${roots.mem}/README.md ]
    [ ! -e ${roots.mem}/node_modules ]
    ! grep -E 'completeSimple|\bgetModel\(' ${roots.mem}/index.ts >/dev/null \
      || fail "pi-mem retains automatic remote dashboard summarization"
    ! grep -E 'Groups by topic using an LLM call|automatically injected into the system prompt|SCRATCHPAD.md \(open items only\)' \
      ${roots.mem}/README.md >/dev/null \
      || fail "pi-mem packaged README contradicts the managed runtime"
    grep -F 'synthetic user message immediately before the newest real user request' \
      ${roots.mem}/README.md >/dev/null \
      || fail "pi-mem packaged README omits the managed injection boundary"
    [ "$(grep -c 'writePrivateFile(' ${roots.mem}/index.ts)" -eq 4 ] \
      || fail "pi-mem atomic replacement sites changed unexpectedly"
    [ "$(grep -c 'updatePrivateFile(' ${roots.mem}/index.ts)" -eq 6 ] \
      || fail "pi-mem read-modify-write sites changed unexpectedly"
    ! grep -F 'fs.writeFileSync' ${roots.mem}/index.ts >/dev/null \
      || fail "pi-mem persistent writes bypass the private-state helpers"
    ! grep -E 'PI_AUTOCOMMIT|gitCommit|execFileSync' \
      ${roots.mem}/index.ts ${roots.mem}/lib.ts >/dev/null \
      || fail "managed pi-mem retains Git autocommit code"
    [ ! -e ${roots.mem}/tests/autocommit.test.ts ] \
      || fail "managed pi-mem retains upstream autocommit tests"
    for required_pi_mem_policy in \
      'removes upstream Git autocommit' \
      'field are inert' \
      'private Git workflow outside Pi Mem' \
      'same-host owner is proven to have' \
      'in-progress-recovery locks'
    do
      grep -F "$required_pi_mem_policy" ${roots.mem}/README.md >/dev/null \
        || fail "pi-mem packaged README omits policy: $required_pi_mem_policy"
    done
    [ -f ${roots.mem}/tests/private-file.test.ts ]
    [ -f ${roots.mem}/tests/private-file-worker.mjs ]
    (
      cd ${roots.mem}
      ${nodejs_24}/bin/node \
        --experimental-strip-types --test tests/*.test.ts
    )
    pi_mem_runtime="$TMPDIR/pi-mem-runtime"
    mkdir -p "$pi_mem_runtime/home" "$pi_mem_runtime/project"
    cat > "$pi_mem_runtime/probe.mjs" <<'EOF'
    import assert from "node:assert/strict";
    import {
      chmodSync,
      existsSync,
      lstatSync,
      mkdirSync,
      readFileSync,
      readdirSync,
      rmdirSync,
      statSync,
      symlinkSync,
      unlinkSync,
      utimesSync,
      writeFileSync,
    } from "node:fs";
    import { execFile } from "node:child_process";
    import { hostname } from "node:os";
    import { join } from "node:path";
    import { promisify } from "node:util";

    const runtime = process.env.PI_MEM_RUNTIME;
    const memory = process.env.PI_MEMORY_DIR;
    const daily = process.env.PI_DAILY_DIR;
    const agent = process.env.PI_CODING_AGENT_DIR;
    const extensionRoot = process.env.PI_MEM_ROOT;
    const piRoot = process.env.PI_CODING_AGENT_ROOT;
    const gitSentinel = process.env.PI_MEM_GIT_SENTINEL;
    assert.ok(runtime && memory && daily && agent && extensionRoot && piRoot && gitSentinel);

    mkdirSync(memory, { recursive: true });
    writeFileSync(
      join(memory, ".pi-mem.json"),
      JSON.stringify({ autocommit: true }) + "\n",
      { mode: 0o600 },
    );

    const writeSession = (directory, title) => {
      const sessionDir = join(agent, "sessions", directory);
      mkdirSync(sessionDir, { recursive: true });
      writeFileSync(join(sessionDir, "fixture.jsonl"), [
        JSON.stringify({ timestamp: new Date().toISOString(), cwd: runtime }),
        JSON.stringify({ type: "session_info", name: title }),
      ].join("\n") + "\n");
    };
    writeSession("--Users-pi-mem-fixture--", "macOS session sentinel");
    writeSession("--home-pi-mem-fixture--", "Linux session sentinel");
    const outsideSession = join(runtime, "outside-session.jsonl");
    writeFileSync(outsideSession, [
      JSON.stringify({ timestamp: new Date().toISOString(), cwd: runtime }),
      JSON.stringify({ type: "session_info", name: "outside session sentinel" }),
    ].join("\n") + "\n");
    symlinkSync(
      outsideSession,
      join(agent, "sessions", "--home-pi-mem-fixture--", "outside-link.jsonl"),
    );
    process.umask(0o000);

    const { loadExtensions } = await import(
      piRoot + "/dist/core/extensions/loader.js"
    );
    const loaded = await loadExtensions([join(extensionRoot, "index.ts")], runtime);
    assert.deepEqual(loaded.errors, []);
    assert.equal(loaded.extensions.length, 1);
    const extension = loaded.extensions[0];
    assert.deepEqual(
      [...extension.tools.keys()].sort(),
      ["memory_read", "memory_search", "memory_write", "scratchpad"],
    );

    let modelRegistryAccesses = 0;
    const ctx = {
      hasUI: true,
      modelRegistry: new Proxy({}, {
        get(_target, property) {
          modelRegistryAccesses++;
          if (property === "find") return () => undefined;
          if (property === "getApiKeyAndHeaders") return async () => ({ ok: false });
          throw new Error(
            "unexpected model-registry access: " + String(property)
          );
        },
      }),
      sessionManager: { getSessionId: () => "pi-mem-runtime-session" },
      ui: { setWidget() {} },
    };
    const emit = async (name, event = {}) => {
      let result;
      for (const handler of extension.handlers.get(name) ?? []) {
        result = await handler(event, ctx);
      }
      return result;
    };
    const execute = async (name, params) => {
      const tool = extension.tools.get(name)?.definition;
      assert.ok(tool, "missing tool: " + name);
      return tool.execute("pi-mem-runtime-call", params, undefined, undefined, ctx);
    };
    const mode = (path) => statSync(path).mode & 0o777;
    const assertMode = (path, expected) => assert.equal(mode(path), expected, path);
    const execFileAsync = promisify(execFile);
    const runWorker = (kind, id, env = {}) => execFileAsync(
      process.env.PI_MEM_NODE,
      [process.env.PI_MEM_WORKER, kind, String(id)],
      {
        env: { ...process.env, ...env },
        maxBuffer: 1024 * 1024,
      },
    );
    const occurrences = (text, needle) => text.split(needle).length - 1;
    const createLock = (
      filePath,
      token,
      ageMs = 0,
      ownerPid = process.pid,
      ownerHostname = hostname(),
    ) => {
      const lockPath = filePath + ".lock";
      mkdirSync(lockPath, { mode: 0o700 });
      writeFileSync(
        join(lockPath, token),
        JSON.stringify({ token, pid: ownerPid, hostname: ownerHostname }),
        { mode: 0o600 },
      );
      if (ageMs > 0) {
        const stale = new Date(Date.now() - ageMs);
        utimesSync(lockPath, stale, stale);
      }
      return lockPath;
    };
    const privateDebris = (root) => {
      const found = [];
      const visit = (directory) => {
        for (const entry of readdirSync(directory, { withFileTypes: true })) {
          const entryPath = join(directory, entry.name);
          if (/\.lock(?:\.|$)|\.stale\.|\.tmp$/.test(entry.name)) {
            found.push(entryPath);
          }
          if (entry.isDirectory()) visit(entryPath);
        }
      };
      visit(root);
      return found;
    };

    const currentRequest = {
      role: "user",
      content: "actual user request",
      timestamp: 0,
    };
    const initialContext = await emit("context", { messages: [currentRequest] });
    assert.equal(initialContext.messages.at(-1).content, currentRequest.content);
    assert.match(initialContext.messages.at(-2).content, /<pi-mem-injected>/);
    assert.match(
      initialContext.messages.at(-2).content,
      /current user explicitly asks you to remember or update something/,
    );
    assert.doesNotMatch(initialContext.messages.at(-2).content, /If someone says/);
    assert.doesNotMatch(initialContext.messages.at(-2).content, /Daily Log Rule/);
    assert.match(
      extension.tools.get("memory_write").definition.description,
      /only when the user explicitly asks/,
    );
    assert.match(
      extension.tools.get("scratchpad").definition.description,
      /mutating actions only when the user explicitly asks/,
    );
    const notes = join(memory, "notes");
    for (const path of [memory, daily, notes]) assertMode(path, 0o700);
    for (const path of [memory, daily, notes]) chmodSync(path, 0o777);

    await execute("memory_write", { target: "long_term", content: "first durable fact" });
    const memoryFile = join(memory, "MEMORY.md");
    assertMode(memoryFile, 0o600);
    chmodSync(memoryFile, 0o666);
    await execute("memory_write", {
      target: "long_term",
      content: "final durable fact",
      mode: "overwrite",
    });
    assertMode(memoryFile, 0o600);
    assert.match(readFileSync(memoryFile, "utf8"), /final durable fact/);
    assert.doesNotMatch(readFileSync(memoryFile, "utf8"), /first durable fact/);
    for (const path of [memory, daily, notes]) assertMode(path, 0o700);

    await execute("memory_write", { target: "daily", content: "daily outcome" });
    const dailyName = readdirSync(daily).find((name) => name.endsWith(".md"));
    assert.ok(dailyName);
    const dailyFile = join(daily, dailyName);
    assertMode(dailyFile, 0o600);
    chmodSync(dailyFile, 0o666);
    await execute("memory_write", { target: "daily", content: "daily append outcome" });
    assertMode(dailyFile, 0o600);
    assert.match(readFileSync(dailyFile, "utf8"), /daily outcome/);
    assert.match(readFileSync(dailyFile, "utf8"), /daily append outcome/);

    const noteFile = join(notes, "topic.md");
    await execute("memory_write", { target: "note", filename: "topic.md", content: "first note" });
    chmodSync(noteFile, 0o666);
    await execute("memory_write", {
      target: "note",
      filename: "topic.md",
      content: "final note",
      mode: "overwrite",
    });
    assertMode(noteFile, 0o600);
    assert.match(readFileSync(noteFile, "utf8"), /final note/);
    assert.doesNotMatch(readFileSync(noteFile, "utf8"), /first note/);

    const scratchpad = join(memory, "SCRATCHPAD.md");
    await execute("scratchpad", { action: "add", text: "follow up" });
    assert.match(readFileSync(scratchpad, "utf8"), /- \[ \] follow up/);
    chmodSync(scratchpad, 0o666);
    await execute("scratchpad", { action: "done", text: "follow up" });
    assert.match(readFileSync(scratchpad, "utf8"), /- \[x\] follow up/);
    await execute("scratchpad", { action: "clear_done" });
    assertMode(scratchpad, 0o600);
    assert.doesNotMatch(readFileSync(scratchpad, "utf8"), /follow up/);

    const workerCount = 4;
    await Promise.all(
      ["memory", "daily", "note", "scratchpad"].flatMap((kind) =>
        Array.from({ length: workerCount }, (_, id) => runWorker(kind, id))
      ),
    );
    const concurrentTargets = [
      [memoryFile, "memory worker "],
      [dailyFile, "daily worker "],
      [join(notes, "concurrent.md"), "note worker "],
      [scratchpad, "scratchpad worker "],
    ];
    for (const [path, prefix] of concurrentTargets) {
      const content = readFileSync(path, "utf8");
      for (let id = 0; id < workerCount; id++) {
        assert.equal(occurrences(content, prefix + id), 1, path + ":" + id);
      }
      assertMode(path, 0o600);
    }

    await Promise.all(
      Array.from({ length: workerCount }, (_, id) => runWorker("overwrite", id)),
    );
    const atomicFile = join(notes, "atomic.md");
    const atomicContent = readFileSync(atomicFile, "utf8");
    const atomicMatch = atomicContent.match(/overwrite worker (\d):\n([\s\S]*)$/);
    assert.ok(atomicMatch);
    assert.equal(
      atomicMatch[2],
      ("whole payload " + atomicMatch[1] + "\n").repeat(4096),
    );

    await Promise.all(
      Array.from({ length: workerCount }, (_, id) => runWorker("cache", id)),
    );
    JSON.parse(readFileSync(join(daily, "cache.json"), "utf8"));

    const emptyRuntime = join(runtime, "empty-cache");
    const emptyMemory = join(emptyRuntime, "memory");
    const emptyDaily = join(emptyRuntime, "daily");
    const emptyAgent = join(emptyRuntime, "agent");
    mkdirSync(join(emptyAgent, "sessions"), { recursive: true });
    const emptyEnv = {
      PI_MEM_RUNTIME: emptyRuntime,
      PI_MEMORY_DIR: emptyMemory,
      PI_DAILY_DIR: emptyDaily,
      PI_CODING_AGENT_DIR: emptyAgent,
    };
    const emptyCache = join(emptyDaily, "cache.json");
    const produced = JSON.parse(
      (await runWorker("cache", "empty-produce", emptyEnv)).stdout,
    );
    assert.equal(produced.widgetCalls, 0);
    assertMode(emptyCache, 0o600);
    const freshEmptyBytes = readFileSync(emptyCache);
    const freshEmpty = JSON.parse(freshEmptyBytes.toString("utf8"));
    assert.equal(freshEmpty.summary, "");
    assert.equal(typeof freshEmpty.timestamp, "number");

    const sentinelSession = join(
      emptyAgent,
      "sessions",
      "--empty-cache-fixture--",
    );
    mkdirSync(sentinelSession, { recursive: true });
    writeFileSync(join(sentinelSession, "fixture.jsonl"), [
      JSON.stringify({ timestamp: new Date().toISOString(), cwd: emptyRuntime }),
      JSON.stringify({ type: "session_info", name: "EMPTY_CACHE_RESCAN_SENTINEL" }),
    ].join("\n") + "\n");
    const reused = JSON.parse(
      (await runWorker("cache", "empty-reuse", emptyEnv)).stdout,
    );
    assert.equal(reused.widgetCalls, 0);
    assert.deepEqual(readFileSync(emptyCache), freshEmptyBytes);

    writeFileSync(
      emptyCache,
      JSON.stringify({ ...freshEmpty, timestamp: 0 }),
    );
    const rebuilt = JSON.parse(
      (await runWorker("cache", "empty-stale", emptyEnv)).stdout,
    );
    assert.equal(rebuilt.widgetCalls, 1);
    assert.match(
      JSON.parse(readFileSync(emptyCache, "utf8")).summary,
      /EMPTY_CACHE_RESCAN_SENTINEL/,
    );

    const beforeFreshLock = readFileSync(memoryFile, "utf8");
    const freshLock = createLock(memoryFile, "fresh-owner-token");
    await assert.rejects(
      execute("memory_write", {
        target: "long_term",
        content: "must not pass a fresh lock",
      }),
      /Timed out waiting for memory file lock/,
    );
    assert.equal(readFileSync(memoryFile, "utf8"), beforeFreshLock);
    unlinkSync(join(freshLock, "fresh-owner-token"));
    rmdirSync(freshLock);

    const beforeLiveStaleLock = readFileSync(memoryFile, "utf8");
    const liveStaleLock = createLock(
      memoryFile,
      "live-stale-owner-token",
      10 * 60 * 1000,
    );
    await assert.rejects(
      execute("memory_write", {
        target: "long_term",
        content: "must not replace a stale lock with a live owner",
      }),
      /Timed out waiting for memory file lock/,
    );
    assert.equal(readFileSync(memoryFile, "utf8"), beforeLiveStaleLock);
    unlinkSync(join(liveStaleLock, "live-stale-owner-token"));
    rmdirSync(liveStaleLock);

    const exitedOwnerPid = await new Promise((resolve, reject) => {
      const child = execFile(process.env.PI_MEM_NODE, ["-e", ""], (error) => {
        if (error) reject(error);
        else resolve(child.pid);
      });
      assert.ok(child.pid);
    });
    assert.throws(
      () => process.kill(exitedOwnerPid, 0),
      (error) => error?.code === "ESRCH",
    );

    const beforeForeignStaleLock = readFileSync(memoryFile, "utf8");
    const foreignStaleLock = createLock(
      memoryFile,
      "foreign-stale-owner-token",
      10 * 60 * 1000,
      exitedOwnerPid,
      "remote-pi-fixture",
    );
    await assert.rejects(
      execute("memory_write", {
        target: "long_term",
        content: "must not replace a stale lock from another host",
      }),
      /Timed out waiting for memory file lock/,
    );
    assert.equal(readFileSync(memoryFile, "utf8"), beforeForeignStaleLock);
    unlinkSync(join(foreignStaleLock, "foreign-stale-owner-token"));
    rmdirSync(foreignStaleLock);

    createLock(
      memoryFile,
      "stale-owner-token",
      10 * 60 * 1000,
      exitedOwnerPid,
    );
    await execute("memory_write", {
      target: "long_term",
      content: "stale lock recovered",
    });
    assert.match(readFileSync(memoryFile, "utf8"), /stale lock recovered/);
    assert.equal(lstatSync(memoryFile).isFile(), true);

    const invalidLocks = [
      {
        token: "malformed-owner-token",
        marker: "not json",
        extras: [],
      },
      {
        token: "extra-entry-owner-token",
        marker: JSON.stringify({
          token: "extra-entry-owner-token",
          pid: process.pid,
          hostname: hostname(),
        }),
        extras: [["preserve-me", "must survive"]],
      },
    ];
    for (const invalid of invalidLocks) {
      const beforeInvalidLock = readFileSync(memoryFile, "utf8");
      const lockPath = memoryFile + ".lock";
      mkdirSync(lockPath, { mode: 0o700 });
      writeFileSync(join(lockPath, invalid.token), invalid.marker, { mode: 0o600 });
      for (const [name, content] of invalid.extras) {
        writeFileSync(join(lockPath, name), content, { mode: 0o600 });
      }
      const stale = new Date(Date.now() - 10 * 60 * 1000);
      utimesSync(lockPath, stale, stale);
      await assert.rejects(
        execute("memory_write", {
          target: "long_term",
          content: "must not replace an invalid lock",
        }),
        /invalid memory file lock/i,
      );
      assert.equal(readFileSync(memoryFile, "utf8"), beforeInvalidLock);
      assert.equal(readFileSync(join(lockPath, invalid.token), "utf8"), invalid.marker);
      for (const [name, content] of invalid.extras) {
        assert.equal(readFileSync(join(lockPath, name), "utf8"), content);
        unlinkSync(join(lockPath, name));
      }
      assert.deepEqual(
        readdirSync(memory).filter((name) => name.includes(".stale.")),
        [],
      );
      unlinkSync(join(lockPath, invalid.token));
      rmdirSync(lockPath);
    }
    assert.deepEqual(privateDebris(memory), []);

    const read = await execute("memory_read", { target: "long_term" });
    assert.match(read.content[0].text, /final durable fact/);
    const outsideDaily = join(runtime, "outside.md");
    writeFileSync(outsideDaily, "outside daily sentinel");
    const escapedDaily = await execute("memory_read", {
      target: "daily",
      date: "../../outside",
    });
    assert.match(escapedDaily.content[0].text, /must use YYYY-MM-DD/);
    assert.doesNotMatch(escapedDaily.content[0].text, /outside daily sentinel/);
    const search = await execute("memory_search", { query: "final durable" });
    assert.match(search.content[0].text, /MEMORY\.md/);
    const context = await emit("context", { messages: [currentRequest] });
    assert.equal(context.messages.at(-1).content, currentRequest.content);
    assert.match(context.messages.at(-2).content, /final durable fact/);

    const realSetInterval = globalThis.setInterval;
    const realClearInterval = globalThis.clearInterval;
    const timer = {};
    let intervalCallback;
    let timerCleared = false;
    globalThis.setInterval = (callback, delay) => {
      assert.equal(delay, 15 * 60 * 1000);
      intervalCallback = callback;
      return timer;
    };
    globalThis.clearInterval = (value) => {
      assert.equal(value, timer);
      timerCleared = true;
    };
    try {
      await emit("session_start");
      assert.equal(modelRegistryAccesses, 0, "dashboard consulted a remote model registry");
      const cache = join(daily, "cache.json");
      assertMode(cache, 0o600);
      const summary = JSON.parse(readFileSync(cache, "utf8")).summary;
      assert.match(summary, /macOS session sentinel/);
      assert.match(summary, /Linux session sentinel/);
      assert.doesNotMatch(summary, /outside session sentinel/);
      chmodSync(cache, 0o666);
      assert.ok(intervalCallback);
      await intervalCallback();
      assertMode(cache, 0o600);
      const outsideCache = join(runtime, "outside-cache.json");
      writeFileSync(outsideCache, "outside cache sentinel", { mode: 0o644 });
      unlinkSync(cache);
      symlinkSync(outsideCache, cache);
      await intervalCallback();
      assert.equal(readFileSync(outsideCache, "utf8"), "outside cache sentinel");
      assert.equal(lstatSync(cache).isSymbolicLink(), true);
      await emit("session_shutdown");
      assert.equal(timerCleared, true);
    } finally {
      globalThis.setInterval = realSetInterval;
      globalThis.clearInterval = realClearInterval;
    }

    const outsideWrite = join(runtime, "outside-write.md");
    writeFileSync(outsideWrite, "outside write sentinel", { mode: 0o644 });
    const linkedNote = join(notes, "linked.md");
    symlinkSync(outsideWrite, linkedNote);
    await assert.rejects(
      execute("memory_write", {
        target: "note",
        filename: "linked.md",
        content: "must not append through a symlink",
      }),
      /Refusing non-file memory path/,
    );
    await assert.rejects(
      execute("memory_write", {
        target: "note",
        filename: "linked.md",
        mode: "overwrite",
        content: "must not replace a symlink",
      }),
      /Refusing non-file memory path/,
    );
    assert.equal(readFileSync(outsideWrite, "utf8"), "outside write sentinel");
    assert.equal(lstatSync(linkedNote).isSymbolicLink(), true);
    const linkedNoteRead = await execute("memory_read", {
      target: "note",
      filename: "linked.md",
    });
    assert.doesNotMatch(linkedNoteRead.content[0].text, /outside write sentinel/);

    const nonregularNote = join(notes, "nonregular.md");
    mkdirSync(nonregularNote);
    writeFileSync(join(nonregularNote, "sentinel"), "unchanged");
    await assert.rejects(
      execute("memory_write", {
        target: "note",
        filename: "nonregular.md",
        mode: "overwrite",
        content: "must not replace a directory",
      }),
      /Refusing non-file memory path/,
    );
    assert.equal(readFileSync(join(nonregularNote, "sentinel"), "utf8"), "unchanged");

    const outsideRead = join(runtime, "outside-read");
    mkdirSync(outsideRead);
    writeFileSync(join(outsideRead, "secret.md"), "outside read sentinel");
    symlinkSync(outsideRead, join(memory, "linked-read"));
    const escapedFile = await execute("memory_read", {
      target: "file",
      filename: "linked-read/secret.md",
    });
    assert.doesNotMatch(escapedFile.content[0].text, /outside read sentinel/);

    const contextTarget = join(runtime, "outside-context.md");
    writeFileSync(contextTarget, "outside context sentinel");
    symlinkSync(contextTarget, join(memory, "context-link.md"));
    const catchupTarget = join(runtime, "outside-catchup");
    const catchupDate = new Date().toISOString().slice(0, 10);
    mkdirSync(join(catchupTarget, catchupDate), { recursive: true });
    writeFileSync(
      join(catchupTarget, catchupDate, "INDEX.md"),
      "outside catchup sentinel",
    );
    mkdirSync(join(catchupTarget, "outside-list-sentinel"));
    writeFileSync(
      join(catchupTarget, catchupDate, "outside-name-sentinel.md"),
      "ordinary outside content",
    );
    symlinkSync(catchupTarget, join(memory, "catchup"));
    const privateContext = await emit("context", { messages: [currentRequest] });
    assert.doesNotMatch(
      privateContext.messages.at(-2).content,
      /outside (context|catchup) sentinel/,
    );
    const privateList = await execute("memory_read", { target: "list" });
    assert.doesNotMatch(privateList.content[0].text, /outside-list-sentinel/);
    const privateSearch = await execute("memory_search", {
      query: "outside-name-sentinel",
    });
    assert.equal(
      privateSearch.content[0].text,
      'No results for "outside-name-sentinel".',
    );
    assert.deepEqual(privateDebris(memory), []);
    assert.deepEqual(privateDebris(daily), []);
    assert.equal(existsSync(gitSentinel), false, "managed pi-mem invoked Git");
    EOF
    cat > "$pi_mem_runtime/worker.mjs" <<'EOF'
    import assert from "node:assert/strict";
    import { join } from "node:path";

    const [kind, id] = process.argv.slice(2);
    const piRoot = process.env.PI_CODING_AGENT_ROOT;
    const extensionRoot = process.env.PI_MEM_ROOT;
    assert.ok(kind && id && piRoot && extensionRoot);
    const { loadExtensions } = await import(
      piRoot + "/dist/core/extensions/loader.js"
    );
    const loaded = await loadExtensions(
      [join(extensionRoot, "index.ts")],
      process.env.PI_MEM_RUNTIME,
    );
    assert.deepEqual(loaded.errors, []);
    const extension = loaded.extensions[0];
    let widgetCalls = 0;
    const ctx = {
      hasUI: true,
      modelRegistry: new Proxy({}, {
        get() { throw new Error("worker consulted model registry"); },
      }),
      sessionManager: { getSessionId: () => "pi-mem-worker-" + id },
      ui: { setWidget() { widgetCalls++; } },
    };
    const execute = async (name, params) => {
      const tool = extension.tools.get(name)?.definition;
      assert.ok(tool, "missing tool: " + name);
      return tool.execute("pi-mem-worker-call", params, undefined, undefined, ctx);
    };
    const emit = async (name) => {
      for (const handler of extension.handlers.get(name) ?? []) {
        await handler({}, ctx);
      }
    };

    if (kind === "memory") {
      await execute("memory_write", {
        target: "long_term",
        content: "memory worker " + id,
      });
    } else if (kind === "daily") {
      await execute("memory_write", {
        target: "daily",
        content: "daily worker " + id,
      });
    } else if (kind === "note") {
      await execute("memory_write", {
        target: "note",
        filename: "concurrent.md",
        content: "note worker " + id,
      });
    } else if (kind === "scratchpad") {
      await execute("scratchpad", {
        action: "add",
        text: "scratchpad worker " + id,
      });
    } else if (kind === "overwrite") {
      await execute("memory_write", {
        target: "note",
        filename: "atomic.md",
        mode: "overwrite",
        content:
          "overwrite worker " + id + ":\n" +
          ("whole payload " + id + "\n").repeat(4096),
      });
    } else if (kind === "cache") {
      try {
        await emit("session_start");
      } finally {
        await emit("session_shutdown");
      }
      process.stdout.write(JSON.stringify({ widgetCalls }) + "\n");
    } else {
      throw new Error("unknown worker kind: " + kind);
    }
    EOF
    pi_mem_fake_bin="$pi_mem_runtime/fake-bin"
    pi_mem_git_sentinel="$pi_mem_runtime/git-invoked"
    mkdir -p "$pi_mem_fake_bin"
    cat > "$pi_mem_fake_bin/git" <<'EOF'
    #!/bin/sh
    : > "$PI_MEM_GIT_SENTINEL"
    exit 97
    EOF
    chmod +x "$pi_mem_fake_bin/git"
    pi_mem_repo="$pi_mem_runtime/memory"
    mkdir -p "$pi_mem_repo"
    printf '%s\n' 'repository baseline' > "$pi_mem_repo/repository-sentinel.txt"
    ${git}/bin/git -C "$pi_mem_repo" init -q
    ${git}/bin/git -C "$pi_mem_repo" config user.name 'pi-mem fixture'
    ${git}/bin/git -C "$pi_mem_repo" config user.email 'pi-mem@example.invalid'
    ${git}/bin/git -C "$pi_mem_repo" add -- repository-sentinel.txt
    ${git}/bin/git -C "$pi_mem_repo" -c commit.gpgsign=false commit -qm baseline
    printf '%s\n' 'repository staged sentinel' > "$pi_mem_repo/repository-sentinel.txt"
    ${git}/bin/git -C "$pi_mem_repo" add -- repository-sentinel.txt
    printf '%s\n' 'repository worktree sentinel' > "$pi_mem_repo/repository-sentinel.txt"
    pi_mem_head_before=$(${git}/bin/git -C "$pi_mem_repo" rev-parse HEAD)
    pi_mem_status_before=$(${git}/bin/git -C "$pi_mem_repo" status --porcelain=v1 -- repository-sentinel.txt)
    pi_mem_index_before=$(sha256sum "$pi_mem_repo/.git/index" | cut -d ' ' -f 1)
    pi_mem_worktree_before=$(sha256sum "$pi_mem_repo/repository-sentinel.txt" | cut -d ' ' -f 1)
    (
      cd "$pi_mem_runtime/project"
      umask 000
      PATH="$pi_mem_fake_bin:$PATH" \
      HOME="$pi_mem_runtime/home" \
      PI_MEM_RUNTIME="$pi_mem_runtime" \
      PI_CODING_AGENT_DIR="$pi_mem_runtime/agent" \
      PI_MEMORY_DIR="$pi_mem_runtime/memory" \
      PI_DAILY_DIR="$pi_mem_runtime/external-daily" \
      PI_CONTEXT_FILES=context-link.md \
      PI_SEARCH_DIRS=catchup \
      PI_AUTOCOMMIT=1 \
      PI_MEM_GIT_SENTINEL="$pi_mem_git_sentinel" \
      PI_TIMEZONE=UTC \
      PI_OFFLINE=1 \
      PI_MEM_ROOT=${roots.mem} \
      PI_CODING_AGENT_ROOT=${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent \
      PI_MEM_NODE=${nodejs_24}/bin/node \
      PI_MEM_WORKER="$pi_mem_runtime/worker.mjs" \
        ${nodejs_24}/bin/node "$pi_mem_runtime/probe.mjs"
    )
    [ ! -e "$pi_mem_git_sentinel" ] \
      || fail "managed pi-mem invoked Git"
    [ "$(sha256sum "$pi_mem_repo/.git/index" | cut -d ' ' -f 1)" = "$pi_mem_index_before" ] \
      || fail "managed pi-mem changed the Git index"
    [ "$(sha256sum "$pi_mem_repo/repository-sentinel.txt" | cut -d ' ' -f 1)" = "$pi_mem_worktree_before" ] \
      || fail "managed pi-mem changed unrelated worktree state"
    [ "$(${git}/bin/git -C "$pi_mem_repo" rev-parse HEAD)" = "$pi_mem_head_before" ] \
      || fail "managed pi-mem changed Git HEAD"
    [ "$(${git}/bin/git -C "$pi_mem_repo" status --porcelain=v1 -- repository-sentinel.txt)" = "$pi_mem_status_before" ] \
      || fail "managed pi-mem changed unrelated Git state"
    [ -f ${roots.usage}/index.ts ]
    [ ! -e ${roots.usage}/node_modules ]
    usage_runtime="$TMPDIR/pi-usage-runtime"
    mkdir -p "$usage_runtime"
    cat > "$usage_runtime/probe.ts" <<EOF
    import { Database } from "bun:sqlite";
    import { mkdirSync } from "node:fs";
    import { collectUsageData } from "${roots.usage}/data.ts";

    mkdirSync(process.env.PI_USAGE_SESSIONS!, { recursive: true });
    const legacy = new Database(process.env.PI_USAGE_CACHE!);
    legacy.exec("PRAGMA user_version = 0");
    legacy.close();
    await collectUsageData({
      sessionsDir: process.env.PI_USAGE_SESSIONS!,
      cachePath: process.env.PI_USAGE_CACHE!,
    });
    EOF
    PI_USAGE_CACHE="$usage_runtime/usage-extension-cache.json" \
      PI_USAGE_SESSIONS="$usage_runtime/sessions" \
      ${bun}/bin/bun "$usage_runtime/probe.ts"
    [ "$(stat -c '%a' "$usage_runtime/usage-extension-cache.json")" = 600 ] \
      || fail "Usage Dashboard cache mode is not 0600"
    usage_history_stderr="$TMPDIR/pi-usage-bounded-history.stderr"
    if PI_USAGE_ROOT=${roots.usage} \
      ${nodejs_24}/bin/node --experimental-strip-types \
        ${sourceForChecks}/test/ai/pi-usage-bounded-history.check.ts \
        2>"$usage_history_stderr"
    then
      :
    else
      status=$?
      cat "$usage_history_stderr" >&2
      exit "$status"
    fi
    cat "$usage_history_stderr" >&2
    if grep -Fq MODULE_TYPELESS_PACKAGE_JSON "$usage_history_stderr"; then
      fail "Pi Usage bounded-history check emitted a module-type warning"
    fi
    [ -f ${roots.multi-pass}/extensions/multi-sub.ts ]
    [ ! -e ${roots.multi-pass}/node_modules ]
    [ -f ${piPackages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts ]
    [ -f ${piPackages.pi-loop}/share/pi-packages/pi-loop/LICENSE ]
    [ ! -e ${piPackages.pi-loop}/share/pi-packages/pi-loop/node_modules ]
    for provider_root in ${roots.llama-swap-provider} ${roots.omlx-provider}; do
      [ -f "$provider_root/index.ts" ]
      [ -f "$provider_root/local-openai-provider.ts" ]
      [ -f "$provider_root/LICENSE" ]
      [ ! -e "$provider_root/node_modules" ]
    done
    [ -f ${roots.router}/extensions/index.ts ]
    [ -f ${roots.router}/extensions/routing.ts ]
    [ ! -e ${roots.router}/node_modules ]
    [ -f ${roots.rewind}/src/index.ts ]
    [ -f ${roots.rewind}/src/core.ts ]
    [ -f ${roots.rewind}/src/ui.ts ]
    [ ! -e ${roots.rewind}/node_modules ]
    [ -f ${roots.trace}/extensions/trace/index.ts ]
    [ -f ${roots.trace}/extensions/trace/trace_to_html.py ]
    [ ! -e ${roots.trace}/node_modules ]
    [ -z "$(find ${roots.trace} \( -name '*.pyc' -o -name __pycache__ \) -print -quit)" ]
    trace_runtime="$TMPDIR/pi-trace-runtime"
    mkdir -p "$trace_runtime/home/.pi/agent/sessions" "$trace_runtime/project"
    cat > "$trace_runtime/probe.ts" <<EOF
    import { readFileSync } from "node:fs";
    import trace from "${roots.trace}/extensions/trace/index.ts";

    const handlers = new Map<string, Array<(event: any, ctx?: any) => any>>();
    const commands = new Map<string, { handler: (args: string, ctx: any) => Promise<void> }>();
    const pi = {
      on(name: string, handler: (event: any, ctx?: any) => any) {
        const current = handlers.get(name) ?? [];
        current.push(handler);
        handlers.set(name, current);
      },
      registerCommand(name: string, command: any) { commands.set(name, command); },
    };
    trace(pi as any);
    const ctx = {
      cwd: process.env.TRACE_PROJECT,
      sessionManager: { getSessionFile: () => process.env.TRACE_SESSION_FILE },
      ui: { setStatus() {}, notify() {} },
    };
    const call = async (name: string, event: any = {}) => {
      for (const handler of handlers.get(name) ?? []) await handler(event, ctx);
    };

    await call("session_start", { sessionId: "runtime-session", reason: "test" });
    await call("before_agent_start", { prompt: "trace fixture", systemPrompt: "fixture" });
    await call("turn_start", { turnIndex: 0 });
    await call("before_provider_request", {
      payload: {
        model: "fixture",
        max_tokens: 42,
        apiKey: "trace-secret-sentinel",
        "x-api-key": "trace-x-api-key-sentinel",
        cookie: "trace-cookie-sentinel",
      },
    });
    await call("message_end", {
      message: {
        role: "assistant",
        content: [{ type: "text", text: "ordinary successful response" }],
        stopReason: "stop",
      },
    });
    await call("tool_execution_start", {
      toolCallId: "tool-1",
      toolName: "read",
      args: { path: "probe", authorization: "trace-secret-sentinel" },
    });
    await call("tool_execution_end", {
      toolCallId: "tool-1",
      toolName: "read",
      args: { path: "probe" },
      result: {
        apiKey: "trace-secret-sentinel",
        proxyAuthorization: "trace-proxy-auth-sentinel",
        secretAccessKey: "trace-secret-access-sentinel",
        value: "safe-result",
      },
      isError: false,
    });
    for (let i = 0; i < 2000; i++) {
      await call("model_select", {
        model: { id: "flush-model-" + i },
      });
    }
    await call("turn_end", {
      turnIndex: 0,
      message: {
        role: "assistant",
        content: [{ type: "text", text: "trace-final-flush-sentinel" }],
      },
      toolResults: [],
    });
    await commands.get("trace")?.handler("", ctx);
    const activeHtml = readFileSync(
      process.env.TRACE_PROJECT + "/../home/.pi/agent/traces/runtime-session/trace.html",
      "utf8",
    );
    if (!activeHtml.includes("trace-final-flush-sentinel")) {
      throw new Error("active /trace render omitted buffered events");
    }
    await call("session_shutdown");
    EOF
    HOME="$trace_runtime/home" \
      TRACE_PROJECT="$trace_runtime/project" \
      TRACE_SESSION_FILE="$trace_runtime/home/.pi/agent/sessions/runtime-session.jsonl" \
      ${bun}/bin/bun "$trace_runtime/probe.ts"
    trace_dir="$trace_runtime/home/.pi/agent/traces/runtime-session"
    trace_events="$trace_dir/events.jsonl"
    trace_html="$trace_dir/trace.html"
    [ -f "$trace_events" ] || fail "Trace runtime fixture did not write events.jsonl"
    [ -f "$trace_html" ] || fail "Trace runtime fixture did not render trace.html"
    [ "$(${coreutils}/bin/stat -c '%a' "$trace_dir")" = 700 ] \
      || fail "Trace session directory is not private"
    [ "$(${coreutils}/bin/stat -c '%a' "$trace_events")" = 600 ] \
      || fail "Trace events are not private"
    [ "$(${coreutils}/bin/stat -c '%a' "$trace_html")" = 600 ] \
      || fail "Rendered trace is not private"
    ! grep -F 'trace-secret-sentinel' "$trace_events" "$trace_html" >/dev/null \
      || fail "Trace persisted a secret-like value"
    for secret in \
      trace-x-api-key-sentinel \
      trace-cookie-sentinel \
      trace-proxy-auth-sentinel \
      trace-secret-access-sentinel; do
      ! grep -F "$secret" "$trace_events" "$trace_html" >/dev/null \
        || fail "Trace persisted an extended secret-like value"
    done
    grep -F 'trace-final-flush-sentinel' "$trace_events" >/dev/null \
      || fail "Trace did not flush its final event"
    grep -F 'trace-final-flush-sentinel' "$trace_html" >/dev/null \
      || fail "Trace rendered before its final event was flushed"
    ${jq}/bin/jq -s -e '
      any(
        .[];
        .type == "llm_request"
        and .input.max_tokens == 42
        and .input.apiKey == "[REDACTED]"
        and .input["x-api-key"] == "[REDACTED]"
        and .input.cookie == "[REDACTED]"
      )
      and any(
        .[];
        .type == "tool_end"
        and (.resultPreview | fromjson | .apiKey) == "[REDACTED]"
        and (.resultPreview | fromjson | .proxyAuthorization) == "[REDACTED]"
        and (.resultPreview | fromjson | .secretAccessKey) == "[REDACTED]"
      )
      and any(.[]; .type == "step_end" and (has("errorMessage") | not))
    ' "$trace_events" >/dev/null \
      || fail "Trace sanitizer changed telemetry or optional-field semantics"
    ${python3}/bin/python3 - "$trace_events" "$trace_dir" \
      ${roots.trace}/extensions/trace/trace_to_html.py <<'PY'
    import importlib.util
    import json
    from pathlib import Path
    import sys

    events_path = Path(sys.argv[1])
    session_dir = sys.argv[2]
    renderer_path = sys.argv[3]
    spec = importlib.util.spec_from_file_location("pi_trace_renderer", renderer_path)
    renderer = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(renderer)
    events = [json.loads(line) for line in events_path.read_text().splitlines() if line]
    root = renderer.build_tree(events, session_dir=session_dir)

    def nodes(node):
        yield node
        for child in node.get("children", []):
            yield from nodes(child)

    steps = [node for node in nodes(root) if node.get("type") == "step"]
    if len(steps) != 1 or steps[0].get("status") != "ok":
        raise SystemExit("Trace renderer misclassified an ordinary step")
    PY

    for package_root in \
      ${roots.trace} \
      ${roots.cache-optimizer}; do
      ! grep -R -i 'litellm' "$package_root" >/dev/null \
        || fail "Pi extension package reintroduced a retired LiteLLM reference: $package_root"
    done
    [ -f ${roots.hashline}/index.ts ]
    [ ! -e ${roots.hashline}/node_modules/better-sqlite3 ]
    [ -d ${roots.hashline}/node_modules/sql.js ]
    [ -d ${roots.hashline}/node_modules/xxhash-wasm ]
    [ -f ${roots.smart-fetch}/dist/index.js ]
    [ -d ${roots.smart-fetch}/node_modules/defuddle ]
    [ -d ${roots.smart-fetch}/node_modules/linkedom ]
    [ -d ${roots.smart-fetch}/node_modules/wreq-js ]
    [ ! -e ${roots.smart-fetch}/node_modules/@earendil-works ]
    [ ! -e ${roots.smart-fetch}/node_modules/@sinclair/typebox ]
    [ -f ${roots.smart-web-search}/index.ts ]
    [ -f ${roots.smart-web-search}/markdown.ts ]
    [ -d ${roots.smart-web-search}/node_modules/defuddle ]
    [ -d ${roots.smart-web-search}/node_modules/linkedom ]
    [ -d ${roots.smart-web-search}/node_modules/wreq-js ]

    [ -f ${roots.lens}/dist/index.js ]
    ! grep -R -F 'autoInstall: true' ${roots.lens}/dist/clients >/dev/null \
      || fail "Lens still enables an auto-installer"
    grep -F 'disabled by Nix policy' ${roots.lens}/dist/clients/installer/index.js >/dev/null \
      || fail "Lens installer policy patch is missing"
    [ "$(grep -Fc 'if (process.env.PI_LENS_DISABLE_TOOL_INSTALL === "1") {' \
      ${roots.lens}/dist/index.js)" -eq 3 ] \
      || fail "Lens bundled tool-install gates differ"
    for lens_install_gate in \
      ${roots.lens}/dist/clients/project-trust.js \
      ${roots.lens}/dist/index.js
    do
      grep -F 'if (process.env.PI_LENS_DISABLE_TOOL_INSTALL === "1") return false;' \
        "$lens_install_gate" >/dev/null \
        || fail "Lens install authorization does not enforce the Nix policy"
    done
    PI_LENS_DISABLE_TOOL_INSTALL=1 node --input-type=module <<'JS'
    const projectTrust = await import(
      "file://${roots.lens}/dist/clients/project-trust.js"
    );
    if (projectTrust.assertInstallAllowed("Nix policy test") !== false) {
      throw new Error("Lens install authorization ignored the Nix policy");
    }
    JS
    ! grep -R -E '"npx(\.cmd)?"' ${roots.lens}/dist >/dev/null \
      || fail "Lens still contains a live npx fallback"
    grep -F 'setStatus("pi-lens-lsp", activeIds.length > 0 ? theme.bold("LSP") : theme.fg("dim", "LSP"));' \
      ${roots.lens}/dist/index.js >/dev/null \
      || fail "Lens footer status is not compact"
    for lens_runtime in \
      ${roots.lens}/dist/index.js \
      ${roots.lens}/dist/clients/runtime-tool-result.js
    do
      grep -F 'const rawFilePath = typeof rawPath === "string" ? rawPath : void 0;' \
        "$lens_runtime" >/dev/null \
        || fail "Lens does not ignore array-valued tool paths"
      node --check "$lens_runtime"
    done


    [ -f ${roots.ponytail}/pi-extension/index.js ]

    [ -f ${roots.browser}/dist/extensions/agent-browser/index.js ]
    [ -f ${roots.blackhole}/index.ts ]
    [ ! -e ${roots.blackhole}/node_modules ]
    [ -f ${roots.blackhole}/src/om/compaction-threshold.ts ]
    (
      cd ${sourceForChecks}
      PI_BLACKHOLE_THRESHOLD_HELPER=${roots.blackhole}/src/om/compaction-threshold.ts \
        bun test ./test/ai/pi-blackhole-compaction.check.ts
    )
    ${jq}/bin/jq -e '
      .memory == true
      and .compaction == "auto"
      and .compactionEngine == "blackhole"
    ' ${roots.blackhole}/example-config.json >/dev/null \
      || fail "Blackhole does not ship memory and automatic Blackhole compaction defaults"
    [ -f ${roots.cache-optimizer}/index.ts ]
    [ ! -e ${roots.cache-optimizer}/node_modules ]
    [ -f ${roots.caveman}/extensions/caveman.ts ]
    [ ! -e ${roots.caveman}/node_modules ]
    [ -f ${roots.copy-message}/extensions/copy-message.ts ]
    [ ! -e ${roots.copy-message}/node_modules ]
    (
      cd ${sourceForChecks}
      PI_COPY_MESSAGE_EXTENSION=${roots.copy-message}/extensions/copy-message.ts \
        bun test ./test/ai/pi-copy-message.check.ts
    )
    [ -f ${roots.goal}/extensions/goal.ts ]
    ${python3}/bin/python3 - ${roots.goal}/extensions/goal.ts <<'PY'
    import pathlib
    import sys

    source = pathlib.Path(sys.argv[1]).read_text()
    guarded_entry = (
        'export default function goalExtension(pi: ExtensionAPI): void {\n'
        '\tif (process.env.PI_SUBAGENT_CHILD === "1") return;'
    )
    if source.count(guarded_entry) != 1:
        raise SystemExit("Goal X child guard is not the first extension statement")
    PY
    [ ! -e ${roots.goal}/node_modules ]
    [ -f ${roots.markdown-preview}/index.ts ]
    [ -d ${roots.markdown-preview}/node_modules/puppeteer-core ]
    [ -f ${roots.rtk-optimizer}/index.ts ]
    [ ! -e ${roots.rtk-optimizer}/node_modules ]
    [ -f ${roots.cymbal-extension}/dist/index.ts ]
    [ ! -e ${roots.cymbal-extension}/node_modules ]
    [ -f ${roots.dynamic-workflows}/extensions/workflow.ts ]
    [ -d ${roots.dynamic-workflows}/node_modules/acorn ]
    [ -f ${roots.dynamic-workflows}/skills/workflow-authoring/SKILL.md ]
    [ -f ${roots.dynamic-workflows}/skills/workflow-patterns/SKILL.md ]
    [ -f ${roots.subagents}/index.ts ]
    [ -d ${roots.subagents}/node_modules/jiti ]
    [ -d ${roots.subagents}/node_modules/yaml ]
    [ ! -e ${roots.subagents}/node_modules/typebox ]
    [ -f ${roots.subagents}/skills/pi-subagents/SKILL.md ]
    cymbal_version=$(${lib.getExe piPackages.cymbal} --version)
    printf '%s\n' "$cymbal_version" | grep -F '${manifest.supportSources.cymbal.version}' >/dev/null \
      || fail "Cymbal version drifted: $cymbal_version"

    rtk_version=$(${lib.getExe piPackages.rtk} --version)
    printf '%s\n' "$rtk_version" | grep -F '${manifest.supportSources.rtk.version}' >/dev/null \
      || fail "RTK version drifted: $rtk_version"


    browser_version=$(${lib.getExe piPackages.agent-browser} --version)
    printf '%s\n' "$browser_version" | grep -F '${manifest.supportSources.agent-browser.version}' >/dev/null \
      || fail "agent-browser version drifted: $browser_version"

    [ -f ${gallery}/runtime.ts ]
    [ -f ${gallery}/index.ts ]
    [ -f ${gallery}/timing.ts ]
    [ -f ${gallery}/loader.ts ]
    [ -f ${gallery}/projection.json ]
    grep -Fq 'process.env.PI_LENS_DISABLE_LSP_INSTALL = "1";' ${gallery}/runtime.ts \
      || fail "gallery runtime does not disable Lens LSP installation"
    grep -Fq 'process.env.PI_LENS_DISABLE_TOOL_INSTALL = "1";' ${gallery}/runtime.ts \
      || fail "gallery runtime does not disable Lens tool installation"
    ! grep -Fq 'PI_LENS_AUTO_INSTALL' ${gallery}/runtime.ts \
      || fail "gallery runtime retains the obsolete Lens installation toggle"
    [ "$(jq '.packages | length' ${gallery}/projection.json)" -eq ${toString (builtins.length manifest.order)} ]
    [ "$(jq '[.packages[].skills // [] | length] | add' ${gallery}/projection.json)" -eq ${toString expectedSkillCount} ]
    [ "$(jq '[.packages[].prompts // [] | length] | add' ${gallery}/projection.json)" -eq ${toString expectedPromptCount} ]
    jq --argjson expected '${builtins.toJSON expectedPublicNames}' -e '
      [.packages[].name] == $expected
      and (.packages[] | select(.name == "@dietrichgebert/ponytail") | .skills == [])
    ' ${gallery}/projection.json >/dev/null || fail "projection manifest differs"
    jq -e '
      ([.packages[].name] | index("pi-btw")) as $btw
      | ([.packages[].name] | index("pi-goal-x")) as $goal
      | $btw != null and $goal != null and $btw < $goal
    ' ${gallery}/projection.json >/dev/null \
      || fail "BTW must register before Goal X so its focused overlay owns the first Escape"
    cat > "$TMPDIR/expected-gallery-static-imports" <<'EOF'
    ${lib.concatStringsSep "\n" expectedStaticImportRecords}
    EOF
    sed -nE \
      's#^[[:space:]]*import[[:space:]]+([A-Za-z0-9_]+)[[:space:]]+from[[:space:]]+"([^"]+)";$#\1|\2#p' \
      ${gallery}/index.ts > "$TMPDIR/actual-gallery-static-imports"
    cmp "$TMPDIR/expected-gallery-static-imports" "$TMPDIR/actual-gallery-static-imports" \
      || fail "ordinary gallery static import identity, order, or membership differs"
    if grep -Fq 'module import' ${gallery}/index.ts; then
      fail "ordinary gallery entrypoint contains timing imports"
    fi

    cat > "$TMPDIR/expected-gallery-timing-imports" <<'EOF'
    ${lib.concatStringsSep "\n" expectedActiveImportRecords}
    EOF
    sed -nE \
      's#^[[:space:]]*const \{ default: ([A-Za-z0-9_]+) \} = await timeGallery\("([^"]+)", "module import", \(\) => import\("([^"]+)"\)\);$#\2|\1|\3#p' \
      ${gallery}/timing.ts > "$TMPDIR/actual-gallery-timing-imports"
    cmp "$TMPDIR/expected-gallery-timing-imports" "$TMPDIR/actual-gallery-timing-imports" \
      || fail "timed gallery import identity, order, or membership differs"
    grep -Fq 'process.env.PI_TIMING === "1"' ${gallery}/loader.ts \
      || fail "managed gallery timing is not selected by exact PI_TIMING=1"
    grep -Fq 'await import("./timing.ts")' ${gallery}/loader.ts \
      || fail "managed gallery loader cannot select the timed entrypoint"
    grep -Fq 'await import("./index.ts")' ${gallery}/loader.ts \
      || fail "managed gallery loader cannot select the ordinary entrypoint"
    grep -Fq 'performance.now()' ${gallery}/timing.ts \
      || fail "gallery timing does not use a monotonic clock"
    if grep -Fq 'Date.now()' ${gallery}/timing.ts; then
      fail "gallery timing uses the wall clock"
    fi

    cat > "$TMPDIR/expected-gallery-registrations" <<'EOF'
    ${lib.concatStringsSep "\n" expectedActiveRegistrationRecords}
    EOF
    sed -nE \
      's/^[[:space:]]*\["([^"]+)",[[:space:]]+([A-Za-z0-9_]+)\],?$/\1|\2/p' \
      ${gallery}/index.ts > "$TMPDIR/actual-gallery-registrations"
    cmp "$TMPDIR/expected-gallery-registrations" "$TMPDIR/actual-gallery-registrations" \
      || fail "gallery registration identity, order, or membership differs from the platform contract"
    sed -nE \
      's/^[[:space:]]*\["([^"]+)",[[:space:]]+([A-Za-z0-9_]+)\],?$/\1|\2/p' \
      ${gallery}/timing.ts > "$TMPDIR/actual-gallery-timing-registrations"
    cmp "$TMPDIR/expected-gallery-registrations" "$TMPDIR/actual-gallery-timing-registrations" \
      || fail "timed gallery registration identity, order, or membership differs"
    echo "Pi gallery check: dynamic local providers"
    PI_CODING_AGENT_ROOT=${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent \
      ${bun}/bin/bun ${sourceForChecks}/test/ai/local-openai-provider.check.ts
    PI_GOAL_X_ROOT=${roots.goal} \
    PI_CODING_AGENT_ROOT=${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent \
      ${nodejs_24}/bin/node --experimental-strip-types \
        ${sourceForChecks}/test/ai/pi-goal-x-bounded-history.check.ts
    PI_SUBAGENTS_ROOT=${roots.subagents} \
    PI_SUBAGENTS_HISTORY_BYTES=67108864 \
    PI_SUBAGENTS_MAX_RSS_DELTA_BYTES=32505856 \
      ${bun}/bin/bun test ${sourceForChecks}/test/ai/pi-subagents-bounded-history.check.ts
    PI_BLACKHOLE_ROOT=${roots.blackhole} \
    PI_BLACKHOLE_CLEANUP_BODY_BYTES=67108864 \
    PI_BLACKHOLE_CLEANUP_MAX_RSS_DELTA_BYTES=16777216 \
      ${bun}/bin/bun ${sourceForChecks}/test/ai/pi-blackhole-bounded-history.check.ts
    PI_BLACKHOLE_ROOT=${roots.blackhole} \
      ${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/.bin/jiti \
        ${sourceForChecks}/test/ai/pi-blackhole-exact-history.check.mts
    echo "Pi gallery check: patched agent-core history source"
    ${nodejs_24}/bin/node --input-type=module <<'EOF'
    import { Agent } from "${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core/dist/index.js";

    const agent = new Agent({
      streamFn: () => {
        throw new Error("package contract must not dispatch");
      },
    });
    let materializations = 0;
    agent.setMessageSource({
      length: 1,
      materialize: () => {
        materializations++;
        return [{ role: "user", content: "persisted", timestamp: 1 }];
      },
      last: () => ({ role: "user", content: "persisted", timestamp: 1 }),
      *iterateReverse() {
        yield { role: "user", content: "persisted", timestamp: 1 };
      },
    });
    if (agent.messageCount !== 1 || agent.lastMessage?.role !== "user") {
      throw new Error("packaged agent-core omitted deferred history support");
    }
    agent.appendMessage({ role: "user", content: "tail", timestamp: 2 });
    if (agent.messageCount !== 2 || materializations !== 0) {
      throw new Error("packaged agent-core eagerly materialized deferred history");
    }
    if (agent.getMessagesSnapshot().length !== 2 || materializations !== 1) {
      throw new Error("packaged agent-core snapshot semantics drifted");
    }
    EOF
    echo "Pi gallery check: bounded core session growth"
    PI_CODING_AGENT_ROOT=${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent \
    PI_SESSION_SCALE_BYTES=16777216 \
    PI_SESSION_PAYLOAD_BYTES=262144 \
    PI_SESSION_COMPACTION_EVERY=4 \
    PI_SESSION_MIN_COMPACTIONS=4 \
      ${nodejs_24}/bin/node ${sourceForChecks}/test/ai/pi-session-memory.check.mjs scale
    routing_smoke="$TMPDIR/pi-model-router-smoke"
    mkdir -p "$routing_smoke/home" "$routing_smoke/agent" "$routing_smoke/project"
    cat > "$routing_smoke/agent/models.json" <<'JSON'
    {
      "providers": {
        "router": {
          "api": "router-local-api",
          "apiKey": "pi-model-router",
          "baseUrl": "router://local",
          "modelOverrides": {
            "sol": {
              "defaultThinkingLevel": "off",
              "reasoning": true,
              "input": ["text"],
              "thinkingLevelMap": {
                "minimal": null,
                "low": null,
                "medium": null,
                "high": "high",
                "xhigh": null,
                "max": null
              }
            }
          },
          "models": [{
            "id": "sol",
            "name": "Router sol",
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 128000,
            "maxTokens": 16384
          }]
        },
        "omlx": {
          "api": "synthetic-api",
          "apiKey": "synthetic",
          "baseUrl": "synthetic://omlx",
          "modelOverrides": {
            "Qwen3.6-27B-oQ6e-mtp": {
              "defaultThinkingLevel": "off",
              "reasoning": true,
              "input": ["text"],
              "thinkingLevelMap": {
                "minimal": null,
                "low": null,
                "medium": null,
                "high": "high",
                "xhigh": null,
                "max": null
              },
              "compat": {
                "supportsReasoningEffort": false,
                "thinkingFormat": "qwen-chat-template"
              }
            }
          }
        }
      }
    }
    JSON
    cat > "$routing_smoke/agent/model-router.json" <<'JSON'
    {
      "models": {
        "sol": {
          "model": "synthetic/target",
          "reasoning": true,
          "thinkingLevels": ["off", "high"]
        }
      },
      "profiles": {
        "sol": {
          "low": {
            "model": "sol",
            "thinking": "off"
          },
          "medium": {
            "model": "sol",
            "thinking": "off"
          },
          "high": {
            "model": "sol",
            "thinking": "off"
          }
        }
      }
    }
    JSON
    cat > "$routing_smoke/synthetic.ts" <<'TS'
    import { appendFileSync } from "node:fs";
    import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
    import { registerApiProvider } from "@earendil-works/pi-ai/compat";

    function syntheticStream(model: any, _context: any, options: any) {
      const stream = createAssistantMessageEventStream();
      queueMicrotask(() => {
        const text = options?.reasoning ?? "off";
        if (process.env.PI_ROUTER_REASONING_LOG) {
          appendFileSync(process.env.PI_ROUTER_REASONING_LOG, `''${text}\n`);
        }
        const message: any = {
          role: "assistant",
          content: [{ type: "text", text }],
          api: model.api,
          provider: model.provider,
          model: model.id,
          usage: {
            input: 0,
            output: 1,
            cacheRead: 0,
            cacheWrite: 0,
            totalTokens: 1,
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
          },
          stopReason: "stop",
          timestamp: Date.now(),
        };
        stream.push({ type: "start", partial: message });
        stream.push({ type: "text_start", contentIndex: 0, partial: message });
        stream.push({ type: "text_delta", contentIndex: 0, delta: text, partial: message });
        stream.push({ type: "text_end", contentIndex: 0, content: text, partial: message });
        stream.push({ type: "done", reason: "stop", message });
        stream.end();
      });
      return stream;
    }

    export default function synthetic(pi: any) {
      registerApiProvider({
        api: "synthetic-api",
        stream: syntheticStream,
        streamSimple: syntheticStream,
      });
      pi.registerProvider("synthetic", {
        baseUrl: "synthetic://local",
        apiKey: "synthetic",
        api: "synthetic-api",
        models: [{
          id: "target",
          name: "Synthetic",
          reasoning: true,
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: 128000,
          maxTokens: 16384,
          thinkingLevelMap: {
            minimal: null,
            low: null,
            medium: null,
            high: "high",
            xhigh: null,
            max: null,
          },
        }, {
          id: "plain",
          name: "Plain",
          reasoning: false,
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: 128000,
          maxTokens: 16384,
        }],
      });
      pi.registerProvider("omlx", {
        baseUrl: "synthetic://omlx",
        apiKey: "synthetic",
        api: "synthetic-api",
        models: [{
          id: "Qwen3.6-27B-oQ6e-mtp",
          name: "Sparse Qwen",
          reasoning: false,
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: 262144,
          maxTokens: 65536,
        }],
      });
    }
    TS
    while IFS='|' read -r prompt expected_tier; do
      session_file="$routing_smoke/tier-$expected_tier.jsonl"
      env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$routing_smoke/home" \
      PI_CODING_AGENT_DIR="$routing_smoke/agent" \
      PI_ROUTER_REASONING_LOG="$routing_smoke/reasoning.log" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --print --offline --session "$session_file" --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${routingExtension} \
        --extension "$routing_smoke/synthetic.ts" \
        --provider router --model sol "$prompt" \
        </dev/null >"$routing_smoke/output" 2>"$routing_smoke/error" || {
          status=$?
          cat "$routing_smoke/error" >&2
          fail "model router failed for a disabled tier with status $status"
        }
      [ "$(cat "$routing_smoke/output")" = off ] || {
        cat "$routing_smoke/output" >&2
        cat "$routing_smoke/error" >&2
        fail "model router did not keep its selected tier at reasoning off"
      }
      jq -s -e --arg expected "$expected_tier" '
        ([.[]
          | select(
              .type == "custom"
              and .customType == "router-state"
              and .data.lastDecision != null
            )
        ] | last | .data.lastDecision.tier) == $expected
      ' "$session_file" >/dev/null || {
        cat "$session_file" >&2
        fail "model router did not retain its $expected_tier workload-tier decision"
      }
    done <<'CASES'
    briefly answer|low
    implement the change|medium
    think deeply about this architecture|high
    CASES
    cat > "$routing_smoke/rpc-input.jsonl" <<'JSON'
    {"id":"before","type":"get_state"}
    {"id":"levels","type":"get_available_thinking_levels"}
    {"id":"router-off","type":"prompt","message":"exercise the router disabled path"}
    {"id":"plain","type":"set_model","provider":"synthetic","modelId":"plain"}
    {"id":"qwen","type":"set_model","provider":"omlx","modelId":"Qwen3.6-27B-oQ6e-mtp"}
    {"id":"direct","type":"get_state"}
    {"id":"direct-levels","type":"get_available_thinking_levels"}
    {"id":"direct-off","type":"prompt","message":"exercise the direct disabled path"}
    {"id":"direct-cycle","type":"cycle_thinking_level"}
    {"id":"direct-high","type":"prompt","message":"exercise the direct enabled path"}
    {"id":"direct-reset","type":"cycle_thinking_level"}
    {"id":"router","type":"set_model","provider":"router","modelId":"sol"}
    {"id":"router-cycle","type":"cycle_thinking_level"}
    {"id":"router-high-state","type":"get_state"}
    {"id":"router-high","type":"prompt","message":"exercise the router enabled path"}
    JSON
    env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$routing_smoke/home" \
      PI_CODING_AGENT_DIR="$routing_smoke/agent" \
      PI_ROUTER_REASONING_LOG="$routing_smoke/reasoning.log" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${python3}/bin/python3 "$rpc_sequence" \
        "$routing_smoke/rpc-input.jsonl" \
        "$routing_smoke/rpc-output.jsonl" \
        "$routing_smoke/rpc-error.log" \
        ${lib.getExe piPackage} \
        --mode rpc --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${routingExtension} \
        --extension "$routing_smoke/synthetic.ts" \
        --provider router --model sol || {
      status=$?
      cat "$routing_smoke/rpc-output.jsonl" >&2
      cat "$routing_smoke/rpc-error.log" >&2
      fail "model router thinking-cycle RPC failed with status $status"
    }
    jq -s -e '
      any(.[]; .type == "response" and .id == "before" and .data.thinkingLevel == "off")
      and any(.[]; .type == "response" and .id == "levels" and .data.levels == ["off", "high"])
      and any(.[]; .type == "response" and .id == "router-off" and .success == true)
      and any(.[]; .type == "response" and .id == "plain" and .success == true)
      and any(.[]; .type == "response" and .id == "qwen" and .success == true)
      and any(.[];
        .type == "response"
        and .id == "direct"
        and .data.thinkingLevel == "off"
        and .data.model.provider == "omlx"
        and .data.model.id == "Qwen3.6-27B-oQ6e-mtp"
        and .data.model.reasoning == true
        and .data.model.input == ["text"]
        and .data.model.defaultThinkingLevel == "off"
      )
      and any(.[]; .type == "response" and .id == "direct-levels" and .data.levels == ["off", "high"])
      and any(.[]; .type == "response" and .id == "direct-off" and .success == true)
      and any(.[]; .type == "response" and .id == "direct-cycle" and .data.level == "high")
      and any(.[]; .type == "response" and .id == "direct-high" and .success == true)
      and any(.[]; .type == "response" and .id == "direct-reset" and .data.level == "off")
      and any(.[]; .type == "response" and .id == "router" and .success == true)
      and any(.[]; .type == "response" and .id == "router-cycle" and .data.level == "high")
      and any(.[];
        .type == "response"
        and .id == "router-high-state"
        and .data.thinkingLevel == "high"
        and .data.model.provider == "router"
        and .data.model.id == "sol"
      )
      and any(.[]; .type == "response" and .id == "router-high" and .success == true)
    ' "$routing_smoke/rpc-output.jsonl" >/dev/null || {
      cat "$routing_smoke/rpc-output.jsonl" >&2
      cat "$routing_smoke/rpc-error.log" >&2
      fail "model router did not expose or cycle the exact off/high contract"
    }
    [ "$(jq -R -s -c 'split("\n")[:-1]' "$routing_smoke/reasoning.log")" = \
      '["off","off","off","off","off","high","high"]' ] || {
      cat "$routing_smoke/reasoning.log" >&2
      fail "model router did not delegate off by default and high after thinking-cycle"
    }

    loop_smoke="$TMPDIR/pi-loop-smoke"
    mkdir -p "$loop_smoke/home" "$loop_smoke/agent"
    env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$loop_smoke/home" \
      PI_CODING_AGENT_DIR="$loop_smoke/agent" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --print --offline --session "$loop_smoke/session.jsonl" --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${piPackages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts \
        --extension "$routing_smoke/synthetic.ts" \
        --provider synthetic --model target \
        '/loop --yes --delay 0 --max 2 test' \
        </dev/null >"$loop_smoke/output" 2>"$loop_smoke/error" || {
      status=$?
      cat "$loop_smoke/error" >&2
      fail "pi-loop nested session-entry smoke failed with status $status"
    }
    jq -s -e '
      ([.[] | select(.type == "message" and .message.role == "user")] | length) == 2
      and ([.[] | select(.type == "message" and .message.role == "assistant")] | length) == 2
    ' "$loop_smoke/session.jsonl" >/dev/null || {
      cat "$loop_smoke/output" >&2
      cat "$loop_smoke/error" >&2
      fail "pi-loop did not complete two nested session-entry iterations"
    }
    loop_log=$(find "$loop_smoke/home/.pi/loops" -maxdepth 1 -type f -name 'loop-*.json' -print -quit)
    if [ -z "$loop_log" ] || ! jq -e '.entries | length == 2' "$loop_log" >/dev/null; then
      [ -z "$loop_log" ] || cat "$loop_log" >&2
      fail "pi-loop did not record two completed iterations"
    fi

    smoke="$TMPDIR/pi-gallery-smoke"
    mkdir -p \
      "$smoke/home/.config/pi/agent/extensions/nix-gallery" \
      "$smoke/home/.agents/skills/shared-discovery" \
      "$smoke/project" "$smoke/sentinels"
    ln -s "$smoke/home/.config/pi" "$smoke/home/.pi"
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      cat > "$smoke/discovery-server.py" <<'PY'
      import json
      from http.server import BaseHTTPRequestHandler, HTTPServer
      from pathlib import Path
      import sys

      port_file, request_log = map(Path, sys.argv[1:])

      class Handler(BaseHTTPRequestHandler):
          def do_GET(self):
              with request_log.open("a") as output:
                  output.write(f"{self.path}\n")
              body = json.dumps({"data": [{"id": "catalog-endpoint-probe", "type": "chat"}]}).encode()
              self.send_response(200)
              self.send_header("Content-Type", "application/json")
              self.send_header("Content-Length", str(len(body)))
              self.end_headers()
              self.wfile.write(body)

          def log_message(self, *_args):
              pass

      server = HTTPServer(("127.0.0.1", 0), Handler)
      port_file.write_text(str(server.server_port))
      server.serve_forever()
      PY
      ${python3}/bin/python3 \
        "$smoke/discovery-server.py" \
        "$smoke/discovery-port" \
        "$smoke/discovery-requests" &
      discovery_server_pid=$!
      cleanup_discovery_server() {
        kill "$discovery_server_pid" 2>/dev/null || true
        wait "$discovery_server_pid" 2>/dev/null || true
      }
      trap cleanup_discovery_server EXIT
      for _ in $(seq 1 100); do
        [ -s "$smoke/discovery-port" ] && break
        sleep 0.05
      done
      [ -s "$smoke/discovery-port" ] || fail "managed Pi discovery server did not start"
      discovery_port=$(cat "$smoke/discovery-port")
      cat > "$smoke/home/.config/pi/agent/extensions/nix-gallery/index.ts" <<EOF
      import { createNixGallery } from ${builtins.toJSON "${gallery}/loader.ts"};

      export default createNixGallery({
        "llama-swap": "http://127.0.0.1:$discovery_port/llama/v1",
        "omlx": "http://127.0.0.1:$discovery_port/omlx/v1"
      });
      EOF
    ''}
    ${lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
      ln -s ${gallery}/loader.ts \
        "$smoke/home/.config/pi/agent/extensions/nix-gallery/index.ts"
    ''}
    printf '%s\n' '{"providers":{"sentinel":{"apiKey":"unchanged"}}}' \
      > "$smoke/home/.config/pi/agent/models.json"
    cp "$smoke/home/.config/pi/agent/models.json" "$smoke/models-before.json"
    cat > "$smoke/home/.agents/skills/shared-discovery/SKILL.md" <<'MARKDOWN'
    ---
    name: shared-discovery
    description: Verify default shared skill discovery.
    ---

    # Shared discovery sentinel
    MARKDOWN
    printf '%s\n' '{"name":"lens-language-gate","private":true}' > "$smoke/project/package.json"
    printf '%s\n' 'const answer: number = 42;' > "$smoke/project/probe.ts"
    printf '%s\n' 'answer: int = 42' > "$smoke/project/probe.py"
    printf '%s\n' \
      '{"id":"commands","type":"get_commands"}' \
      '{"id":"ponytail","type":"prompt","message":"/ponytail ultra"}' \
      '{"id":"cache-fix","type":"prompt","message":"/cache-optimizer fix"}' \
      '{"id":"entries","type":"get_entries"}' > "$smoke/input.jsonl"
    for command in npm npx pip pip3 curl wget bun pnpm yarn; do
      cat > "$smoke/sentinels/$command" <<'SH'
    #!/bin/sh
    printf '%s\n' "$0 $*" >> "$PI_GALLERY_INSTALLER_SENTINEL"
    exit 97
    SH
      chmod +x "$smoke/sentinels/$command"
    done
    jq -r '.packages[].skills[]?' ${gallery}/projection.json \
      | while IFS= read -r skill_root; do
        find "$skill_root" -type f -name SKILL.md -print
      done \
      | sort -u > "$smoke/expected-skills"
    cat > "$smoke/active-tools.ts" <<'EOF'
    import { writeFileSync } from "node:fs";
    export default function activeTools(pi: any) {
      pi.on("session_start", () => {
        writeFileSync(process.env.PI_GALLERY_ACTIVE_TOOLS!, JSON.stringify(pi.getActiveTools().sort()));
      });
    }
    EOF
    (
      cd "$smoke/project"
      env -u PI_CODING_AGENT_DIR \
      HOME="$smoke/home" \
      PI_GALLERY_ACTIVE_TOOLS="$smoke/active-tools.json" \
      PI_GALLERY_TOOL_OWNERS_FILE="$smoke/tool-owners.json" \
      PI_GALLERY_INSTALLER_SENTINEL="$smoke/installer-invocations" \
      PI_OFFLINE=1 \
      PI_TIMING=0 \
      PATH="$smoke/sentinels":${
        lib.makeBinPath [
          piPackages.agent-browser
          piPackages.cymbal
          piPackages.rtk
        ]
      }:$PATH \
        ${coreutils}/bin/timeout 120 \
        ${python3}/bin/python3 "$rpc_sequence" \
        "$smoke/input.jsonl" \
        "$smoke/output.log" \
        "$smoke/error.log" \
        ${lib.getExe piPackage} \
        --mode rpc --no-session --offline \
        --no-prompt-templates \
        --no-context-files --no-approve \
        --extension "$smoke/active-tools.ts"
    ) || {
      cat "$smoke/output.log" >&2
      cat "$smoke/error.log" >&2
      fail "aggregate Pi gallery failed to load"
    }
    if grep -Fq '[pi-gallery timing]' "$smoke/error.log"; then
      fail "gallery timing ran when PI_TIMING was not exactly 1"
    fi
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      validate_discovery_requests() {
        [ "$(wc -l < "$smoke/discovery-requests")" -eq 2 ] \
          && grep -Fxq '/llama/v1/models' "$smoke/discovery-requests" \
          && grep -Fxq '/omlx/v1/models' "$smoke/discovery-requests"
      }
      validate_discovery_requests \
        || fail "managed Pi gallery discovery requests differ"
      : > "$smoke/discovery-requests"
    ''}
    printf '%s\n' '{"id":"timing","type":"get_commands"}' \
      > "$smoke/timing-input.jsonl"
    (
      cd "$smoke/project"
      env -u PI_CODING_AGENT_DIR \
      HOME="$smoke/home" \
      PI_GALLERY_ACTIVE_TOOLS="$smoke/timing-active-tools.json" \
      PI_GALLERY_TOOL_OWNERS_FILE="$smoke/timing-tool-owners.json" \
      PI_GALLERY_INSTALLER_SENTINEL="$smoke/installer-invocations" \
      PI_OFFLINE=1 \
      PI_TIMING=1 \
      PATH="$smoke/sentinels":${
        lib.makeBinPath [
          piPackages.agent-browser
          piPackages.cymbal
          piPackages.rtk
        ]
      }:$PATH \
        ${coreutils}/bin/timeout 120 \
        ${python3}/bin/python3 "$rpc_sequence" \
        "$smoke/timing-input.jsonl" \
        "$smoke/timing-output.log" \
        "$smoke/timing-error.log" \
        ${lib.getExe piPackage} \
        --mode rpc --no-session --offline \
        --no-prompt-templates \
        --no-context-files --no-approve \
        --extension "$smoke/active-tools.ts"
    ) || {
      cat "$smoke/timing-output.log" >&2
      cat "$smoke/timing-error.log" >&2
      fail "timed aggregate Pi gallery failed to load"
    }
    cat > "$TMPDIR/expected-gallery-timings" <<'EOF'
    ${lib.concatStringsSep "\n" expectedGalleryTimingRecords}
    EOF
    sed -nE \
      's/^\[pi-gallery timing\] ([^ ]+) (module import|factory): [0-9]+ms$/\1|\2/p' \
      "$smoke/timing-error.log" > "$TMPDIR/actual-gallery-timings"
    cmp "$TMPDIR/expected-gallery-timings" "$TMPDIR/actual-gallery-timings" \
      || fail "gallery per-member timing membership, phase, or order differs"
    gallery_commands() {
      jq -s -c '
        [.[]
          | select(.type == "response" and .command == "get_commands" and .success == true)
          | .data.commands
          | map(.name)
          | sort]
        | if length == 1 then .[0] else error("expected one command response") end
      ' "$1"
    }
    cmp <(gallery_commands "$smoke/output.log") <(gallery_commands "$smoke/timing-output.log") \
      || fail "timed gallery changed registered commands"
    cmp "$smoke/active-tools.json" "$smoke/timing-active-tools.json" \
      || fail "timed gallery changed the active tool surface"
    cmp "$smoke/tool-owners.json" "$smoke/timing-tool-owners.json" \
      || fail "timed gallery changed tool ownership"
    grep -E '^\[pi-gallery timing\] [^ ]+ (module import|factory): [0-9]+ms$' \
      "$smoke/timing-error.log"
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      validate_discovery_requests \
        || fail "timed managed Pi gallery discovery requests differ"
      cleanup_discovery_server
      trap - EXIT
    ''}
    jq -s -e '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and ([
          "blackhole",
          "blackhole-memory",
          "blackhole-recall",
          "btw",
          "btw:tangent",
          "cache-optimizer",
          "caveman",
          "copy-message",
          "copy-user",
          "cymbal:remind",
          "gather-context-and-clarify",
          "goal",
          "goal-abort",
          "goal-clear",
          "goal-focus",
          "goal-list",
          "goal-pause",
          "goal-resume",
          "goal-settings",
          "goal-status",
          "goal-tweak",
          "goals",
          "goals-set",
          "sisyphus",
          "sisyphus-set",
          "insights",
          "mp-preset",
          "pool",
          "subs",
          "parallel-cleanup",
          "parallel-research",
          "parallel-review",
          "ponytail",
          "preview",
          "preview-browser",
          "preview-clear-cache",
          "preview-pdf",
          "review-loop",
          "rewind",
          ${lib.optionalString stdenv.hostPlatform.isDarwin ''"router",''}
          "rtk",
          "run",
          "subagents",
          "subagents-doctor",
          "subagents-fleet",
          "subagents-models",
          "subagents-watchdog",
          "trace",
          "usage",
          "workflows"
        ] - [.data.commands[].name] | length) == 0
        and ([.data.commands[].name
          | select(. == "parallel-context-build" or . == "parallel-handoff-plan")]
          | length) == 0
        and ([.data.commands[].name | select(startswith("sidebar"))] | length) == 0
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "new Pi gallery commands were not registered"
    }
    jq -s -e --arg skill "$smoke/home/.agents/skills/shared-discovery/SKILL.md" '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and any(
          .data.commands[];
          .name == "skill:shared-discovery"
          and .source == "skill"
          and .sourceInfo.path == $skill
        )
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "Pi did not discover the shared skill tree through HOME"
    }
    # The trailing anvil clause is a prohibition, not a leftover reference. It
    # survives the Anvil retirement deliberately: retiring the convergence that
    # removed existing Anvil state is not the same as allowing the gallery to
    # advertise an Anvil tool again. It was deleted with that machinery in
    # cc0f6718 and restored in e5b7f905; a source search for "anvil" will find
    # this line, and it is the one that should stay.
    jq -e '
      . as $actual
      | ($actual | length) == ($actual | unique | length)
        and all(
          [
            "batch_web_fetch",
            "edit",
            "read",
            "recall",
            "web_fetch",
            "web_search",
            "write"
          ][];
          . as $required | $actual | index($required) != null
        )
        and all(
          ["memory_read", "memory_search", "memory_write", "scratchpad"][];
          . as $inactive | $actual | index($inactive) == null
        )
        and all($actual[]; contains("anvil") | not)
    ' "$smoke/active-tools.json" >/dev/null || {
      cat "$smoke/active-tools.json" >&2
      fail "Pi gallery required tools, uniqueness, or retired-tool invariant failed"
    }
    validate_web_tool_owners() {
      jq -e '
        .batch_web_fetch == ["smart-fetch"]
        and .web_fetch == ["smart-fetch"]
        and .web_search == ["smart-web-search"]
      ' "$1" >/dev/null
    }
    validate_web_tool_owners "$smoke/tool-owners.json" || {
      cat "$smoke/tool-owners.json" >&2
      fail "Pi gallery web tools do not have exactly one declared owner"
    }
    jq -e '.recall == ["blackhole"]' "$smoke/tool-owners.json" >/dev/null || {
      cat "$smoke/tool-owners.json" >&2
      fail "Blackhole does not exclusively own recall"
    }
    jq '.web_search += ["smart-fetch"]' "$smoke/tool-owners.json" \
      > "$smoke/tool-owners-duplicate.json"
    if validate_web_tool_owners "$smoke/tool-owners-duplicate.json"; then
      fail "tool-ownership gate accepted a second web_search owner"
    fi
    jq '.web_fetch = ["smart-web-search"]' "$smoke/tool-owners.json" \
      > "$smoke/tool-owners-wrong.json"
    if validate_web_tool_owners "$smoke/tool-owners-wrong.json"; then
      fail "tool-ownership gate accepted the wrong web_fetch owner"
    fi
    jq -s -e '
      any(
        .[];
        .type == "extension_ui_request"
        and .method == "notify"
        and .notifyType == "warning"
        and .message == "Nix manages models.json; edit config/ai and switch the configuration instead."
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "Cache Optimizer did not refuse its models.json write path"
    }
    jq -s -e '
      any(
        .[];
        .type == "entry_appended"
        and .entry.customType == "ponytail-mode"
        and .entry.data.mode == "ultra"
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "Ponytail command did not activate through the aggregate gallery"
    }
    while IFS= read -r skill; do
      jq -s -e --arg skill "$skill" '
        any(
          .[];
          .type == "response"
          and .command == "get_commands"
          and .success == true
          and any(.data.commands[]; .source == "skill" and .sourceInfo.path == $skill)
        )
      ' "$smoke/output.log" >/dev/null \
        || fail "Pi did not parse packaged skill frontmatter: $skill"
    done < "$smoke/expected-skills"
    [ ! -e "$smoke/home/.config/pi/agent/settings.json" ] || fail "gallery wrote Pi settings"
    cmp -s "$smoke/models-before.json" "$smoke/home/.config/pi/agent/models.json" \
      || fail "Cache Optimizer changed Nix-managed models.json"
    [ ! -e "$smoke/home/.npm" ] || fail "gallery invoked npm"
    [ ! -e "$smoke/installer-invocations" ] || {
      cat "$smoke/installer-invocations" >&2
      fail "an active Gallery extension invoked a package installer or downloader"
    }

    quiet_smoke="$TMPDIR/pi-quiet-renderer-smoke"
    mkdir -p "$quiet_smoke/home" "$quiet_smoke/agent"
    printf '%s\n' '{"type":"get_commands"}' | (
      cd "$quiet_smoke/home"
      HOME="$quiet_smoke/home" \
      PI_CODING_AGENT_DIR="$quiet_smoke/agent" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --mode rpc --no-session --offline \
        --no-extensions --no-skills --no-prompt-templates \
        --no-context-files --no-approve \
        --extension ${quiet}
    ) >"$quiet_smoke/output.jsonl" 2>"$quiet_smoke/error.log" || {
      cat "$quiet_smoke/error.log" >&2
      fail "pi-quiet renderer seam smoke failed"
    }
    jq -s -e '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and any(.data.commands[]; .name == "quiet" and (.description | contains("built-in + Foreign Tools")))
      )
    ' "$quiet_smoke/output.jsonl" >/dev/null || {
      cat "$quiet_smoke/output.jsonl" >&2
      fail "pi-quiet did not select the one-argument renderer seam"
    }

    touch "$out"
  ''
