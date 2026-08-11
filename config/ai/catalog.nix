{
  lib,
  resources,
}:

let
  clients = [
    "claude"
    "codex"
    "droid"
    "pi"
    "prime"
  ];
  contentClients = clients;
  commandClients = [
    "claude"
    "codex"
    "pi"
    "prime"
  ];
  audiences = [
    "personal"
    "positron"
  ];
  hosts = [
    "clio"
    "hera"
    "shared-work"
    "vps"
    "vulcan"
  ];
  platforms = [
    "darwin"
    "linux"
  ];
  mkProfile = client: profileAudiences: host: platform: root: {
    inherit
      client
      host
      platform
      root
      ;
    audiences = profileAudiences;
    # Provider name -> base URL of a local-inference endpoint this profile
    # routes models to, or null. Declared here so renderers and the composer
    # read a capability instead of re-deriving the fact from host or
    # platform identity.
    localModelEndpoints = null;
  };

  # The local inference stack: config/launchd.nix runs llama-swap and omlx as
  # ungated user agents on every Darwin workstation (hera and clio alike), so
  # every workstation profile that routes models locally declares the same
  # endpoints. Only codex consumes the URL values; pi and prime gate their
  # local provider wiring on the field being non-null. The field asserts that
  # the services are DEFINED on the host — which models their unmanaged
  # configs (~/Models/llama-swap.yaml, ~/.config/omlx) actually serve is
  # mutable host state outside Nix.
  workstationLocalModelEndpoints = {
    omlx = "http://localhost:8000/v1";
    llama-swap = "http://localhost:8080/v1";
  };

  profileSpecs = {
    clio-claude-personal = mkProfile "claude" [ "personal" ] "clio" "darwin" ".config/claude/personal";
    clio-claude-positron = mkProfile "claude" [ "positron" ] "clio" "darwin" ".config/claude/positron";
    clio-codex = mkProfile "codex" [ "personal" ] "clio" "darwin" ".config/codex" // {
      localModelEndpoints = workstationLocalModelEndpoints;
    };
    clio-pi = mkProfile "pi" [ "personal" ] "clio" "darwin" ".config/pi/agent" // {
      localModelEndpoints = workstationLocalModelEndpoints;
    };

    hera-claude-personal = mkProfile "claude" [ "personal" ] "hera" "darwin" ".config/claude/personal";
    hera-claude-positron = mkProfile "claude" [ "positron" ] "hera" "darwin" ".config/claude/positron";
    hera-codex = mkProfile "codex" [ "personal" ] "hera" "darwin" ".config/codex" // {
      localModelEndpoints = workstationLocalModelEndpoints;
    };
    hera-droid = mkProfile "droid" [ "personal" ] "hera" "darwin" ".config/factory";
    hera-pi = mkProfile "pi" [ "personal" ] "hera" "darwin" ".config/pi/agent" // {
      localModelEndpoints = workstationLocalModelEndpoints;
    };
    hera-prime = mkProfile "prime" [ "personal" ] "hera" "darwin" ".prime/agent" // {
      localModelEndpoints = workstationLocalModelEndpoints;
    };

    shared-work-claude-positron = mkProfile "claude" [ "positron" ] "shared-work" "linux" ".claude";
    shared-work-codex = mkProfile "codex" [
      "personal"
      "positron"
    ] "shared-work" "linux" ".codex";
    shared-work-pi = mkProfile "pi" [ "personal" ] "shared-work" "linux" ".config/pi/agent";
    vps-claude-personal = mkProfile "claude" [ "personal" ] "vps" "linux" ".claude";
    vps-pi = mkProfile "pi" [ "personal" ] "vps" "linux" ".config/pi/agent";
    vulcan-claude-personal = mkProfile "claude" [ "personal" ] "vulcan" "linux" ".claude";
    vulcan-pi = mkProfile "pi" [ "personal" ] "vulcan" "linux" ".config/pi/agent";
  };
  catalogProfiles = lib.mapAttrs (id: profile: profile // { inherit id; }) profileSpecs;

  matchesAny = actual: wanted: wanted == null || lib.any (value: builtins.elem value actual) wanted;

  matches =
    profile: selectors:
    matchesAny [ profile.client ] (selectors.clients or null)
    && matchesAny profile.audiences (selectors.audiences or null)
    && matchesAny [ profile.host ] (selectors.hosts or null)
    && matchesAny [ profile.platform ] (selectors.platforms or null)
    && matchesAny [ profile.id ] (selectors.profiles or null)
    && !(builtins.elem profile.id (selectors.excludeProfiles or [ ]));

  resolveItem =
    profile: item:
    let
      transportByHost = item.transportByHost or { };
      resolved =
        builtins.removeAttrs item [ "transportByHost" ]
        // lib.optionalAttrs (builtins.hasAttr profile.host transportByHost) {
          transport = transportByHost.${profile.host};
        };
    in
    assert !(resolved ? transport) || validateTransport resolved.transport;
    resolved
    // lib.optionalAttrs (resolved ? transport) {
      transport = renderTransportArguments resolved.transport;
    };
  select =
    profile: itemSet:
    lib.mapAttrs (_: resolveItem profile) (
      lib.filterAttrs (_: item: matches profile (item.selectors or { })) itemSet
    );

  agentMetadata = lib.mapAttrs (name: metadata: metadata // { inherit name; }) {
    "bash-reviewer" = {
      "description" =
        "Expert Bash/Shell script reviewer specializing in quoting correctness, POSIX compliance, security, and robustness patterns. Use when reviewing shell scripts or shell fragments embedded in CI configs, Makefiles, or installers.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "coq-reviewer" = {
      "description" =
        "Expert Coq/Rocq code reviewer specializing in proof soundness, tactic hygiene, termination arguments, and proof engineering patterns. Use when reviewing Coq/Rocq (.v) proof developments.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "cpp-pro" = {
      "description" =
        "Write idiomatic C++ with modern features, RAII, smart pointers, STL algorithms. Handles templates, move semantics, performance optimization. Use PROACTIVELY for C++ refactoring, memory safety, complex C++ patterns.";
    };
    "cpp-reviewer" = {
      "description" =
        "Expert C++ code reviewer specializing in memory safety, undefined behavior, modern C++ idioms, and concurrency. Use when reviewing C or C++ source and header changes.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "elisp-reviewer" = {
      "description" =
        "Expert Emacs Lisp code reviewer specializing in lexical binding, package conventions, macro hygiene, and performance. Use when reviewing Emacs Lisp (.el) code or Emacs configurations.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "emacs-lisp-pro" = {
      "description" =
        "Expert in Emacs Lisp language, editor environment, module system. Use PROACTIVELY for Emacs Lisp development, package management with use-package, Emacs Lisp expression development.";
    };
    "fess-auditor" = {
      "description" =
        "Runs the fess audit in a sub-agent and reports the evidence-backed results to the main session. Use after implementation or verification work when the main agent needs an honesty check.";
    };
    "haskell-pro" = {
      "description" =
        "Expert in Haskell, type-level programming, performance tuning, concurrency, and the Cabal/Stack/Nix build toolchain. Use PROACTIVELY for Haskell development, debugging type errors, diagnosing space leaks, and build configuration.";
    };
    "haskell-reviewer" = {
      "description" =
        "Expert Haskell code reviewer specializing in laziness pitfalls, type safety, space leaks, and idiomatic functional patterns. Use when reviewing Haskell (.hs/.lhs) changes.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "nix-pro" = {
      "description" =
        "Expert in NixOS configurations, Nix language, flakes, module system. Masters declarative system management, derivations, reproducible builds. Use PROACTIVELY for NixOS system configuration, package management, Nix expression development.";
    };
    "nix-reviewer" = {
      "description" =
        "Expert Nix code reviewer specializing in reproducibility, flake hygiene, NixOS module design, and security. Use when reviewing Nix expressions, flakes, or NixOS/Home Manager modules.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "perf-reviewer" = {
      "description" =
        "Cross-language performance reviewer specializing in algorithmic complexity, resource leaks, allocation patterns, and system-level bottlenecks. Use for a cross-cutting performance pass over a changeset, after or alongside language-specific review.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "persian-translator" = {
      "description" = "Translate English language text into high quality, accurate Persian (Farsi) text.";
    };
    "prd-architect" = {
      "description" =
        "Use this agent when you need to create, update, or refine a Product Requirements Document (PRD) for use with Task Master. This includes developing new PRDs, enhancing existing documents, and capturing significant architectural decisions. Use PROACTIVELY when a user describes a new project or feature set without a formal PRD, when technical decisions are being made that should be documented in requirements, when the user mentions uncertainty about project structure, testing, or architecture, or when an existing PRD appears incomplete or lacks critical sections.";
    };
    "prompt-engineer" = {
      "description" =
        "Optimizes prompts for LLMs and AI systems. Use when building AI features, improving agent performance, crafting system prompts. Expert in prompt patterns and techniques.";
    };
    "python-pro" = {
      "description" =
        "Write idiomatic Python with advanced features like decorators, generators, async/await. Optimizes performance, implements design patterns, ensures comprehensive testing. Use PROACTIVELY for Python refactoring, optimization, complex Python features.";
    };
    "python-reviewer" = {
      "description" =
        "Expert Python code reviewer specializing in type safety, security, common pitfalls, and idiomatic patterns. Use when reviewing Python (.py/.pyi) changes.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "rocq-pro" = {
      "description" =
        "Write correct Rocq code establishing proofs for theorems encoded as type specifications.";
    };
    "rust-pro" = {
      "description" =
        "Write idiomatic Rust with ownership patterns, lifetimes, trait implementations. Masters async/await, safe concurrency, zero-cost abstractions. Use PROACTIVELY for Rust memory safety, performance optimization, systems programming.";
    };
    "rust-reviewer" = {
      "description" =
        "Expert Rust code reviewer specializing in ownership, unsafe code, error handling, and idiomatic patterns. Use when reviewing Rust (.rs) changes.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "security-reviewer" = {
      "description" =
        "Cross-language security reviewer specializing in vulnerability detection, authentication, data exposure, and supply chain security. Use for a cross-cutting security pass over any changeset, especially code handling user input, auth, secrets, or network boundaries.";
      "tools" = "Read, Grep, Glob, Bash";
    };
    "sql-pro" = {
      "description" =
        "Write complex SQL queries, optimize execution plans, design normalized schemas. Masters CTEs, window functions, stored procedures. Use PROACTIVELY for query optimization, complex joins, database design.";
    };
    "task-breakdown" = {
      "description" =
        "Expert in decomposing Org-mode tasks into complete, ordered, actionable subtasks with valid properties drawers. Use PROACTIVELY when asked to break down, decompose, or plan an Org-mode TODO item.";
    };
    "typescript-pro" = {
      "description" =
        "Expert in TypeScript specializing in type safety, monorepo architecture, advanced types, modern patterns. Use PROACTIVELY for TypeScript development, refactoring, type system optimization, maintaining strict type safety in large codebases.";
    };
    "typescript-reviewer" = {
      "description" =
        "Expert TypeScript code reviewer specializing in type safety, async correctness, security, and idiomatic patterns. Use when reviewing TypeScript or TSX changes.";
      "tools" = "Read, Grep, Glob, Bash";
    };
  };
  commandMetadata = {
    "alexey" = {
      "description" =
        "Spawn a read-only subagent to review a pull request with the review discipline of Alexey -- correctness verified by construction, benchmarks read first, prose audited for truth, tests interrogated for meaning, scope policed -- reporting findings only, never modifying the PR or posting comments.";
    };
    "assess" = {
      "description" =
        "Deeply analyze co-worker comments on the current PR and present findings plus an approach for responding";
    };
    "bankruptcy" = { };
    "breakdown" = {
      "description" =
        "Decompose a single Org-mode task into a comprehensive, ordered set of actionable subtasks in Org-mode format";
    };
    "bugbot" = {
      "description" =
        "Fix and resolve all automated bot comments (BugBot, Graphite, Cursor, Devin) on the current PR via a strict 5-phase protocol";
    };
    "bugbot-stack" = {
      "description" =
        "Address all bot comments on every PR in the current Graphite stack, fixing issues and resolving the comment threads";
    };
    "capture" = {
      "description" = "Capture a web page or file into the Org-mode wiki.";
    };
    "cleanup" = {
      "description" =
        "Run lefthook pre-commit on every branch in the current Graphite stack, drop empty commits, amend formatting fixes, and restack";
      "disable-model-invocation" = true;
    };
    "code-review" = {
      "description" =
        "Comprehensive repository health review using the agents named in arguments -- correctness, security, performance, structure, tests, and docs";
    };
    "commit" = {
      "description" =
        "Commit all work as a series of atomic, logically sequenced commits, each one coherent, reviewable, and revertible on its own";
    };
    "deep-review" = {
      "allowed-tools" =
        "Read, Grep, Glob, Bash(git:*), Bash(find:*), Bash(wc:*), Bash(gh pr diff:*), Skill, Task";
      "argument-hint" = [
        "files"
        "directories"
        "commit range"
        "or branch name"
      ];
      "description" = "Deep multi-language code review with specialist sub-agents";
    };
    "heavy-review" = {
      "allowed-tools" =
        "Read, Grep, Glob, Bash(git:*), Bash(find:*), Bash(wc:*), Bash(gh pr diff:*), Task, Skill, Workflow";
      "argument-hint" = "repository | working-tree | pr [N] | path | revision range";
      "description" =
        "Coordinate deep, Alexey-discipline, abstraction-alignment, validated multi-model, Ponytail, dead-code, and comment audits concurrently, one subagent per pass, into one deduplicated report";
    };
    "discover-bundles" = {
      "description" =
        "Find, verify, and rank external prompt and skill bundles that fit this repository, without installing them";
    };
    "eliminate-dead-code" = {
      "argument-hint" = [
        {
          "optional scope" = "path";
        }
        "docs"
        "imports"
        "feature-flags"
        "or empty for full repo"
      ];
      "description" =
        "Find and remove dead code and stale documentation with evidence-based safety, using a mark / debate / act / verify workflow";
    };
    "expense-report" = {
      "argument-hint" = "[receipt files/directory] [\"Trip Name\"]";
      "description" = "Parse receipts and generate a filled expense report spreadsheet";
    };
    "fess" = {
      "description" = "Fess up";
    };
    "fix" = {
      "description" =
        "Think, research, plan, act, review -- deeply analyze a GitHub issue, fix it step by step with regression tests, open a PR, and monitor CI";
    };
    "fix-alert" = {
      "description" = "Diagnose and resolve Alertmanager alerts using NixOS tools";
    };
    "fix-ci" = {
      "description" =
        "Diagnose and fix failing CI on this PR, push the fixes, and monitor with gh until all checks pass, addressing any bot comments along the way";
    };
    "fix-github-issue" = {
      "description" =
        "Analyze and fix a GitHub issue in a dedicated git worktree and branch, leaving the work uncommitted for review";
    };
    "fix-integration" = {
      "description" = "Diagnose and fix a Home Assistant integration whose config flow fails to load";
    };
    "fix-transcript" = {
      "description" =
        "Clean up a transcript file in place -- paragraphs, punctuation, capitalization -- without changing wording or meaning";
    };
    "flaky-rust" = {
      "description" =
        "Use rust-pro to diagnose and fix the flaky Rust tests reported in arguments so they become robust signals of correctness";
    };
    "forge" = {
      "description" =
        "Run the forge skill's multi-phase, multi-model collaborative workflow on the stated problem";
    };
    "gravity" = {
      "description" =
        "Act as gravity for an idea -- attack the weakest points, challenge assumptions, and expose what is missing, without sugarcoating";
    };
    "halt" = {
      "description" =
        "Bring work to a clean stopping point -- update the handoff document, commit and push, and produce a comprehensive remaining-scope plan/PRD with verifiable completion criteria";
    };
    "heavy" = {
      "description" =
        "Plan and execute a task with the full toolkit -- the standard pro-agent toolkit plus multi-model consensus via pal and Positron's Notion context";
    };
    "infer-tasks" = {
      "description" =
        "Extract a flat list of independently committed Org-mode task headlines from unstructured text, without decomposing into subtasks";
    };
    "initialize" = {
      "description" =
        "Analyze the codebase and create a CLAUDE.md covering common commands and big-picture architecture";
    };
    "install-service" = {
      "argument-hint" = "[service-name]";
      "description" = "Install and configure a service with nginx, monitoring, and secrets";
      "disable-model-invocation" = true;
    };
    "journal" = {
      "description" = "Maintain an append-only learning journal for active work";
    };
    "lefthook" = {
      "description" =
        "Add a lefthook.yml that runs formatting, warning-free builds, tests, linting, and coverage checks on pre-commit";
    };
    "markdown" = {
      "description" =
        "Write the findings to a GitHub-flavored Markdown document using GitHub suggestion blocks, ready to paste into review comments";
    };
    "medium" = {
      "description" =
        "Plan and execute a task using the standard pro-agent toolkit, ensuring lint and type checks pass";
    };
    "meeting-notes" = {
      "description" =
        "Transform raw meeting notes into a structured, fact-only Markdown report -- metadata, themes, decisions, action items, open questions, and timeline. Use on a notes file passed as the argument, or to collect notes interactively when none is given.";
    };
    "narrative" = {
      "description" =
        "Write a human-oriented development narrative from a journal, git history, working tree, and planning documents";
    };
    "nix-rebuild" = {
      "description" = "Use nix-pro to diagnose and fix a failing ./build system Nix rebuild";
      "disable-model-invocation" = true;
    };
    "partner-cleanup" = {
      "argument-hint" = [
        "optional observations directory"
      ];
      "description" =
        "Consume partner review observations, fix them through a sub-agent, and commit the cleanup";
    };
    "partner-collaborator" = {
      "argument-hint" = [
        "optional baseline ref"
        "commit range"
        "or poll interval seconds"
      ];
      "description" =
        "Watch new commits and publish one atomic observation file per actionable review finding or worthwhile new idea";
    };
    "partner-reviewer" = {
      "argument-hint" = [
        "optional baseline ref"
        "commit range"
        "or poll interval seconds"
      ];
      "description" =
        "Watch new commits and publish one atomic observation file per actionable review finding";
    };
    "prepare-with" = {
      "description" =
        "Use the named agents to deeply analyze the project and give expert guidance for constructing its CLAUDE.md";
    };
    "process-checklist" = {
      "description" =
        "Work through a Markdown checklist file, completing and checking off every unfinished task";
    };
    "productize" = {
      "description" =
        "Productize a repository -- README, LICENSE, flake.nix dev shell, formatting, linting, coverage, CI, and lefthook pre-commit checks";
    };
    "proofread" = {
      "description" =
        "Fix spelling, grammar, and punctuation errors in all Markdown, Org-mode, and text files while preserving style, tone, and meaning";
    };
    "push" = {
      "description" = "Commit all work via the commit command, then create a PR and push it to GitHub";
      "disable-model-invocation" = true;
    };
    "query-builder" = {
      "description" =
        "Build an SQL query with sql-pro and the mssql MCP from schema alone, never revealing any table data";
    };
    "quick-review" = {
      "allowed-tools" = "Read, Grep, Glob, Bash(git:*), Bash(find:*), Bash(wc:*)";
      "argument-hint" = [
        "files"
        "commit range"
        "or branch"
      ];
      "description" = "Quick single-pass code review (no sub-agents, faster but less thorough)";
    };
    "rebase" = {
      "description" =
        "Plan and execute a rebase onto a branch, resolving conflicts with haskell-pro and updating descendant branches and their PRs";
      "disable-model-invocation" = true;
    };
    "rebase-and-fix" = {
      "description" =
        "Rebase the working tree onto a branch, resolving conflicts with haskell-pro and cpp-pro, then rewrite and force-push descendant branches";
    };
    "recommit" = {
      "description" =
        "Rebuild this branch as logical, successive commits from main, each passing CI on its own, ready for stacked PRs";
      "disable-model-invocation" = true;
    };
    "remove-service" = {
      "argument-hint" = "[service-name]";
      "description" =
        "Remove a service from system, including nginx virtual hosts, monitoring, alerting, systemd services and timers, containers, Nagios, Alertmanager, Prometheus exporters, etc.";
      "disable-model-invocation" = true;
    };
    "report" = {
      "description" =
        "Pause and create a comprehensive completion report detailing the remaining roadmap phase by phase -- open questions, design, implementation, testing, documentation, cleanup, and review -- for a reader familiar with the project.";
    };
    "resolve" = {
      "description" =
        "Resolve the merge conflicts in the working tree, preserving both sides' intent; git add the results but do not commit";
    };
    "respond" = {
      "description" =
        "Draft a Markdown report answering every open reviewer comment on a PR, instead of replying on GitHub";
    };
    "restack" = {
      "description" =
        "Restack the entire Graphite stack onto main, resolving and verifying every conflict, then submit and report";
      "disable-model-invocation" = true;
    };
    "retest" = {
      "argument-hint" =
        "[model|slug|tag…] [--all] [--no-perf] [--no-review] [--no-comments] [--no-semantic]";
      "description" =
        "Full model-support battery on any branch — rebuild, unit tests, FPGA correctness vs the HuggingFace transformers source of truth, code review, comment-check, and a perf pass. Derives the target model set from the branch diff.";
    };
    "retest-categorical" = {
      "argument-hint" = "[model-tag…] [--no-perf] [--no-semantic]";
      "description" =
        "Full categorical-vs-legacy retest — rebuild, unit tests, FPGA byte-identity for every model, and a perf-divergence pass";
    };
    "review-github-pr" = {
      "description" =
        "Analyze and review a GitHub PR, reporting findings locally only -- never posting to GitHub";
    };
    "run-orchestrator" = {
      "description" =
        "Act as the project orchestrator -- analyze the work to be done and coordinate execution by spawning sub-agents with the Task tool";
    };
    "sec-audit" = {
      "allowed-tools" = "Read, Grep, Glob, Bash(git:*), Bash(find:*), Bash(grep:*), Bash(wc:*), Task";
      "argument-hint" = [
        "files"
        "directories"
        "commit range"
        "or branch"
      ];
      "description" = "Security-focused code review";
    };
    "sitrep" = {
      "description" =
        "Produce a concise situational report on the current project status, progress, blockers, estimates, and parallel work opportunities";
    };
    "smooth" = {
      "description" =
        "Lightly polish the given text -- simplify, trim duplication, fix grammar -- while preserving its voice, power, and content";
    };
    "teams" = {
      "description" =
        "Create an agent team to explore a problem from research, prior-art, UX, architecture, planning, and testing angles";
    };
    "transcribe-image" = {
      "description" =
        "Transcribe handwriting from images into paragraph-form Markdown, then re-review with pal for correctness and accuracy";
    };
    "tron-debug" = {
      "description" =
        "Debug the C++ produced by the Torch Fx ingest pipeline, tracing through the Bulk, Loopy, Tron, and CPP IRs";
    };
    "webfix" = {
      "description" =
        "Use Playwright with typescript-pro and python-pro to diagnose and fix issues in the current web application";
    };
    "wiggum" = {
      "description" =
        "Turn on autonomous-continuation mode -- run, checkpoint, and verify until done, following the wiggum loop methodology";
      "disable-model-invocation" = true;
    };
  };
  personalFilenameTagCommands = [
    "capture"
    "fix-alert"
    "install-service"
    "remove-service"
    "webfix"
  ];
  onlyPersonalCommands = [
    "expense-report"
    "fix-integration"
  ];
  personalCommands = personalFilenameTagCommands ++ onlyPersonalCommands;
  positronCommands = [
    "cleanup"
    "forge"
    "heavy"
    "retest"
    "retest-categorical"
    "tron-debug"
  ];
  droidCommands = [
    "discover-bundles"
    "fess"
    "restack"
  ];

  commandSelectors =
    name:
    {
      clients = commandClients ++ lib.optional (builtins.elem name droidCommands) "droid";
    }
    // lib.optionalAttrs (builtins.elem name personalCommands) {
      audiences = [ "personal" ];
    }
    // lib.optionalAttrs (builtins.elem name positronCommands) {
      audiences = [ "positron" ];
    };

  mkDocumentItems =
    sourceRoot: suffix: metadataSet: selectorsFor:
    lib.mapAttrs (name: metadata: {
      inherit metadata;
      source = sourceRoot + "/${name}${suffix}";
      selectors = selectorsFor name;
    }) metadataSet;

  agents = mkDocumentItems ./agents ".md" agentMetadata (_name: {
    clients = contentClients;
  });
  ordinaryCommands = mkDocumentItems ./commands ".md" commandMetadata commandSelectors;
  commands = ordinaryCommands // {
    # The specialist and direct command are two projections of one audit
    # authority. Keeping the rubric with the specialist also makes delegated
    # use independent of renderer-specific command paths.
    fess = ordinaryCommands.fess // {
      source = agents.fess-auditor.source;
    };
  };

  localBroadSkills = [
    "abstraction-review"
    "alexey-review"
    "caveman"
    "comment-audit"
    "eliminate-dead-code"
    "fix-all"
    "fix-transcript"
    "it-voice"
    "johnw"
    "nixos"
    "node-red"
    "parallelize"
    "persian"
    "swiftui"
    "toolkit"
    "validated-code-review"
    "wiggum"
  ];
  resourceBroadSkills = [
    "git-surgeon"
    "ponytail"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
    "ponytail-review"
    "skill-creator"
    "translate-en"
  ];
  positronPyTorchSkills = [
    "add-uint-support"
    "at-dispatch-v2"
    "docstring"
  ];
  resourceSkills = resources + "/share/agent-resources/skills";

  mkSkill = sourceRoot: name: selectors: {
    inherit selectors;
    source = sourceRoot + "/${name}";
  };

  broadLocalSkillItems = lib.genAttrs localBroadSkills (
    name: mkSkill ./skills name { clients = contentClients; }
  );
  broadResourceSkillItems = lib.genAttrs resourceBroadSkills (
    name: mkSkill resourceSkills name { clients = contentClients; }
  );
  positronPyTorchSkillItems = lib.genAttrs positronPyTorchSkills (
    name: mkSkill ./skills name { audiences = [ "positron" ]; }
  );
  skills =
    broadLocalSkillItems
    // broadResourceSkillItems
    // positronPyTorchSkillItems
    // {
      forge = mkSkill ./skills "forge" { clients = [ "claude" ]; };
      retest = mkSkill ./skills "retest" { audiences = [ "positron" ]; };
    };

  builtInPrompts = lib.genAttrs [ "emacs" "spanish" ] (name: {
    source = ./prompts + "/${name}.md";
    selectors.clients = contentClients;
  });
  prompts = builtInPrompts;

  typedEnv = env: { inherit env; };
  publicArg = public: { inherit public; };
  protectedFileArg = protectedFile: { inherit protectedFile; };
  publicArgs = map publicArg;
  mcpHttpHeaders = { };
  baseMcpSelectors = {
    clients = contentClients;
  };
  mkMcp = transport: selectors: {
    inherit transport selectors;
  };

  mcpServers = {
    devonthink =
      mkMcp
        {
          command = "/Applications/DEVONthink.app/Contents/Library/LoginItems/DEVONthink MCP.app/Contents/MacOS/DEVONthink MCP";
          args = publicArgs [ "--stdio" ];
        }
        {
          profiles = [
            "clio-claude-personal"
            "clio-pi"
            "hera-claude-personal"
            "hera-droid"
            "hera-pi"
            "hera-prime"
          ];
        };

    drafts =
      mkMcp
        {
          command = "/etc/profiles/per-user/johnw/bin/drafts-mcp-server";
          args = [ ];
        }
        {
          profiles = [
            "clio-claude-personal"
            "clio-pi"
            "hera-claude-personal"
            "hera-droid"
            "hera-pi"
            "hera-prime"
          ];
        };

    # The operator path uses SSH stdio because it exposes drafts_run_action;
    # the autonomous Hermes/OpenClaw SSE route intentionally does not.
    drafts-hera =
      mkMcp
        {
          command = "ssh";
          args =
            publicArgs [
              "-T"
              "-i"
            ]
            ++ [ (protectedFileArg "/run/secrets/drafts/hera-ssh-private-key") ]
            ++ publicArgs [
              "-o"
              "IdentitiesOnly=yes"
              "-o"
              "BatchMode=yes"
              "-o"
              "StrictHostKeyChecking=yes"
              "-o"
              "ConnectTimeout=10"
              "-o"
              "ServerAliveInterval=30"
              "-o"
              "ServerAliveCountMax=3"
              "johnw@hera.lan"
              "/etc/profiles/per-user/johnw/bin/drafts-mcp-server"
            ];
        }
        {
          profiles = [
            "vulcan-claude-personal"
          ];
        };

    pal =
      mkMcp
        {
          command = "pal-mcp-server";
          args = [ ];
          env = {
            ANTHROPIC_API_KEY = typedEnv "ANTHROPIC_API_KEY";
            GEMINI_API_KEY = typedEnv "GEMINI_API_KEY";
            OPENAI_API_KEY = typedEnv "OPENAI_API_KEY";
            DISABLED_TOOLS = "testgen,secaudit,docgen,tracer";
            DEFAULT_MODEL = "auto";
          };
        }
        {
          clients = [
            "claude"
            "codex"
            "droid"
            "pi"
            "prime"
          ];
        };

    searxng =
      (mkMcp
        {
          command = "mcp-searxng";
          args = [ ];
          env.SEARXNG_URL = "https://searxng.vulcan.lan";
        }
        {
          hosts = [
            "clio"
            "hera"
            "vulcan"
          ];
        }
      )
      // {
        transportByHost.vulcan = {
          command = "mcp-searxng";
          args = [ ];
          env.SEARXNG_URL = "http://localhost:8890";
        };
      };

    sequential-thinking =
      (mkMcp {
        command = "mcp-server-sequential-thinking";
        args = [ ];
      } baseMcpSelectors)
      // {
        overrides.codex.command = "mcp-server-sequential-thinking";
      };

    stock-trader =
      mkMcp
        {
          command = "/etc/profiles/per-user/johnw/bin/stock-trader-mcp";
          args = [ ];
        }
        {
          profiles = [
            "clio-claude-personal"
            "clio-pi"
            "hera-claude-personal"
            "hera-droid"
            "hera-pi"
            "hera-prime"
          ];
        };
  };

  hooks = {
    agent-deck-claude = {
      selectors.clients = [ "claude" ];
      hooks = {
        SessionStart = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
                async = true;
              }
            ];
          }
        ];
        UserPromptSubmit = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
                async = true;
              }
            ];
          }
        ];
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
        PermissionRequest = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
        Notification = [
          {
            matcher = "permission_prompt|elicitation_dialog";
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
                async = true;
              }
            ];
          }
        ];
        SessionEnd = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
                async = true;
              }
            ];
          }
        ];
        PreCompact = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
      };
    };

    agent-deck-codex = {
      selectors.clients = [ "codex" ];
      codex.notify = [
        "agent-deck"
        "codex-notify"
      ];
      hooks = {
        SessionStart = [
          {
            matcher = "startup|resume|clear|compact";
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
        UserPromptSubmit = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
        PermissionRequest = [
          {
            matcher = "*";
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
        PreCompact = [
          {
            matcher = "manual|auto";
            hooks = [
              {
                type = "command";
                command = "agent-deck hook-handler";
              }
            ];
          }
        ];
      };
    };

    claude-code = {
      selectors.clients = [ "claude" ];
      # The Stop bell makes iTerm mark the Claude tab as active.
      hooks.Stop = [
        {
          matcher = ".*";
          hooks = [
            {
              type = "command";
              command = "printf '\\a' > /dev/tty 2>/dev/null || true";
            }
          ];
        }
      ];
    };

    claude-vault = {
      selectors.clients = [ "claude" ];
      hooks = {
        PreCompact = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-vault import >/dev/null 2>&1";
              }
            ];
          }
        ];
        SessionEnd = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-vault import >/dev/null 2>&1 &";
              }
            ];
          }
        ];
      };
    };
  };

  marketplaces = {
    claude-code-plugins = {
      selectors.clients = [ "claude" ];
      source = {
        source = "github";
        repo = "anthropics/claude-code";
      };
      plugins.frontend-design = true;
    };

    # Claude Code bundles this marketplace, so it needs no extra source registration.
    claude-plugins-official = {
      selectors.clients = [ "claude" ];
      plugins = {
        clangd-lsp = true;
        pyright-lsp = true;
        rust-analyzer-lsp = true;
      };
    };
  };

  settings = {
    claude = {
      selectors.clients = [ "claude" ];

      base = {
        env = {
          ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-sonnet-5";
          CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "80";
          CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
          CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
          CLAUDE_CODE_MAX_OUTPUT_TOKENS = "64000";
          CLAUDE_CODE_NO_FLICKER = "1";
          CLAUDE_CODE_SUBAGENT_MODEL = "claude-opus-5";
          DISABLE_AUTOUPDATER = "1";
          ENABLE_LSP_TOOL = "1";
          ENABLE_TOOL_SEARCH = "1";
          FORCE_AUTOUPDATE_PLUGINS = "1";
          MCP_TIMEOUT = "1800000";
          MCP_TOOL_TIMEOUT = "1800000";
        };
        statusLine.type = "command";
        sandbox = {
          enabled = false;
          autoAllowBashIfSandboxed = true;
          filesystem = {
            allowWrite = [
              "/private/tmp"
              "/var/folders"
            ];
            allowRead = [
              "/private/tmp"
              "/var/folders"
              "/Users/johnw/Products"
            ];
          };
          excludedCommands = [ "gh" ];
        };
        effortLevel = "max";
        showThinkingSummaries = true;
        skipDangerousModePermissionPrompt = true;
        verbose = true;
        remoteControlAtStartup = true;
        agentPushNotifEnabled = true;
        model = "claude-opus-5[1m]";
        theme = "dark";
      };

      statusLineCommand = {
        executable = "bash";
        rootRelativePath = "statusline-command.sh";
      };
    };

    claude-personal-workstation-notifications = {
      selectors = {
        clients = [ "claude" ];
        audiences = [ "personal" ];
        hosts = [
          "clio"
          "hera"
        ];
      };
      base.preferredNotifChannel = "iterm2_with_bell";
    };
  };

  catalogItems = {
    inherit
      agents
      commands
      skills
      prompts
      mcpServers
      hooks
      marketplaces
      settings
      ;
  };

  allowedSelectorKeys = [
    "clients"
    "audiences"
    "hosts"
    "platforms"
    "profiles"
    "excludeProfiles"
  ];
  allowedProfileIds = builtins.attrNames catalogProfiles;

  ensure =
    condition: message: if condition then true else throw "agent catalog validation: ${message}";

  declaredEnvNames = [
    "ANTHROPIC_API_KEY"
    "GEMINI_API_KEY"
    "OPENAI_API_KEY"
  ];

  validEnvName = value: builtins.isString value && builtins.match "^[A-Z][A-Z0-9_]*$" value != null;

  # Structural recognition is shared with the renderers (env-reference.nix);
  # the catalog additionally requires the name to be on the declared roster.
  isEnvReference =
    value: (import ./env-reference.nix).isTypedEnv value && builtins.elem value.env declaredEnvNames;

  containsRenderedReference =
    value:
    lib.any (fragment: lib.hasInfix fragment value) [
      "$"
      "{"
      "}"
    ];

  validUrl =
    allowHttp: value:
    builtins.isString value
    && (lib.hasPrefix "https://" value || (allowHttp && lib.hasPrefix "http://" value))
    && !(lib.any (fragment: lib.hasInfix fragment value) [
      "?"
      "#"
      "@"
      " "
      "\t"
      "\n"
      "\r"
    ])
    && !(containsRenderedReference value);

  approvedLiteralEnvironment = {
    DISABLED_TOOLS = [ "testgen,secaudit,docgen,tracer" ];
    DEFAULT_MODEL = [ "auto" ];
    SEARXNG_URL = [
      "http://localhost:8890"
      "https://searxng.vulcan.lan"
    ];
  };

  validEnvironmentValue =
    name: value:
    validEnvName name
    && (
      (isEnvReference value && value.env == name)
      || (
        builtins.hasAttr name approvedLiteralEnvironment
        && builtins.elem value approvedLiteralEnvironment.${name}
      )
    );

  validHeaderName = name: builtins.match "^[A-Za-z0-9_-]+$" name != null;
  validItemName =
    name: builtins.isString name && builtins.match "^[A-Za-z0-9][A-Za-z0-9._-]*$" name != null;
  # Providers own model syntax; reject only control bytes and an unterminated
  # CSI-like suffix.
  c1Controls = builtins.fromJSON ''
    [
      "\u0080",
      "\u0081",
      "\u0082",
      "\u0083",
      "\u0084",
      "\u0085",
      "\u0086",
      "\u0087",
      "\u0088",
      "\u0089",
      "\u008a",
      "\u008b",
      "\u008c",
      "\u008d",
      "\u008e",
      "\u008f",
      "\u0090",
      "\u0091",
      "\u0092",
      "\u0093",
      "\u0094",
      "\u0095",
      "\u0096",
      "\u0097",
      "\u0098",
      "\u0099",
      "\u009a",
      "\u009b",
      "\u009c",
      "\u009d",
      "\u009e",
      "\u009f"
    ]
  '';
  validModelIdentifier =
    value:
    builtins.isString value
    && value != ""
    && builtins.match "^[^[:cntrl:]]+$" value != null
    && !(lib.any (control: lib.hasInfix control value) c1Controls)
    && builtins.match ".*\\[[0-9:;<=>?]*[ -/]*[@-~]$" value == null;

  validPublicArgument =
    value:
    builtins.isString value
    && builtins.match "^[^[:cntrl:]]*$" value != null
    && !(containsRenderedReference value);
  validProtectedFile =
    value:
    let
      relative = if builtins.isString value then lib.removePrefix "/run/secrets/" value else "";
      parts = lib.splitString "/" relative;
    in
    builtins.isString value
    && lib.hasPrefix "/run/secrets/" value
    && relative != ""
    && builtins.all (
      part: part != "" && part != "." && part != ".." && builtins.match "^[A-Za-z0-9._-]+$" part != null
    ) parts;
  validArgument =
    value:
    builtins.isAttrs value
    && (
      (builtins.attrNames value == [ "public" ] && validPublicArgument value.public)
      || (builtins.attrNames value == [ "protectedFile" ] && validProtectedFile value.protectedFile)
    );
  validArguments = values: builtins.isList values && builtins.all validArgument values;
  renderArgument = value: value.public or value.protectedFile;
  renderTransportArguments =
    transport:
    transport
    // lib.optionalAttrs (transport ? args) {
      args = map renderArgument transport.args;
    };

  validateSelectors =
    selectors:
    let
      keys = builtins.attrNames selectors;
      validDimension =
        name: allowed:
        let
          wanted = selectors.${name} or [ ];
        in
        builtins.isList wanted && builtins.all (value: builtins.elem value allowed) wanted;
    in
    builtins.isAttrs selectors
    && builtins.all (key: builtins.elem key allowedSelectorKeys) keys
    && validDimension "clients" clients
    && validDimension "audiences" audiences
    && validDimension "hosts" hosts
    && validDimension "platforms" platforms
    && validDimension "profiles" allowedProfileIds
    && validDimension "excludeProfiles" allowedProfileIds;

  allowedOverrideFields = {
    claude = [ "timeout" ];
    codex = [
      "command"
      "startup_timeout_sec"
      "tool_timeout_sec"
    ];
    droid = [ ];
    pi = [ ];
  };

  validateOverrides =
    overrides:
    let
      validOverrideValue =
        field: value:
        if field == "command" then validPublicArgument value else builtins.isInt value && value > 0;
    in
    builtins.isAttrs overrides
    && builtins.all (
      client:
      builtins.hasAttr client allowedOverrideFields
      && builtins.isAttrs overrides.${client}
      && builtins.all (
        field:
        builtins.elem field allowedOverrideFields.${client}
        && validOverrideValue field overrides.${client}.${field}
      ) (builtins.attrNames overrides.${client})
    ) (builtins.attrNames overrides);

  validateTransport =
    transport:
    let
      isCommand = builtins.hasAttr "command" transport;
      isHttp = builtins.hasAttr "url" transport;
      allowedKeys =
        if isCommand then
          [
            "command"
            "args"
            "env"
          ]
        else
          [
            "url"
            "headers"
          ];
      environment = transport.env or { };
      headers = transport.headers or { };
    in
    builtins.isAttrs transport
    && isCommand != isHttp
    && builtins.all (key: builtins.elem key allowedKeys) (builtins.attrNames transport)
    && (
      if isCommand then
        validPublicArgument transport.command
        && validArguments (transport.args or [ ])
        && builtins.isAttrs environment
        && builtins.all (name: validEnvironmentValue name environment.${name}) (
          builtins.attrNames environment
        )
      else
        validUrl false transport.url
        && builtins.isAttrs headers
        && builtins.all (name: validHeaderName name && isEnvReference headers.${name}) (
          builtins.attrNames headers
        )
    );

  validateMcpHeaders = name: transport: (transport.headers or { }) == (mcpHttpHeaders.${name} or { });

  validate =
    {
      profiles ? catalogProfiles,
      items ? catalogItems,
    }:
    let
      itemSets = builtins.attrValues items;
      allItems = lib.concatMap builtins.attrValues itemSets;
      itemChecks = lib.concatLists (
        lib.mapAttrsToList (
          category: itemSet:
          lib.mapAttrsToList (
            key: _item: ensure (validItemName key) "unsafe item name in ${category}/${key}"
          ) itemSet
        ) items
      );
      selectorChecks = map (
        item: ensure (validateSelectors (item.selectors or { })) "invalid item selector"
      ) allItems;
      settingsChecks = lib.concatLists (
        lib.mapAttrsToList (
          name: item:
          let
            base = item.base or { };
            environmentModels = lib.filterAttrs (environmentName: _: lib.hasSuffix "_MODEL" environmentName) (
              base.env or { }
            );
          in
          lib.optional (base ? model) (
            ensure (validModelIdentifier base.model) "invalid model identifier in settings/${name}/base/model"
          )
          ++ lib.mapAttrsToList (
            environmentName: value:
            ensure (validModelIdentifier value) "invalid model identifier in settings/${name}/base/env/${environmentName}"
          ) environmentModels
        ) items.settings
      );
      profileChecks = lib.mapAttrsToList (
        id: profile:
        ensure (
          profile.id == id
          && builtins.elem profile.client clients
          && builtins.isList profile.audiences
          && builtins.all (audience: builtins.elem audience audiences) profile.audiences
          && builtins.elem profile.host hosts
          && builtins.elem profile.platform platforms
          && profile.root == profileSpecs.${id}.root
          && (
            profile.localModelEndpoints == null
            || (
              builtins.isAttrs profile.localModelEndpoints
              # Exactly the provider names the codex renderer indexes, each a
              # URL held to the same standard as MCP transports.
              &&
                builtins.attrNames profile.localModelEndpoints == [
                  "llama-swap"
                  "omlx"
                ]
              && builtins.all (validUrl true) (builtins.attrValues profile.localModelEndpoints)
            )
          )
        ) "invalid profile ${id}"
      ) profiles;
      fessProjectionChecks = lib.mapAttrsToList (
        id: profile:
        let
          selectedAgents = select profile items.agents;
          selectedCommands = select profile items.commands;
        in
        ensure (
          selectedAgents ? fess-auditor
          && selectedCommands ? fess
          && selectedAgents.fess-auditor.source == selectedCommands.fess.source
        ) "fess auditor has no same-source direct command in profile ${id}"
      ) profiles;
      mcpChecks = lib.mapAttrsToList (
        name: server:
        let
          hostTransports = server.transportByHost or { };
          matchingProfiles = lib.filter (profile: matches profile (server.selectors or { })) (
            builtins.attrValues profiles
          );
        in
        ensure (
          validateTransport server.transport
          && validateMcpHeaders name server.transport
          && builtins.all (host: lib.any (profile: profile.host == host) matchingProfiles) (
            builtins.attrNames hostTransports
          )
          && builtins.all (
            host: validateTransport hostTransports.${host} && validateMcpHeaders name hostTransports.${host}
          ) (builtins.attrNames hostTransports)
          && validateOverrides (server.overrides or { })
        ) "invalid MCP server ${name}"
      ) items.mcpServers;
      mcpResolutionChecks = lib.concatMap (
        profile:
        lib.mapAttrsToList (
          name: server:
          let
            selected = select profile (
              builtins.listToAttrs [
                {
                  inherit name;
                  value = server;
                }
              ]
            );
            shouldSelect = matches profile (server.selectors or { });
            expectedTransport = renderTransportArguments (
              (server.transportByHost or { }).${profile.host} or server.transport
            );
          in
          ensure (
            if shouldSelect then
              builtins.hasAttr name selected
              && selected.${name}.transport == expectedTransport
              && !(selected.${name} ? transportByHost)
            else
              !(builtins.hasAttr name selected)
          ) "invalid resolved MCP server ${profile.id}/${name}"
        ) items.mcpServers
      ) (builtins.attrValues profiles);
      checks =
        itemChecks
        ++ selectorChecks
        ++ settingsChecks
        ++ profileChecks
        ++ fessProjectionChecks
        ++ mcpChecks
        ++ mcpResolutionChecks;
    in
    builtins.deepSeq checks true;
  # Clients that read the shared `.agents/skills` root. That root is one
  # directory on disk, so the effective skill set for these clients is the
  # union of their profiles' selections — a per-home rule this catalog owns.
  # Consequence, by physical necessity: an audience-scoped skill selected by
  # ANY of a home's shared-root profiles is visible to ALL of that home's
  # shared-root clients.
  sharedSkillClients = [
    "codex"
    "pi"
    "prime"
  ];

  sharedSkillsFor =
    profiles:
    lib.foldl' (
      acc: profile:
      if builtins.elem profile.client sharedSkillClients then
        acc // select profile catalogItems.skills
      else
        acc
    ) { } profiles;
in
{
  profiles = catalogProfiles;
  items = catalogItems;
  inherit
    matches
    select
    sharedSkillClients
    sharedSkillsFor
    validate
    ;
}
