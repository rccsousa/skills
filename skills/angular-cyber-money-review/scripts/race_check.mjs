import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

export const DEFAULT_TIMEOUT_MS = 5000;

const failure = (type, message, details = {}) => ({
  type,
  message,
  ...details,
});

function errorInfo(error) {
  return error instanceof Error
    ? { name: error.name, message: error.message }
    : { name: typeof error, message: String(error) };
}

function protocolError(message) {
  const error = new Error(message);
  error.name = "RaceCheckError";
  return error;
}

function deferred() {
  let resolvePromise;
  let rejectPromise;
  const promise = new Promise((resolve, reject) => {
    resolvePromise = resolve;
    rejectPromise = reject;
  });
  promise.catch(() => {});
  return { promise, resolve: resolvePromise, reject: rejectPromise };
}

function rejected(error) {
  const promise = Promise.reject(error);
  promise.catch(() => {});
  return promise;
}

function settleWithin(operation, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };
    const timer = setTimeout(() => finish({ status: "timeout" }), timeoutMs);
    Promise.resolve()
      .then(operation)
      .then(
        (value) => finish({ status: "fulfilled", value }),
        (error) => finish({ status: "rejected", error }),
      );
  });
}

function validTimeout(timeoutMs) {
  return Number.isInteger(timeoutMs) && timeoutMs > 0;
}

function validateAdapter(adapter) {
  if (!adapter || typeof adapter !== "object") {
    return failure("adapter_failure", "Adapter must export an object.");
  }
  const { actorNames } = adapter;
  if (
    !Array.isArray(actorNames) ||
    actorNames.length !== 2 ||
    actorNames.some(
      (name) => typeof name !== "string" || name.trim().length === 0,
    ) ||
    new Set(actorNames).size !== actorNames.length
  ) {
    return failure(
      "adapter_failure",
      "Adapter actorNames must contain exactly two unique non-empty strings.",
    );
  }
  return typeof adapter.createCase === "function"
    ? null
    : failure("adapter_failure", "Adapter must export createCase.");
}

function validateCase(caseValue, actorNames) {
  if (!caseValue || typeof caseValue !== "object") {
    return failure("adapter_failure", "createCase must return an object.");
  }
  const actors = caseValue.actors;
  const missing = actorNames.filter(
    (name) => typeof actors?.[name] !== "function",
  );
  const extra = actors
    ? Object.keys(actors).filter((name) => !actorNames.includes(name))
    : [];
  if (!actors || typeof actors !== "object") {
    return failure("adapter_failure", "A case must return an actors map.");
  }
  if (missing.length > 0 || extra.length > 0) {
    return failure(
      "adapter_failure",
      "The actors map must contain exactly actorNames.",
      { missing, extra },
    );
  }
  if (typeof caseValue.verify !== "function") {
    return failure("adapter_failure", "A case must return verify.");
  }
  return caseValue.cleanup === undefined ||
    typeof caseValue.cleanup === "function"
    ? null
    : failure("adapter_failure", "case cleanup must be a function.");
}

async function runActors(caseValue, order, timeoutMs) {
  const controller = new AbortController();
  const { signal } = controller;
  const gates = new Map(order.map((name) => [name, deferred()]));
  const counts = new Map(order.map((name) => [name, 0]));
  const failures = [];
  const winner = order[0];
  const second = order[1];
  let arrivals = 0;
  let winnerReleased = false;
  let winnerSettled = false;
  let runnerAborted = false;
  let closed = false;

  const addFailure = (type, message, details) => {
    if (!closed) failures.push(failure(type, message, details));
  };
  const abort = (reason) => {
    if (signal.aborted) return;
    runnerAborted = true;
    controller.abort(reason);
    for (const gate of gates.values()) gate.reject(reason);
  };
  const checkpointFor = (name) => () => {
    if (closed || signal.aborted) {
      return rejected(signal.reason ?? protocolError("Race schedule aborted."));
    }
    const count = counts.get(name) + 1;
    counts.set(name, count);
    if (count > 1) {
      const error = protocolError(`${name} called checkpoint more than once.`);
      addFailure("duplicate_checkpoint", error.message, { actor: name });
      abort(error);
      return rejected(error);
    }
    arrivals += 1;
    if (arrivals === 2) {
      winnerReleased = true;
      gates.get(winner).resolve();
    }
    if (winnerSettled) gates.get(second).resolve();
    return gates.get(name).promise;
  };
  const actorSettled = (name, error) => {
    if (!error && counts.get(name) === 0) {
      addFailure("skipped", `${name} returned without calling checkpoint.`, {
        actor: name,
      });
    }
    if (name === winner) {
      winnerSettled = true;
      if (winnerReleased) gates.get(second).resolve();
      else if (!signal.aborted) {
        abort(
          protocolError(`${winner} settled before both checkpoints arrived.`),
        );
      }
    } else if (!winnerReleased && !signal.aborted) {
      abort(protocolError(`${second} settled before the winner was released.`));
    }
  };
  const actor = async (name) => {
    let error;
    try {
      await caseValue.actors[name]({ checkpoint: checkpointFor(name), signal });
    } catch (caught) {
      error = caught;
      if (!runnerAborted) {
        addFailure("actor_failure", `${name} rejected.`, {
          actor: name,
          error: errorInfo(caught),
        });
        abort(caught);
      }
    } finally {
      actorSettled(name, error);
    }
    return { actor: name, ok: !error };
  };

  const actors = await settleWithin(
    () => Promise.all(order.map(actor)),
    timeoutMs,
  );
  if (actors.status === "timeout") {
    const error = protocolError(
      `Actor schedule timed out after ${timeoutMs}ms.`,
    );
    addFailure("timeout", error.message, { phase: "actors" });
    abort(error);
    closed = true;
    return actorResult(failures, counts, signal, abort, true, false);
  }
  for (const name of order) {
    if (
      counts.get(name) === 0 &&
      !failures.some((item) => item.actor === name && item.type === "skipped")
    ) {
      addFailure("skipped", `${name} did not reach checkpoint.`, {
        actor: name,
      });
    }
  }
  closed = true;
  return actorResult(
    failures,
    counts,
    signal,
    abort,
    false,
    actors.value.every((result) => result.ok) &&
      order.every((name) => counts.get(name) === 1) &&
      failures.length === 0,
  );
}

function scheduleResult(order, failures, checkpointCounts = {}, options = {}) {
  return {
    order: [...order],
    ok: failures.length === 0,
    skipped: options.skipped ?? false,
    failures,
    checkpointCounts,
    unableToGuaranteeCancellation:
      options.unableToGuaranteeCancellation ?? false,
  };
}

function actorResult(failures, counts, signal, abort, uncertain, ok) {
  return {
    ok,
    failures: failures.slice(),
    checkpointCounts: Object.fromEntries(counts),
    signal,
    abort,
    unableToGuaranteeCancellation: uncertain,
  };
}

function runResult(actorNames, timeoutMs, schedules, extraFailures = []) {
  const failures = extraFailures.length
    ? extraFailures
    : schedules.flatMap((schedule) =>
        schedule.failures.map((item) => ({ order: schedule.order, ...item })),
      );
  return {
    ok:
      extraFailures.length === 0 &&
      schedules.length === 2 &&
      schedules.every((schedule) => schedule.ok),
    actorNames,
    timeoutMs,
    schedules,
    failures,
    unableToGuaranteeCancellation: schedules.some(
      (schedule) => schedule.unableToGuaranteeCancellation,
    ),
  };
}

async function runCase(adapter, order, timeoutMs) {
  const created = await settleWithin(
    () => adapter.createCase({ order: [...order] }),
    timeoutMs,
  );
  if (created.status === "timeout") {
    return scheduleResult(
      order,
      [
        failure("timeout", `createCase timed out after ${timeoutMs}ms.`, {
          phase: "createCase",
        }),
      ],
      {},
      { unableToGuaranteeCancellation: true },
    );
  }
  if (created.status === "rejected") {
    return scheduleResult(order, [
      failure("adapter_failure", "createCase rejected.", {
        phase: "createCase",
        error: errorInfo(created.error),
      }),
    ]);
  }

  const caseValue = created.value;
  const cleanup =
    typeof caseValue?.cleanup === "function" ? caseValue.cleanup : null;
  const invalidCase = validateCase(caseValue, order);
  const failures = invalidCase ? [invalidCase] : [];
  const fallbackController = new AbortController();
  let actors;
  let uncertain = false;
  try {
    if (!invalidCase) {
      actors = await runActors(caseValue, order, timeoutMs);
      failures.push(...actors.failures);
      uncertain ||= actors.unableToGuaranteeCancellation;
      if (actors.ok) {
        const verified = await settleWithin(
          () => caseValue.verify({ order: [...order], signal: actors.signal }),
          timeoutMs,
        );
        if (verified.status === "timeout") {
          const error = protocolError(`verify timed out after ${timeoutMs}ms.`);
          failures.push(failure("timeout", error.message, { phase: "verify" }));
          actors.abort(error);
          uncertain = true;
        } else if (verified.status === "rejected") {
          failures.push(
            failure("wrong_invariant", "verify rejected.", {
              error: errorInfo(verified.error),
            }),
          );
        } else if (
          verified.value === false ||
          (verified.value?.ok === false && typeof verified.value === "object")
        ) {
          failures.push(
            failure("wrong_invariant", "verify reported a wrong invariant.", {
              details: verified.value,
            }),
          );
        }
      }
    }
  } finally {
    if (cleanup) {
      const cleanupSignal = actors?.signal ?? fallbackController.signal;
      const cleaned = await settleWithin(
        () => cleanup({ order: [...order], signal: cleanupSignal }),
        timeoutMs,
      );
      if (cleaned.status === "timeout") {
        const error = protocolError(`cleanup timed out after ${timeoutMs}ms.`);
        failures.push(failure("timeout", error.message, { phase: "cleanup" }));
        if (actors) actors.abort(error);
        else fallbackController.abort(error);
        uncertain = true;
      } else if (cleaned.status === "rejected") {
        failures.push(
          failure("cleanup_failure", "cleanup rejected.", {
            error: errorInfo(cleaned.error),
          }),
        );
      }
    }
  }
  return scheduleResult(order, failures, actors?.checkpointCounts, {
    unableToGuaranteeCancellation: uncertain,
  });
}

function skippedSchedule(order) {
  return scheduleResult(
    order,
    [
      failure(
        "skipped",
        "Schedule skipped because the prior case could not guarantee cancellation.",
        { phase: "schedule" },
      ),
    ],
    {},
    { skipped: true, unableToGuaranteeCancellation: true },
  );
}

/** Run both controlled orders with fresh cases; a pass covers only those schedules. */
export async function runSchedule(
  adapter,
  { timeoutMs = DEFAULT_TIMEOUT_MS } = {},
) {
  if (!validTimeout(timeoutMs)) {
    return runResult(
      [],
      timeoutMs,
      [],
      [failure("adapter_failure", "timeoutMs must be a positive integer.")],
    );
  }
  const invalidAdapter = validateAdapter(adapter);
  if (invalidAdapter) {
    return runResult(
      Array.isArray(adapter?.actorNames) ? [...adapter.actorNames] : [],
      timeoutMs,
      [],
      [invalidAdapter],
    );
  }

  const actorNames = [...adapter.actorNames];
  const schedules = [];
  let stop = false;
  for (const order of [actorNames, [...actorNames].reverse()]) {
    const schedule = stop
      ? skippedSchedule(order)
      : await runCase(adapter, order, timeoutMs);
    schedules.push(schedule);
    stop ||= schedule.unableToGuaranteeCancellation;
  }
  return runResult(actorNames, timeoutMs, schedules);
}

export function formatHelp() {
  return `Usage: node race_check.mjs <adapter-path> [--timeout-ms N]

Adapter contract (named exports or one default-exported object):
  export const actorNames = ["actor-a", "actor-b"];
  export async function createCase({ order }) {
    return {
      actors: {
        "actor-a": async ({ checkpoint, signal }) => { /* stale read; await checkpoint(); persist */ },
        "actor-b": async ({ checkpoint, signal }) => { /* stale read; await checkpoint(); persist */ },
      },
      verify: async ({ order, signal }) => { /* assert the business invariant */ },
      cleanup: async ({ order, signal }) => { /* release fixture resources */ },
    };
  }
  const result = await runSchedule(adapter, { timeoutMs: 5000 });
  assert(result.ok);

createCase receives a fresh case per order. order[0] is released after both
actors call checkpoint exactly once; order[1] is released after order[0] settles.
verify runs only after both actors succeed. A pass covers these two controlled
schedules and does not prove every possible concurrency interleaving.
Timeouts request cooperative cancellation through signal. A non-cooperative
timeout fails closed, marks the remaining schedule skipped, and the CLI exits.

Exit 0 means both schedules verified. Exit 1 means JSON failures were reported;
exit 2 means invalid CLI arguments or an adapter import failure.`;
}

function parseArguments(argv) {
  let adapterPath;
  let timeoutMs = DEFAULT_TIMEOUT_MS;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") return { help: true };
    if (argument === "--timeout-ms") {
      const value = argv[index + 1];
      if (value === undefined)
        throw new Error("--timeout-ms requires a value.");
      timeoutMs = Number(value);
      index += 1;
      continue;
    }
    if (argument.startsWith("-"))
      throw new Error(`Unknown option: ${argument}`);
    if (adapterPath !== undefined) {
      throw new Error("Only one adapter path may be supplied.");
    }
    adapterPath = argument;
  }
  if (!adapterPath) throw new Error("An adapter path is required.");
  if (!validTimeout(timeoutMs)) {
    throw new Error("--timeout-ms must be a positive integer.");
  }
  return { adapterPath, timeoutMs };
}

async function importAdapter(adapterPath) {
  const location = adapterPath.startsWith("file:")
    ? adapterPath
    : pathToFileURL(resolve(process.cwd(), adapterPath)).href;
  const module = await import(location);
  return module.default ?? module;
}

function writeLine(stream, line) {
  return new Promise((resolvePromise, reject) => {
    stream.write(`${line}\n`, (error) =>
      error ? reject(error) : resolvePromise(),
    );
  });
}

async function cli(argv) {
  let parsed;
  try {
    parsed = parseArguments(argv);
  } catch (error) {
    await writeLine(
      process.stderr,
      `${errorInfo(error).message}\n${formatHelp()}`,
    );
    return 2;
  }
  if (parsed.help) {
    await writeLine(process.stdout, formatHelp());
    return 0;
  }
  let adapter;
  try {
    adapter = await importAdapter(parsed.adapterPath);
  } catch (error) {
    await writeLine(
      process.stdout,
      JSON.stringify({
        ok: false,
        failures: [
          failure("adapter_failure", "Adapter import failed.", {
            error: errorInfo(error),
          }),
        ],
      }),
    );
    return 2;
  }
  const result = await runSchedule(adapter, { timeoutMs: parsed.timeoutMs });
  await writeLine(process.stdout, JSON.stringify(result));
  return result.ok ? 0 : 1;
}

const isMain =
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  cli(process.argv.slice(2))
    .then((code) => process.exit(code))
    .catch(async (error) => {
      await writeLine(
        process.stdout,
        JSON.stringify({
          ok: false,
          failures: [
            failure("adapter_failure", "CLI failed.", {
              error: errorInfo(error),
            }),
          ],
        }),
      );
      process.exit(2);
    });
}
