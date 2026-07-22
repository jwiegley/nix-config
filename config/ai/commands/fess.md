Assume you've been dishonest about the work. Your job now is to find what you hid, glossed over, or quietly downgraded. Be specific. Cite file:line. No hedging, no "may have," no "possibly."

The signals listed under each section are *illustrative examples* drawn from common languages and tools. They are not a checklist of literal strings to grep for — your codebase may use entirely different syntax, tooling, or idioms. Translate the underlying pattern to whatever this codebase actually uses. The principle in each section is what matters; the examples just show what the principle looks like in the wild.

If you're uncertain whether something counts as a hit, say so explicitly and describe what you'd need to check to find out. Don't resolve uncertainty by claiming "none" and don't resolve it by manufacturing a sin. Convert it into a verification action.

Audit yourself against these, and report each hit explicitly — say "none" only if you actually checked:

**Stubs and fakes**
Functions that exist but don't do the work. Examples of the pattern: TODO/FIXME/XXX markers, no-op function bodies, "not implemented" exceptions, empty catch blocks, hardcoded happy-path return values, mocks left in place where real code should run.

**Vacuous tests**
A test that passes without actually exercising the behavior it claims to test. The harm: the green checkmark is a lie, and now there's a test "covering" the area so nobody writes a real one. Examples of the pattern:
- Tautological asserts (comparing a value to itself, asserting True, asserting non-null when null was never possible).
- Asserting a mock was called without asserting on arguments or downstream effects.
- Tests with no assertions — they pass if the code doesn't throw. (Smoke tests are fine if labeled; the problem is when they masquerade as behavioral tests.)
- Setup and assertion are the same value round-tripped (`obj.x = 5; assert obj.x == 5`).
- Tests that catch the exception they should be asserting on.
- Parametrized tests where every case collapses to the same trivial check.
- Asserting on shape/type when the contract is about contents.
- The killer test: would this test still pass if the function under test were replaced with a stub that returns a mock of the right shape? If yes, it's vacuous.

For every test you wrote or modified: state what behavior it actually verifies, in one sentence. If you can't, it's vacuous.

**Mock and fixture drift**
The test passes because the mocks return what the test expects, not what the real dependency returns. The test isn't tautological — it's testing against a fiction. This is its own failure mode because the test can look thorough and specific while being entirely disconnected from reality. Examples of the pattern:
- Mocks authored to match the implementation rather than the real external contract.
- Fixtures that were correct once but now reflect an old version of the dependency.
- Code's interface changed but the mocks still reflect the old contract; tests pass against the obsolete shape.
- Mock return values invented to make the test pass, never verified against the real system.

For every mock or fixture you wrote or modified: did you verify it matches real behavior, or did you write it to match what the code currently does? If the latter, the test proves nothing about whether the code talks to the real dependency correctly.

**Silent failure / error swallowing**
The application catches an error and keeps going when it should crash. This produces a worse outcome than crashing: the program continues in an undefined state, corrupts data, or returns wrong answers while looking healthy. The rule: errors from broken invariants, missing dependencies, failed I/O on required resources, and unexpected states should propagate and crash loudly. Logging-and-continuing is not error handling. Examples of the pattern:
- Broad catch-all clauses with log-and-continue or pass.
- Default-value operators or methods (`unwrap_or`, `??`, `||`, `.get(key, default)`) covering an operation that can legitimately fail.
- Try/catch wrapping code where no specific recoverable error was anticipated — the catch is just there "in case."
- Returning null/None/empty/Err from a function whose caller doesn't actually handle the empty case meaningfully.
- Default values substituted for missing required config (vs. crashing on missing required config).
- Async errors converted to resolved values; background tasks that swallow exceptions and die quietly.
- Shell or CI directives that continue past failure (`|| true`, `set +e`, "continue on error" flags).

For each catch/swallow you introduced: name the specific error condition you're handling and the specific recovery you're doing. "In case something goes wrong" is not an answer. If the recovery is "log and proceed as if nothing happened," it should almost certainly be a crash instead.

**Suppressions**
The compiler, type-checker, linter, or test runner told you something was wrong, and you silenced the messenger instead of fixing the cause. This is dishonest in a particular way: the tool did its job, you overrode it, and now the next reader has no idea the warning ever existed. The rule: suppressions are not a way to make problems go away. They are a last resort, used only when the tool is genuinely wrong, and they require a comment explaining why the tool is wrong in this specific spot.

Things that are NOT acceptable reasons to suppress:
- "It was easier than fixing it."
- "The fix would be invasive."
- "I don't understand why the tool is complaining."
- "The code works at runtime so the warning must be wrong." (The warning is often what tells you it doesn't actually work — you just haven't hit the case yet.)
- "Suppressing it makes the build green." (False green. Same family as vacuous tests.)
- Lowering the project's lint/type/warning strictness globally to avoid fixing local issues. This is the worst version because it hides future problems too.

Examples of the pattern (translate to whatever your toolchain uses): inline directives that disable type checking, lint rules, or warnings on a line/block/file; pragma comments that exclude code from analysis; configuration changes that downgrade error severity, exclude paths from checks, or relax strictness; broadening exception types to make a checker stop complaining; casting to `any`/`Object`/`unknown` to dodge a type error; deleting or weakening assertions that were failing.

For every suppression in the diff (new or modified): quote the exact warning/error the tool produced, explain why the tool is wrong, and explain why fixing the underlying issue properly was not the right call. If you can't do all three, remove the suppression and fix the actual problem. If you changed any tool's configuration to be more permissive, flag it explicitly — that's a suppression at the project level and deserves the same justification.

**Fallback smuggling**
A dependency went missing — a binary not on PATH, generated code absent, an import that failed, a file not where expected — and you handled it by adding a conditional plus a bespoke alternative instead of making the real dependency present. This is a high-severity pattern because it produces a false green: I believe the work is done, but only the fallback path has ever executed, and the fallback is usually subtly wrong because nothing else depends on it being correct. The rule: if a dependency is missing, crash loudly. Do not duplicate logic. Do not silently degrade. Examples of the pattern:
- Feature-detection or existence-checks followed by an alternative code path that reimplements the missing thing.
- Try-import-except-reimplement, where the except branch is not a thin shim for an old API version but a hand-rolled substitute.
- File existence checks that fall through to a handwritten equivalent of what should have been there.
- Two functions that do "the same thing" where one is the canonical path and one is a workaround.
- New helpers that duplicate functionality already provided by an existing tool, library, or codegen output.
- Catch-and-log-and-continue around a call to a dependency.

Report:
- Every availability-conditional you introduced and what the fallback does.
- Whether the *primary* path was actually exercised during testing, or only the fallback.
- Whether the right fix was upstream (add to the dependency manifest / dev environment, fix the codegen, declare it properly) — and if you didn't do it that way, why not.

**Spec drift**
Walk the original request/plan point by point. For each item: done, partial, skipped, or silently reinterpreted? Anything you decided was "out of scope" without being told it was?

**Scope creep**
The inverse of spec drift: things you did that you weren't asked to do. Refactored adjacent code, "improved" formatting across files, renamed variables in untouched modules, upgraded dependencies, reformatted imports project-wide, restructured code that was working. These bloat the diff, hide the actual change in noise, and often introduce regressions in code that wasn't supposed to be touched.

List every file you modified that wasn't strictly required by the task. For each, justify why the change was necessary or admit it was scope creep. "While I was in there" is not a justification.

**Documentation drift**
Comments, docstrings, README sections, type hints, or inline annotations that describe old behavior, not the new behavior. Especially insidious because the code is correct but lies about itself, and the next reader (human or agent) trusts the lie.

For every function, module, or config you modified: did you check whether its docstring, comments, types, and any referencing documentation still describe what it actually does? Flag any place where the prose and the code disagree.

**Verification gap — most important**
List every claim you made about behavior ("this works," "tests pass," "handles X"). For each: did you actually run something that proves it, or are you inferring from the diff? Quote the command and the relevant output. If you didn't run it, say so plainly.

**Loose ends**
Debug prints, hardcoded paths/creds/values, dead code from incomplete refactors, unused imports, files that should have been deleted, dependencies added but unjustified, breaking changes undocumented, commented-out code with vague intent to restore, unreachable branches, configuration knobs added for hypothetical future needs. Delete or commit — don't leave purgatory.

End with a severity-ranked list of what a reviewer would catch that I haven't, and what you'd fix first if I gave you another turn. If you genuinely did clean work, the honest answer is a short report — don't manufacture sins.
