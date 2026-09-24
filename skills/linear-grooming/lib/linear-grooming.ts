#!/usr/bin/env bun
// linear-grooming.ts project [--project P]                         → print resolved {name,dir,repos,team}
// linear-grooming.ts plan [--project P] [--api | --issues F [--enrich E]]
//   --api: fetch from Linear GraphQL. --issues: MCP list_issues output (array or pages of {issues}).
//   MCP mode exits 3 + prints `NEEDS <ids>` when parents or no-PR issues need children/attachments (--enrich).
// linear-grooming.ts apply <safe|all|1-3,5>                         → api plan: mutate + verify; mcp plan: print {id,state} lines
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";

const HOME = homedir();
const PLAN_FILE = `${HOME}/.cache/linear-grooming/plan.json`;
const PROJECTS_FILE = `${HOME}/.config/linear-grooming/projects.json`;
const TERMINAL = new Set(["completed", "canceled", "duplicate"]);
const RANK: Record<string, number> = {
  triage: 0,
  backlog: 1,
  unstarted: 2,
  started: 3,
  completed: 4,
};
// Heuristic, calibrated on real PR bodies ("partial" alone mostly means "partial index"); only downgrades safe → ask.
const UNFINISHED =
  /\bNOT_RUN\b|\b(?:was|were|is|are|did) not (?:yet )?(?:been )?(?:run|verified|tested|exercised)\b|\bunverified\b|\bpartial(?:ly)? (?:done|complete|completed|implemented|delivered|verified)\b|\bverdict\W+partial\b|\bdeferred\b|\b(?:later|next|separate|follow-?up) (?:pr|slice)\b/i;
type Statuses = { inProgress: string; inReview: string; done: string };
const DEFAULT_STATUSES: Statuses = {
  inProgress: "In Progress",
  inReview: "In Review",
  done: "Done",
};
let S = DEFAULT_STATUSES;
const statusRank = (name: string): number | undefined =>
  ({ [S.inProgress]: 3, [S.inReview]: 3.5, [S.done]: 4 })[name];

type Project = {
  name: string;
  dir: string;
  repos: string[];
  team: string | null;
  statuses: Statuses;
};
type Child = { identifier: string; state: { name: string; type: string } };
type Issue = {
  id: string;
  identifier: string;
  title: string;
  state: { name: string; type: string };
  states: { id: string; name: string; type: string }[] | null;
  children: Child[] | null;
  attachments: string[] | null;
  isParent: boolean;
};
type GhPr = {
  number: number;
  state: string;
  isDraft: boolean;
  mergedAt: string | null;
  url: string;
  title: string;
  headRefName: string;
  body: string | null;
};
type Pr = Pick<GhPr, "number" | "state" | "isDraft" | "mergedAt" | "url"> & {
  match: string;
  unfinished: string | null;
};
type LocalBranch = { branch: string; ahead: number };
type Enrichment = Record<
  string,
  { attachments?: string[]; children?: Child[] }
>;
type Row = {
  n: number;
  issueId: string;
  identifier: string;
  title: string;
  now: string;
  target: string | null;
  stateId: string | null;
  safe: boolean;
  kind: "move" | "flag" | "noop";
  evidence: string;
};

function sh(cmd: string[], cwd?: string): string {
  const p = Bun.spawnSync(cmd, { stderr: "pipe", cwd });
  if (p.exitCode !== 0)
    throw new Error(`${cmd.join(" ")}: ${p.stderr.toString()}`);
  return p.stdout.toString();
}

function flag(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}

// Exact ID match: ENG-113 must not match ENG-1130.
function mentions(text: string | null | undefined, id: string): boolean {
  const key = id.toLowerCase().replace(/[^a-z0-9-]/g, "");
  return new RegExp(`(?:^|[^a-z0-9])${key}(?![0-9])`).test(
    (text ?? "").toLowerCase(),
  );
}

async function resolveProject(arg?: string): Promise<Project> {
  const config: Record<
    string,
    Omit<Project, "name" | "statuses"> & { statuses?: Partial<Statuses> }
  > = existsSync(PROJECTS_FILE) ? await Bun.file(PROJECTS_FILE).json() : {};
  const expand = (d: string) => d.replace(/^~/, HOME);
  const withStatuses = (
    p: Omit<Project, "name" | "statuses"> & { statuses?: Partial<Statuses> },
  ) => ({
    ...p,
    statuses: { ...DEFAULT_STATUSES, ...p.statuses },
  });
  if (arg && config[arg])
    return {
      name: arg,
      ...withStatuses(config[arg]),
      dir: expand(config[arg].dir),
    };
  const dir = expand(arg ?? process.cwd());
  if (!existsSync(dir))
    throw new Error(
      `unknown project "${arg}" — not in ${PROJECTS_FILE} and not a directory`,
    );
  const top = sh(["git", "rev-parse", "--show-toplevel"], dir).trim();
  const known = Object.entries(config).find(([, p]) => expand(p.dir) === top);
  if (known) return { name: known[0], ...withStatuses(known[1]), dir: top };
  const repo = sh(
    ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
    top,
  ).trim();
  return {
    name: top.split("/").pop()!,
    dir: top,
    repos: [repo],
    team: null,
    statuses: DEFAULT_STATUSES,
  };
}

function apiKey(): string {
  if (process.env.LINEAR_API_KEY) return process.env.LINEAR_API_KEY;
  const p = Bun.spawnSync([
    "security",
    "find-generic-password",
    "-s",
    "linear-api-key",
    "-w",
  ]);
  if (p.exitCode === 0) return p.stdout.toString().trim();
  console.error(
    "No Linear key. Create one at https://linear.app/settings/account/security, then:\n" +
      "  security add-generic-password -s linear-api-key -a $USER -w <key>",
  );
  process.exit(2);
}

async function gql<T>(
  query: string,
  variables: Record<string, unknown> = {},
): Promise<T> {
  const res = await fetch("https://api.linear.app/graphql", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: apiKey() },
    body: JSON.stringify({ query, variables }),
  });
  const body = (await res.json()) as { data?: T; errors?: unknown };
  if (body.errors || !body.data)
    throw new Error(JSON.stringify(body.errors ?? body));
  return body.data;
}

async function fetchIssuesApi(team: string | null): Promise<Issue[]> {
  const q = `query($after: String, $filter: IssueFilter) { viewer { assignedIssues(first: 100, after: $after, filter: $filter) {
    nodes { id identifier title state { name type }
      team { states { nodes { id name type } } }
      children { nodes { identifier state { name type } } }
      attachments { nodes { url } } }
    pageInfo { hasNextPage endCursor } } } }`;
  const filter = team ? { team: { name: { eqIgnoreCase: team } } } : undefined;
  const out: Issue[] = [];
  let after: string | null = null;
  do {
    const d: any = await gql(q, { after, filter });
    const page = d.viewer.assignedIssues;
    for (const n of page.nodes) {
      out.push({
        id: n.id,
        identifier: n.identifier,
        title: n.title,
        state: n.state,
        states: n.team.states.nodes,
        children: n.children.nodes,
        attachments: n.attachments.nodes.map((a: { url: string }) => a.url),
        isParent: n.children.nodes.length > 0,
      });
    }
    after = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : null;
  } while (after);
  return out.filter((i) => !TERMINAL.has(i.state.type));
}

async function readIssuesMcp(
  file: string,
  enrichFile?: string,
): Promise<Issue[]> {
  const raw = await Bun.file(file).json();
  const pages = Array.isArray(raw) ? raw : [raw];
  const nodes = pages.flatMap((p: any) =>
    Array.isArray(p?.issues) ? p.issues : [p],
  );
  const enrich: Enrichment = enrichFile
    ? await Bun.file(enrichFile).json()
    : {};
  const parents = new Set(nodes.map((n: any) => n.parentId).filter(Boolean));
  return nodes
    .filter((n: any) => !TERMINAL.has(n.statusType))
    .map((n: any) => ({
      id: n.id,
      identifier: n.id,
      title: n.title,
      state: { name: n.status, type: n.statusType },
      states: null,
      children: enrich[n.id]?.children ?? null,
      attachments: enrich[n.id]?.attachments ?? null,
      isParent: parents.has(n.id),
    }));
}

function authoredPrs(repo: string): GhPr[] {
  return JSON.parse(
    sh([
      "gh",
      "pr",
      "list",
      "-R",
      repo,
      "--author",
      "@me",
      "--state",
      "all",
      "--limit",
      "300",
      "--json",
      "number,title,state,isDraft,mergedAt,url,headRefName,body",
    ]),
  );
}

function toPr(
  p: Pick<GhPr, "number" | "state" | "isDraft" | "mergedAt" | "url" | "body">,
  match: string,
): Pr {
  return {
    number: p.number,
    state: p.state,
    isDraft: p.isDraft,
    mergedAt: p.mergedAt,
    url: p.url,
    match,
    unfinished: (p.body ?? "").match(UNFINISHED)?.[0] ?? null,
  };
}

function prEvidence(issue: Issue, pool: GhPr[]): Pr[] {
  const id = issue.identifier;
  const found = new Map<string, Pr>();
  for (const p of pool) {
    const match = mentions(p.title, id)
      ? "title"
      : mentions(p.headRefName, id)
        ? "branch"
        : mentions(p.body, id)
          ? "body"
          : null;
    if (match) found.set(p.url, toPr(p, match));
  }
  for (const url of issue.attachments ?? []) {
    if (
      !/github\.com\/[^/]+\/[^/]+\/pull\/\d+/.test(url) ||
      found.get(url)?.match === "title"
    )
      continue;
    const v = JSON.parse(
      sh([
        "gh",
        "pr",
        "view",
        url,
        "--json",
        "number,state,isDraft,mergedAt,url,body",
      ]),
    );
    found.set(url, toPr(v, "attachment"));
  }
  return [...found.values()];
}

const hasStrongPr = (prs: Pr[]) => prs.some((p) => p.match !== "body");

function remoteBranches(repos: string[]): string[] {
  return repos.flatMap((r) =>
    sh(["git", "ls-remote", "--heads", `https://github.com/${r}.git`])
      .toLowerCase()
      .split("\n"),
  );
}

function unpushedBranches(dir: string, ids: string[]): LocalBranch[] {
  return sh(
    ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads"],
    dir,
  )
    .split("\n")
    .filter((branch) => branch && ids.some((id) => mentions(branch, id)))
    .map((branch) => ({
      branch,
      ahead: Number(
        sh(
          [
            "git",
            "rev-list",
            "--count",
            `refs/heads/${branch}`,
            "--not",
            "--remotes",
          ],
          dir,
        ).trim(),
      ),
    }))
    .filter((b) => b.ahead > 0);
}

function fmtPr(p: Pr): string {
  const s = p.state === "OPEN" && p.isDraft ? "DRAFT" : p.state;
  return `#${p.number} ${s}${p.mergedAt ? ` ${p.mergedAt.slice(5, 10)}` : ""}`;
}

type Decision = Pick<Row, "target" | "safe" | "kind" | "evidence">;

function decide(
  issue: Issue,
  prs: Pr[],
  remote: string[],
  local: LocalBranch[],
): Decision {
  const strong = prs.filter((p) => p.match !== "body");
  const weak = prs.filter((p) => p.match === "body");
  const ev = strong.map(fmtPr).join(", ");
  const move = (target: string, safe: boolean, evidence = ev): Decision => ({
    target,
    safe,
    kind: "move",
    evidence,
  });
  const flagged = (evidence: string): Decision => ({
    target: null,
    safe: false,
    kind: "flag",
    evidence,
  });
  const noop = (evidence = ev): Decision => ({
    target: null,
    safe: false,
    kind: "noop",
    evidence,
  });

  const children = issue.children ?? [];
  if (children.length) {
    const open = children.filter((c) => !TERMINAL.has(c.state.type)).length;
    if (open) return noop(`parent: ${open}/${children.length} children open`);
    return move(
      S.done,
      false,
      `parent: all ${children.length} children closed`,
    );
  }
  const open = strong.filter((p) => p.state === "OPEN");
  const merged = strong.filter((p) => p.state === "MERGED");
  if (merged.length && !open.length) {
    const caveats = merged.filter((p) => p.unfinished);
    if (!caveats.length) return move(S.done, true);
    const quoted = caveats.map((p) => `#${p.number} says "${p.unfinished}"`);
    return move(S.done, false, `${ev} — ${quoted.join(", ")}`);
  }
  if (open.some((p) => !p.isDraft)) return move(S.inReview, true);
  if (open.length) return move(S.inProgress, true);
  if (strong.length)
    return flagged(`only closed-unmerged: ${ev} — superseded? cancel?`);
  if (remote.some((b) => mentions(b, issue.identifier)))
    return move(S.inProgress, false, "branch pushed, no PR");
  const unpushed = local.find((b) => mentions(b.branch, issue.identifier));
  if (unpushed)
    return move(
      S.inProgress,
      false,
      `${unpushed.ahead} unpushed commit(s) on ${unpushed.branch}, no PR`,
    );
  if (weak.length)
    return flagged(`only mentioned in ${weak.map(fmtPr).join(", ")}`);
  if (issue.state.type === "started")
    return flagged("started, no PR or branch — stale? move back to backlog?");
  return noop("no PR");
}

function finalize(issue: Issue, d: Decision): Omit<Row, "n"> {
  const base = {
    issueId: issue.id,
    identifier: issue.identifier,
    title: issue.title,
    now: issue.state.name,
  };
  if (d.kind !== "move" || !d.target || d.target === issue.state.name) {
    return {
      ...base,
      ...d,
      kind: d.kind === "move" ? "noop" : d.kind,
      target: null,
      stateId: null,
      safe: false,
    };
  }
  const state = issue.states?.find((s) => s.name === d.target);
  if (issue.states && !state) {
    return {
      ...base,
      kind: "flag",
      target: null,
      stateId: null,
      safe: false,
      evidence: `no "${d.target}" status on team`,
    };
  }
  const nowRank = statusRank(issue.state.name) ?? RANK[issue.state.type] ?? 0;
  const forward =
    (statusRank(d.target) ?? RANK[state?.type ?? ""] ?? 0) > nowRank;
  return {
    ...base,
    ...d,
    stateId: state?.id ?? null,
    safe: d.safe && forward,
    evidence: forward ? d.evidence : `${d.evidence} (backwards)`,
  };
}

function openPrsOnOtherTickets(pool: GhPr[], issues: Issue[]): Omit<Row, "n">[] {
  const keys = [
    ...new Set(
      issues.map((i) =>
        i.identifier
          .split("-")[0]
          .toLowerCase()
          .replace(/[^a-z0-9]/g, ""),
      ),
    ),
  ].filter(Boolean);
  if (!keys.length) return [];
  const mine = new Set(issues.map((i) => i.identifier.toLowerCase()));
  const re = new RegExp(
    `(?:^|[^a-z0-9])((?:${keys.join("|")})-\\d+)(?![0-9])`,
    "g",
  );
  const byId = new Map<string, { title: string; prs: number[] }>();
  for (const p of pool.filter((p) => p.state === "OPEN")) {
    for (const [, id] of `${p.title} ${p.headRefName}`
      .toLowerCase()
      .matchAll(re)) {
      if (mine.has(id)) continue;
      const entry = byId.get(id) ?? { title: p.title, prs: [] };
      if (!entry.prs.includes(p.number)) entry.prs.push(p.number);
      byId.set(id, entry);
    }
  }
  return [...byId].map(([id, e]) => ({
    issueId: "",
    identifier: id.toUpperCase(),
    title: e.title,
    now: "—",
    target: null,
    stateId: null,
    safe: false,
    kind: "flag",
    evidence: `your open ${e.prs.map((n) => `#${n}`).join(", ")} — not one of your open tickets`,
  }));
}

function printTable(project: Project, rows: Row[]) {
  const trunc = (s: string, n: number) =>
    (s.length > n ? `${s.slice(0, n - 1)}…` : s).padEnd(n);
  console.log(
    `project ${project.name} · team ${project.team ?? "(all)"} · repos ${project.repos.join(", ")}\n`,
  );
  const show = rows.filter((r) => r.kind !== "noop");
  if (!show.length) console.log("Nothing to move or flag.");
  for (const r of show) {
    const target = r.kind === "move" ? `→ ${r.target}` : "(flag)";
    const safe = r.kind === "move" ? (r.safe ? "safe" : "ask") : "";
    console.log(
      `${String(r.n).padStart(2)}  ${r.identifier.padEnd(12)} ${trunc(r.title, 48)} ${r.now.padEnd(12)} ${target.padEnd(14)} ${safe.padEnd(5)} ${r.evidence}`,
    );
  }
  const noops = rows.filter((r) => r.kind === "noop");
  if (noops.length)
    console.log(
      `\n${noops.length} unchanged: ${noops.map((r) => r.identifier).join(" ")}`,
    );
}

async function plan(args: string[]) {
  const project = await resolveProject(flag(args, "--project"));
  S = project.statuses;
  const issuesFile = flag(args, "--issues");
  const enrichFile = flag(args, "--enrich");
  if (!issuesFile && !args.includes("--api"))
    throw new Error("plan needs --api or --issues <file>");

  const issues = issuesFile
    ? await readIssuesMcp(issuesFile, enrichFile)
    : await fetchIssuesApi(project.team);
  const pool = project.repos.flatMap(authoredPrs);
  const evidence = new Map(
    issues.map((i) => [i.identifier, prEvidence(i, pool)]),
  );

  const needs = issues.filter(
    (i) =>
      (i.isParent && i.children === null) ||
      (i.attachments === null && !hasStrongPr(evidence.get(i.identifier)!)),
  );
  if (needs.length) {
    console.log(`NEEDS ${needs.map((i) => i.identifier).join(" ")}`);
    process.exit(3);
  }

  const remote = remoteBranches(project.repos);
  const local = unpushedBranches(
    project.dir,
    issues.map((i) => i.identifier),
  );
  const order = ["move", "flag", "noop"];
  const rows = [
    ...issues.map((i) =>
      finalize(i, decide(i, evidence.get(i.identifier)!, remote, local)),
    ),
    ...openPrsOnOtherTickets(pool, issues),
  ]
    .sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind))
    .map((r, idx) => ({ ...r, n: idx + 1 }));
  mkdirSync(PLAN_FILE.replace(/\/[^/]+$/, ""), { recursive: true });
  const mode = issuesFile ? "mcp" : "api";
  await Bun.write(
    PLAN_FILE,
    JSON.stringify(
      { createdAt: new Date().toISOString(), mode, project, rows },
      null,
      2,
    ),
  );
  printTable(project, rows);
}

function select(sel: string, moves: Row[]): Row[] {
  if (sel === "safe") return moves.filter((r) => r.safe);
  if (sel === "all") return moves;
  const picked = new Set<number>();
  for (const part of sel.split(",")) {
    const m = part.trim().match(/^(\d+)(?:-(\d+))?$/);
    if (!m)
      throw new Error(`bad selection "${part}" — use safe, all, or e.g. 1-3,5`);
    const [a, b] = [Number(m[1]), Number(m[2] ?? m[1])];
    for (let n = Math.min(a, b); n <= Math.max(a, b); n++) picked.add(n);
  }
  return moves.filter((r) => picked.has(r.n));
}

async function apply(sel: string) {
  const { rows, mode } = (await Bun.file(PLAN_FILE).json()) as {
    rows: Row[];
    mode: "api" | "mcp";
  };
  const picked = select(
    sel,
    rows.filter((r) => r.kind === "move"),
  );
  if (!picked.length) return console.log("Nothing selected.");
  if (mode === "mcp") {
    for (const r of picked)
      console.log(JSON.stringify({ id: r.identifier, state: r.target }));
    return;
  }
  for (const r of picked) {
    try {
      const d: any = await gql(
        `mutation($id: String!, $stateId: String!) { issueUpdate(id: $id, input: { stateId: $stateId }) { success issue { state { name } } } }`,
        { id: r.issueId, stateId: r.stateId },
      );
      const landed = d.issueUpdate.issue?.state?.name;
      console.log(
        landed === r.target
          ? `ok   ${r.identifier} ${r.now} → ${r.target}`
          : `FAIL ${r.identifier} ${r.now} → ${r.target} (Linear says ${landed ?? "?"})`,
      );
    } catch (e) {
      console.log(`FAIL ${r.identifier}: ${(e as Error).message}`);
    }
  }
}

const [cmd, ...rest] = process.argv.slice(2);
try {
  if (cmd === "project")
    console.log(JSON.stringify(await resolveProject(flag(rest, "--project"))));
  else if (cmd === "plan") await plan(rest);
  else if (cmd === "apply" && rest[0]) await apply(rest[0]);
  else
    throw new Error(
      "usage: linear-grooming.ts project [--project P] | plan [--project P] (--api | --issues F [--enrich E]) | apply <safe|all|1-3,5>",
    );
} catch (e) {
  console.error((e as Error).message);
  process.exit(1);
}
