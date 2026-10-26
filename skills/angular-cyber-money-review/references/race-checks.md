# Deterministic race checks

Use this recipe for a supported race hypothesis: competing writers read the same state, cross an asynchronous boundary, and authorize a side effect from a stale snapshot. The reviewer chooses the invariant, reachable starting states, and checkpoint. The helper controls only two specified execution orders; it does not detect races or prove all concurrency schedules safe.

## Choose the proof

- Enumerate the writers, the state each reads, the contested write, and the observable effect. Name the event being claimed: a status transition and a first identity binding can happen at different times.
- Inspect the actual SQL/transaction guards and result consumed by the caller. A fresh read after a write does not identify which writer first claimed an event.
- Put one checkpoint per actor after its relevant stale read and immediately before contested persistence. Keep the service and repository path real where possible; inject scheduling through the existing test fixture or narrow method wrappers.
- Run each actor first using fresh state. Include an already-transitioned but still-unbound state when the claimed event is distinct from that transition. Follow with ordinary re-observation assertions and relevant conflicting-ID/terminal guards using existing test coverage.
- Assert the business effect and preserved behavior, not an internal boolean alone. Counts, notifications, durable identity, and evidence preservation can be separate invariants.
- For a confirmed finding being fixed, preserve one focused red result against the reviewed code and one green result against the fix when practical. Do not repeat until green or add arbitrary stability loops.

## Callable helper

From a permitted local test worktree, an agent can run:

```sh
node <skill-directory>/scripts/race_check.mjs /absolute/path/to/adapter.mjs --timeout-ms 5000
```

Use `--help` for the adapter contract. The module exports `runSchedule(adapter, { timeoutMs })`; the adapter exports `actorNames` (two unique names) and `createCase({ order })`. Each fresh case returns `actors`, `verify`, and optional `cleanup`. `verify` throws on a violated invariant. Library callers must assert the returned `ok` field; returning a failure object alone does not fail a test:

```js
const result = await runSchedule(adapter, { timeoutMs: 5000 });
assert.equal(result.ok, true, JSON.stringify(result));
```

Keep the adapter small and reuse the repository test runner's database setup and fixtures. It does not install dependencies, create worktrees, mutate a PR, or discover credentials. An adapter executes code, so use the same authorization and isolation as a local integration test.

The adapter supplies two named actors, a fresh case factory, an assertion callback, and optional cleanup. Each actor awaits its provided checkpoint exactly once. Both must reach it before either proceeds; then the designated first actor finishes before the second is released. The second schedule creates a new fixture. A failed assertion, missing/duplicate checkpoint, actor rejection, or timeout must produce failure, not a passing report. Do not swallow checkpoint errors.

Use a checkpoint at the specific contested boundary; releasing an entire actor to completion does not explore interleavings inside its write/effect sequence. Add a separate targeted test when that finer boundary matters. An actor must not wait for the blocked second actor after it has been released, or the selected schedule will deadlock and time out.

The timeout bounds each asynchronous case phase; it does not preempt synchronous blocking code or adapter-module import. Use the execution environment's outer timeout for those. Timeout cancellation is cooperative in library use. Supply the abort signal to cancellable work and configure database/test timeouts. After a non-cooperative timeout, abandon that fixture/process; do not reuse it or report cleanup/cancellation as established. The CLI terminates on failure rather than treating an incomplete run as success.

## Evidence and review boundaries

Record exact target SHA or diff, starting state, checkpoint location, actor order, invariant, command, and result. Separate repository doubles, real persistence, and live provider behavior. A fake provider plus real PostgreSQL establishes local persistence behavior; it does not establish provider semantics. The helper's synthetic self-tests validate only the helper.

Keep hypotheses and adapters private between blind review passes until reconciliation. Put scratch adapters and logs outside tracked project files during review; commit a repository-native regression only within authorized fix work. Keep evaluation candidates and prior verdicts out of blind-review inputs. No global hook or mandatory concurrency suite is added by this recipe.
