const state = {
  missions: [],
  activeMissionId: null,
  activeDetail: null,
  selectedTaskId: null,
  events: [],
  proofCache: new Map(), // "mission/task" -> accepted proof JSON
  collapsedDecomps: new Set(), // "mission:parent:decomp_id"
  missionFilter: { category: "all", query: "", openOnly: false },
  taskFilter: { status: "all", query: "" },
  pendingDeepLink: null,
  detailRequestSeq: 0,
};

const $ = (id) => document.getElementById(id);

function escapeHtml(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function fmtTime(unixSec) {
  if (!unixSec) return "";
  return new Date(unixSec * 1000).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

async function fetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

/**
 * Render the Sunstead "Strange Attractor" phase-space trajectory artwork in the Deep Indigo hero:
 * branching gossamer trajectories on the left flowing into a Cyan Teal & Antique Gold basin on the right.
 */
function renderAttractorArt() {
  const svg = $("attractor-svg");
  if (!svg) return;
  const cx = 965;
  const cy = 215;
  let html = `<defs>
    <radialGradient id="basin-glow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#C6A15A" stop-opacity="0.55" />
      <stop offset="28%" stop-color="#2A7D7F" stop-opacity="0.35" />
      <stop offset="70%" stop-color="#2A7D7F" stop-opacity="0.06" />
      <stop offset="100%" stop-color="#0D1B3D" stop-opacity="0" />
    </radialGradient>
    <linearGradient id="traj-gold" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#F4F1EA" stop-opacity="0.06" />
      <stop offset="55%" stop-color="#F4F1EA" stop-opacity="0.34" />
      <stop offset="100%" stop-color="#C6A15A" stop-opacity="0.85" />
    </linearGradient>
    <linearGradient id="traj-teal" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#2A7D7F" stop-opacity="0.08" />
      <stop offset="100%" stop-color="#4AA6A8" stop-opacity="0.52" />
    </linearGradient>
  </defs>`;

  html += `<circle cx="${cx}" cy="${cy}" r="210" fill="url(#basin-glow)" />`;

  // Concentric perturbed attractor orbits around (cx, cy)
  for (let i = 0; i < 24; i++) {
    const rx = 24 + i * 10.5;
    const ry = 16 + i * 7.8;
    const rot = -14 + i * 0.7;
    const isGold = i % 5 === 0 || i < 3;
    const stroke = isGold ? "#C6A15A" : "#4AA6A8";
    const opacity = Math.max(0.08, 0.56 - i * 0.019).toFixed(3);
    html += `<ellipse cx="${cx + (i % 3) * 2}" cy="${cy + (i % 2) * 1.5}" rx="${rx.toFixed(1)}" ry="${ry.toFixed(1)}"
      transform="rotate(${rot.toFixed(1)} ${cx} ${cy})"
      fill="none" stroke="${stroke}" stroke-width="${isGold ? 0.95 : 0.7}" opacity="${opacity}" />`;
  }

  // Incoming phase-space trajectories converging into the attractor neck
  for (let i = 0; i < 26; i++) {
    const t = i / 25;
    const y0 = 15 + t * 390;
    const x0 = 430 + Math.sin(i * 1.7) * 90;
    const c1x = 650 + (i % 4) * 18;
    const c1y = y0 * 0.45 + cy * 0.55;
    const c2x = 815;
    const c2y = cy + (t - 0.5) * 42;
    const isGold = i % 3 === 0;
    html += `<path d="M ${x0.toFixed(1)} ${y0.toFixed(1)} C ${c1x.toFixed(1)} ${c1y.toFixed(1)}, ${c2x} ${c2y.toFixed(1)}, ${cx} ${cy}"
      fill="none" stroke="${isGold ? "url(#traj-gold)" : "url(#traj-teal)"}" stroke-width="${isGold ? 1.05 : 0.75}" />`;

    // Subtle trajectory anchor nodes
    const mx = x0 * 0.55 + c1x * 0.45;
    const my = y0 * 0.6 + c1y * 0.4;
    html += `<circle cx="${mx.toFixed(1)}" cy="${my.toFixed(1)}" r="${isGold ? 1.7 : 1.2}"
      fill="${isGold ? "#C6A15A" : "#8EE0E2"}" opacity="0.55" />`;
  }

  // Luminous antique-gold focal core
  html += `<circle cx="${cx}" cy="${cy}" r="11" fill="#2A7D7F" opacity="0.45" />`;
  html += `<circle cx="${cx}" cy="${cy}" r="4.5" fill="#C6A15A" />`;
  html += `<circle cx="${cx}" cy="${cy}" r="2" fill="#F4F1EA" />`;

  svg.innerHTML = html;
}

async function loadHealth() {
  const pill = $("health-pill");
  if (!pill) return;
  try {
    const h = await fetchJson("/api/health");
    if (h.docker_verifier_ready) {
      pill.textContent = h.verifier_label || "Verifier Ready · Lean 4";
      pill.className = "pill pill-ok";
    } else {
      pill.textContent = "Hub Online · No Verifier";
      pill.className = "pill pill-warn";
    }
  } catch {
    pill.textContent = "Hub Offline";
    pill.className = "pill pill-muted";
  }
}

function resolvedTaskCount(m) {
  if (!m) return 0;
  if (typeof m.resolved_tasks === "number") return m.resolved_tasks;
  return (m.verified_tasks || 0) + (m.refuted_tasks || 0);
}

function isOpenConjectureTaskDef(manifest, def) {
  if (!def || def.decomp_id) return false;
  if (typeof def.open_conjecture === "boolean") return def.open_conjecture;
  return Boolean(manifest && manifest.open_conjecture);
}

function isMissionCompleted(m) {
  const resolved = typeof m?.resolved_tasks === "number"
    ? m.resolved_tasks
    : (m?.verified_tasks || 0) + (m?.refuted_tasks || 0);
  if (!m || m.total_tasks <= 0) return false;
  return m.mode === "hillclimb" ? (m.proven_optimal_tasks || 0) >= m.total_tasks : resolved >= m.total_tasks;
}

function optimalityCitation(mode, task) {
  const citation = task.def?.best_known?.proven_optimal;
  return mode === "hillclimb" && citation?.source && safeHttpUrl(citation.url) ? citation : null;
}

// ---------------- Pure Filter, Layout & Deep-Link Helpers ----------------

function matchesMissionCategory(m, category) {
  if (!m) return false;
  if (!category || category === "all") return true;
  if (category === "dag") {
    return m.mode === "dag" && !m.open_conjecture && m.snapshot?.mode !== "repo-snapshot";
  }
  if (category === "conjectures") {
    return m.open_conjecture === true;
  }
  if (category === "hillclimb") {
    return m.mode === "hillclimb";
  }
  if (category === "repo-snapshot") {
    return m.snapshot?.mode === "repo-snapshot";
  }
  return true;
}

function matchesMissionQuery(m, query) {
  const q = String(query ?? "").trim().toLowerCase();
  if (!q) return true;
  const haystacks = [
    m?.id,
    m?.title,
    m?.upstream?.repo,
    m?.verifier_toolchain,
  ];
  return haystacks.some((val) => typeof val === "string" && val.toLowerCase().includes(q));
}

function missionHasOpenWork(m) {
  return Array.isArray(m?.frontier_task_ids) && m.frontier_task_ids.length > 0;
}

function filterMissions(missions, filters = {}) {
  const list = Array.isArray(missions) ? missions : [];
  const category = filters.category || "all";
  const query = filters.query || "";
  const openOnly = Boolean(filters.openOnly);
  return list.filter(
    (m) =>
      matchesMissionCategory(m, category) &&
      matchesMissionQuery(m, query) &&
      (!openOnly || missionHasOpenWork(m))
  );
}

function countMissionCategories(missions, filters = {}) {
  const list = Array.isArray(missions) ? missions : [];
  const query = filters.query || "";
  const openOnly = Boolean(filters.openOnly);
  const base = list.filter(
    (m) => matchesMissionQuery(m, query) && (!openOnly || missionHasOpenWork(m))
  );
  return {
    all: base.length,
    dag: base.filter((m) => matchesMissionCategory(m, "dag")).length,
    conjectures: base.filter((m) => matchesMissionCategory(m, "conjectures")).length,
    hillclimb: base.filter((m) => matchesMissionCategory(m, "hillclimb")).length,
    "repo-snapshot": base.filter((m) => matchesMissionCategory(m, "repo-snapshot")).length,
  };
}

function isTaskReady(task, mode) {
  if (!task || !task.unlocked) return false;
  if (task.disputed_counterexample || (task.def && task.def.upstream_disputed)) return false;
  if (task.active_lease) return false;
  if (task.status === "refuted") return false;
  if (mode === "hillclimb") return true;
  return task.status !== "verified";
}

function matchesTaskStatus(task, mode, status) {
  if (!task) return false;
  if (!status || status === "all") return true;
  if (status === "ready") return isTaskReady(task, mode);
  if (status === "verified") return task.status === "verified";
  if (status === "refuted") return task.status === "refuted";
  if (status === "claimed") return Boolean(task.active_lease);
  return true;
}

function matchesTaskQuery(task, query) {
  const q = String(query ?? "").trim().toLowerCase();
  if (!q) return true;
  const haystacks = [task?.def?.id, task?.def?.title, task?.def?.subgoal_id];
  return haystacks.some((val) => typeof val === "string" && val.toLowerCase().includes(q));
}

function filterBlueprintTasks(tasks, mode, filters = {}) {
  const list = Array.isArray(tasks) ? tasks : [];
  const status = filters.status || "all";
  const query = filters.query || "";
  return list.filter(
    (t) => matchesTaskStatus(t, mode, status) && matchesTaskQuery(t, query)
  );
}

function countTaskStatuses(tasks, mode, query = "") {
  const list = Array.isArray(tasks) ? tasks : [];
  const base = list.filter((t) => matchesTaskQuery(t, query));
  return {
    all: base.length,
    ready: base.filter((t) => matchesTaskStatus(t, mode, "ready")).length,
    verified: base.filter((t) => matchesTaskStatus(t, mode, "verified")).length,
    refuted: base.filter((t) => matchesTaskStatus(t, mode, "refuted")).length,
    claimed: base.filter((t) => matchesTaskStatus(t, mode, "claimed")).length,
  };
}

function parseDeepLink(search) {
  const params = new URLSearchParams(search || "");
  const mission = (params.get("mission") || "").trim() || null;
  const task = (params.get("task") || "").trim() || null;
  return { mission, task };
}

function buildDeepLinkUrl(currentHref, missionId, taskId) {
  const url = new URL(currentHref);
  if (missionId) url.searchParams.set("mission", missionId);
  else url.searchParams.delete("mission");
  if (taskId) url.searchParams.set("task", taskId);
  else url.searchParams.delete("task");
  return `${url.pathname}${url.search}${url.hash}`;
}

function syncUrlDeepLink(missionId, taskId) {
  if (
    typeof window === "undefined" ||
    typeof history === "undefined" ||
    typeof history.replaceState !== "function"
  ) {
    return;
  }
  const next = buildDeepLinkUrl(window.location.href, missionId, taskId);
  history.replaceState(null, "", next);
}

function normalizeLedgerEntryKind(entry) {
  const kind = entry?.entry_kind;
  if (kind === "refutation" || kind === "subgoal" || kind === "assembled") return kind;
  return "proof";
}

function matchesLedgerQuery(entry, query) {
  const q = String(query ?? "").trim().toLowerCase();
  if (!q) return true;
  const haystacks = [
    entry?.contributor,
    entry?.display_name,
    entry?.github,
    entry?.task_id,
    entry?.task_title,
    entry?.mission_id,
    entry?.mission_title,
    entry?.proof_id,
  ];
  if (Array.isArray(entry?.co_authors)) {
    for (const ca of entry.co_authors) {
      haystacks.push(ca?.handle, ca?.display_name);
    }
  }
  return haystacks.some((val) => typeof val === "string" && val.toLowerCase().includes(q));
}

function filterLedgerProofs(proofs, filters = {}) {
  const list = Array.isArray(proofs) ? proofs : [];
  const missionId = String(filters.missionId || "").trim();
  const kind = filters.kind || "all";
  const query = filters.query || "";
  return list.filter((p) => {
    if (missionId && p?.mission_id !== missionId) return false;
    if (kind !== "all" && normalizeLedgerEntryKind(p) !== kind) return false;
    return matchesLedgerQuery(p, query);
  });
}

function countLedgerKinds(proofs, filters = {}) {
  const list = Array.isArray(proofs) ? proofs : [];
  const missionId = String(filters.missionId || "").trim();
  const query = filters.query || "";
  const base = list.filter(
    (p) => (!missionId || p?.mission_id === missionId) && matchesLedgerQuery(p, query)
  );
  return {
    all: base.length,
    proof: base.filter((p) => normalizeLedgerEntryKind(p) === "proof").length,
    refutation: base.filter((p) => normalizeLedgerEntryKind(p) === "refutation").length,
    subgoal: base.filter((p) => normalizeLedgerEntryKind(p) === "subgoal").length,
    assembled: base.filter((p) => normalizeLedgerEntryKind(p) === "assembled").length,
  };
}

async function loadMissions() {
  const data = await fetchJson("/api/missions");
  state.missions = data.missions || [];

  const totalTasks = state.missions.reduce((acc, m) => acc + m.total_tasks, 0);
  const resolvedTasks = state.missions.reduce((acc, m) => acc + resolvedTaskCount(m), 0);
  const refutedTasks = state.missions.reduce((acc, m) => acc + (m.refuted_tasks || 0), 0);
  const openFrontier = state.missions.reduce((acc, m) => acc + (m.frontier_task_ids?.length || 0), 0);
  $("stat-verified").textContent = `${resolvedTasks}/${totalTasks}`;
  $("stat-verified").title = refutedTasks > 0
    ? `${resolvedTasks - refutedTasks} proved + ${refutedTasks} refuted (¬T) out of ${totalTasks} tasks`
    : "";
  $("stat-frontier").textContent = `${openFrontier}`;
  $("stat-missions").textContent = `${state.missions.length}`;

  if (state.pendingDeepLink) {
    const { mission, task } = state.pendingDeepLink;
    state.pendingDeepLink = null;
    if (mission && state.missions.some((m) => m.id === mission)) {
      state.activeMissionId = mission;
      state.selectedTaskId = task || null;
    }
  }

  if (
    state.missions.length > 0 &&
    (!state.activeMissionId || !state.missions.some((m) => m.id === state.activeMissionId))
  ) {
    const firstActive = state.missions.find((m) => !isMissionCompleted(m)) || state.missions[0];
    state.activeMissionId = firstActive.id;
    state.selectedTaskId = null;
  }
  renderMissionTabs();
  if (state.activeMissionId) {
    await loadMissionDetail(state.activeMissionId);
  }
}

function renderMissionCardHtml(m, completed) {
  const resolved = resolvedTaskCount(m);
  const refuted = m.refuted_tasks || 0;
  const optimal = m.proven_optimal_tasks || 0;
  const pct = m.total_tasks > 0 ? Math.round(((optimal || resolved) / m.total_tasks) * 100) : 0;
  const active = m.id === state.activeMissionId ? "active" : "";
  const doneClass = completed ? "mission-tab-completed" : "";
  const modeLabel =
    m.mode === "hillclimb"
      ? "HILL-CLIMB"
      : completed
        ? "COMPLETE"
        : m.open_conjecture
          ? "CONJECTURES"
          : "BLUEPRINT";
  const countText = optimal > 0
    ? `${optimal}/${m.total_tasks} optimal`
    : refuted > 0 ? `${resolved}/${m.total_tasks} (${refuted} ¬T)` : `${resolved}/${m.total_tasks}`;
  const conjectureBadge = m.open_conjecture
    ? `<span class="badge-conjecture" title="Two-sided open conjecture: prove T or refute ¬T for full credit">T OR ¬T</span>`
    : "";
  const snapshotBadge = m.snapshot?.mode === "repo-snapshot"
    ? `<span class="badge-snapshot" title="Repo-snapshot mission pinned to full upstream Lean 4 repository">SNAPSHOT</span>`
    : "";
  const demoBadge = m.demo
    ? `<span class="badge-demo" title="Protocol sandbox: awards 0 leaderboard points">SANDBOX</span>`
    : "";
  return `
    <button class="mission-tab ${doneClass} ${active}" data-id="${escapeHtml(m.id)}">
      <div class="tab-top">
        <span style="display:inline-flex;align-items:center;gap:6px;flex-wrap:wrap"><span class="badge-gold">Tier ${m.tier}</span>${conjectureBadge}${snapshotBadge}${demoBadge}</span>
        <span class="badge-teal">${modeLabel} · ${countText}</span>
      </div>
      <div class="tab-title">${escapeHtml(m.title)}</div>
      <div class="muted small" style="font-family:var(--mono)">${escapeHtml(m.id)}</div>
      <div class="progress-track"><div class="progress-fill" style="width:${pct}%"></div></div>
    </button>
  `;
}

function isMissionFilterActive() {
  return (
    state.missionFilter.category !== "all" ||
    state.missionFilter.query.trim() !== "" ||
    state.missionFilter.openOnly
  );
}

function resetMissionFilters() {
  state.missionFilter = { category: "all", query: "", openOnly: false };
  const searchEl = $("mission-search");
  if (searchEl) searchEl.value = "";
  const openEl = $("mission-open-only");
  if (openEl) openEl.checked = false;
  renderMissionTabs();
}

function resetTaskFilters() {
  state.taskFilter = { status: "all", query: "" };
  const searchEl = $("task-search");
  if (searchEl) searchEl.value = "";
}

function updateMissionFilterUi(shownCount, totalCount) {
  const counts = countMissionCategories(state.missions, {
    query: state.missionFilter.query,
    openOnly: state.missionFilter.openOnly,
  });
  const pillsRoot = $("mission-category-pills");
  if (pillsRoot) {
    pillsRoot.querySelectorAll(".filter-pill").forEach((btn) => {
      const cat = btn.dataset.category || "all";
      btn.classList.toggle("active", cat === state.missionFilter.category);
      const badge = btn.querySelector(".pill-count");
      if (badge) badge.textContent = String(counts[cat] ?? 0);
    });
  }
  const countEl = $("mission-filter-count");
  if (countEl) {
    countEl.textContent = `Showing ${shownCount} of ${totalCount} mission${totalCount === 1 ? "" : "s"}`;
  }
  const clearEl = $("mission-filter-clear");
  if (clearEl) {
    clearEl.classList.toggle("hidden", !isMissionFilterActive());
  }
}

function setupMissionFilters() {
  const pillsRoot = $("mission-category-pills");
  if (pillsRoot) {
    pillsRoot.querySelectorAll(".filter-pill").forEach((btn) => {
      btn.addEventListener("click", () => {
        state.missionFilter.category = btn.dataset.category || "all";
        renderMissionTabs();
      });
    });
  }
  const searchEl = $("mission-search");
  if (searchEl) {
    searchEl.addEventListener("input", () => {
      state.missionFilter.query = searchEl.value;
      renderMissionTabs();
    });
  }
  const openEl = $("mission-open-only");
  if (openEl) {
    openEl.addEventListener("change", () => {
      state.missionFilter.openOnly = openEl.checked;
      renderMissionTabs();
    });
  }
  const clearEl = $("mission-filter-clear");
  if (clearEl) {
    clearEl.addEventListener("click", resetMissionFilters);
  }
}

function renderMissionTabs() {
  const activeContainer = $("mission-tabs");
  const completedSection = $("completed-missions-section");
  const completedContainer = $("completed-mission-tabs");
  const completedCount = $("completed-missions-count");

  const filtered = filterMissions(state.missions, state.missionFilter);
  updateMissionFilterUi(filtered.length, state.missions.length);

  const activeMissions = filtered.filter((m) => !isMissionCompleted(m));
  const completedMissions = filtered.filter((m) => isMissionCompleted(m));

  if (filtered.length === 0) {
    activeContainer.innerHTML = `
      <div class="filter-empty">
        <div>No missions match your current filters.</div>
        <button type="button" class="filter-clear" id="mission-empty-clear">Clear filters</button>
      </div>
    `;
    const emptyClear = $("mission-empty-clear");
    if (emptyClear) emptyClear.addEventListener("click", resetMissionFilters);
  } else if (activeMissions.length === 0) {
    activeContainer.innerHTML = `
      <div class="filter-empty">
        <div>All matching missions are in the Completed Showcase below.</div>
      </div>
    `;
  } else {
    activeContainer.innerHTML = activeMissions.map((m) => renderMissionCardHtml(m, false)).join("");
  }

  if (completedSection && completedContainer) {
    if (completedMissions.length > 0) {
      completedSection.classList.remove("hidden");
      if (completedCount) {
        completedCount.textContent = `${completedMissions.length} completed mission${completedMissions.length === 1 ? "" : "s"}`;
      }
      completedContainer.innerHTML = completedMissions.map((m) => renderMissionCardHtml(m, true)).join("");
    } else {
      completedSection.classList.add("hidden");
      completedContainer.innerHTML = "";
    }
  }

  const wire = (root) => {
    if (!root) return;
    root.querySelectorAll(".mission-tab").forEach((btn) => {
      btn.addEventListener("click", () => {
        const nextId = btn.dataset.id;
        if (nextId !== state.activeMissionId) {
          resetTaskFilters();
        }
        state.activeMissionId = nextId;
        state.selectedTaskId = null;
        syncUrlDeepLink(state.activeMissionId, null);
        renderMissionTabs();
        loadMissionDetail(state.activeMissionId, { syncUrl: true });
      });
    });
  };
  wire(activeContainer);
  wire(completedContainer);
}

async function loadMissionDetail(missionId, opts = {}) {
  const reqSeq = ++state.detailRequestSeq;
  const detail = await fetchJson(`/api/missions/${encodeURIComponent(missionId)}`);
  if (reqSeq !== state.detailRequestSeq) return;
  state.activeDetail = detail;

  const manifest = detail.mission.manifest;
  $("active-tier").textContent = `Tier ${manifest.tier}`;
  $("active-mode").textContent =
    manifest.mode === "hillclimb"
      ? `HILL-CLIMB (${manifest.score_direction})`
      : manifest.open_conjecture
        ? "OPEN CONJECTURE BLUEPRINT"
        : "PROOF BLUEPRINT";
  if ($("active-open-conjecture")) {
    $("active-open-conjecture").classList.toggle("hidden", !manifest.open_conjecture);
  }
  $("active-demo").classList.toggle("hidden", !manifest.demo);
  const upEl = $("active-upstream");
  if (upEl) {
    if (manifest.upstream && manifest.upstream.repo && manifest.upstream.commit) {
      const shortSha = manifest.upstream.commit.slice(0, 7);
      upEl.textContent = `Upstream: ${manifest.upstream.repo}@${shortSha} (${manifest.upstream.license}) ↗`;
      upEl.href = `https://github.com/${manifest.upstream.repo}/tree/${manifest.upstream.commit}`;
      upEl.classList.remove("hidden");
    } else {
      upEl.classList.add("hidden");
    }
  }
  $("active-spec-hash").textContent = detail.mission.spec_sha256.slice(0, 23) + "…";
  $("active-spec-hash").title = `Frozen spec hash: ${detail.mission.spec_sha256}`;
  $("active-title").textContent = manifest.title;
  $("active-desc").textContent = manifest.description || "";

  const hasValidSelection =
    state.selectedTaskId && detail.tasks.some((t) => t.def.id === state.selectedTaskId);
  if (!hasValidSelection && detail.tasks.length > 0) {
    state.selectedTaskId = detail.frontier[0] || detail.tasks[0].def.id;
  }
  if (opts.syncUrl) {
    syncUrlDeepLink(missionId, state.selectedTaskId);
  }

  renderTaskFilterBar(detail);
  renderDag(detail);
  renderInspector(detail);
}

function computeLayers(tasks) {
  const byId = new Map(tasks.map((t) => [t.def.id, t]));
  const childIdsByParent = new Map();
  for (const t of tasks) {
    if (t.def.parent_task_id && byId.has(t.def.parent_task_id)) {
      const list = childIdsByParent.get(t.def.parent_task_id) || [];
      list.push(t.def.id);
      childIdsByParent.set(t.def.parent_task_id, list);
    }
  }
  const memo = new Map();
  const visiting = new Set();

  function depth(id) {
    if (memo.has(id)) return memo.get(id);
    if (visiting.has(id)) return 0;
    visiting.add(id);
    const t = byId.get(id);
    if (!t) {
      visiting.delete(id);
      memo.set(id, 0);
      return 0;
    }
    const prereqs = [...(t.def.depends_on || []), ...(childIdsByParent.get(id) || [])].filter((p) =>
      byId.has(p)
    );
    let d = 0;
    if (prereqs.length > 0) {
      d = 1 + Math.max(...prereqs.map(depth));
    }
    visiting.delete(id);
    memo.set(id, d);
    return d;
  }

  const layers = new Map();
  for (const t of tasks) {
    const d = depth(t.def.id);
    if (!layers.has(d)) layers.set(d, []);
    layers.get(d).push(t);
  }
  // Return sorted by depth column index
  return new Map([...layers.entries()].sort((a, b) => a[0] - b[0]));
}

function nodePalette(task, mode) {
  if (task.disputed_counterexample) {
    return {
      fill: "#FDF3F3",
      stroke: "#B44343",
      badge: "DISPUTED ¬T",
      badgeColor: "#9B2C2C",
      titleColor: "#6B1B1B",
    };
  }
  if (task.status === "refuted") {
    return {
      fill: "#F6EFF8",
      stroke: "#7A3B7E",
      badge: "REFUTED ¬T",
      badgeColor: "#6B2D6F",
      titleColor: "#3D1640",
    };
  }
  if (task.def && task.def.upstream_disputed) {
    return {
      fill: "#FDF3F3",
      stroke: "#B44343",
      badge: "UPSTREAM DISPUTED",
      badgeColor: "#9B2C2C",
      titleColor: "#6B1B1B",
    };
  }
  if (optimalityCitation(mode, task)) {
    return {
      fill: "#EEF7F7",
      stroke: "#2A7D7F",
      badge: "PROVEN OPTIMAL",
      badgeColor: "#2A7D7F",
      titleColor: "#0D1B3D",
    };
  }
  if (!task.unlocked) {
    return {
      fill: "#F2EFE7",
      stroke: "#C8C0B0",
      badge: "WAITING",
      badgeColor: "#7A7E87",
      titleColor: "#5A5E66",
    };
  }
  if (mode === "hillclimb") {
    if (task.active_lease) {
      return {
        fill: "#EDF1F8",
        stroke: "#0D1B3D",
        badge: "CLAIMED",
        badgeColor: "#0D1B3D",
        titleColor: "#0D1B3D",
      };
    }
    if (task.status === "verified") {
      return {
        fill: "#EEF7F7",
        stroke: "#C6A15A",
        badge: "RECORD · OPEN",
        badgeColor: "#2A7D7F",
        titleColor: "#0D1B3D",
      };
    }
    return {
      fill: "#FDFBF5",
      stroke: "#C6A15A",
      badge: "READY",
      badgeColor: "#9F7C38",
      titleColor: "#1B1D1F",
    };
  }
  if (task.status === "verified") {
    return {
      fill: "#EEF7F7",
      stroke: "#2A7D7F",
      badge: "VERIFIED",
      badgeColor: "#2A7D7F",
      titleColor: "#0D1B3D",
    };
  }
  if (task.active_lease) {
    return {
      fill: "#EDF1F8",
      stroke: "#0D1B3D",
      badge: "CLAIMED",
      badgeColor: "#0D1B3D",
      titleColor: "#0D1B3D",
    };
  }
  return {
    fill: "#FDFBF5",
    stroke: "#C6A15A",
    badge: "READY",
    badgeColor: "#9F7C38",
    titleColor: "#1B1D1F",
  };
}

function decompClusterKey(missionId, parentTaskId, decompId) {
  return `${missionId}:${parentTaskId}:${decompId}`;
}

function computeBlueprintLayout(tasks, activeDecomps = [], collapsedDecomps = new Set(), missionId = "") {
  const byId = new Map(tasks.map((t) => [t.def.id, t]));
  const layers = computeLayers(tasks);

  const hasDepEdges = tasks.some((t) =>
    (t.def.depends_on || []).some((depId) => byId.has(depId))
  );
  const hasExpandedDecomp =
    tasks.some((t) => t.def.parent_task_id && byId.has(t.def.parent_task_id)) ||
    (activeDecomps || []).some((d) => {
      const key = decompClusterKey(missionId, d.parent_task_id, d.decomp_id);
      if (collapsedDecomps && collapsedDecomps.has(key)) return false;
      return tasks.some(
        (t) => t.def.parent_task_id === d.parent_task_id && t.def.decomp_id === d.decomp_id
      );
    });

  const useFlatGrid = !hasDepEdges && !hasExpandedDecomp && layers.size === 1 && tasks.length > 6;

  if (useFlatGrid) {
    const nodeW = 252;
    const nodeH = 92;
    const cols = 3;
    const rows = Math.ceil(tasks.length / cols);
    const colGap = 18;
    const hasCollapsedPill = (activeDecomps || []).some(
      (d) =>
        collapsedDecomps &&
        collapsedDecomps.has(decompClusterKey(missionId, d.parent_task_id, d.decomp_id)) &&
        byId.has(d.parent_task_id)
    );
    const rowGap = hasCollapsedPill ? 26 : 18;
    const padX = 18;
    const padY = 24;
    const width = padX * 2 + cols * nodeW + (cols - 1) * colGap;
    const height = Math.max(240, padY * 2 + rows * nodeH + (rows - 1) * rowGap);
    const pos = new Map();
    tasks.forEach((t, idx) => {
      const col = idx % cols;
      const row = Math.floor(idx / cols);
      const x = padX + col * (nodeW + colGap);
      const y = padY + row * (nodeH + rowGap);
      pos.set(t.def.id, { x, y });
    });
    return { mode: "grid", cols, rows, nodeW, nodeH, colGap, rowGap, width, height, pos, layers };
  }

  const nodeW = 262;
  const nodeH = 92;
  const colGap = 94;
  const rowGap = 24;
  const padX = 36;
  const padY = 44;

  const numCols = Math.max(1, layers.size);
  const maxRows = Math.max(1, ...Array.from(layers.values()).map((col) => col.length));
  const width = Math.max(780, padX * 2 + numCols * nodeW + (numCols - 1) * colGap);
  const height = Math.max(350, padY * 2 + maxRows * nodeH + (maxRows - 1) * rowGap);

  const pos = new Map();
  let colPosIdx = 0;
  for (const [, colTasks] of layers.entries()) {
    const colHeight = colTasks.length * nodeH + (colTasks.length - 1) * rowGap;
    const startY = (height - colHeight) / 2;
    colTasks.forEach((t, rowIdx) => {
      const x = padX + colPosIdx * (nodeW + colGap);
      const y = startY + rowIdx * (nodeH + rowGap);
      pos.set(t.def.id, { x, y });
    });
    colPosIdx += 1;
  }
  return { mode: "dag", cols: numCols, rows: maxRows, nodeW, nodeH, colGap, rowGap, width, height, pos, layers };
}

function isTaskFilterActive() {
  return state.taskFilter.status !== "all" || state.taskFilter.query.trim() !== "";
}

function renderTaskFilterBar(detail) {
  const bar = $("task-filter-bar");
  if (!bar) return;
  const allTasks = detail?.tasks || [];
  const show = allTasks.length > 8;
  bar.classList.toggle("hidden", !show);
  if (!show) {
    resetTaskFilters();
    return;
  }
  const mode = detail.mission.manifest.mode;
  const counts = countTaskStatuses(allTasks, mode, state.taskFilter.query);
  const pillsRoot = $("task-status-pills");
  if (pillsRoot) {
    pillsRoot.querySelectorAll(".filter-pill").forEach((btn) => {
      const st = btn.dataset.status || "all";
      btn.classList.toggle("active", st === state.taskFilter.status);
      const badge = btn.querySelector(".pill-count");
      if (badge) badge.textContent = String(counts[st] ?? 0);
    });
  }
  const searchEl = $("task-search");
  if (searchEl && searchEl.value !== state.taskFilter.query) {
    searchEl.value = state.taskFilter.query;
  }
  const shown = filterBlueprintTasks(allTasks, mode, state.taskFilter).length;
  const countEl = $("task-filter-count");
  if (countEl) {
    countEl.textContent = `Showing ${shown} of ${allTasks.length}`;
  }
  const clearEl = $("task-filter-clear");
  if (clearEl) {
    clearEl.classList.toggle("hidden", !isTaskFilterActive());
  }
}

function setupTaskFilters() {
  const pillsRoot = $("task-status-pills");
  if (pillsRoot) {
    pillsRoot.querySelectorAll(".filter-pill").forEach((btn) => {
      btn.addEventListener("click", () => {
        state.taskFilter.status = btn.dataset.status || "all";
        if (state.activeDetail) {
          renderTaskFilterBar(state.activeDetail);
          renderDag(state.activeDetail);
        }
      });
    });
  }
  const searchEl = $("task-search");
  if (searchEl) {
    searchEl.addEventListener("input", () => {
      state.taskFilter.query = searchEl.value;
      if (state.activeDetail) {
        renderTaskFilterBar(state.activeDetail);
        renderDag(state.activeDetail);
      }
    });
  }
  const clearEl = $("task-filter-clear");
  if (clearEl) {
    clearEl.addEventListener("click", () => {
      resetTaskFilters();
      if (state.activeDetail) {
        renderTaskFilterBar(state.activeDetail);
        renderDag(state.activeDetail);
      }
    });
  }
}

function renderDag(detail) {
  const svg = $("dag-svg");
  const emptyEl = $("dag-empty");
  const allTasks = detail.tasks;
  const manifest = detail.mission.manifest;
  const activeDecomps = (detail.decompositions || []).filter((d) => d.status === "active");
  const activeDecompByParent = new Map(activeDecomps.map((d) => [d.parent_task_id, d]));

  // Hide descendants of collapsed decomposition sub-clusters.
  const allById = new Map(allTasks.map((t) => [t.def.id, t]));
  const isHiddenByCollapse = (t) => {
    let cur = t;
    while (cur && cur.def.parent_task_id && cur.def.decomp_id) {
      if (state.collapsedDecomps.has(decompClusterKey(manifest.id, cur.def.parent_task_id, cur.def.decomp_id))) {
        return true;
      }
      cur = allById.get(cur.def.parent_task_id);
    }
    return false;
  };
  const uncollapsedTasks = allTasks.filter((t) => !isHiddenByCollapse(t));
  const tasks =
    allTasks.length > 8
      ? filterBlueprintTasks(uncollapsedTasks, manifest.mode, state.taskFilter)
      : uncollapsedTasks;

  if (tasks.length === 0) {
    svg.innerHTML = "";
    svg.classList.add("hidden");
    if (emptyEl) {
      emptyEl.classList.remove("hidden");
      emptyEl.innerHTML = `
        <div>No tasks match your current task filter.</div>
        <button type="button" class="filter-clear" id="dag-empty-clear">Clear task filter</button>
      `;
      const btn = $("dag-empty-clear");
      if (btn) {
        btn.addEventListener("click", () => {
          resetTaskFilters();
          renderTaskFilterBar(detail);
          renderDag(detail);
        });
      }
    }
    return;
  }

  svg.classList.remove("hidden");
  if (emptyEl) {
    emptyEl.classList.add("hidden");
    emptyEl.innerHTML = "";
  }

  const layout = computeBlueprintLayout(tasks, activeDecomps, state.collapsedDecomps, manifest.id);
  const { nodeW, nodeH, width, height, pos } = layout;

  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  if (layout.mode === "grid") {
    svg.style.width = "100%";
    svg.style.maxWidth = `${width}px`;
    svg.style.height = "auto";
    svg.style.aspectRatio = `${width} / ${height}`;
    svg.style.minHeight = "0";
  } else {
    svg.style.width = width > 900 ? `${width}px` : "";
    svg.style.maxWidth = "";
    svg.style.height = height > 760 ? `${height}px` : "";
    svg.style.aspectRatio = "";
    svg.style.minHeight = `${Math.min(height, 680)}px`;
  }

  let defsHtml = `<defs>
    <clipPath id="dag-card-clip">
      <rect x="10" y="0" width="${nodeW - 20}" height="${nodeH}" />
    </clipPath>
    <marker id="arrow-muted" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#B5AC9A" />
    </marker>
    <marker id="arrow-teal" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#2A7D7F" />
    </marker>
    <marker id="arrow-plum" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#7A3B7E" />
    </marker>
    <marker id="arrow-gold" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#C6A15A" />
    </marker>
  </defs>`;

  // Render collapsible dashed sub-cluster frames around each expanded active decomposition.
  let clustersHtml = "";
  for (const d of activeDecomps) {
    const key = decompClusterKey(manifest.id, d.parent_task_id, d.decomp_id);
    if (state.collapsedDecomps.has(key)) continue;
    const members = tasks.filter(
      (t) => t.def.parent_task_id === d.parent_task_id && t.def.decomp_id === d.decomp_id
    );
    if (members.length === 0) continue;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const m of members) {
      const p = pos.get(m.def.id);
      if (!p) continue;
      minX = Math.min(minX, p.x);
      minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + nodeW);
      maxY = Math.max(maxY, p.y + nodeH);
    }
    if (!Number.isFinite(minX)) continue;
    const fx = minX - 14;
    const fy = minY - 30;
    const fw = maxX - minX + 28;
    const fh = maxY - minY + 44;
    const label = `▾ DECOMP ${d.decomp_id} · ${d.verified_subgoals}/${d.total_subgoals} · by ${d.proposer}`;
    clustersHtml += `
      <g class="decomp-cluster" data-decomp-key="${escapeHtml(key)}">
        <rect x="${fx}" y="${fy}" width="${fw}" height="${fh}" rx="7"
              fill="rgba(198, 161, 90, 0.06)" stroke="#C6A15A" stroke-width="1.25" stroke-dasharray="5 4" />
        <g class="decomp-toggle" data-decomp-key="${escapeHtml(key)}" style="cursor:pointer">
          <rect x="${fx + 8}" y="${fy + 5}" width="${Math.min(fw - 16, 252)}" height="19" rx="3"
                fill="rgba(253, 251, 245, 0.94)" stroke="rgba(198, 161, 90, 0.55)" stroke-width="0.9" />
          <text x="${fx + 14}" y="${fy + 18}" fill="#8B6926" font-size="9.5" font-weight="600" font-family="JetBrains Mono, monospace">${escapeHtml(label.slice(0, 38))}</text>
        </g>
      </g>
    `;
  }

  let edgesHtml = "";
  const byId = new Map(tasks.map((t) => [t.def.id, t]));
  for (const t of tasks) {
    const dst = pos.get(t.def.id);
    // 1. Standard DAG dependency edges.
    for (const depId of t.def.depends_on || []) {
      const src = pos.get(depId);
      const depTask = byId.get(depId);
      if (!src || !dst) continue;
      const x1 = src.x + nodeW;
      const y1 = src.y + nodeH / 2;
      const x2 = dst.x;
      const y2 = dst.y + nodeH / 2;
      const mx = (x1 + x2) / 2;
      const satisfied = depTask && (depTask.status === "verified" || depTask.status === "refuted");
      const refutedDep = depTask && depTask.status === "refuted";
      const stroke = refutedDep ? "#7A3B7E" : satisfied ? "#2A7D7F" : "#BDB5A5";
      const marker = refutedDep ? "url(#arrow-plum)" : satisfied ? "url(#arrow-teal)" : "url(#arrow-muted)";
      edgesHtml += `<path d="M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}"
        fill="none" stroke="${stroke}" stroke-width="${satisfied ? 2 : 1.4}"
        stroke-dasharray="${satisfied ? "" : "4 4"}" marker-end="${marker}" />`;
      edgesHtml += `<circle cx="${x1}" cy="${y1}" r="2.8" fill="${stroke}" />`;
    }
    // 2. Dashed decomposition reduction edges (subgoal L_i ---▸ parent T).
    if (t.def.parent_task_id && byId.has(t.def.parent_task_id)) {
      const src = pos.get(t.def.id);
      const parentPos = pos.get(t.def.parent_task_id);
      if (src && parentPos) {
        const x1 = src.x + nodeW;
        const y1 = src.y + nodeH / 2;
        const x2 = parentPos.x;
        const y2 = parentPos.y + nodeH / 2;
        const mx = (x1 + x2) / 2;
        const solved = t.status === "verified";
        const stroke = solved ? "#2A7D7F" : "#C6A15A";
        const marker = solved ? "url(#arrow-teal)" : "url(#arrow-gold)";
        edgesHtml += `<path class="decomp-edge" d="M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}"
          fill="none" stroke="${stroke}" stroke-width="${solved ? 2 : 1.6}"
          stroke-dasharray="6 4" marker-end="${marker}" />`;
        edgesHtml += `<circle cx="${x1}" cy="${y1}" r="2.8" fill="${stroke}" />`;
      }
    }
  }

  let nodesHtml = "";
  for (const t of tasks) {
    const p = pos.get(t.def.id);
    const c = nodePalette(t, manifest.mode);
    const sel = t.def.id === state.selectedTaskId ? "selected" : "";
    const isSub = Boolean(t.def.decomp_id);
    const isOpenConj = isOpenConjectureTaskDef(manifest, t.def);
    const activeChildDecomp = activeDecompByParent.get(t.def.id);
    const badgeLabel = isSub
      ? `${c.badge} · SUBGOAL`
      : isOpenConj &&
          t.status !== "verified" &&
          t.status !== "refuted" &&
          !t.disputed_counterexample &&
          !(t.def && t.def.upstream_disputed)
        ? `${c.badge} · T/¬T`
        : c.badge;
    const innerTextW = nodeW - 28;
    const maxTitleChars = Math.max(24, Math.floor(innerTextW / 7.6));
    const maxIdChars = Math.max(
      10,
      Math.min(18, Math.floor((innerTextW - badgeLabel.length * 6.8 - 8) / 6.1))
    );
    const maxFooterChars = Math.max(28, Math.floor(innerTextW / 6.6));
    const shortTitle =
      t.def.title.length > maxTitleChars ? t.def.title.slice(0, maxTitleChars - 1) + "…" : t.def.title;
    const rawIdLabel = isSub && t.def.subgoal_id ? t.def.subgoal_id : t.def.id;
    const shortId =
      rawIdLabel.length > maxIdChars ? rawIdLabel.slice(0, maxIdChars - 1) + "…" : rawIdLabel;
    let footer = `${t.attempts} run${t.attempts === 1 ? "" : "s"}`;
    if (t.status === "refuted") {
      const refuter = t.refuted_resolution?.refuter || t.verified_by || "contributor";
      footer = `refuted ¬T by ${refuter}`;
    } else if (t.disputed_counterexample) {
      footer = `disputed ¬T by ${t.disputed_counterexample.refuter}`;
    } else if (t.def && t.def.upstream_disputed) {
      footer = `upstream disputed (${t.def.upstream_disputed.recorded_at || "excluded"})`;
    } else if (optimalityCitation(manifest.mode, t)) {
      footer = `optimum: ${t.def.best_known.value} · closed`;
    } else if (manifest.mode === "hillclimb" && t.best_score !== null && t.best_score !== undefined) {
      if (t.active_lease) {
        footer = `best: ${t.best_score} · claimed: ${t.active_lease.contributor}`;
      } else if (t.verified_by) {
        footer = `best: ${t.best_score} · by ${t.verified_by}`;
      } else {
        footer = `best: ${t.best_score} · ${footer}`;
      }
      if (t.def.best_known && typeof t.def.best_known.value === "number") {
        footer += ` · known: ${t.def.best_known.value}`;
      }
    } else if (t.verified_by) {
      footer = `verified by ${t.verified_by}`;
    } else if (t.active_lease) {
      footer = `claimed: ${t.active_lease.contributor}`;
    } else if (activeChildDecomp) {
      footer = `split ${activeChildDecomp.decomp_id}: ${activeChildDecomp.verified_subgoals}/${activeChildDecomp.total_subgoals} subgoals`;
    }
    const shortFooter =
      footer.length > maxFooterChars ? footer.slice(0, maxFooterChars - 1) + "…" : footer;

    let collapsedPillHtml = "";
    if (activeChildDecomp) {
      const key = decompClusterKey(manifest.id, activeChildDecomp.parent_task_id, activeChildDecomp.decomp_id);
      if (state.collapsedDecomps.has(key)) {
        const pillText = `▸ ${activeChildDecomp.total_subgoals} subgoals (${activeChildDecomp.verified_subgoals}/${activeChildDecomp.total_subgoals})`;
        collapsedPillHtml = `
          <g class="decomp-toggle" data-decomp-key="${escapeHtml(key)}" transform="translate(${p.x + 12},${p.y + nodeH + 4})" style="cursor:pointer">
            <rect width="176" height="19" rx="3" fill="#FDFBF5" stroke="#C6A15A" stroke-width="1" stroke-dasharray="3 2" />
            <text x="8" y="13" fill="#8B6926" font-size="9.5" font-weight="600" font-family="JetBrains Mono, monospace">${escapeHtml(pillText)}</text>
          </g>
        `;
      }
    }

    nodesHtml += `
      <g class="dag-node ${sel} ${isSub ? "dag-node-subgoal" : ""}" data-task-id="${escapeHtml(t.def.id)}" transform="translate(${p.x},${p.y})">
        <title>${escapeHtml(`${t.def.title} (${t.def.id})`)}</title>
        <rect class="node-box" width="${nodeW}" height="${nodeH}" rx="5"
              fill="${c.fill}" stroke="${c.stroke}" stroke-width="1.5"
              ${isSub ? 'stroke-dasharray="4 2"' : ""} />
        <line x1="12" y1="29" x2="${nodeW - 12}" y2="29" stroke="${c.stroke}" stroke-opacity="0.24" stroke-width="1" />
        <g clip-path="url(#dag-card-clip)">
          <text x="12" y="20" fill="${c.badgeColor}" font-size="9.5" font-weight="700" letter-spacing="0.08em" font-family="Inter, sans-serif">${escapeHtml(badgeLabel)}</text>
          <text x="${nodeW - 12}" y="20" text-anchor="end" fill="#6F747D" font-size="10" font-family="JetBrains Mono, monospace">${escapeHtml(shortId)}</text>
          <text x="12" y="51" fill="${c.titleColor}" font-size="15.5" font-weight="600" font-family="Cormorant Garamond, Georgia, serif">${escapeHtml(shortTitle)}</text>
          <text x="12" y="75" fill="#5A5E66" font-size="10.5" font-family="JetBrains Mono, monospace">${escapeHtml(shortFooter)}</text>
        </g>
      </g>
      ${collapsedPillHtml}
    `;
  }

  svg.innerHTML = defsHtml + clustersHtml + edgesHtml + nodesHtml;
  svg.querySelectorAll(".dag-node").forEach((g) => {
    g.addEventListener("click", () => {
      state.selectedTaskId = g.dataset.taskId;
      syncUrlDeepLink(manifest.id, state.selectedTaskId);
      renderDag(detail);
      renderInspector(detail);
    });
  });
  svg.querySelectorAll(".decomp-toggle").forEach((g) => {
    g.addEventListener("click", (ev) => {
      ev.stopPropagation();
      const key = g.dataset.decompKey;
      if (state.collapsedDecomps.has(key)) state.collapsedDecomps.delete(key);
      else state.collapsedDecomps.add(key);
      renderDag(detail);
      renderInspector(detail);
    });
  });
}

function renderInspector(detail) {
  const el = $("task-inspector");
  const task = detail.tasks.find((t) => t.def.id === state.selectedTaskId);
  if (!task) {
    el.innerHTML = `<div class="muted">Select a node on the blueprint above to inspect details.</div>`;
    return;
  }
  const m = detail.mission.manifest;
  const origin = window.location.origin;
  const scoreHtml =
    task.best_score !== null && task.best_score !== undefined
      ? `<div class="kv"><div class="kv-label">Best Verified Score (${escapeHtml(m.score_direction)})</div><div class="kv-val">${task.best_score}</div></div>`
      : "";
  const bk = task.def.best_known;
  const optimum = optimalityCitation(m.mode, task);
  const bestKnownHtml =
    optimum
      ? `<div class="kv"><div class="kv-label">Solved · Proven Optimal</div><div class="kv-val">${escapeHtml(bk.value)} · <a class="proof-link" href="${escapeHtml(optimum.url)}" target="_blank" rel="noopener">${escapeHtml(optimum.source)} ↗</a><div class="muted small">Closed to claims and submissions. This is a literature result, not a Sunstead verification.</div></div></div>`
      :
    bk && typeof bk.value === "number"
      ? `<div class="kv"><div class="kv-label">Best Known Outside Sunstead</div><div class="kv-val">${escapeHtml(bk.value)} · <a href="${escapeHtml(bk.url)}" target="_blank" rel="noopener" style="color:var(--teal);text-decoration:none" title="${escapeHtml(bk.source)}">source ↗</a><div class="muted" style="font-size:12px;margin-top:4px">Full points only for beating this; tying it pays 25.</div></div></div>`
      : "";
  const upstreamHtml = task.def.upstream_url
    ? `<div class="kv"><div class="kv-label">Upstream Statement</div><div class="kv-val"><a href="${escapeHtml(task.def.upstream_url)}" target="_blank" rel="noopener" style="color:var(--teal);text-decoration:none">${escapeHtml(task.def.upstream_url.replace(/^https:\/\/github\.com\//, ""))} ↗</a></div></div>`
    : "";

  const activeDecomp = (detail.decompositions || []).find(
    (d) => d.parent_task_id === task.def.id && d.status === "active"
  );
  const subgoalBannerHtml = task.def.decomp_id
    ? `<div class="decomp-banner">
        <div class="decomp-banner-head">
          <span class="ledger-badge ledger-badge-decomp">v2 Subgoal · depth ${escapeHtml(task.def.decomp_depth || 1)}</span>
          <button type="button" class="btn-outline-ink decomp-jump" data-jump-task="${escapeHtml(task.def.parent_task_id || "")}">Parent: ${escapeHtml(task.def.parent_task_id || "")}</button>
        </div>
        ${task.def.subgoal_statement ? `<pre class="decomp-stmt">${escapeHtml(task.def.subgoal_statement)}</pre>` : ""}
        <div class="muted small">
          Frozen reduction: <code>${escapeHtml(task.def.reduction_file || "")}</code> ·
          Subgoal spec: <code>${escapeHtml((task.def.subgoal_spec_sha256 || "").slice(0, 23))}…</code> ·
          Open refutation endpoint: <code>POST /api/missions/${escapeHtml(m.id)}/tasks/${escapeHtml(task.def.id)}/refute</code>
        </div>
      </div>`
    : "";

  const parentDecompBannerHtml = activeDecomp
    ? (() => {
        const key = decompClusterKey(m.id, activeDecomp.parent_task_id, activeDecomp.decomp_id);
        const collapsed = state.collapsedDecomps.has(key);
        return `<div class="decomp-banner">
          <div class="decomp-banner-head">
            <span class="ledger-badge ledger-badge-decomp">Active Decomposition · ${escapeHtml(activeDecomp.decomp_id)} (${activeDecomp.verified_subgoals}/${activeDecomp.total_subgoals} verified)</span>
            <button type="button" class="btn-outline-ink decomp-toggle-btn" data-decomp-key="${escapeHtml(key)}">${collapsed ? "Expand sub-cluster ▸" : "Collapse sub-cluster ▾"}</button>
          </div>
          <div class="muted small">
            Proposed by <strong>${escapeHtml(activeDecomp.proposer)}</strong> ·
            Economics: <code>${activeDecomp.solver_points_per_subgoal} pts</code>/subgoal, <code>${activeDecomp.architect_points} pts</code> architect share (vests on untouched <code>./verify</code> closure) ·
            Direct proof bypass: <strong>${m.decomposition?.allow_direct_bypass === false ? "disabled" : "enabled"}</strong>
          </div>
        </div>`;
      })()
    : "";

  const isOpenConj = isOpenConjectureTaskDef(m, task.def);
  const refutedBannerHtml = task.status === "refuted"
    ? (() => {
        const rr = task.refuted_resolution;
        const refuter = rr?.refuter || task.verified_by || "contributor";
        const when = rr?.created_at ? ` (${escapeHtml(fmtUtc(rr.created_at))})` : "";
        const link = rr?.proof_id
          ? ` · <a class="proof-link" href="/proofs/${escapeHtml(rr.proof_id)}">inspect counterexample ↗</a>`
          : "";
        return `<div class="refuted-banner">
          <strong>Open Conjecture Resolved — Refuted (¬ T):</strong>
          Kernel-verified counterexample by <code>${escapeHtml(refuter)}</code>${when}${link}
        </div>`;
      })()
    : "";

  const upstreamDispute = task.def?.upstream_disputed || null;
  const upstreamDisputeUrl = upstreamDispute ? safeHttpUrl(upstreamDispute.url) : null;
  const disputedBannerHtml = task.disputed_counterexample
    ? `<div class="dispute-banner">
        <strong>Disputed Counterexample (¬ T):</strong>
        Kernel-verified refutation by <code>${escapeHtml(task.disputed_counterexample.refuter)}</code>
        (${escapeHtml(fmtUtc(task.disputed_counterexample.created_at))})
        ${task.disputed_counterexample.proof_id ? ` · <a class="proof-link" href="/proofs/${escapeHtml(task.disputed_counterexample.proof_id)}">inspect counterexample ↗</a>` : ""}
      </div>`
    : upstreamDispute
      ? `<div class="dispute-banner">
          <strong>Upstream Disputed:</strong>
          ${escapeHtml(upstreamDispute.reason)}
          ${upstreamDispute.recorded_at ? ` <span class="muted small">(${escapeHtml(upstreamDispute.recorded_at)})</span>` : ""}
          ${upstreamDisputeUrl ? ` · <a class="proof-link" href="${escapeHtml(upstreamDisputeUrl)}" target="_blank" rel="noopener">upstream issue ↗</a>` : ""}
        </div>`
      : "";

  const conjectureBannerHtml =
    isOpenConj && task.status !== "verified" && task.status !== "refuted" && !task.disputed_counterexample && !upstreamDispute
      ? `<div class="conjecture-banner">
          <strong>Two-Sided Open Conjecture (Prove T or Refute ¬ T):</strong>
          Submit a Lean 4 proof of <code>T</code> via <code>POST .../submit</code> or a kernel-verified counterexample proving <code>¬ T</code> via <code>POST .../refute</code> — either resolves the task for full Tier ${escapeHtml(m.tier)} credit.
        </div>`
      : "";

  const hasAcceptedArtifact = task.status === "verified" || task.status === "refuted";

  el.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap">
      <div>
        <span style="font-family:var(--serif);font-size:21px;font-weight:600;color:var(--indigo)">${escapeHtml(task.def.title)}</span>
        <span class="muted small" style="margin-left:8px"><code>${escapeHtml(task.def.id)}</code></span>
      </div>
      <a class="small" style="color:var(--teal);font-weight:500;text-decoration:none" href="/api/missions/${encodeURIComponent(m.id)}/bundle.tar.gz">Download live bundle (.tar.gz) ↓</a>
    </div>
    ${task.def.description ? `<p class="muted small" style="margin:6px 0 0">${escapeHtml(task.def.description)}</p>` : ""}
    ${refutedBannerHtml}
    ${disputedBannerHtml}
    ${conjectureBannerHtml}
    ${subgoalBannerHtml}
    ${parentDecompBannerHtml}
    <div class="inspector-grid">
      <div class="kv">
        <div class="kv-label">Allowed target_files</div>
        <div class="kv-val">${escapeHtml((task.def.target_files || []).join(", "))}</div>
      </div>
      ${upstreamHtml}
      <div class="kv">
        <div class="kv-label">Verifier Image (network=none)</div>
        <div class="kv-val">${escapeHtml(m.verifier.image)}</div>
      </div>
      ${scoreHtml}
      ${bestKnownHtml}
      ${optimum ? "" : `<div class="kv">
        <div class="kv-label">Submit Endpoint${isOpenConj ? " (Prove T)" : ""}</div>
        <div class="kv-val">POST ${escapeHtml(origin)}/api/missions/${escapeHtml(m.id)}/tasks/${escapeHtml(task.def.id)}/submit</div>
      </div>`}
      ${
        isOpenConj && !task.def.decomp_id
          ? `<div class="kv"><div class="kv-label">Refute Endpoint (Disprove ¬ T)</div><div class="kv-val">POST ${escapeHtml(origin)}/api/missions/${escapeHtml(m.id)}/tasks/${escapeHtml(task.def.id)}/refute (open to all)</div></div>${
              m.decomposition?.enabled
                ? `<div class="kv"><div class="kv-label">v2 Decompose</div><div class="kv-val">POST .../tasks/${escapeHtml(task.def.id)}/decompose (allowlist)</div></div>`
                : ""
            }`
          : m.mode === "dag"
            ? `<div class="kv"><div class="kv-label">${m.decomposition?.enabled && !task.def.decomp_id ? "Disprove / Decompose" : "Disprove False Statement"}</div><div class="kv-val">POST .../tasks/${escapeHtml(task.def.id)}/refute (open to all)${m.decomposition?.enabled && !task.def.decomp_id ? ` · /decompose (allowlist)` : ""}</div></div>`
            : ""
      }
    </div>
    ${hasAcceptedArtifact ? `<div class="proof-panel" id="proof-panel" aria-live="polite"><div class="muted small">${task.status === "refuted" ? "Loading kernel-verified refutation…" : "Loading verified proof…"}</div></div>` : ""}
  `;
  el.querySelectorAll(".decomp-jump").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (btn.dataset.jumpTask) {
        state.selectedTaskId = btn.dataset.jumpTask;
        syncUrlDeepLink(m.id, state.selectedTaskId);
        renderDag(detail);
        renderInspector(detail);
      }
    });
  });
  el.querySelectorAll(".decomp-toggle-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const key = btn.dataset.decompKey;
      if (state.collapsedDecomps.has(key)) state.collapsedDecomps.delete(key);
      else state.collapsedDecomps.add(key);
      renderDag(detail);
      renderInspector(detail);
    });
  });
  if (hasAcceptedArtifact) loadProof(m.id, task.def.id);
}

function fmtDuration(ms) {
  if (typeof ms !== "number" || !Number.isFinite(ms) || ms <= 0) return "n/a";
  return ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(1)} s`;
}

function diffLineClass(line) {
  if (line.startsWith("+++ ") || line.startsWith("--- ") || line.startsWith("diff ") || line.startsWith("index ")) {
    return "diff-meta";
  }
  if (line.startsWith("@@")) return "diff-hunk";
  if (line.startsWith("+")) return "diff-add";
  if (line.startsWith("-")) return "diff-del";
  return "diff-ctx";
}

function renderDiffHtml(patch) {
  const lines = String(patch ?? "").replace(/\r\n/g, "\n").replace(/\n$/, "").split("\n");
  return lines
    .map((line) => `<span class="diff-line ${diffLineClass(line)}">${escapeHtml(line) || " "}</span>`)
    .join("");
}

async function loadProof(missionId, taskId) {
  const key = `${missionId}/${taskId}`;
  const stillSelected = () =>
    state.activeMissionId === missionId && state.selectedTaskId === taskId && $("proof-panel");
  let proof = state.proofCache.get(key);
  if (!proof) {
    try {
      proof = await fetchJson(
        `/api/missions/${encodeURIComponent(missionId)}/tasks/${encodeURIComponent(taskId)}/proof`
      );
      state.proofCache.set(key, proof);
    } catch (e) {
      if (stillSelected()) {
        $("proof-panel").innerHTML = `<div class="muted small">Could not load the verified proof (${escapeHtml(e.message)}).</div>`;
      }
      return;
    }
  }
  if (!stillSelected()) return;
  renderProofPanel(proof);
}

function fmtUtc(unixSec) {
  return unixSec ? new Date(unixSec * 1000).toISOString().replace("T", " ").slice(0, 16) + " UTC" : "";
}

/** Only http(s) URLs become links; anything else is shown as text. */
function safeHttpUrl(u) {
  try {
    const url = new URL(String(u ?? ""));
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
  } catch {
    return null;
  }
}

const GITHUB_REPO_RE = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const HEX_RE = /^[0-9a-f]{7,64}$/;
const GITHUB_HANDLE_RE = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$/;
const X_HANDLE_RE = /^[A-Za-z0-9_]{1,15}$/;
const LINKEDIN_HANDLE_RE = /^[A-Za-z0-9-]{3,100}$/;

const SOCIAL_ICONS = {
  github: `<svg class="social-icon" viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>`,
  x: `<svg class="social-icon" viewBox="0 0 16 16" width="11" height="11" aria-hidden="true"><path fill="currentColor" d="M12.6 1h2.2l-4.8 5.5L15.7 15h-4.4L7.8 10.4 3.8 15H1.6l5.1-5.9L1.3 1h4.5l3.1 4.2L12.6 1zm-.8 12.6h1.2L4.9 2.3H3.6l8.2 11.3z"/></svg>`,
  linkedin: `<svg class="social-icon" viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path fill="currentColor" d="M13.6 1H2.4C1.6 1 1 1.6 1 2.4v11.2c0 .8.6 1.4 1.4 1.4h11.2c.8 0 1.4-.6 1.4-1.4V2.4c0-.8-.6-1.4-1.4-1.4zM5.3 13H3.1V6.3h2.2V13zM4.2 5.4c-.7 0-1.3-.6-1.3-1.3s.6-1.3 1.3-1.3 1.3.6 1.3 1.3-.6 1.3-1.3 1.3zM13 13h-2.2V9.6c0-.8 0-1.9-1.1-1.9s-1.3.9-1.3 1.8V13H6.2V6.3h2.1v.9h.03c.3-.6 1-1.1 2.1-1.1 2.2 0 2.6 1.5 2.6 3.4V13z"/></svg>`,
};

/**
 * Render canonical outbound social links strictly from validated handles
 * (never raw URLs from JSON; proof-gated server-side; no verified badge).
 */
function renderSocialLinksHtml(entry) {
  const parts = [];
  const gh = typeof entry?.github === "string" && GITHUB_HANDLE_RE.test(entry.github) ? entry.github : null;
  if (gh) {
    parts.push(
      `<a class="social-link" href="https://github.com/${encodeURIComponent(gh)}" target="_blank" rel="noopener noreferrer nofollow ugc" title="GitHub: ${escapeHtml(gh)}">${SOCIAL_ICONS.github}<span>@${escapeHtml(gh)}</span>${entry.github_verified_handle === gh ? ' <span class="github-verification">Verified GitHub</span>' : ""}</a>`
    );
  }
  const x = typeof entry?.x === "string" && X_HANDLE_RE.test(entry.x) ? entry.x : null;
  if (x) {
    parts.push(
      `<a class="social-link" href="https://x.com/${encodeURIComponent(x)}" target="_blank" rel="noopener noreferrer nofollow ugc" title="X: @${escapeHtml(x)}">${SOCIAL_ICONS.x}<span>@${escapeHtml(x)}</span></a>`
    );
  }
  const li = typeof entry?.linkedin === "string" && LINKEDIN_HANDLE_RE.test(entry.linkedin) ? entry.linkedin : null;
  if (li) {
    parts.push(
      `<a class="social-link" href="https://www.linkedin.com/in/${encodeURIComponent(li)}" target="_blank" rel="noopener noreferrer nofollow ugc" title="LinkedIn: in/${escapeHtml(li)}">${SOCIAL_ICONS.linkedin}<span>in/${escapeHtml(li)}</span></a>`
    );
  }
  return parts.length ? ` <span class="social-links">${parts.join("")}</span>` : "";
}

/** "owner/repo @ abc1234" linked to that commit's tree on GitHub when the parts look sane. */
function upstreamHtml(up) {
  if (!up) return `<span class="muted">none recorded</span>`;
  const short = String(up.commit || "").slice(0, 7);
  const label = `${escapeHtml(up.repo)} @ <code>${escapeHtml(short)}</code>`;
  const repoOk = GITHUB_REPO_RE.test(String(up.repo || ""));
  const commitOk = HEX_RE.test(String(up.commit || ""));
  const main =
    repoOk && commitOk
      ? `<a class="proof-link" href="https://github.com/${escapeHtml(up.repo)}/tree/${escapeHtml(up.commit)}" target="_blank" rel="noopener">${label}</a>`
      : label;
  const taskUrl = safeHttpUrl(up.task_url);
  const taskLinkLabel =
    up.anchor_kind === "optimization_spec"
      ? "upstream spec ↗"
      : up.anchor_kind === "challenge_node"
        ? "upstream challenge ↗"
        : up.anchor_kind === "extracted_lemma"
          ? "upstream context ↗"
          : "upstream sorry ↗";
  const task = taskUrl
    ? ` · <a class="proof-link" href="${escapeHtml(taskUrl)}" target="_blank" rel="noopener">${taskLinkLabel}</a>`
    : "";
  return `${main}${up.license ? ` <span class="muted small">(${escapeHtml(up.license)})</span>` : ""}${task}`;
}

function contributorHtml(proof) {
  const name = proof.display_name || proof.contributor;
  return `<strong>${escapeHtml(name)}</strong> <span class="muted small"><code>${escapeHtml(proof.contributor)}</code></span>${renderSocialLinksHtml(proof)}`;
}

/** Diff, metadata and rebuild command for one accepted proof (task panel and ledger page). */
function proofDetailHtml(proof) {
  const isRefutation = proof.entry_kind === "refutation";
  const specNote =
    proof.spec_is_current || isRefutation || proof.entry_kind === "subgoal"
      ? ""
      : `<div class="proof-warn small">Accepted under an earlier frozen spec than the one live now.</div>`;
  const proofId = String(proof.patch_sha256 || "").replace(/^sha256:/, "");
  const permalink = /^[0-9a-f]{64}$/.test(proofId) ? `<a class="proof-link" href="/proofs/${proofId}">permalink</a>` : "";
  const rebuildCmd = isRefutation
    ? null
    : proof.verification
      ? proof.verification.mission_replay?.command || null
      : proof.how_to_rebuild || null;
  const verifyCmd = proof.verification
    ? proof.verification.upstream_replay?.command || null
    : proof.verify_command || null;
  return `
    ${specNote}
    <div class="inspector-grid">
      <div class="kv"><div class="kv-label">Verification Time</div><div class="kv-val">${escapeHtml(fmtDuration(proof.verify_ms))}</div></div>
      <div class="kv"><div class="kv-label">Accepted</div><div class="kv-val">${escapeHtml(fmtUtc(proof.accepted_at))}</div></div>
      <div class="kv"><div class="kv-label">Spec SHA-256 at Acceptance</div><div class="kv-val">${escapeHtml(proof.spec_sha256)}</div></div>
      <div class="kv"><div class="kv-label">Patch SHA-256 ${permalink}</div><div class="kv-val">${escapeHtml(proof.patch_sha256)}</div></div>
    </div>
    ${proof.summary ? `<p class="muted small proof-summary">${escapeHtml(proof.summary)}</p>` : ""}
    <div class="proof-block">
      <div class="proof-block-head">
        <span class="kv-label">${isRefutation ? "Accepted Lean 4 refutation diff (¬ T)" : "Accepted Lean 4 diff"} · ${escapeHtml((proof.files || []).join(", "))}</span>
        <button type="button" class="btn-outline-ink proof-copy" data-copy="patch" data-label="Copy diff">Copy diff</button>
      </div>
      <pre class="proof-diff" tabindex="0">${renderDiffHtml(proof.patch)}</pre>
    </div>
    ${
      rebuildCmd
        ? `<div class="proof-block">
      <div class="proof-block-head">
        <span class="kv-label">Rebuild and check it yourself (seed bundle + git am)</span>
        <button type="button" class="btn-outline-ink proof-copy" data-copy="rebuild" data-label="Copy command">Copy command</button>
      </div>
      <pre class="proof-cmd" tabindex="0">${escapeHtml(rebuildCmd)}</pre>
    </div>`
        : ""
    }
    ${
      verifyCmd
        ? `<div class="proof-block">
      <div class="proof-block-head">
        <span class="kv-label">Check it against upstream, without trusting Sunstead (<a class="proof-link" href="/proofs#verify-yourself">how</a>)</span>
        <button type="button" class="btn-outline-ink proof-copy" data-copy="verify" data-label="Copy command">Copy command</button>
      </div>
      <pre class="proof-cmd" tabindex="0">${escapeHtml(verifyCmd)}</pre>
    </div>`
        : ""
    }
  `;
}

function wireProofCopyButtons(root, proof) {
  const rebuildCmd = proof.verification
    ? proof.verification.mission_replay?.command || ""
    : proof.how_to_rebuild || "";
  const verifyCmd = proof.verification
    ? proof.verification.upstream_replay?.command || ""
    : proof.verify_command || "";
  root.querySelectorAll(".proof-copy").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text =
        btn.dataset.copy === "patch"
          ? proof.patch
          : btn.dataset.copy === "verify"
            ? verifyCmd
            : rebuildCmd;
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = "Copied ✓";
      } catch {
        btn.textContent = "Copy failed";
      }
      clearTimeout(btn._resetTimer);
      btn._resetTimer = setTimeout(() => (btn.textContent = btn.dataset.label), 1600);
    });
  });
}

function renderProofPanel(proof) {
  const panel = $("proof-panel");
  const isRefutation = proof.entry_kind === "refutation";
  const isHistoryEntry = !isRefutation && proof.entry_kind !== "subgoal";
  const kickerClass = isRefutation ? "proof-kicker proof-kicker-refute" : "proof-kicker";
  const kickerText = isRefutation
    ? `Kernel-verified refutation (¬ T) · commit #${escapeHtml(proof.seq)}`
    : `Verified proof · commit #${escapeHtml(proof.seq)}`;
  panel.innerHTML = `
    <div class="proof-head">
      <div>
        <div class="${kickerClass}">${kickerText}</div>
        <div class="proof-by">${contributorHtml(proof)}</div>
      </div>
      ${isHistoryEntry ? `<a class="btn-outline-ink" href="${escapeHtml(proof.history_mbox)}">history.mbox ↓</a>` : ""}
    </div>
    ${proofDetailHtml(proof)}
  `;
  wireProofCopyButtons(panel, proof);
}

// ---------------- Verified Proofs Ledger (/proofs, /proofs/<sha256>) ----------------

function ledgerBadges(p) {
  const out = [];
  if (p.entry_kind === "refutation") {
    if (p.decomposition && p.decomposition.open_conjecture) {
      out.push(`<span class="ledger-badge ledger-badge-conjecture" title="Kernel-verified disproof (¬ T) resolving an open conjecture">conjecture refuted ¬T</span>`);
    } else {
      out.push(`<span class="ledger-badge ledger-badge-refute" title="Kernel-verified disproof (¬ statement)">refutation ¬</span>`);
    }
  } else if (p.entry_kind === "subgoal") {
    out.push(`<span class="ledger-badge ledger-badge-decomp" title="Verified v2 decomposition subgoal">subgoal</span>`);
  } else if (p.entry_kind === "assembled") {
    out.push(`<span class="ledger-badge ledger-badge-ok" title="Auto-assembled decomposition proof verified via untouched ./verify">assembled ✓</span>`);
  }
  if (p.mission_retired) out.push(`<span class="ledger-badge ledger-badge-muted">retired mission</span>`);
  if (p.mission_demo) out.push(`<span class="ledger-badge ledger-badge-muted">demo · 0 pts</span>`);
  if (!p.spec_is_current && !p.mission_retired && p.entry_kind !== "subgoal" && p.entry_kind !== "refutation") {
    out.push(`<span class="ledger-badge ledger-badge-warn">earlier spec</span>`);
  }
  return out.join(" ");
}

function renderDecompProvenanceHtml(p) {
  const parts = [];
  const d = p.decomposition;
  if (d && typeof d === "object") {
    if (d.decomp_id) parts.push(`decomp <code>${escapeHtml(d.decomp_id)}</code>`);
    if (d.parent_task_id && d.parent_task_id !== p.task_id) {
      parts.push(`parent <code>${escapeHtml(d.parent_task_id)}</code>`);
    }
    if (d.proposer) parts.push(`proposer <code>${escapeHtml(d.proposer)}</code>`);
    if (d.open_conjecture) parts.push(`resolved open conjecture (¬ T)`);
    else if (d.target_kind === "root") parts.push(`root counterexample`);
  }
  if (Array.isArray(p.co_authors) && p.co_authors.length > 0) {
    const names = p.co_authors
      .map((ca) => `${escapeHtml(ca.display_name || ca.handle)}${ca.role ? ` (${escapeHtml(ca.role)})` : ""}`)
      .join(", ");
    parts.push(`co-authors: ${names}`);
  }
  return parts.length > 0 ? `<div class="muted small decomp-prov">${parts.join(" · ")}</div>` : "";
}

function ledgerRowHtml(p) {
  const hash = String(p.proof_id || "");
  const link = /^[0-9a-f]{64}$/.test(hash) ? `/proofs/${hash}` : null;
  const title = escapeHtml(p.task_title || p.task_id);
  return `
    <li class="ledger-row">
      <div class="ledger-main">
        <div class="ledger-title">${link ? `<a href="${link}">${title}</a>` : title} ${ledgerBadges(p)}</div>
        <div class="muted small">${escapeHtml(p.mission_title || p.mission_id)} · <code>${escapeHtml(p.task_id)}</code></div>
        ${renderDecompProvenanceHtml(p)}
        <div class="small">Upstream: ${upstreamHtml(p.upstream)}</div>
      </div>
      <div class="ledger-side small">
        <div>${contributorHtml(p)}</div>
        <div class="muted">${escapeHtml(fmtUtc(p.accepted_at))}</div>
        <div class="ledger-hash"><code>${escapeHtml(hash.slice(0, 12))}</code></div>
      </div>
    </li>`;
}

async function loadLedgerList(root) {
  if (!$("ledger-list")) {
    root.innerHTML = `
      <div class="card-header ledger-card-header"><h3>All accepted proofs</h3><span id="ledger-count" class="muted small"></span></div>
      <div class="filter-bar ledger-filter-bar" id="ledger-filters" aria-label="Filter accepted proofs">
        <div class="filter-bar-top">
          <div class="filter-pills" id="ledger-kind-pills" role="group" aria-label="Filter proofs by entry kind">
            <button type="button" class="filter-pill active" data-kind="all">All <span class="pill-count">0</span></button>
            <button type="button" class="filter-pill filter-pill-teal" data-kind="proof">Proofs <span class="pill-count">0</span></button>
            <button type="button" class="filter-pill filter-pill-plum" data-kind="refutation">Refutations <span class="pill-count">0</span></button>
            <button type="button" class="filter-pill filter-pill-gold" data-kind="subgoal">Subgoals <span class="pill-count">0</span></button>
            <button type="button" class="filter-pill filter-pill-teal" data-kind="assembled">Assembled <span class="pill-count">0</span></button>
          </div>
          <div class="filter-controls">
            <select id="ledger-mission-filter" class="filter-select" aria-label="Filter proofs by mission">
              <option value="">All missions</option>
            </select>
            <input id="ledger-search" class="filter-input" type="search" placeholder="Search contributor, task, mission, or hash…" aria-label="Search proofs by contributor, task, mission, or hash" />
          </div>
        </div>
        <div class="filter-status-row">
          <span id="ledger-filter-summary" class="muted small">Loading the ledger…</span>
          <button type="button" id="ledger-filter-clear" class="filter-clear hidden">Clear filters</button>
        </div>
      </div>
      <ol id="ledger-list" class="ledger-list"></ol>
      <div class="ledger-more"><button type="button" id="ledger-more" class="btn-outline-ink hidden">Load older proofs</button></div>`;
  }

  const list = $("ledger-list");
  const more = $("ledger-more");
  const missionSelect = $("ledger-mission-filter");
  const searchInput = $("ledger-search");
  const kindPills = $("ledger-kind-pills");
  const summaryEl = $("ledger-filter-summary");
  const clearBtn = $("ledger-filter-clear");

  const initialParams = new URLSearchParams(window.location.search || "");
  const initialMission = (initialParams.get("mission") || initialParams.get("mission_id") || "").trim();

  const ledgerState = {
    proofs: [],
    total: 0,
    missions: [],
    loadError: null,
    filters: { missionId: initialMission, kind: "all", query: "" },
  };
  let before = null;

  const isFiltered = () =>
    ledgerState.filters.missionId !== "" ||
    ledgerState.filters.kind !== "all" ||
    ledgerState.filters.query.trim() !== "";

  const syncMissionOptions = () => {
    if (!missionSelect) return;
    const byId = new Map();
    for (const m of ledgerState.missions) {
      if (m && m.id) byId.set(m.id, { id: m.id, title: m.title || m.id, count: 0 });
    }
    for (const p of ledgerState.proofs) {
      if (!p || !p.mission_id) continue;
      const cur = byId.get(p.mission_id) || {
        id: p.mission_id,
        title: p.mission_title || p.mission_id,
        count: 0,
      };
      cur.count += 1;
      byId.set(p.mission_id, cur);
    }
    const entries = [...byId.values()].sort((a, b) => {
      if (b.count !== a.count) return b.count - a.count;
      return a.title.localeCompare(b.title);
    });
    const prevValue = ledgerState.filters.missionId;
    missionSelect.innerHTML = `<option value="">All missions</option>${entries
      .map((e) => {
        const label = e.count > 0 ? `${e.title} (${e.count})` : e.title;
        return `<option value="${escapeHtml(e.id)}">${escapeHtml(label)}</option>`;
      })
      .join("")}`;
    if (prevValue && byId.has(prevValue)) {
      missionSelect.value = prevValue;
    } else if (prevValue) {
      const opt = document.createElement("option");
      opt.value = prevValue;
      opt.textContent = prevValue;
      missionSelect.appendChild(opt);
      missionSelect.value = prevValue;
    }
  };

  const resetLedgerFilters = () => {
    ledgerState.filters = { missionId: "", kind: "all", query: "" };
    if (missionSelect) missionSelect.value = "";
    if (searchInput) searchInput.value = "";
    renderFilteredLedger();
  };

  const renderFilteredLedger = () => {
    const counts = countLedgerKinds(ledgerState.proofs, {
      missionId: ledgerState.filters.missionId,
      query: ledgerState.filters.query,
    });
    if (kindPills) {
      kindPills.querySelectorAll(".filter-pill").forEach((btn) => {
        const kind = btn.dataset.kind || "all";
        btn.classList.toggle("active", kind === ledgerState.filters.kind);
        const badge = btn.querySelector(".pill-count");
        if (badge) badge.textContent = String(counts[kind] ?? 0);
      });
    }
    const filtered = filterLedgerProofs(ledgerState.proofs, ledgerState.filters);
    if (clearBtn) clearBtn.classList.toggle("hidden", !isFiltered());
    if (summaryEl) {
      const loaded = ledgerState.proofs.length;
      const total = Math.max(ledgerState.total, loaded);
      if (total === 0) {
        summaryEl.textContent = "0 accepted proofs";
      } else if (loaded < total) {
        summaryEl.textContent = `Showing ${filtered.length} of ${loaded} loaded (${total} total)`;
      } else {
        summaryEl.textContent = `Showing ${filtered.length} of ${total} proof${total === 1 ? "" : "s"}`;
      }
    }
    if (ledgerState.proofs.length === 0) {
      list.innerHTML = ledgerState.loadError
        ? `<li class="muted small">Could not load the ledger (${escapeHtml(ledgerState.loadError)}).</li>`
        : `<li class="muted small">No proofs have been accepted yet.</li>`;
    } else if (filtered.length === 0) {
      list.innerHTML = `
        <li class="filter-empty">
          <div>No loaded proofs match your filters.${before !== null ? " Try loading older proofs or clearing filters." : ""}</div>
          <button type="button" class="filter-clear" id="ledger-empty-clear">Clear filters</button>
        </li>`;
      const emptyClear = $("ledger-empty-clear");
      if (emptyClear) emptyClear.addEventListener("click", resetLedgerFilters);
    } else {
      list.innerHTML = filtered.map(ledgerRowHtml).join("");
    }
  };

  if (kindPills) {
    kindPills.querySelectorAll(".filter-pill").forEach((btn) => {
      btn.addEventListener("click", () => {
        ledgerState.filters.kind = btn.dataset.kind || "all";
        renderFilteredLedger();
      });
    });
  }
  if (missionSelect) {
    missionSelect.addEventListener("change", () => {
      ledgerState.filters.missionId = missionSelect.value;
      renderFilteredLedger();
    });
  }
  if (searchInput) {
    searchInput.addEventListener("input", () => {
      ledgerState.filters.query = searchInput.value;
      renderFilteredLedger();
    });
  }
  if (clearBtn) {
    clearBtn.addEventListener("click", resetLedgerFilters);
  }

  const loadPage = async () => {
    more.disabled = true;
    try {
      const q = before === null ? "" : `&before=${encodeURIComponent(before)}`;
      const data = await fetchJson(`/api/proofs?limit=100${q}`);
      ledgerState.loadError = null;
      ledgerState.total = Number(data.total) || 0;
      $("ledger-count").textContent = `${ledgerState.total} total`;
      if (Array.isArray(data.proofs) && data.proofs.length > 0) {
        ledgerState.proofs.push(...data.proofs);
      }
      before = data.next_before ?? null;
      more.classList.toggle("hidden", before === null);
      syncMissionOptions();
      renderFilteredLedger();
    } catch (e) {
      ledgerState.loadError = e.message;
      if (ledgerState.proofs.length === 0) {
        renderFilteredLedger();
      } else {
        list.insertAdjacentHTML("beforeend", `<li class="muted small">Could not load older proofs (${escapeHtml(e.message)}).</li>`);
      }
    } finally {
      more.disabled = false;
    }
  };
  more.addEventListener("click", loadPage);

  const [missionsResp] = await Promise.all([
    fetchJson("/api/missions").catch(() => ({ missions: [] })),
    loadPage(),
  ]);
  ledgerState.missions = missionsResp.missions || [];
  syncMissionOptions();
  renderFilteredLedger();
}

async function loadLedgerProof(root, hash) {
  let proof;
  try {
    proof = await fetchJson(`/api/proofs/${hash}`);
  } catch (e) {
    root.innerHTML = `<p><a class="proof-link" href="/proofs">← All proofs</a></p>
      <div class="muted">No accepted proof has patch SHA-256 <code>${escapeHtml(hash)}</code> (${escapeHtml(e.message)}).</div>`;
    return;
  }
  const isRefutation = proof.entry_kind === "refutation";
  const isHistoryEntry = !isRefutation && proof.entry_kind !== "subgoal";
  document.title = `${proof.task_title || proof.task_id} · ${isRefutation ? "Verified refutation" : "Verified proof"} · Sunstead`;
  const also = (proof.also_accepted_as || [])
    .map((a) => `<li><code>${escapeHtml(a.mission_id)}/${escapeHtml(a.task_id)}</code> by <code>${escapeHtml(a.contributor)}</code>, ${escapeHtml(fmtUtc(a.accepted_at))}</li>`)
    .join("");
  root.innerHTML = `
    <p><a class="proof-link" href="/proofs">← All proofs</a></p>
    <div class="proof-head">
      <div>
        <div class="${isRefutation ? "proof-kicker proof-kicker-refute" : "proof-kicker"}">${isRefutation ? "Kernel-verified refutation (¬ T)" : "Verified proof"} · ${escapeHtml(proof.mission_title || proof.mission_id)} · commit #${escapeHtml(proof.seq)} ${ledgerBadges(proof)}</div>
        <h2 class="serif-h2 ledger-proof-title">${escapeHtml(proof.task_title || proof.task_id)}</h2>
        <div class="proof-by">${contributorHtml(proof)}</div>
      </div>
      ${isHistoryEntry ? `<a class="btn-outline-ink" href="${escapeHtml(proof.history_mbox)}">history.mbox ↓</a>` : ""}
    </div>
    <div class="small ledger-upstream">Upstream: ${upstreamHtml(proof.upstream)}</div>
    ${renderDecompProvenanceHtml(proof)}
    ${proofDetailHtml(proof)}
    ${also ? `<div class="small ledger-also"><div class="kv-label">The same patch was also accepted as</div><ul>${also}</ul></div>` : ""}
  `;
  wireProofCopyButtons(root, proof);
}

function loadLedgerPage() {
  const root = $("ledger-root");
  const m = location.pathname.match(/^\/proofs\/([0-9a-f]{64})\/?$/);
  return m ? loadLedgerProof(root, m[1]) : loadLedgerList(root);
}

async function loadInitialFeedAndLeaderboard() {
  const [subs, lb] = await Promise.all([
    fetchJson("/api/submissions?limit=20"),
    fetchJson("/api/leaderboard"),
  ]);

  state.events = (subs.submissions || []).map((s) => ({
    kind:
      s.status === "verifying"
        ? "verification_started"
        : s.accepted
          ? "submission_accepted"
          : "submission_rejected",
    mission_id: s.mission_id,
    task_id: s.task_id,
    contributor: s.contributor,
    accepted: s.status === "verifying" ? null : s.accepted,
    score: s.score,
    summary: s.summary,
    timestamp: s.created_at,
  }));
  renderEvents();
  renderLeaderboard(lb.leaderboard || []);
}

function renderEvents() {
  const ul = $("event-feed");
  if (!ul) return;
  if (state.events.length === 0) {
    ul.innerHTML = `<li class="muted small" style="padding:10px">No proofs submitted yet. Point an agent at <code>/join.txt</code> to claim and verify an open theorem.</li>`;
    return;
  }
  ul.innerHTML = state.events
    .slice(0, 30)
    .map((ev) => {
      let cls = "verifying";
      let icon = "✦";
      if (ev.kind === "submission_accepted") { cls = "accepted"; icon = "✓"; }
      else if (ev.kind === "submission_rejected") { cls = "rejected"; icon = "✕"; }
      else if (ev.kind === "task_decomposed") { cls = "accepted"; icon = "◇"; }
      else if (ev.kind === "task_refuted") { cls = "refuted"; icon = "¬"; }
      else if (ev.kind === "decomposition_refuted") { cls = "rejected"; icon = "¬"; }
      else if (ev.kind === "lease_claimed") { cls = "claimed"; icon = "●"; }
      else if (ev.kind === "lease_released") { cls = "claimed"; icon = "○"; }
      const scoreBadge =
        ev.score !== null && ev.score !== undefined ? ` · score=${ev.score}` : "";
      return `
        <li class="event-item ${cls}">
          <div class="event-head">
            <span>${icon} ${escapeHtml(ev.mission_id)}${ev.task_id ? ` / ${escapeHtml(ev.task_id)}` : ""}</span>
            <span>${fmtTime(ev.timestamp)}</span>
          </div>
          <div><strong>${escapeHtml(ev.contributor || "hub")}</strong>${escapeHtml(scoreBadge)}</div>
          <div class="muted small">${escapeHtml(ev.summary)}</div>
        </li>
      `;
    })
    .join("");
}

function renderLeaderboard(entries) {
  const el = $("leaderboard");
  if (!entries.length) {
    el.innerHTML = `<div class="muted small">Awaiting first verified submission…</div>`;
    return;
  }
  el.innerHTML = entries
    .map((e, idx) => {
      const name = e.display_name || e.contributor;
      const socialHtml = renderSocialLinksHtml(e);
      const pts = e.points !== undefined ? `${e.points} pts · ` : "";
      const crowns = e.active_records > 0 ? ` · ★${e.active_records}` : "";
      return `
      <div class="lb-row">
        <div>
          <strong>#${idx + 1} ${escapeHtml(name)}</strong>${socialHtml}
          <div class="muted" style="font-size:11px;font-family:var(--mono)">${escapeHtml(e.contributor)}</div>
        </div>
        <div class="small" style="font-family:var(--mono);color:var(--teal);font-weight:500;text-align:right">
          <div>${pts}${e.verified_tasks} verified${crowns}</div>
          <div class="muted" style="font-size:10.5px">${e.accepted_submissions}/${e.total_submissions} accepted</div>
        </div>
      </div>
    `;
    })
    .join("");
}

function connectSse() {
  const es = new EventSource("/api/events");
  const ind = $("sse-indicator");
  // After a dropped stream (for example a deploy resetting the hub), events
  // sent while disconnected are lost, so reload state once the stream is back.
  let wasDisconnected = false;
  es.onopen = () => {
    ind.textContent = "LIVE";
    if (wasDisconnected) {
      wasDisconnected = false;
      state.proofCache.clear();
      scheduleRefresh();
    }
  };
  es.onerror = () => {
    ind.textContent = "RECONNECTING";
    wasDisconnected = true;
  };

  let refreshTimer = null;
  let refreshInFlight = false;
  let refreshQueued = false;

  const scheduleRefresh = () => {
    if (refreshTimer) clearTimeout(refreshTimer);
    refreshTimer = setTimeout(async () => {
      refreshTimer = null;
      if (refreshInFlight) {
        refreshQueued = true;
        return;
      }
      refreshInFlight = true;
      try {
        await loadMissions();
        const lb = await fetchJson("/api/leaderboard");
        renderLeaderboard(lb.leaderboard || []);
      } catch (err) {
        console.error("SSE refresh error", err);
      } finally {
        refreshInFlight = false;
        if (refreshQueued) {
          refreshQueued = false;
          scheduleRefresh();
        }
      }
    }, 750);
  };

  const handle = (e) => {
    try {
      const ev = JSON.parse(e.data);
      if ((ev.kind === "submission_accepted" || ev.kind === "task_refuted") && ev.mission_id && ev.task_id) {
        state.proofCache.delete(`${ev.mission_id}/${ev.task_id}`);
      }
      state.events.unshift(ev);
      state.events = state.events.slice(0, 40);
      renderEvents();
      scheduleRefresh();
    } catch (err) {
      console.error("SSE parse error", err);
    }
  };

  [
    "lease_claimed",
    "lease_released",
    "verification_started",
    "submission_accepted",
    "submission_rejected",
    "task_decomposed",
    "decomposition_refuted",
    "task_refuted",
  ].forEach((name) => es.addEventListener(name, handle));
}

function setupJoinModal() {
  const modal = $("join-modal");
  if (!modal) return;
  const promptText = `Read ${window.location.origin}/join.txt and contribute a verified patch to an open task on Sunstead.`;
  const promptEl = $("agent-prompt");
  if (promptEl) promptEl.textContent = promptText;

  const open = async () => {
    modal.classList.remove("hidden");
    try {
      const res = await fetch("/join.txt");
      $("join-txt-preview").textContent = await res.text();
    } catch {
      $("join-txt-preview").textContent = "Failed to load /join.txt";
    }
  };
  const close = () => modal.classList.add("hidden");

  [$("join-btn"), $("hero-join-btn"), ...document.querySelectorAll("[data-open-join]")].forEach((btn) => {
    if (btn) btn.addEventListener("click", open);
  });
  if ($("close-join")) $("close-join").addEventListener("click", close);
  if ($("join-backdrop")) $("join-backdrop").addEventListener("click", close);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !modal.classList.contains("hidden")) close();
  });
  if ($("copy-prompt")) {
    $("copy-prompt").addEventListener("click", async () => {
      await navigator.clipboard.writeText(promptText);
      $("copy-prompt").textContent = "Copied!";
      setTimeout(() => ($("copy-prompt").textContent = "Copy Prompt"), 1500);
    });
  }
}

async function init() {
  renderAttractorArt();
  setupJoinModal();
  const tasks = [loadHealth()];
  if ($("mission-tabs")) {
    state.pendingDeepLink = parseDeepLink(window.location.search);
    setupMissionFilters();
    setupTaskFilters();
    tasks.push(loadMissions(), loadInitialFeedAndLeaderboard());
  }
  if ($("ledger-root")) {
    tasks.push(loadLedgerPage());
  }
  await Promise.all(tasks);
  if ($("event-feed")) {
    connectSse();
  }
}

if (typeof document !== "undefined" && typeof window !== "undefined") {
  init();
}
