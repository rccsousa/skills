---
name: code-writing-standards
description: The enforced code-writing standards for module shape, seam discipline, and comments — the source of truth the write/review skills apply. Use when writing or reviewing code, deciding how to split a function or module, where to put a seam, or whether a comment/docstring earns its place. Opinionated house rules; for the underlying deep-module vocabulary use /codebase-design.
---

# Code-Writing Standards

House rules for **how code gets shaped** — functions, modules, seams, comments. This is the source of truth `implement`, `tdd`, `issue-worker`, and `code-review` apply at write and review time. It is *opinionated*, not a vocabulary primer: for the underlying deep-module terms (module/interface/depth/seam/adapter) see `/codebase-design`; for detecting existing violations see `/improve-codebase-architecture`.

The through-line: **a deep pure core behind thin seams, expressed in code so clear it needs no prose.** Everything below serves that.

**Living document.** This is a charter that sharpens as the author's architecture judgement sharpens — not a frozen spec. It currently crystallizes the dimensions grilled so far: **function splits, module cohesion, seams, comments**. Adjacent standards not yet grilled in (error handling / let-it-fail, naming depth, testing posture) still live in the `surgical-review` reviewer prompt; they migrate here as they get grilled. When a rule below proves wrong or too blunt in practice, change it here — this is the one place that propagates to the whole write → review → fix chain.

---

## 1. Functions — single responsibility, but deep

- **SRP = one *reason to change*.** Not "one operation," not a line count. A function that parses *and* calculates *and* loops *and* branches has many reasons to change — split it. A function that does one cohesive thing in 40 lines has one reason to change — leave it.
- **Prefer a deep orchestrator over a monster.** A `calculate_tax_on_goods` that reads like a recipe — `find_goods` → `calculate_prices` → `apply_tax` — over one 300-LOC function that does everything. The 300-LOC monster is the enemy.
- **The 3-part split test.** An extracted function earns its existence if it passes **≥1** of:
  1. **Independently meaningful** — its name describes a complete operation, explainable without "…then the caller does the next step."
  2. **Independently testable** — testable through its own inputs/outputs, no reconstructing caller state.
  3. **Reused** — 2+ real call sites (actual DRY, not speculative).

  Fails all three → it's a fragment. Inline it back or redraw the seam.
- **Banned: temporal decomposition.** `step1()` / `step2()` chopped by execution order, each meaningless alone, called only in sequence. Same silhouette as a good split, opposite quality.
- **The tell:** a sub-function takes a big mutable `ctx`/bag param and mutates it. That's the signature of "split by line-count, not by responsibility" — it fails test #2 by construction.

## 2. Modules — one cohesive responsibility

- **Boundary = one cohesive responsibility, one body of related state.** That is what defines a module, not its size.
- **Single owner.** Each responsibility has exactly **one home module**; every other module **delegates across a seam** rather than growing its own copy. An accounting module that needs to notify **delegates to the notifications module** — it never grows its own notification-issuing functions. This is module-level DRY, and it's the force that keeps modules from accreting into god modules.
- **Split trigger = the cohesion test.** Do the module's functions partition into subsets touching **disjoint** state/data, with few cross-edges? If so it's N modules wearing one file → split by responsibility. (Distinct from depth: a god module can be "deep" — small interface — and still fail this. See `/improve-codebase-architecture`.)
- **Size is a smell, not a verdict.** A genuinely single-responsibility large module is allowed. Fn-count alone never force-splits a cohesive module.
- **Soft tripwire (enforceable hook).** A module past **~15-20 exported functions**, or a function past **~40-50 LOC**, does **not** auto-fail — it **obligates** the reviewer to run the cohesion/split test and **record the verdict**. The number makes the check fire; cohesion delivers the call. (Thresholds are a starting point — tune to the codebase.)

## 3. Seams — only where the world is non-deterministic

- **Seam only at true external / non-deterministic boundaries:** I/O, network, DB, clock, randomness, payments — anything you can't run for real in a test.
- **No seam inside the pure domain core.** Pure functions are tested **by value** (input → output). No interface, no injection, no mock. `calculate_prices` / `apply_tax` get called directly in tests — never doubled.
- **Shape = functional-core / imperative-shell.** Deep pure core; thin seams only at the edges. This satisfies deep-modules, testability, and no-speculation at once.
- **The fake is the real second adapter.** A boundary seam isn't speculative because the in-memory fake *is* its genuine second adapter (real impl + fake = two adapters = a real seam). Inside the domain, introduce no interface until a real second implementation actually appears.
- **Anti-pattern:** injecting or mocking pure logic "for testability." That's the shallow-module factory wearing a testing badge.

## 4. Comments & docs — earned, never default

Default is **no prose**. Code is made self-explanatory through naming, small deep functions, and types (`@spec`/signatures). Prose is *earned* against the ladder below.

**Audience = agents.** Claude and its subagents are effectively the only ones reading and editing this code. That does **not** license more comments — it changes *which* ones survive. An agent re-reads the file every session and can follow any symbol it references, so narration and tutoring are pure noise it must pay for. What it can't cheaply recover is **non-local** fact: a contract enforced in another service, an ordering constraint, an upstream bug being worked around, a migration that must land first. Those earn one dense line.

**The recoverability test** (apply before writing any comment):
> Would a competent agent, given this file plus the symbols it references, reconstruct this fact?
>
> **Yes** → no comment. **No** → one line, fact-dense, pointer-first.

**Also banned, beyond HOW:**
- **Change-log commentary** — `// added retry`, `// was previously X`, `// NEW:`, `// TODO(2024): remove`. Git carries history; these rot on first refactor.
- **Signature restatement** — a docstring listing the params and their types the signature already declares.
- **Tutoring / hedging prose** — explaining a language feature, a stdlib call, or a standard pattern.
- **Banner dividers** — `// ===== HELPERS =====`. If a file needs sections, it needs splitting (§2).

**Shape when earned:** one line, caveman-terse, no articles or filler. Prefer a pointer (`see RFC 5545 §3.8.2.2`, `must run after 20240712_backfill`) over restating. Multi-line only at a genuine representation gap (below).

**On existing code:** delete violating comments in code you're already touching. No comment-only sweeps unless asked.

- **HOW comments are banned.** `# loop over items`, `# now apply tax`. If you feel the need, the code isn't clear — **extract or rename** instead.
- **Rationale → ADR or commit message, never a forever inline comment.** The "why we chose 60/min" belongs in an ADR or the commit that set it, not bolted above the constant where it rots and bloats every future diff. Good names (`feed_limit`, `feed_window_ms`) carry the *what*; delete the essay.
- **Contract fact types/names can't carry → climb the ladder, in order:**
  1. **Name it** — `end_date` → `exclusive_end`. First resort; kills most cases.
  2. **Type it** — a `DateRange`/`Money` type that defines the contract once, enforced by the compiler.
  3. **Test it** — a named test (`"DTEND is the exclusive end"`) that fails the instant someone flips it. The spec becomes executable.
  4. **Only if 1-3 genuinely can't hold it** → one line of prose, preferring a **pointer** (`# see RFC 5545 §3.8.2.2`) over restating.
- **Prose is earned only at a *representation gap*** — where the code is a non-obvious *encoding* of a simpler model and a competent reader can't reconstruct the WHAT from the code: complex/fixed-point math, bit-twiddling, protocol or ordering invariants, gnarly regex. Then the prose states the **WHAT / reference model** (`fee(t) = baseRate(t) × weightedUnits`, in fixed-point) — **never the HOW** (it does not narrate the bit-shifts) — and points at the spec where one exists.

  **Discriminator:** no gap (an `ICal` module that plainly emits `VEVENT`s — the name and code say it) → cut the moduledoc. Real gap (fixed-point arithmetic that hides the formula it implements) → keep the docstring. Both are docstrings; only one is load-bearing.

---

## Review checklist (the hook `code-review` runs)

- [ ] Any function > ~40-50 LOC or module > ~15-20 exported functions → cohesion/split test **run**, verdict recorded.
- [ ] Every extracted function passes the 3-part test — else inline it or redraw the seam.
- [ ] No temporal decomposition; no mutable-`ctx`-bag "splits."
- [ ] Seams only at external/non-deterministic boundaries; the pure core is untouched by mocks.
- [ ] Each responsibility has a single owner; no duplicated cross-module functions (delegate instead).
- [ ] No HOW comments. Rationale lives in ADR/commit. Prose only at a genuine representation gap, and it states the WHAT.
- [ ] Every surviving comment passes the recoverability test — carries non-local fact or a real trap, not narration, change-log, signature restatement, or tutoring.
- [ ] Comments in touched code that fail the test are **deleted**, not left in place.
