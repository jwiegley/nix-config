# Frozen Promptdeploy Oracle and Canonical Asset Evidence

Recorded: 2026-07-22

## Decision and scope

This record freezes Promptdeploy as a read-only migration oracle for the five Nix-managed clients: Claude Code, Codex, OpenCode, Droid, and Pi. It does not make Promptdeploy a build input or a steady-state runtime dependency. The original checkout was not edited, its dirty models.yaml was preserved, and no .env file or live secret-bearing client document was read into this repository.

GPTel and git-ai remain unmanaged exclusions. The rendered gptel-emacs target was retained only inside the protected oracle so the composed deployment could be proved; no GPTel asset or ownership state was imported. The existing git-ai persona, files, and manifests are not adopted or deleted.

## Frozen source authority

- Promptdeploy HEAD: 7a12b54d31385ed46e368d97a6a3f4ec4088aeca on main.
- Classified dirty state: exactly one unstaged file, models.yaml.
- translate-tool submodule: bffdb7ba3e5db603ea1390fee555354c1d45d642.
- Locked Superpowers revision: d884ae04edebef577e82ff7c4e143debd0bbec99.
- Locked Ponytail revision: 16f29800fd2681bdf24f3eb4ccffe38be3baec6b.
- Locked llm-agents revision: ba8c89d5b4836d46f7bdbffd2df34c66dadef725.
- Snapshot ID and framed-manifest SHA-256: bf0c00fe3b01d8a069817098be52314f49918217039c903514bfb85758c13c7b.
- Snapshot inventory: 295 entries: 49 directories, 244 regular files, and 2 confined symlinks.
- Protection: macOS UF_IMMUTABLE on the root and every selected entry.
- Storage: source and snapshot are on the same local APFS volume, /dev/disk3s5.
- Final post-operation regeneration: the 295-entry framed manifest remained byte-identical and continued to hash to the snapshot ID.

The two symlinks are skills/translate-en to ../translate-tool/skill and translate-tool/skill/GLOSSARY.csv to ../glossary.csv. Both resolve within the reviewed set. Six entries were excluded without reading their contents: the empty untracked skills/alexey-review directories, three generated __pycache__ directories, and src/promptdeploy.egg-info.

| Frozen path | SHA-256 |
|---|---|
| bundles/ponytail.yaml | 06767aabfb78fed35e7438e9e89ea28982e14b7d0e367dec46dfa3a0781520b8 |
| deploy.yaml | 9a18492297f8b1b9d3919b180f3a82b7b5dd6c9141b3b65f5e8ee8d542f0c346 |
| flake.lock | 66bd535e13626f2232c31b196ae035f9f08a5deccb611e2568b6ab5af4628c9f |
| flake.nix | e75ed8bcaa21fe1b155fddc5e84d50cf560eeff244267646aae5ffd233e7ded4 |
| models.yaml | c6a18cba992a54500796bd26cd99ffeeb422b080a72f7bc6065474457e8db98d |
| prompts/emacs.poet | 1f499971b038daf557ac503e958fa15a87d95b11adffd451145e4c59fbc04176 |
| prompts/spanish.poet | e91d1534e49abf6aafedd614a018af1d895d9271f3540940f0d53cbf5c3b0875 |
| settings.yaml | ef45db2fc07aa4d4e7a465ec9a950403693dc17c43c72b3cfa28fb3342a44fa0 |
| skills/.promptdeploy-skill-links.json | 054d59d541bf57ead9db9413c249734f276010d3d1db4cdf03e954fa0c5b5eaf |
| statusline-command.sh | 7cb1fcb475bc94fb61b7324ab6ff2f349e3bfe86fdca775e19842fd74dd28729 |
| translate-tool/glossary.csv | 8eab769223267b8b8cded5ba62f7a4250dfcf25d94d35cffd7e360354b3e9523 |
| translate-tool/skill/SKILL.md | f26ff06e43b9d99e96876cbd567a7f6d8585983b0a550b97ef5e672f294790fb |

## Isolated named-app oracle

Only the composed named #promptdeploy app was invoked. The default deployment app, #raw, de, direnv, nix develop, uv, npm, rsync, and the mutable checkout were not used.

- Named wrapper: /nix/store/2yb34kv2xli8s8lf5nm7bd6xcxp3dzxh-promptdeploy.
- Packaged Python application: /nix/store/xkxd8pfswq2mj04i1rg896f902rqwjbc-promptdeploy-0.1.0.
- Composed deployment: /nix/store/rf50rqkgrvdw67h6djvq7qivraa8knj6-promptdeploy-deployment.
- Closure: 73 paths and exactly one bin/.promptdeploy-wrapped.
- Interpreter: /nix/store/0kpmn91hpcg7fx0kd4ji2blhnigzvw98-python3-3.12.13/bin/python3.12; its store root is in the closure.
- Isolation shims for ssh, scp, rsync, osascript, defaults, security, open, and process termination recorded zero invocations.
- validate exited 0 with 0 errors and 6 expected warnings.
- First Hera deployment: 2709 created, 0 updated, 0 removed, 0 unchanged.
- Second Hera deployment: 0 created, 0 updated, 0 removed, 2709 unchanged.
- First Clio deployment: 2709 created, 0 updated, 0 removed, 0 unchanged.
- Second Clio deployment: 0 created, 0 updated, 0 removed, 2709 unchanged.
- Every required literal environment reference remained in both host trees. Synthetic values occurred zero times in Hera output, Clio output, manifests, and logs.
- The named-app closure scan covered 24,401 non-.env regular files, 1,461,365,760 bytes, with zero synthetic-value matches. One .env-named closure fixture remained deliberately unopened. Nix purity and the unchanged store closure establish that the run-time sentinels were not build inputs.
- The persisted run-one.zsh harness contains the eight deliberate synthetic sentinel strings; it is an execution harness, not rendered output, a manifest, a log, or a closure member.

Endpoint Security traces attached before exec and followed the process tree. The complete cached validate trace has 4,093 events and SHA-256 24958057938cabc5ae9a0c2a84b5840ddd6fa2336c5b716d93a2ead473d8bb17. The complete first Hera deployment trace has 14,680 events and SHA-256 d1b9d37b91501effd8aff45a262d4aa5d3fe198f9ab63c6476d45218bf58fcd9. The complete cached Clio deployment trace has 26,854 events and SHA-256 558cc801511e1a59b93040aaa6926642a013e18ec16fbc9e40d61f769755be08; it recorded the expected 2,709 unchanged paths. The complete Clio exact-selector verification trace has 27,091 events and SHA-256 ca39931d61e992283587c6ca1465ea05dbe64c1d7dc4246c85386dbf18002410; verification returned the documented status 1 with the same 314-line stderr and SHA-256 beca4e0e2d085b1863fad5e2732722a6bbd94f761e8d4a5da354e5f189879281. All four complete traces were independently scanned: no opened /Users/johnw path was outside the synthetic run root, the protected snapshot, or the exec gate; other paths were confined to required Nix and operating-system runtime locations.

The second Hera target completed its zero-action result before trace shutdown. Its trace contains 25,302 relevant events, but the filter rejected eslogger's final truncated JSON fragment at raw line 1,064,522. This shutdown artifact is not represented as a complete trace and is not relied upon; the complete Clio deployment and verification captures exercise the host-selected Clio branch.

## Named verification and independent structural proof

The exact selector union was passed to both named-app verify runs. Both status replays recorded exit 1, empty stdout, and the same 314 unique selector-target findings. Every finding was unprovable; there were no mismatches, manifest mismatches, unreadable targets, or no-applicable-target results. The exact stderr SHA-256 is beca4e0e2d085b1863fad5e2732722a6bbd94f761e8d4a5da354e5f189879281. Category accounting is 244 command, 28 hook, 16 marketplace, 8 settings, 8 models, and 10 prompt findings.

This is a frozen Promptdeploy verification limitation, not a passing named verification result. Aggregate projections and unsupported client projections cannot be proved by its target_item_matches_source path after manifest validation. The result is accepted only alongside the independent structural proof below.

The independent verifier:

- strictly parsed all 90 JSON and 108 TOML files per host, rejecting duplicate JSON keys, non-finite values, unsafe paths, hard links, special nodes, escaping links, misplaced manifests, target-path collisions, and missing target paths;
- compared every manifest item map, relative path, type, mode, symlink target, normalized timestamp, and framed tree hash;
- proved all four shared Claude trees exact and all four shared OpenCode trees exact;
- proved codex-local, codex-hera, and codex-clio exact and codex-andoria their precise six-command/one-skill superset;
- proved the complete 161-selector manifest union exact;
- proved all 314 named findings match selected manifest entries and the pinned finding-set hash;
- recorded exit 1 from both named status replays;
- found zero synthetic values and zero shim invocations; and
- re-bound the result to the 295-entry immutable source record.

The report is logs/structural-verification.json under the host-local render root, SHA-256 5b160f0073291dacf2c965c4c9e3df4af2305fadf7814f0e97d6e377ed98c947.

Twenty Hera/Clio target pairs are exact after surgical timestamp normalization. Droid has one approved host-selected semantic projection and no other difference:

| Host | Droid custom models | settings.json SHA-256 | Manifest model source hash |
|---|---:|---|---|
| Hera | 87 | 377bec75bfc5b97636d7f1eea1a99d5db2e32a7a5ad485df58be93f924b7eabf | sha256:55b9475d18dd3419b19359df44297d731a6cf0c6f63da7476e3848d33aa89ec6 |
| Clio | 88 | 892b19f2f19bde59ad0ebe17cf9eb9de08e673b83f9541c49ed2d2aacd0747c3 | sha256:81c1ca782ae34349c60e3ed1430394c11ab3b65c0eb317ee427ec473d4eb5990 |

## Exact selector union

The union contains 161 unique sorted selectors: 26 agents, 1 bundle, 65 commands, 4 hooks, 2 marketplaces, 13 MCP servers, 1 models item, 8 prompts, 1 settings item, and 40 skills. Its JSON SHA-256 is 8afe91a3dd95d36ab41676d9fdaeac2cd883170bf9992df91cced636e0827a29.

    agent:bash-reviewer
    agent:coq-reviewer
    agent:cpp-pro
    agent:cpp-reviewer
    agent:elisp-reviewer
    agent:emacs-lisp-pro
    agent:fess-auditor
    agent:haskell-pro
    agent:haskell-reviewer
    agent:nix-pro
    agent:nix-reviewer
    agent:perf-reviewer
    agent:persian-translator
    agent:prd-architect
    agent:prompt-engineer
    agent:python-pro
    agent:python-reviewer
    agent:rocq-pro
    agent:rust-pro
    agent:rust-reviewer
    agent:security-reviewer
    agent:sql-pro
    agent:task-breakdown
    agent:typescript-pro
    agent:typescript-reviewer
    agent:web-searcher
    bundle:ponytail
    command:assess
    command:bankruptcy
    command:breakdown
    command:bugbot
    command:bugbot-stack
    command:capture
    command:cleanup
    command:code-review
    command:commit
    command:deep-review
    command:discover-bundles
    command:eliminate-dead-code
    command:expense-report
    command:fess
    command:fix
    command:fix-alert
    command:fix-ci
    command:fix-github-issue
    command:fix-integration
    command:fix-transcript
    command:flaky-rust
    command:forge
    command:gravity
    command:halt
    command:heavy
    command:infer-tasks
    command:initialize
    command:install-service
    command:journal
    command:lefthook
    command:markdown
    command:medium
    command:meeting-notes
    command:narrative
    command:nix-rebuild
    command:partner-cleanup
    command:partner-collaborator
    command:partner-reviewer
    command:prepare-with
    command:process-checklist
    command:productize
    command:proofread
    command:push
    command:query-builder
    command:quick-review
    command:rebase
    command:rebase-and-fix
    command:recommit
    command:remove-service
    command:report
    command:resolve
    command:respond
    command:restack
    command:retest
    command:retest-categorical
    command:review-github-pr
    command:run-orchestrator
    command:sec-audit
    command:sitrep
    command:smooth
    command:teams
    command:transcribe-image
    command:tron-debug
    command:webfix
    command:wiggum
    hook:agent-deck-claude
    hook:agent-deck-codex
    hook:claude-code
    hook:claude-vault
    marketplace:claude-code-plugins
    marketplace:claude-plugins-official
    mcp:Ref
    mcp:anvil
    mcp:anvil-tools
    mcp:context-hub
    mcp:context7
    mcp:devonthink
    mcp:drafts
    mcp:drafts-hera
    mcp:memory-vault
    mcp:pal
    mcp:perplexity
    mcp:sequential-thinking
    mcp:stock-trader
    models:models
    prompt:emacs
    prompt:ponytail
    prompt:ponytail-audit
    prompt:ponytail-debt
    prompt:ponytail-gain
    prompt:ponytail-help
    prompt:ponytail-review
    prompt:spanish
    settings:settings
    skill:anvil
    skill:brainstorming
    skill:caveman
    skill:comment-audit
    skill:dispatching-parallel-agents
    skill:eliminate-dead-code
    skill:executing-plans
    skill:finishing-a-development-branch
    skill:fix-all
    skill:fix-transcript
    skill:forge
    skill:git-surgeon
    skill:it-voice
    skill:johnw
    skill:nixos
    skill:node-red
    skill:parallelize
    skill:persian
    skill:ponytail
    skill:ponytail-audit
    skill:ponytail-debt
    skill:ponytail-gain
    skill:ponytail-help
    skill:ponytail-review
    skill:receiving-code-review
    skill:requesting-code-review
    skill:retest
    skill:skill-creator
    skill:subagent-driven-development
    skill:swiftui
    skill:systematic-debugging
    skill:test-driven-development
    skill:toolkit
    skill:translate-en
    skill:using-git-worktrees
    skill:using-superpowers
    skill:verification-before-completion
    skill:wiggum
    skill:writing-plans
    skill:writing-skills


Legacy selector translation is fixed as follows:

- Filename tag personal: capture, fix-alert, install-service, remove-service, and webfix.
- Filename tag positron: cleanup, forge, heavy, retest, retest-categorical, and tron-debug.
- only personal: expense-report and fix-integration.
- Droid command projections: discover-bundles and restack.
- Forge is Claude-only; Retest is Positron-only.
- Personal command selection is 59, Positron selection is 58, and the shared Codex union is 65.
- The private selector-source record remains outside Git. It contains 112 unique canonical discovery records (26 agents, 65 commands, 19 discovered skills including excluded translate-en, and 2 prompts), SHA-256 bd686f3423475bbf86d7de8ea83ef697565f2df8475abd18e438cf94850240d4.

## Oracle target mappings

The table records exact manifest item counts. Clio has the same counts; only the pinned Droid model payload differs as described above.

| Target | Agents | Commands | Skills | MCP | Models | Hooks | Prompts | Settings | Marketplaces | Bundles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| claude-andoria-t2 | 26 | 58 | 40 | 8 | 0 | 3 | 2 | 1 | 2 | 1 |
| claude-andoria | 26 | 58 | 40 | 8 | 0 | 3 | 2 | 1 | 2 | 1 |
| claude-delphi-3bd4 | 26 | 58 | 40 | 8 | 0 | 3 | 2 | 1 | 2 | 1 |
| claude-gpu-server | 26 | 58 | 40 | 8 | 0 | 3 | 2 | 1 | 2 | 1 |
| claude-personal | 26 | 59 | 39 | 12 | 0 | 3 | 2 | 1 | 2 | 1 |
| claude-positron | 26 | 58 | 40 | 8 | 0 | 3 | 2 | 1 | 2 | 1 |
| claude-vps | 26 | 59 | 39 | 8 | 0 | 3 | 2 | 1 | 2 | 1 |
| claude-vulcan | 26 | 59 | 39 | 10 | 0 | 3 | 2 | 1 | 2 | 1 |
| codex-andoria | 26 | 65 | 39 | 7 | 0 | 1 | 2 | 0 | 0 | 1 |
| codex-clio | 26 | 59 | 38 | 7 | 0 | 1 | 2 | 0 | 0 | 1 |
| codex-hera | 26 | 59 | 38 | 7 | 0 | 1 | 2 | 0 | 0 | 1 |
| codex-local | 26 | 59 | 38 | 7 | 0 | 1 | 2 | 0 | 0 | 1 |
| droid | 26 | 2 | 38 | 7 | 1 | 0 | 2 | 0 | 0 | 1 |
| gptel-emacs | 0 | 0 | 0 | 0 | 0 | 0 | 8 | 0 | 0 | 1 |
| opencode-andoria-08 | 26 | 58 | 39 | 7 | 1 | 0 | 2 | 0 | 0 | 1 |
| opencode-andoria-t2 | 26 | 58 | 39 | 7 | 1 | 0 | 2 | 0 | 0 | 1 |
| opencode-clio | 26 | 59 | 38 | 10 | 1 | 0 | 2 | 0 | 0 | 1 |
| opencode-delphi-3bd4 | 26 | 58 | 39 | 7 | 1 | 0 | 2 | 0 | 0 | 1 |
| opencode-gpu-server | 26 | 58 | 39 | 7 | 1 | 0 | 2 | 0 | 0 | 1 |
| opencode-hera | 26 | 59 | 38 | 10 | 1 | 0 | 2 | 0 | 0 | 1 |
| opencode-vulcan | 26 | 59 | 38 | 9 | 1 | 0 | 2 | 0 | 0 | 1 |


## Canonical import and adoption decisions

Promptdeploy's packaged Python runtime was entered with -I -B, and its wrapper was bootstrapped without invoking the CLI. Extraction called list(SourceDiscovery(Path(snapshot)).discover_all()) exactly.

- Agents and commands are exact body-only Markdown. Canonical frontmatter APIs proved the deployment fields were stripped before body extraction.
- Eighteen repository-owned skills are complete canonical materializations. The external translate-en tree is excluded here because ai-nix owns the pinned ordinary tree.
- emacs.md and spanish.md each match all 30 approved Claude/OpenCode candidates. Their SHA-256 values are bf97fe8df58266d9684ed863d9cffcdf4a5c6ae3efa324bb2a8c9e442b67d30b and 1887e44e53ebb1da4fa8f4db713ad35720ac85b994b302822c18a1854ff2cfd5.
- statusline-command.sh matches the frozen source exactly, SHA-256 7cb1fcb475bc94fb61b7324ab6ff2f349e3bfe86fdca775e19842fd74dd28729.
- The extraction contains 39 directories and 163 files. Its extraction-stage framed asset-root SHA-256, including original numeric modes, is 640dd6663d3d1dd10889725449075b9dca71610c9bb977bad267454a386d32c2; extraction-report.json has SHA-256 3b32017b3761ffa9501a3d1c23d7a6fd0a4b17060d05ea9e3eaf7bf3213d32e1.
- The committed copy is normalized to Git-canonical 0644/0755 modes. A second Git-stable recursive digest binds every path, type, executable bit, symlink target, size, and byte: 422c4e45bc09b660118f3f3651f7fbce632ec07dbc678105c323ab5cb74e1768.
- An independent audit compared all 676 rendered Claude, Codex, OpenCode, and Droid skill occurrences and found zero path or byte mismatches.

### OpenCode static adoption

A one-shot silent host-local process read the live source internally and emitted only a mode-0600 whitelist projection. The live expanded source was never displayed, logged, retained, copied, or read into the agent context. Independent validation rejected missing keys, fourth keys, duplicate keys, noncanonical types, secret-shaped values, credential-bearing URLs, and non-0600 output.

Projection SHA-256: 50d3c10b48d78c3f448225754c726c4cdca20874c2d0a54c2dc33fd5a967d10e.

Reviewed nonsecret values:

- $schema: https://opencode.ai/config.json
- disabled_providers: openai, gemini, anthropic
- instructions: CLAUDE.md, AGENTS.md

Only these three values may seed the later complete declarative OpenCode document.

### External resource parity and exclusions

ai-nix agent-resources at /nix/store/rwa7n4cn1fgr5wy454vciy33qymcfg7g-agent-resources supplies the pinned Superpowers, Ponytail, git-surgeon, translate-en, and Pi resources. git-surgeon has two files. Applying Promptdeploy's canonical SKILL.md transformation to the ai-nix resource yields tree hash 9fa1d870438aba9a16bb68b7fd7f008ef0e2b1aa38dbc1a5cb406f10d70df237, exactly equal in Claude, Codex, OpenCode, and Droid oracle trees.

Ponytail contributes only six static skill trees: ponytail, ponytail-review, ponytail-audit, ponytail-debt, ponytail-gain, and ponytail-help. Dormant hooks, modes, status lines, runtime publication, and the OpenCode plugin are excluded. GPTel Ponytail prompt projections remain outside this migration.

The disabled anvil-tools source is a migration tombstone only, SHA-256 1d4fd2d3b9f723dce1cb53d5b34c0b3cc05bca05859ee11875ec0bed5ab95284. It is not catalog content. The active unified anvil source is SHA-256 d3abda1a763759dadf0940dcade1718c7485114d2126c7dcd06f72207ce2225d.

### Native secret-reference transformations

No resolved value is canonical content. The typed catalog form names only an environment variable. Later renderers translate it to the client-native reference:

| Client | Native reference contract |
|---|---|
| Claude | literal environment placeholder |
| OpenCode | {env:VAR} |
| Codex | environment-key fields, env_http_headers, or bearer-token environment fields |
| Droid | literal environment placeholder for models; inherited environment for stdio |
| Pi | native dollar-form environment reference |

The frozen Ref source, SHA-256 8a18aa0ee76851962d181965c22b2e2ecb7ce4977ae19f2bdf646a7b7d5279bf, used a query parameter. The adopted definition instead uses https://api.ref.tools/mcp with an x-ref-api-key environment-backed header. Context7, source SHA-256 d1f10e62c9d122458faa7bfbc87b3e30b09b651bc9af8ec20f55fb06c9d54842, likewise remains an environment-backed header. Droid uses only the pinned static-header bridge where it lacks native header expansion; the bridge's secret/OAuth boundaries are covered by the Task 3 wrapper proof.

The safe PAL source definition is SHA-256 d8e685730e2089c0eec2508fa29d22e97062a56d32814710939bb0d03889f51a. Droid/Hera adopts that typed, environment-referenced definition rather than any expanded live mcp.json bytes. Any other unmanaged Droid MCP entry is a migration collision.

### Relocations and direct Pi inventory

Hard-coded legacy statusline paths are not retained; later rendering derives them from homeDirectory and the selected profile root. Shared Codex keeps CODEX_HOME on the NFS home but relocates only SQLite and logs to the existing host-local root. The managed profile and exact user skill trees stay at their native shared paths.

Pi has no fabricated Promptdeploy target. Its direct acceptance inventory is:

- 26 personal-selected subagent files under ~/.pi/agent/agents;
- 59 personal-selected native command templates plus 2 static prompts under ~/.pi/agent/prompts;
- selected shared skills under ~/.agents/skills, including 6 Ponytail trees;
- 59 command-* and 2 prompt-* Codex projections visible through the same shared skill root;
- models.json providers positron-anthropic, positron-google, positron-openai, nvidia, litellm, omlx, and llama-cpp-local, with no Clio-only llama-cpp-remote and no managed default;
- global MCP catalog entries Ref, context-hub, context7, perplexity, sequential-thinking, and Anvil;
- pinned pi-mcp-adapter and pi-subagent extension roots.

Pi excludes PAL, DEVONthink, Drafts, memory-vault, stock-trader, hooks, marketplaces, and anvil-tools. Mutable Pi settings, auth, sessions, model store, adapter cache/OAuth, and adapter-only settings remain unmanaged.

## Per-file imported asset evidence

The table is generated from the private extraction report and records extraction-stage numeric modes. The extraction-stage root hash above also binds all 39 directory entries and their recorded modes. Git preserves only each file's executable bit; the committed copy is normalized to 0644/0755 and is bound by the separate Git-stable recursive digest above.

| Relative path | Mode | Bytes | SHA-256 |
|---|---:|---:|---|
| agents/bash-reviewer.md | 0644 | 4487 | 65c49a3489a180c3ff21b4e31f70cadf84f267cab38bb61bec8b947f2d6af8ac |
| agents/coq-reviewer.md | 0644 | 4968 | 8805e9d40f685965b121260c517df03fcb3c0b911f3395294a37011d80db2a22 |
| agents/cpp-pro.md | 0644 | 1099 | b7bab002be9c1f619ab7baca68dfab24d3fe5fcaf069fc4a8c574da670a41e8d |
| agents/cpp-reviewer.md | 0644 | 3445 | 08490aef697f703ec6cbcc291a8c497287d0bc09de52bd280925f13e5a5e2929 |
| agents/elisp-reviewer.md | 0644 | 4113 | 1a91dcd49aec2824c63e43f71676205a35ba131431b9abeb2bd9b8f911834a14 |
| agents/emacs-lisp-pro.md | 0644 | 6933 | 3a16ebf53a6560b39ce183f11be6f7b3a84c7c1ddb0f5afe79ec292345cd9dcc |
| agents/fess-auditor.md | 0644 | 1968 | c835e5f121c5f1a3d927b351729347d875657dd7620580a4a4975f5013dfa11b |
| agents/haskell-pro.md | 0644 | 28149 | 4ff98fa574ab7dc794830662860b40182158f198d1ceebe2828eabf75f3049f5 |
| agents/haskell-reviewer.md | 0644 | 4090 | a34f6fd83efe63c60a051283cd17ccb3324ce411f37b81796211b2e83d573e4c |
| agents/nix-pro.md | 0644 | 4864 | 21d28a6083b4e93c9210af388c8973f9795834e22699e3a147bbd3b547901daa |
| agents/nix-reviewer.md | 0644 | 4331 | f9e0e892ae5291a9acfb11e5513410bba513afd12beecbee1bea3cae39135e6b |
| agents/perf-reviewer.md | 0644 | 3285 | 1c777169ec5f0238845674dfa4f64a16f84b118d13a3c7940a03a4f124fc350a |
| agents/persian-translator.md | 0644 | 4234 | 5d74241a1e0638c2ad77ffb2eedb6fe095195fbea67d2e93cda06d36d976ed23 |
| agents/prd-architect.md | 0644 | 8972 | e666ec96671384ffc30c743d241831905c910fe1c77a84bb22643e015f4a8af2 |
| agents/prompt-engineer.md | 0644 | 2825 | 09515a01d6c222a5ae31434488f1464d7f5d509da10e7dbb1539899ad05fa481 |
| agents/python-pro.md | 0644 | 971 | d1cd818f6eaad164b4c690a59453d2e7cbc017b4d7f1d8ec0bc5799c257b6c1c |
| agents/python-reviewer.md | 0644 | 3887 | 443d5c2142c5c34ef39a22838f5cef75fe9466ceff9e6cf6658392d70e0176e2 |
| agents/rocq-pro.md | 0644 | 3796 | 97c564dc04554aae20285a524c36bfcbf8f08f8a480f0b681a081058e38f7b18 |
| agents/rust-pro.md | 0644 | 863 | 676212d5ce881f42c6d6ba69aabb5197472cab3ab9d26b59eafce32479e377d9 |
| agents/rust-reviewer.md | 0644 | 4057 | 285dcb6f06a062fd88a5cbd16bf6fde3e653584322e91e83f16fdd9afad82248 |
| agents/security-reviewer.md | 0644 | 4133 | a9de4b3fb83c3875cb7ce59e5c314822fe342b6ace10805efcbba587c3d9df7f |
| agents/sql-pro.md | 0644 | 911 | ac7cbf730e9abd95a9c55abac513ab8e965ac73a142cca14c8cf3a9119bd3878 |
| agents/task-breakdown.md | 0644 | 9852 | f3352a6d5389ae2f7158ca3f3e0fd071a762b24cfced4e44a5b7691f5a52fff6 |
| agents/typescript-pro.md | 0644 | 8269 | f766c5de2d1f69ef5ce090d167d27aa897850f4c9f288132ed72eb5dff6e0916 |
| agents/typescript-reviewer.md | 0644 | 8162 | 220bae45af1bee8b433537e1233a079e5179db85e416ede87cba43bcdbd38ff0 |
| agents/web-searcher.md | 0644 | 4900 | 88dcfbef9bc2bdcea10dcee0bb8e9225aebe4b77ef96c042c28976279bb150f5 |
| commands/assess.md | 0644 | 389 | af7690f5efd1bacf62b07087bd7784ef904e164fd99241ed74bffa6a3765add0 |
| commands/bankruptcy.md | 0644 | 800 | ba2cbf520a7e291bf1b86a1e3884d0371a1f51e02a8841117c85867677a6b6b1 |
| commands/breakdown.md | 0644 | 7577 | 07d5e85412a7de28865fcb1b10587fd3f805deef5e0f6dd31a2e7a88d1303e8d |
| commands/bugbot-stack.md | 0644 | 1980 | 3a43c3664ed8b3485d399ec6cd61b576ef8697537da90967585fa4e88c40fd60 |
| commands/bugbot.md | 0644 | 4430 | d678dff5cefbc0c427873c0cd9757b09858a8791f44d300f5fffb9bc54dbdb40 |
| commands/capture.md | 0644 | 134 | 6b4085dc00a712bf2c59ca202c648c6a3726bb3ec213a8dd8b3d296b828e863d |
| commands/cleanup.md | 0644 | 543 | ba58fad3eca55e71787c55129b14cee73cbfdc4e0e11a867fda6867d005252dd |
| commands/code-review.md | 0644 | 1562 | 55c074b12865178f0bca34a5c5a61826eefb46036106baa4d8140edf5a283527 |
| commands/commit.md | 0644 | 3782 | c20c30b0eb44b1a1316ce9f92d371f77c9050c1da3df55dfd6b0ea1172ff92d1 |
| commands/deep-review.md | 0644 | 5454 | f6461a58a381a1ada3007aa600311f35319eb89212b9b42ffdb898d481387041 |
| commands/discover-bundles.md | 0644 | 6308 | 0d66aafa4bc28737d3203cb334c4c62684fd2ae49408fd0395d2a92cfd934034 |
| commands/eliminate-dead-code.md | 0644 | 768 | b8e19ba9cf227136b4333181ce94d7544048764e5137c6ea653fb44c32779060 |
| commands/expense-report.md | 0644 | 5902 | 581ed68eb73ac97aafa38fb0ee960a86163ede5201060ec41703da172ec5edb1 |
| commands/fess.md | 0644 | 10739 | 5bf3e27352feb8f1ed9c3ef6d2cf22416cf23889fe7d377867701a0f1b3a01e7 |
| commands/fix-alert.md | 0644 | 114 | 00ca42cb077f961ec3eef3eb59b476ce48cc646b6f24ee279444097bbb4ebc76 |
| commands/fix-ci.md | 0644 | 635 | 18321c05d219837919a64d9c03fa43081ea6f3a3723a161bd0e5c9a9fa4ac1f5 |
| commands/fix-github-issue.md | 0644 | 1122 | d3698e6e2762186178429399ee29c1ad21bfd03885f199cd7c8e53c9a6163349 |
| commands/fix-integration.md | 0644 | 262 | 51a97f136cde41a4ffeccfcf6b77d21b7f29c934280c60d400d1e9b5870011d0 |
| commands/fix-transcript.md | 0644 | 716 | 258dd5fe62dd67a80799398f1fc81d9400b1b0eacf5364ce46500ff310897036 |
| commands/fix.md | 0644 | 7137 | 5edb5dc725f800c9d744c221df806dd82a872ec79624de3c96174e01e780b8ca |
| commands/flaky-rust.md | 0644 | 188 | 756dc63949bafbd09ff3a15fffd418e05f32f03fb6c49e61ede70c972205c6c0 |
| commands/forge.md | 0644 | 292 | fc1ce26af0aa98b0c8ddfda161d9883dd1b20c0d9f80af4cd5b1f86281a43f6a |
| commands/gravity.md | 0644 | 231 | c1f1ba0519bc53a7a258f664eef110c3a5041ee4db77a3327ef5ccd44054c6db |
| commands/halt.md | 0644 | 886 | e10e33e6aba65ea6351e978f6d7a79057d093cddcb5636236720c0c8a61d78ee |
| commands/heavy.md | 0644 | 640 | 0d1a80ea0b21146242692c9ad7e3a162f7a9178da6b0f8d32fcd76a8854e56c7 |
| commands/infer-tasks.md | 0644 | 11542 | 59ce94565e999ae0f10833a2e379eb7550d59cda67ab40886f123b208514bece |
| commands/initialize.md | 0644 | 1601 | b7ddbf450d52e44b67561c0bc70d0443a845376a19810654fc4ded226c021ea3 |
| commands/install-service.md | 0644 | 2285 | 8c5a122f4c763aedbb03f8acb3156e93bf5f48b970b5d5918bd4f59a9c75f7b4 |
| commands/journal.md | 0644 | 2416 | 509385b5de72454634ffd8e1af62836593731eabc90d878618d7df78e1048e62 |
| commands/lefthook.md | 0644 | 393 | 3c88dc19bca6634e0f04fc249b0b65c1caf96189fedfd7466ce56503a7969107 |
| commands/markdown.md | 0644 | 191 | 44c17f513de44f0d0fef04ee050e6928f7c88fd8af6ed6eceadd72a1a36b473b |
| commands/medium.md | 0644 | 200 | 811575690d01111d8ea91a4a1dc8f2facc24830a6b1de9feacc24184b8332fdc |
| commands/meeting-notes.md | 0644 | 7012 | af962ef880b280781cf42edb3b3b581f94f67473322f36d80447bace2f9a3db2 |
| commands/narrative.md | 0644 | 4729 | 181d9889c051496d678f8e32f663500b1d53e34a4887db46e3622720a4c3a0cb |
| commands/nix-rebuild.md | 0644 | 111 | 817e59a74dbcd00b7016df325f090dc1223ef7ad146877f58bba1c19801cd90e |
| commands/partner-cleanup.md | 0644 | 4481 | 8cc588156dc40e20b86dd4467f5c74b350192ab0b833594a96a9459544dac9e9 |
| commands/partner-collaborator.md | 0644 | 7787 | 049a6fd104a8fb5c52885b45cfe528c22dc06c9cc9263784a683740fb2860685 |
| commands/partner-reviewer.md | 0644 | 5362 | 5d4ba280c348dbfe00642cc174b6d3a75902cb0ac6d1d0402a993132deb5132f |
| commands/prepare-with.md | 0644 | 1897 | c5023403b67790d567c880b9e5a1a655abadb63fc3fb52aed37d300dacfe611b |
| commands/process-checklist.md | 0644 | 443 | 7fa3f05b56a6cf861b66530c86051599f11b28fb2fbe02ac76de524420704b9b |
| commands/productize.md | 0644 | 3195 | 7c190f775c619f8fa2a46f0c297e74ad19b01bb49097f6172a0a62e57a2dd4a7 |
| commands/proofread.md | 0644 | 1527 | 6c38fcb5b4975ad31ebcbe0c226037ce9c2148cacf6677fa4f2b2b08e29cc324 |
| commands/push.md | 0644 | 191 | 318479bd864346492f4c9ed1836b22652469718cb74746ed1367bf114e002c69 |
| commands/query-builder.md | 0644 | 381 | e6ed156cff79949fd90d77680b4f54e898dc9339fe5469c4f0e7e99714cad40e |
| commands/quick-review.md | 0644 | 1327 | 084d5e096082d4b402f798fdd11e787da47e7b4afa1241dcf735516edee8dddd |
| commands/rebase-and-fix.md | 0644 | 1685 | 08e67c72ea7063b730477d67132992f3d2f7423bbdc31b83c8edd6be67f3aad4 |
| commands/rebase.md | 0644 | 1199 | 7b281b306c90f6621df608ff76b18c62e28c2d25fc522fec72ad96caef7e9a75 |
| commands/recommit.md | 0644 | 573 | 7184b106f067353ab15fabe3f190a6d045dbb66d7dddb7ecef3c953b49b51f38 |
| commands/remove-service.md | 0644 | 1331 | 3bfae8d3d456010a86d4f1716576df30c02df44cb87ee2cb37c2823fe4d04155 |
| commands/report.md | 0644 | 941 | 250a5d8331dcebab2f228f693a20ce80bc9de7d825fe477706a70cda46d2fc42 |
| commands/resolve.md | 0644 | 353 | db443875c751188655889beebf981709c3d9157c480bde637cbdcbda764e8d6a |
| commands/respond.md | 0644 | 333 | 2e06dc40ec400c474a715257381df015965b1474f949bbd0201c30d566c15269 |
| commands/restack.md | 0644 | 2351 | 5fe69184ebb35b8675495b7295bff795d5705df4edd761419c44fd35594e3345 |
| commands/retest-categorical.md | 0644 | 32323 | 576c55b6f06f5326ecc9e01bf9ee956a9f7049fcd5e9faf256f6ab7a4695659d |
| commands/retest.md | 0644 | 341 | 6de32c502e5de0606364b1c3960d3cb70814fb1791634ce3323bc2ba3b5e0483 |
| commands/review-github-pr.md | 0644 | 2913 | 836c61813d393569ab6bb5dc4b8488e7d29962c342c7ed44128d238d1b67f279 |
| commands/run-orchestrator.md | 0644 | 1499 | 7cf648715fd5b56b2525890cf82f08d702d81abc066d87df2aa89e59a34574a2 |
| commands/sec-audit.md | 0644 | 1378 | b43d67e173487ad4a6f4d26039afcacd32d04f136ffc1fba67b80fdb2fe6d767 |
| commands/sitrep.md | 0644 | 4250 | 26a4dff901c68e72448d53f93a97e4573aaeb95e1b679989a3e30b5ca3407323 |
| commands/smooth.md | 0644 | 619 | 7f52719b78597927f14b9327ae9a77247473804c11117d61262d8923c58309e0 |
| commands/teams.md | 0644 | 567 | 954620f64f6deb221f21239140ae7f8ff207ec5ebcc03fe3c06c2fe9ae9510a9 |
| commands/transcribe-image.md | 0644 | 320 | da38c948ce92ce302b2060f001bb14d033cc3936ece92325f7ec2cdbe71fb7b3 |
| commands/tron-debug.md | 0644 | 1307 | 92bbb87bc95aec77f137d5b9e46f862d623c8c5d169b0a474cea80bf3f2d02b3 |
| commands/webfix.md | 0644 | 320 | cb06785af10e83c53a57bf4fb459de1ab781ac266bdadc6ab56a906e7b0c9aa0 |
| commands/wiggum.md | 0644 | 1556 | 2f34894458b270aaa76b4d10b9f404240af402e7f9eef23fc76d139607145eb6 |
| prompts/emacs.md | 0644 | 7919 | bf97fe8df58266d9684ed863d9cffcdf4a5c6ae3efa324bb2a8c9e442b67d30b |
| prompts/spanish.md | 0644 | 648 | 1887e44e53ebb1da4fa8f4db713ad35720ac85b994b302822c18a1854ff2cfd5 |
| skills/anvil/SKILL.md | 0600 | 11464 | e705eb5a28e7cc4a434c217fc379ce4bc55cc275abd209a310275453f745a969 |
| skills/anvil/references/tools.md | 0644 | 25890 | d3739013980f9b2f2eeff3704421252b3a543d879a9dc936873c2668c6ac9f2a |
| skills/caveman/SKILL.md | 0600 | 2566 | f7086975a7ab691166e4d40f2b1f8ae1ef9c98d5c65c8b0437e74c3a56a06086 |
| skills/comment-audit/SKILL.md | 0600 | 7567 | dddd5da4d1f6151836fb15ea4138443be154c2bc63e4cf8455c5921ea9f47d44 |
| skills/comment-audit/references/claim-taxonomy.md | 0664 | 5856 | a020fe146f5d027d54daedbf998cd65999938f3aeff44750b1f2247aed325a79 |
| skills/comment-audit/references/verification-guide.md | 0664 | 4428 | 87b166c9f1c1bb94a40048a531ef587414b040c6feee86140e3e12a3e5dbe3f8 |
| skills/comment-audit/scripts/inventory_comments.py | 0775 | 25831 | 6715287c781e599c06d297112bd6840c05c7abdad63855cdcec9a7902de4bff2 |
| skills/eliminate-dead-code/SKILL.md | 0600 | 6182 | bc5ff1e523cd5325be60c9a1cfdf644f947e0a63f9da533038ab9439ec06b412 |
| skills/eliminate-dead-code/references/gates-and-report.md | 0664 | 4574 | a60e2f0d32dce009ea5fb19c94d88899cccb77e0744f7f0c8048b06c1a184e17 |
| skills/eliminate-dead-code/references/phases.md | 0664 | 29445 | 8b5fea0d72341e31c4e6a13ffd87c4d6052cd4e9e8dbf9be41bdf1b4fd76c3ed |
| skills/fix-all/README.md | 0664 | 1479 | 09b5d0985a6e1e114e4d168efedfba60cf38bcbc4b459fb33573f38d155c6c15 |
| skills/fix-all/SKILL.md | 0600 | 4118 | bd4f9ec280cc3d0233670ee6aec2a29bfcef44bfd9314808ef6ca3ab9307e08d |
| skills/fix-transcript/SKILL.md | 0600 | 5372 | adec52d8f1db167b3be2441939a04e45a84eb901e3a19f1659cc3ef6f61aacbe |
| skills/fix-transcript/references/symbol-words.md | 0664 | 1655 | ca32b14b5dc1cd82255e2fa6f9ef5070ac2bfc55a130e175a4739599b3cedac4 |
| skills/fix-transcript/references/vocabulary.md | 0664 | 6203 | 45f5ee42491144181e635797ccaee065295842b81669137a1b8ca1a049df51fc |
| skills/forge/SKILL.md | 0600 | 11766 | 31b9b9b400f1a3586fc403cae92a5541e2362c7f570f01ba1bc06d9a7c571aec |
| skills/it-voice/SKILL.md | 0600 | 11485 | 01c0a82a8b07f408ec310ba5c6707a2f94b1ca1a2ecc8df0b66ffcc3251844a0 |
| skills/johnw/SKILL.md | 0600 | 17501 | 748b5c1d0297b3fcba0d15ccc3a34dc20fc988c2594dd4ec4225bcc59f4e573b |
| skills/johnw/references/structure.md | 0664 | 1417 | 85eddeb575ffe62ea7877fcd95c27d24aeafb6873589e3a244632901c03070b1 |
| skills/johnw/references/vocabulary.md | 0664 | 1995 | d90037cb9eb2a8b1d31c7d4a67362d21ba6973a2dedc8cbe70b9e32daf8734be |
| skills/nixos/SKILL.md | 0600 | 1481 | 13e5a351dafca6ddf1359572700319743e9033baea6422ede6787ab1ec62c999 |
| skills/node-red/SKILL.md | 0600 | 15927 | 5126704b4d7cecffeb1b3d0f78242715c15461c26274d2a74a0fc00d2f4d1d30 |
| skills/node-red/assets/boilerplate/function_async.js | 0664 | 2915 | dada83c424bf2e2d262c6f0393af9e25e958e29605c9be81fd9e943547b04563 |
| skills/node-red/assets/boilerplate/function_context.js | 0664 | 5851 | 7614b13c64ffb80d7280b5c0a5fe58d80075cf8a7f2b56734c36bff35ec1f963 |
| skills/node-red/assets/templates/http_api_flow.json | 0664 | 11609 | 49efd6b377372dfa02bb4f43e817715ba4428051c0b86d4ee0d326c680bbbd9d |
| skills/node-red/assets/templates/mqtt_flow.json | 0664 | 6909 | 6e9f712ab56c5adcc28c8506457201a984313f6c793f981bf3079a442d8a1a69 |
| skills/node-red/references/api_reference.md | 0664 | 7691 | 62ec5efe719fd45aef39f87d09f4100985e4e45e3794cdf3e900feb269c2bb1b |
| skills/node-red/references/event_logging.md | 0664 | 7890 | c7e77fe19b6cd13f34a0539b1468cd563cdad7d7846be17c03aa621a98cf3f20 |
| skills/node-red/references/function_snippets.md | 0664 | 13936 | 3f2b9d8e896d16209618237b8199a8988afe071fc040cb9ebc32d4b90c8ef99d |
| skills/node-red/references/node_schemas.md | 0664 | 10089 | 5bc8514d7add9066cc980ead35def450afb05942160ba7fd47c6fd655bcca01d |
| skills/node-red/references/patterns.md | 0664 | 11167 | c83b41af9d71f0608d105000a7754521f17516de670d184bdfe01b78d1f2ceda |
| skills/node-red/references/plugins.md | 0664 | 10871 | d22941c9416f69b6ff089ff33318dbdea55049ad06a9b3088b19a9d618aa53a6 |
| skills/node-red/scripts/create_flow_template.py | 0775 | 11037 | bbfc9129790c4fceef3662e62f9dcef3e42b67b4889a6b6e0300c78ac5aa219b |
| skills/node-red/scripts/generate_uuid.py | 0775 | 566 | 725e5c92d1cf2f9a1461782723ceee6a3feac455b31095bc12f08c528fe32b2f |
| skills/node-red/scripts/validate_flow.py | 0775 | 4136 | c298e39c83a73cc30d6082b4875e29680edbe7046690ec7d239754fdf0096b9c |
| skills/node-red/scripts/wire_nodes.py | 0775 | 2122 | 9b517a2ccc307f48c0f2888fd6a1a1811ae2854eda949e7c4b91a83f1f0f5ea5 |
| skills/parallelize/SKILL.md | 0600 | 11095 | 071e2f0d95fe36209e490fec2c3c59c3600f0ba9905acdeaedc259772df9c9c8 |
| skills/parallelize/references/parallelize-playbook.md | 0664 | 6406 | 4bdd6aad4a2d65187998d07db792ca94e8ef19e975c68cfc7ee307ee1a2d9c54 |
| skills/persian/PersianTerms.txt | 0664 | 103671 | ecfe31651e362c2298eca1df755acca3b199377b98758d4422aaa433a9a5a0be |
| skills/persian/SKILL.md | 0600 | 14233 | 5be604aa098399be4426e0a127e0a30c1dbad4e836f344483ec8d96b75e5994d |
| skills/persian/TERMS.csv | 0664 | 2738 | 27430f856bd13c93901d47b762f475f749abf9436e9b9b0b62b4a9465e79b4b4 |
| skills/persian/Translations/2022 Ridvan Message (English).txt | 0664 | 12204 | a8de0c7463cae74d2cc4b1b4d1e60b3d887898f175600291ba540d86d11c87fe |
| skills/persian/Translations/2022 Ridvan Message (Persian).txt | 0664 | 19850 | 85d2a4e5e57e4f48bac43a09a0bb750927dc55973f645c2d4721cc91668e96ba |
| skills/persian/Translations/2023 Ridvan Message (English).txt | 0664 | 10671 | d22370fda041753e06c24722ac59f378bb32979c4a97c9c5e956117f8e2c3bd6 |
| skills/persian/Translations/2023 Ridván Message (Persian).txt | 0664 | 18320 | 3cfdb03b61bfad5d7799d7a2ffb30c6d11d4f3ac805d8708962e4997124c5b14 |
| skills/retest/SKILL.md | 0600 | 7351 | af5c22fa284fe79458be5d668266c94a4b368b1cf0b9e80bcb5d84b33f6412e5 |
| skills/retest/references/spec.md | 0664 | 41914 | e4caeee5deb900f9268441756347fcf7ddbf7f3d05bc5b48aec358cbd0f6f9ee |
| skills/skill-creator/LICENSE.txt | 0664 | 11357 | 58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd |
| skills/skill-creator/SKILL.md | 0600 | 11881 | 832509efcd4fed74d022d9ced4733f2dbe76ad3acd9e3b48b29d42a41bfb18f8 |
| skills/skill-creator/scripts/init_skill.py | 0775 | 11125 | d907fbc8f65642ae032ef6461f09935eceabaffc3d1d00c658c83d95616fbea5 |
| skills/skill-creator/scripts/package_skill.py | 0775 | 3309 | 34c437481a5e98512e918676691fc21e83b948259889172d2944a2b33b2aaae9 |
| skills/skill-creator/scripts/quick_validate.py | 0775 | 2266 | b89ed010d6d1a021d98b0a765ccb94be9c023548e50cc5fd25971f860aaff2c5 |
| skills/swiftui/LICENSE | 0664 | 1076 | 8f5fd8e5cddb015b5627e45e68b256356586144288a4a0a3db87e38bcb0c9155 |
| skills/swiftui/README.md | 0664 | 6151 | 47689eac7a617718a1adf2eb0f053bfd00a7690fb17fde24b15dddf4db74d675 |
| skills/swiftui/SKILL.md | 0600 | 13568 | eb036b3e2e94b8907df033f912b02f0b25204f6ca6464c4cab8256df6430a942 |
| skills/swiftui/references/image-optimization.md | 0664 | 7752 | 0ff79bf4f12e62313647b3680922fbe0ff01ad5bfca18778a0c639a225a290cf |
| skills/swiftui/references/layout-best-practices.md | 0664 | 7387 | d689c32bae48bdb52600ccfdc67e83759fff5c3fed6594f64aedce40e92f99b7 |
| skills/swiftui/references/liquid-glass.md | 0664 | 9369 | abece64222e7d5856635a0b1b1ecd236de508b16b236866ec3566c716bf592d3 |
| skills/swiftui/references/list-patterns.md | 0664 | 3547 | 5a13f3cc043e404039b8791633dd4bc3787a42a3a890e0e7b7fe01e1bf53666b |
| skills/swiftui/references/modern-apis.md | 0664 | 8819 | 0f478ca9f1b62fc6dabd01f34b2aa7d1df353567da7669b020b4d4f59e960782 |
| skills/swiftui/references/performance-patterns.md | 0664 | 9339 | 64c938ad62e9c010fd4a0208dfdca2d63d9e99049e5773528c99e15119bda322 |
| skills/swiftui/references/scroll-patterns.md | 0664 | 8513 | a50d87f4504e6888b696e403aaa325b840141291f92124412f4cb829c37ca7b6 |
| skills/swiftui/references/sheet-navigation-patterns.md | 0664 | 7150 | 8331c71e4fd116c942a719dd246afabdba81817127b83778f4aa45a399f84743 |
| skills/swiftui/references/state-management.md | 0664 | 12059 | f42795caa39bd6a9abdfb11bb0a23adaaebf882df045813c19dfbb294b274227 |
| skills/swiftui/references/text-formatting.md | 0664 | 6311 | f5642ad65423c89b95cea8c0e7231c80d34b14e16df07c734df8ffd9928a8725 |
| skills/swiftui/references/view-structure.md | 0664 | 7630 | 6564a2605fb5e7fccd49b8113ec0c8afa828fba327efb7f715c9b90921b191aa |
| skills/toolkit/SKILL.md | 0600 | 1629 | b926234329ddeb310158f74c6aecf68cbad1df4ac91309bacf02498a623768ac |
| skills/wiggum/SKILL.md | 0600 | 9018 | 0541b27d19ec855d7be8279ce94bbb8493081df3a8f3c01dcd4358e938ebb0eb |
| skills/wiggum/references/fess-audit.md | 0664 | 1981 | e40d56833c995b2bc6bd4930c07978e27266691255766dbdfb00a71aec7fa63e |
| statusline-command.sh | 0755 | 4271 | 7cb1fcb475bc94fb61b7324ab6ff2f349e3bfe86fdca775e19842fd74dd28729 |


## Acceptance boundary

This document authorizes only the imported canonical assets and later pure Nix renderers described by the approved plan. It does not authorize host activation, collision adoption, rollback-window closure, or Promptdeploy retirement. Those operations remain separately gated.
