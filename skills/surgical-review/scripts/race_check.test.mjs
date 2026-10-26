import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { runSchedule } from "./race_check.mjs";

const script = fileURLToPath(new URL("./race_check.mjs", import.meta.url));

function names() {
  return ["executor", "poller"];
}

function naiveAdapter(cases = []) {
  return {
    actorNames: names(),
    async createCase({ order }) {
      const state = {
        effectCount: 0,
        fixture: cases.length + 1,
        trace: [],
      };
      cases.push({ order, state });
      return {
        actors: Object.fromEntries(
          names().map((name) => [
            name,
            async ({ checkpoint }) => {
              state.trace.push(`${name}:read`);
              const staleClaim = state.effectCount === 0;
              await checkpoint();
              state.trace.push(`${name}:write`);
              if (staleClaim) state.effectCount += 1;
            },
          ]),
        ),
        verify: async () => {
          if (state.effectCount !== 1) {
            throw new Error(`duplicate effect: ${state.effectCount}`);
          }
        },
      };
    },
  };
}

function atomicAdapter(cases = []) {
  return {
    actorNames: names(),
    async createCase({ order }) {
      const state = {
        claimed: false,
        effectCount: 0,
        fixture: cases.length + 1,
        trace: [],
      };
      cases.push({ order, state });
      return {
        actors: Object.fromEntries(
          names().map((name) => [
            name,
            async ({ checkpoint }) => {
              state.trace.push(`${name}:read`);
              await checkpoint();
              state.trace.push(`${name}:write`);
              if (!state.claimed) {
                state.claimed = true;
                state.effectCount += 1;
              }
            },
          ]),
        ),
        verify: async () => assert.equal(state.effectCount, 1),
      };
    },
  };
}

function assertScheduleTrace({ order, state }) {
  const firstWrite = state.trace.findIndex((entry) => entry.endsWith(":write"));
  assert.equal(
    state.trace.slice(0, firstWrite).filter((entry) => entry.endsWith(":read"))
      .length,
    2,
  );
  assert.deepEqual(
    state.trace
      .filter((entry) => entry.endsWith(":write"))
      .map((entry) => entry.slice(0, -6)),
    order,
  );
}

test("naive stale snapshots fail under both controlled winners", async () => {
  const cases = [];
  const result = await runSchedule(naiveAdapter(cases), { timeoutMs: 100 });
  assert.equal(result.ok, false);
  assert.deepEqual(
    result.schedules.map((schedule) => schedule.order),
    [names(), names().reverse()],
  );
  assert.equal(cases.length, 2);
  assert.deepEqual(
    cases.map(({ state }) => state.effectCount),
    [2, 2],
  );
  cases.forEach(assertScheduleTrace);
  assert.equal(
    result.failures.filter(({ type }) => type === "wrong_invariant").length,
    2,
  );
});

test("atomic claim passes both schedules with fresh cases", async () => {
  const cases = [];
  const result = await runSchedule(atomicAdapter(cases), { timeoutMs: 100 });
  assert.equal(result.ok, true);
  assert.deepEqual(
    cases.map(({ state }) => state.effectCount),
    [1, 1],
  );
  cases.forEach(assertScheduleTrace);
  assert.notEqual(cases[0].state, cases[1].state);
});

test("reports a skipped checkpoint and still cleans up", async () => {
  let cleanupCalls = 0;
  const result = await runSchedule(
    {
      actorNames: names(),
      async createCase() {
        return {
          actors: {
            executor: async () => {},
            poller: async ({ checkpoint }) => checkpoint(),
          },
          verify: async () => assert.fail("verify must not run"),
          cleanup: async () => {
            cleanupCalls += 1;
          },
        };
      },
    },
    { timeoutMs: 100 },
  );
  assert.equal(result.ok, false);
  assert.equal(cleanupCalls, 2);
  assert.ok(result.failures.some(({ type }) => type === "skipped"));
});

test("reports duplicate checkpoints", async () => {
  const result = await runSchedule(
    {
      actorNames: names(),
      async createCase() {
        return {
          actors: {
            executor: async ({ checkpoint }) => {
              await checkpoint();
              await checkpoint();
            },
            poller: async ({ checkpoint }) => checkpoint(),
          },
          verify: async () => assert.fail("verify must not run"),
        };
      },
    },
    { timeoutMs: 100 },
  );
  assert.equal(result.ok, false);
  assert.ok(
    result.failures.some(({ type }) => type === "duplicate_checkpoint"),
  );
});

test("reports actor rejection without calling verify", async () => {
  const result = await runSchedule(
    {
      actorNames: names(),
      async createCase() {
        return {
          actors: {
            executor: async () => {
              throw new Error("actor rejected");
            },
            poller: async ({ checkpoint }) => checkpoint(),
          },
          verify: async () => assert.fail("verify must not run"),
        };
      },
    },
    { timeoutMs: 100 },
  );
  assert.equal(result.ok, false);
  assert.ok(result.failures.some(({ type }) => type === "actor_failure"));
});

test("bounds a non-cooperative timeout and fails closed", async () => {
  const started = Date.now();
  let cases = 0;
  const result = await runSchedule(
    {
      actorNames: names(),
      async createCase() {
        cases += 1;
        return {
          actors: {
            executor: async () => new Promise(() => {}),
            poller: async ({ checkpoint }) => checkpoint(),
          },
          verify: async () => {},
        };
      },
    },
    { timeoutMs: 25 },
  );
  assert.ok(Date.now() - started < 500);
  assert.equal(cases, 1);
  assert.equal(result.schedules[1].skipped, true);
  assert.equal(result.unableToGuaranteeCancellation, true);
  assert.ok(result.failures.some(({ type }) => type === "timeout"));
});

test("reports cleanup failures without masking the schedule result", async () => {
  let cleanupCalls = 0;
  const result = await runSchedule(
    {
      actorNames: names(),
      async createCase() {
        return {
          actors: {
            executor: async ({ checkpoint }) => checkpoint(),
            poller: async ({ checkpoint }) => checkpoint(),
          },
          verify: async () => {},
          cleanup: async () => {
            cleanupCalls += 1;
            throw new Error("cleanup failed");
          },
        };
      },
    },
    { timeoutMs: 100 },
  );
  assert.equal(result.ok, false);
  assert.equal(cleanupCalls, 2);
  assert.equal(
    result.failures.filter(({ type }) => type === "cleanup_failure").length,
    2,
  );
});

test("CLI help, JSON success, and JSON failure have bounded exit codes", () => {
  const help = spawnSync(process.execPath, [script, "--help"], {
    encoding: "utf8",
  });
  assert.equal(help.status, 0);
  assert.match(help.stdout, /checkpoint exactly once/);

  const directory = mkdtempSync(join(tmpdir(), "race-check-cli-"));
  const passing = join(directory, "passing.mjs");
  const failing = join(directory, "failing.mjs");
  writeFileSync(
    passing,
    `export const actorNames = ["a", "b"];
export async function createCase({ order }) {
  const state = { count: 0 };
  return {
    actors: {
      a: async ({ checkpoint }) => { await checkpoint(); if (!state.count) state.count += 1; },
      b: async ({ checkpoint }) => { await checkpoint(); if (!state.count) state.count += 1; },
    },
    verify: async () => { if (state.count !== 1) throw new Error(order.join(",")); },
  };
}
`,
  );
  writeFileSync(
    failing,
    `export const actorNames = ["a", "b"];
export async function createCase() {
  return {
    actors: { a: async () => {}, b: async () => {} },
    verify: async () => {},
  };
}
`,
  );
  const passed = spawnSync(
    process.execPath,
    [script, passing, "--timeout-ms", "100"],
    { encoding: "utf8" },
  );
  assert.equal(passed.status, 0);
  assert.equal(JSON.parse(passed.stdout).ok, true);
  const failed = spawnSync(
    process.execPath,
    [script, failing, "--timeout-ms", "100"],
    { encoding: "utf8" },
  );
  assert.equal(failed.status, 1);
  assert.equal(JSON.parse(failed.stdout).ok, false);
});

test("CLI import failure returns exit code 2 and JSON", () => {
  const result = spawnSync(
    process.execPath,
    [script, "/tmp/race-check-adapter-does-not-exist.mjs"],
    { encoding: "utf8" },
  );
  assert.equal(result.status, 2);
  assert.equal(JSON.parse(result.stdout).ok, false);
});
