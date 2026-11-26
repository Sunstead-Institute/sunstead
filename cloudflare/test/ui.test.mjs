// Unit tests for Sunstead web UI scaling helpers (web/app.js, web/index.html, web/proofs.html, web/styles.css).
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");
const WEB_DIR = path.join(REPO_ROOT, "web");
const MISSIONS_DIR = path.join(REPO_ROOT, "missions");

const appJsPath = path.join(WEB_DIR, "app.js");
const appJs = fs.readFileSync(appJsPath, "utf8");
const indexHtml = fs.readFileSync(path.join(WEB_DIR, "index.html"), "utf8");
const proofsHtml = fs.readFileSync(path.join(WEB_DIR, "proofs.html"), "utf8");
const whatIsThisHtml = fs.readFileSync(path.join(WEB_DIR, "what-is-this.html"), "utf8");
const stylesCss = fs.readFileSync(path.join(WEB_DIR, "styles.css"), "utf8");

function plain(value) {
  return JSON.parse(JSON.stringify(value));
}

function loadWebAppContext(extraGlobals = {}) {
  const ctx = vm.createContext({
    URL,
    URLSearchParams,
    console,
    Map,
    Set,
    ...extraGlobals,
  });
  vm.runInContext(appJs, ctx, { filename: "web/app.js" });
  return ctx;
}

function loadAllMissionSummaries() {
  const dirs = fs
    .readdirSync(MISSIONS_DIR)
    .filter((d) => fs.existsSync(path.join(MISSIONS_DIR, d, "sunstead.json")))
    .sort();
  return dirs.map((d) => {
    const m = JSON.parse(fs.readFileSync(path.join(MISSIONS_DIR, d, "sunstead.json"), "utf8"));
    return {
      id: m.id,
      title: m.title,
      tier: m.tier,
      mode: m.mode,
      demo: Boolean(m.demo),
      open_conjecture: Boolean(m.open_conjecture),
      upstream: m.upstream ?? null,
      snapshot: m.snapshot ?? null,
      verifier_toolchain: m.verifier?.toolchain ?? "leanprover/lean4:v4.36.0",
      total_tasks: m.tasks.length,
      verified_tasks: 0,
      refuted_tasks: 0,
      resolved_tasks: 0,
      frontier_task_ids: m.tasks.filter((t) => !(t.depends_on || []).length).map((t) => t.id),
      _raw: m,
    };
  });
}

function makeTask(id, over = {}, defOver = {}) {
  return {
    def: {
      id,
      title: `Theorem ${id}`,
      depends_on: [],
      target_files: [`Mod/${id}.lean`],
      ...defOver,
    },
    status: "open",
    unlocked: true,
    active_lease: null,
    best_score: null,
    verified_by: null,
    attempts: 0,
    ...over,
  };
}

test("web/app.js passes node --check and parses cleanly via Function", () => {
  const res = spawnSync(process.execPath, ["--check", appJsPath], { encoding: "utf8" });
  assert.equal(res.status, 0, res.stderr || "node --check web/app.js failed");
  assert.doesNotThrow(() => new Function(appJs));
});

test("HTML & CSS preserve core hooks and expose filter toolbars and scrollable blueprint stage", () => {
  // Core preserved DOM IDs on index.html
  for (const id of [
    "mission-tabs",
    "completed-missions-section",
    "completed-mission-tabs",
    "dag-stage",
    "dag-svg",
    "dag-empty",
    "task-inspector",
    "mission-filter-bar",
    "mission-category-pills",
    "mission-search",
    "mission-open-only",
    "mission-filter-count",
    "mission-filter-clear",
    "task-filter-bar",
    "task-status-pills",
    "task-search",
    "task-filter-count",
    "task-filter-clear",
  ]) {
    assert.ok(indexHtml.includes(`id="${id}"`), `index.html missing id="${id}"`);
  }
  for (const cat of ["all", "dag", "conjectures", "hillclimb", "repo-snapshot"]) {
    assert.ok(indexHtml.includes(`data-category="${cat}"`), `index.html missing mission category "${cat}"`);
  }
  for (const st of ["all", "ready", "verified", "refuted", "claimed"]) {
    assert.ok(indexHtml.includes(`data-status="${st}"`), `index.html missing task status "${st}"`);
  }

  // Proofs ledger DOM hooks on proofs.html
  for (const id of [
    "ledger-root",
    "ledger-filters",
    "ledger-kind-pills",
    "ledger-mission-filter",
    "ledger-search",
    "ledger-filter-summary",
    "ledger-filter-clear",
    "ledger-list",
    "ledger-more",
  ]) {
    assert.ok(proofsHtml.includes(`id="${id}"`), `proofs.html missing id="${id}"`);
  }
  for (const kind of ["all", "proof", "refutation", "subgoal", "assembled"]) {
    assert.ok(proofsHtml.includes(`data-kind="${kind}"`), `proofs.html missing ledger kind "${kind}"`);
  }

  // Scrollable blueprint stage in styles.css
  assert.match(stylesCss, /\.dag-stage\s*\{[^}]*max-height:\s*760px[^}]*overflow-y:\s*auto[^}]*overflow-x:\s*auto/s);

  // Verification log wraps cleanly without horizontal scrollbar
  assert.match(stylesCss, /\.event-feed\s*\{[^}]*overflow-x:\s*hidden/s);
  assert.match(stylesCss, /\.event-item\s*\{[^}]*min-width:\s*0[^}]*overflow-wrap:\s*anywhere[^}]*word-break:\s*break-word/s);
  assert.match(stylesCss, /\.event-item code\s*\{[^}]*overflow-wrap:\s*anywhere[^}]*word-break:\s*break-word[^}]*min-width:\s*0/s);
});

test("mission filter logic partitions all 47 real arenas and filters by category, search, and open work", () => {
  const ctx = loadWebAppContext();
  const missions = loadAllMissionSummaries();
  assert.equal(missions.length, 47, "expected 47 mission manifests in missions/");

  const counts = ctx.countMissionCategories(missions, { query: "", openOnly: false });
  assert.equal(counts.all, 47);
  assert.equal(counts.dag + counts.conjectures + counts.hillclimb + counts["repo-snapshot"], 47);
  assert.ok(counts.dag > 0 && counts.conjectures > 0 && counts.hillclimb > 0 && counts["repo-snapshot"] > 0);

  // Category predicates
  const dags = ctx.filterMissions(missions, { category: "dag" });
  assert.equal(dags.length, counts.dag);
  assert.ok(
    dags.every((m) => m.mode === "dag" && !m.open_conjecture && m.snapshot?.mode !== "repo-snapshot")
  );

  const conjectures = ctx.filterMissions(missions, { category: "conjectures" });
  assert.equal(conjectures.length, counts.conjectures);
  assert.ok(conjectures.every((m) => m.open_conjecture === true));

  const hillclimbs = ctx.filterMissions(missions, { category: "hillclimb" });
  assert.equal(hillclimbs.length, counts.hillclimb);
  assert.ok(hillclimbs.every((m) => m.mode === "hillclimb"));

  const snapshots = ctx.filterMissions(missions, { category: "repo-snapshot" });
  assert.equal(snapshots.length, counts["repo-snapshot"]);
  assert.ok(snapshots.every((m) => m.snapshot?.mode === "repo-snapshot"));

  // Search on id, title, upstream.repo, verifier_toolchain
  const byId = ctx.filterMissions(missions, { query: "fate-h-fields" });
  assert.deepEqual(byId.map((m) => m.id), ["fate-h-fields-and-groups"]);

  const byToolchain = ctx.filterMissions(missions, { query: "v4.35.0" });
  assert.ok(byToolchain.length > 0 && byToolchain.every((m) => m.verifier_toolchain.includes("v4.35.0")));

  const byUpstream = ctx.filterMissions(missions, { query: "lnsym" });
  assert.ok(
    byUpstream.length > 0 &&
      byUpstream.every(
        (m) =>
          m.id.toLowerCase().includes("lnsym") ||
          m.title.toLowerCase().includes("lnsym") ||
          (m.upstream?.repo || "").toLowerCase().includes("lnsym")
      )
  );

  // Open work only hides missions with empty frontier_task_ids
  const withClosed = missions.map((m, idx) =>
    idx < 5 ? { ...m, frontier_task_ids: [] } : m
  );
  const openOnly = ctx.filterMissions(withClosed, { openOnly: true });
  assert.equal(openOnly.length, missions.length - 5);
  assert.ok(openOnly.every((m) => m.frontier_task_ids.length > 0));
});

test("computeBlueprintLayout switches wide flat packs to crisp multi-column grid and preserves DAG & decomp layouts", () => {
  const ctx = loadWebAppContext();

  // 1. Small flat mission (6 tasks) -> stays layered DAG
  const flat6 = Array.from({ length: 6 }, (_, i) => makeTask(`t_${i + 1}`));
  const lay6 = ctx.computeBlueprintLayout(flat6, [], new Set(), "small-pack");
  assert.equal(lay6.mode, "dag");
  assert.equal(lay6.cols, 1);

  // 2. Medium flat mission (14 tasks) -> 3-column grid
  const flat14 = Array.from({ length: 14 }, (_, i) => makeTask(`t_${i + 1}`));
  const lay14 = ctx.computeBlueprintLayout(flat14, [], new Set(), "med-pack");
  assert.equal(lay14.mode, "grid");
  assert.equal(lay14.cols, 3);
  assert.equal(lay14.rows, 5);
  assert.equal(lay14.nodeW, 252);
  assert.equal(lay14.nodeH, 92);
  assert.equal(lay14.colGap, 18);
  assert.equal(lay14.rowGap, 18);
  assert.equal(lay14.width, 828);
  assert.ok(lay14.width <= 840, `grid width (${lay14.width}px) must fit 1280x800 blueprint pane without horizontal scroll`);
  assert.equal(lay14.pos.size, 14);

  // 3. Real 50-task flat mission (fate-h-fields-and-groups) -> 3-column grid, 17 rows, width <= 840, zero overlaps
  const fateManifest = JSON.parse(
    fs.readFileSync(path.join(MISSIONS_DIR, "fate-h-fields-and-groups", "sunstead.json"), "utf8")
  );
  const fateTasks = fateManifest.tasks.map((def) => makeTask(def.id, {}, def));
  assert.equal(fateTasks.length, 50);
  const lay50 = ctx.computeBlueprintLayout(fateTasks, [], new Set(), fateManifest.id);
  assert.equal(lay50.mode, "grid");
  assert.equal(lay50.cols, 3);
  assert.equal(lay50.rows, 17);
  assert.equal(lay50.nodeW, 252);
  assert.equal(lay50.width, 18 * 2 + 3 * 252 + 2 * 18);
  assert.equal(lay50.width, 828);
  assert.ok(lay50.width <= 840, `50-task grid width (${lay50.width}px) must fit cleanly at 1280x800`);
  assert.equal(lay50.height, 24 * 2 + 17 * 92 + 16 * 18);
  const boxes = [...lay50.pos.values()];
  assert.equal(boxes.length, 50);
  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i];
      const b = boxes[j];
      const overlaps =
        a.x < b.x + lay50.nodeW &&
        a.x + lay50.nodeW > b.x &&
        a.y < b.y + lay50.nodeH &&
        a.y + lay50.nodeH > b.y;
      assert.equal(overlaps, false, `grid nodes ${i} and ${j} must not overlap`);
    }
  }

  // 4. Mission with real depends_on edge (> 6 tasks) -> preserves layered DAG
  const dagTasks = Array.from({ length: 10 }, (_, i) =>
    makeTask(`d_${i}`, {}, { depends_on: i === 9 ? ["d_0"] : [] })
  );
  const layDag = ctx.computeBlueprintLayout(dagTasks, [], new Set(), "real-dag");
  assert.equal(layDag.mode, "dag");
  assert.equal(layDag.cols, 2);
  assert.ok(layDag.pos.get("d_9").x > layDag.pos.get("d_0").x);

  // 5. Expanded active decomposition on flat 10-task mission -> preserves layered DAG
  const decompTasks = [
    ...Array.from({ length: 8 }, (_, i) => makeTask(`r_${i}`)),
    makeTask("r_0__d1__s1", {}, { parent_task_id: "r_0", decomp_id: "d1", subgoal_id: "s1" }),
    makeTask("r_0__d1__s2", {}, { parent_task_id: "r_0", decomp_id: "d1", subgoal_id: "s2" }),
  ];
  const activeDecomps = [{ parent_task_id: "r_0", decomp_id: "d1", status: "active" }];
  const layExpanded = ctx.computeBlueprintLayout(decompTasks, activeDecomps, new Set(), "m1");
  assert.equal(layExpanded.mode, "dag");
  assert.equal(layExpanded.cols, 2);

  // 6. Collapsed active decomposition (subgoals filtered out) -> flat grid with extra rowGap for pill
  const collapsed = new Set([ctx.decompClusterKey("m1", "r_0", "d1")]);
  const rootOnly = decompTasks.filter((t) => !t.def.decomp_id);
  const layCollapsed = ctx.computeBlueprintLayout(rootOnly, activeDecomps, collapsed, "m1");
  assert.equal(layCollapsed.mode, "grid");
  assert.equal(layCollapsed.rowGap, 26);
});

test("task filter logic classifies Ready, Verified, Refuted, Claimed, and searches id/title", () => {
  const ctx = loadWebAppContext();
  const tasks = [
    makeTask("ready_t", { status: "open", unlocked: true }, { title: "Open Lemma" }),
    makeTask("verified_t", { status: "verified", unlocked: true }, { title: "Proved Lemma" }),
    makeTask("refuted_t", { status: "refuted", unlocked: true }, { title: "Disproved Conjecture" }),
    makeTask(
      "claimed_t",
      { status: "open", unlocked: true, active_lease: { contributor: "alice" } },
      { title: "Leased Theorem" }
    ),
    makeTask("blocked_t", { status: "open", unlocked: false }, { title: "Waiting Theorem" }),
    makeTask(
      "disputed_t",
      { status: "open", unlocked: true, disputed_counterexample: { refuter: "bob" } },
      { title: "Disputed Theorem" }
    ),
  ];

  const dagCounts = plain(ctx.countTaskStatuses(tasks, "dag", ""));
  assert.deepEqual(dagCounts, { all: 6, ready: 1, verified: 1, refuted: 1, claimed: 1 });
  assert.deepEqual(
    plain(ctx.filterBlueprintTasks(tasks, "dag", { status: "ready" }).map((t) => t.def.id)),
    ["ready_t"]
  );
  assert.deepEqual(
    plain(ctx.filterBlueprintTasks(tasks, "dag", { status: "refuted" }).map((t) => t.def.id)),
    ["refuted_t"]
  );
  assert.deepEqual(
    plain(ctx.filterBlueprintTasks(tasks, "dag", { status: "claimed" }).map((t) => t.def.id)),
    ["claimed_t"]
  );
  assert.deepEqual(
    plain(ctx.filterBlueprintTasks(tasks, "dag", { query: "conjecture" }).map((t) => t.def.id)),
    ["refuted_t"]
  );

  // In hillclimb mode, verified unleased tasks remain ready to improve (RECORD · OPEN)
  const hcCounts = ctx.countTaskStatuses(tasks, "hillclimb", "");
  assert.equal(hcCounts.ready, 2);
});

test("URL deep-linking parses query params and preserves hash fragments via buildDeepLinkUrl", () => {
  const ctx = loadWebAppContext();
  assert.deepEqual(plain(ctx.parseDeepLink("?mission=fate-h-fields-and-groups&task=thm_12")), {
    mission: "fate-h-fields-and-groups",
    task: "thm_12",
  });
  assert.deepEqual(plain(ctx.parseDeepLink("?mission=  ")), { mission: null, task: null });
  assert.deepEqual(plain(ctx.parseDeepLink("")), { mission: null, task: null });

  assert.equal(
    ctx.buildDeepLinkUrl("https://sunstead.org/#blueprint", "fc-open-oeis-classics", "conj_7"),
    "/?mission=fc-open-oeis-classics&task=conj_7#blueprint"
  );
  assert.equal(
    ctx.buildDeepLinkUrl("https://sunstead.org/?foo=1&mission=old&task=old_t#blueprint", "new-m", null),
    "/?foo=1&mission=new-m#blueprint"
  );
});

test("proofs ledger filtering handles entry kinds, mission dropdown, search, and counts", () => {
  const ctx = loadWebAppContext();
  const proofs = [
    {
      proof_id: "a".repeat(64),
      mission_id: "pnt-analytic-foundations",
      mission_title: "PNT+ analytic foundations",
      task_id: "liouville",
      task_title: "Liouville lemma",
      contributor: "alice",
      display_name: "Alice Euler",
      entry_kind: "proof",
    },
    {
      proof_id: "b".repeat(64),
      mission_id: "fc-open-oeis-classics",
      mission_title: "OEIS Classics",
      task_id: "oeis_42",
      task_title: "Counterexample target",
      contributor: "bob",
      display_name: "Bob Refuter",
      entry_kind: "refutation",
    },
    {
      proof_id: "c".repeat(64),
      mission_id: "arklib-near-capacity-primes",
      mission_title: "ArkLib",
      task_id: "root__d1__s1",
      task_title: "Subgoal 1",
      contributor: "carol",
      display_name: "Carol",
      entry_kind: "subgoal",
    },
    {
      proof_id: "d".repeat(64),
      mission_id: "arklib-near-capacity-primes",
      mission_title: "ArkLib",
      task_id: "near_capacity_prime_supply",
      task_title: "Near-capacity primes",
      contributor: "dave",
      display_name: "Dave",
      entry_kind: "assembled",
      co_authors: [{ handle: "carol", display_name: "Carol Solver", role: "solver" }],
    },
    {
      proof_id: "e".repeat(64),
      mission_id: "pnt-analytic-foundations",
      mission_title: "PNT+ analytic foundations",
      task_id: "legacy_row",
      task_title: "Legacy proof without entry_kind",
      contributor: "eve",
      display_name: "Eve",
    },
  ];

  assert.deepEqual(plain(ctx.countLedgerKinds(proofs, {})), {
    all: 5,
    proof: 2,
    refutation: 1,
    subgoal: 1,
    assembled: 1,
  });
  assert.deepEqual(
    plain(ctx.filterLedgerProofs(proofs, { kind: "refutation" }).map((p) => p.task_id)),
    ["oeis_42"]
  );
  assert.deepEqual(
    plain(ctx.filterLedgerProofs(proofs, { kind: "proof" }).map((p) => p.task_id)),
    ["liouville", "legacy_row"]
  );
  assert.deepEqual(
    plain(ctx.filterLedgerProofs(proofs, { missionId: "arklib-near-capacity-primes" }).map((p) => p.task_id)),
    ["root__d1__s1", "near_capacity_prime_supply"]
  );
  assert.deepEqual(
    plain(ctx.filterLedgerProofs(proofs, { query: "carol" }).map((p) => p.task_id)),
    ["root__d1__s1", "near_capacity_prime_supply"]
  );
  assert.deepEqual(
    plain(ctx.filterLedgerProofs(proofs, { query: "bbbbbbbb" }).map((p) => p.task_id)),
    ["oeis_42"]
  );
});

test("renderDag sets explicit full-size SVG dimensions for flat grids and resets cleanly for small DAGs", () => {
  const mkEl = () => {
    const attrs = {};
    const classes = new Set();
    return {
      attrs,
      style: {},
      innerHTML: "",
      classList: {
        add: (c) => classes.add(c),
        remove: (c) => classes.delete(c),
        toggle: (c, f) => (f ? classes.add(c) : classes.delete(c)),
        contains: (c) => classes.has(c),
      },
      setAttribute: (k, v) => {
        attrs[k] = String(v);
      },
      querySelectorAll: () => [],
      addEventListener: () => {},
    };
  };
  const svgEl = mkEl();
  const emptyEl = mkEl();
  const replaced = [];
  const ctx = loadWebAppContext({
    document: {
      getElementById: (id) => (id === "dag-svg" ? svgEl : id === "dag-empty" ? emptyEl : null),
      querySelectorAll: () => [],
      addEventListener: () => {},
    },
    history: {
      replaceState: (_s, _t, u) => replaced.push(u),
    },
  });
  // Inject window AFTER script load so init() doesn't fire during load, then test syncUrlDeepLink + renderDag.
  ctx.window = { location: { href: "https://sunstead.org/#blueprint" } };

  const flat25 = {
    mission: { manifest: { id: "fc-open-oeis-classics", mode: "dag", open_conjecture: true } },
    tasks: Array.from({ length: 25 }, (_, i) =>
      makeTask(
        `very_long_conjecture_identifier_number_${i + 1}`,
        { verified_by: i === 0 ? "contributor_with_a_very_long_handle_name" : null },
        { title: `Extremely Long Conjecture Title #${i + 1} That Must Truncate Cleanly Inside 252px` }
      )
    ),
    decompositions: [],
  };
  ctx.renderDag(flat25);
  assert.equal(svgEl.style.width, "100%");
  assert.equal(svgEl.style.maxWidth, "828px");
  assert.equal(svgEl.style.height, "auto");
  assert.equal(svgEl.style.aspectRatio, "828 / 1020");
  assert.equal(svgEl.style.minHeight, "0");
  assert.equal(svgEl.attrs.viewBox, "0 0 828 1020");
  assert.ok(svgEl.innerHTML.includes('id="dag-card-clip"'), "grid cards should render inner clipPath");
  assert.ok(svgEl.innerHTML.includes("…"), "long title/id/footer text should truncate cleanly with ellipsis");

  // Switching to a small 2-task layered DAG clears responsive flat-grid sizing.
  const smallDag = {
    mission: { manifest: { id: "small-dag", mode: "dag" } },
    tasks: [makeTask("a"), makeTask("b", {}, { depends_on: ["a"] })],
    decompositions: [],
  };
  ctx.renderDag(smallDag);
  assert.equal(svgEl.style.width, "");
  assert.equal(svgEl.style.maxWidth, "");
  assert.equal(svgEl.style.height, "");
  assert.equal(svgEl.style.aspectRatio, "");
  assert.equal(svgEl.attrs.viewBox, "0 0 780 350");

  ctx.syncUrlDeepLink("fc-open-oeis-classics", "t_7");
  assert.deepEqual(replaced, ["/?mission=fc-open-oeis-classics&task=t_7#blueprint"]);
});

test("web/what-is-this.html reflects current live arenas, wraps code snippets, and has no inline scripts", () => {
  assert.ok(!whatIsThisHtml.includes("across 5 Arenas"), "what-is-this.html must not contain stale 'across 5 Arenas' text");
  for (const required of [
    "Refuted ¬T",
    "best_known",
    "Sphere Packing",
    "Formal Conjectures",
    "/api/frontier",
    "get_open_frontier",
    "47 live arenas spanning 605 tasks",
    "10 Verbatim Arenas",
    "Disputed ¬T",
  ]) {
    assert.ok(whatIsThisHtml.includes(required), `what-is-this.html missing expected text: ${required}`);
  }

  // Zero inline <script> tags (only external <script src="..."> allowed)
  const scripts = [...whatIsThisHtml.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
  assert.ok(scripts.length >= 1, "expected external script tag");
  for (const [, attrs, body] of scripts) {
    assert.match(attrs, /\bsrc=/i, "every <script> tag in what-is-this.html must load an external src");
    assert.equal(body.trim(), "", "inline <script> body is forbidden in what-is-this.html");
  }

  // Section 02 code snippets stay within 50 chars/line so they never clip at 1280x800
  const snippets = [...whatIsThisHtml.matchAll(/<pre class="code-snippet"><code>([\s\S]*?)<\/code><\/pre>/g)];
  assert.equal(snippets.length, 2, "expected BEFORE and AFTER code snippets in Section 02");
  for (const [, code] of snippets) {
    for (const line of code.split("\n")) {
      assert.ok(
        line.length <= 50,
        `code-snippet line exceeds 50 chars (${line.length}): ${line}`
      );
    }
  }
});

test("UI card and ledger row rendering escape all dynamic strings against XSS", () => {
  const ctx = loadWebAppContext();
  const xss = `"><script>alert(1)</script><img src=x onerror=alert(2)>`;
  const cardHtml = ctx.renderMissionCardHtml(
    {
      id: xss,
      title: xss,
      tier: 1,
      mode: "dag",
      total_tasks: 10,
      verified_tasks: 2,
      refuted_tasks: 0,
      open_conjecture: true,
      snapshot: { mode: "repo-snapshot" },
    },
    false
  );
  assert.ok(!cardHtml.includes("<script>"), "mission card must escape <script>");
  assert.ok(!cardHtml.includes("<img "), "mission card must escape <img");
  assert.ok(cardHtml.includes("&lt;script&gt;"));

  const rowHtml = ctx.ledgerRowHtml({
    proof_id: "a".repeat(64),
    mission_id: xss,
    mission_title: xss,
    task_id: xss,
    task_title: xss,
    contributor: xss,
    display_name: xss,
    accepted_at: 1_790_000_000,
    upstream: { repo: xss, commit: "1234567", license: xss, task_url: "javascript:alert(1)" },
  });
  assert.ok(!rowHtml.includes("<script>"), "ledger row must escape <script>");
  assert.ok(!rowHtml.includes("javascript:alert"), "ledger row must reject javascript: URLs");
});
