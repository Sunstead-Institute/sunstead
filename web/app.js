const state = {
  missions: [],
  activeMissionId: null,
  activeDetail: null,
  selectedTaskId: null,
  events: [],
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
  try {
    const h = await fetchJson("/api/health");
    if (h.docker_verifier_ready) {
      pill.textContent = h.verifier_label || "Sandbox Ready · Docker";
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

async function loadMissions() {
  const data = await fetchJson("/api/missions");
  state.missions = data.missions || [];

  const totalTasks = state.missions.reduce((acc, m) => acc + m.total_tasks, 0);
  const verifiedTasks = state.missions.reduce((acc, m) => acc + m.verified_tasks, 0);
  const openFrontier = state.missions.reduce((acc, m) => acc + (m.frontier_task_ids?.length || 0), 0);
  $("stat-verified").textContent = `${verifiedTasks}/${totalTasks}`;
  $("stat-frontier").textContent = `${openFrontier}`;
  $("stat-missions").textContent = `${state.missions.length}`;

  if (!state.activeMissionId && state.missions.length > 0) {
    state.activeMissionId = state.missions[0].id;
  }
  renderMissionTabs();
  if (state.activeMissionId) {
    await loadMissionDetail(state.activeMissionId);
  }
}

function renderMissionTabs() {
  const container = $("mission-tabs");
  container.innerHTML = state.missions
    .map((m) => {
      const pct = m.total_tasks > 0 ? Math.round((m.verified_tasks / m.total_tasks) * 100) : 0;
      const active = m.id === state.activeMissionId ? "active" : "";
      const modeLabel = m.mode === "hillclimb" ? "HILL-CLIMB" : "BLUEPRINT DAG";
      return `
        <button class="mission-tab ${active}" data-id="${escapeHtml(m.id)}">
          <div class="tab-top">
            <span class="badge-gold">Tier ${m.tier}</span>
            <span class="badge-teal">${modeLabel} · ${m.verified_tasks}/${m.total_tasks}</span>
          </div>
          <div class="tab-title">${escapeHtml(m.title)}</div>
          <div class="muted small" style="font-family:var(--mono)">${escapeHtml(m.id)}</div>
          <div class="progress-track"><div class="progress-fill" style="width:${pct}%"></div></div>
        </button>
      `;
    })
    .join("");

  container.querySelectorAll(".mission-tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.activeMissionId = btn.dataset.id;
      state.selectedTaskId = null;
      renderMissionTabs();
      loadMissionDetail(state.activeMissionId);
    });
  });
}

async function loadMissionDetail(missionId) {
  const detail = await fetchJson(`/api/missions/${encodeURIComponent(missionId)}`);
  state.activeDetail = detail;

  const manifest = detail.mission.manifest;
  $("active-tier").textContent = `Tier ${manifest.tier}`;
  $("active-mode").textContent =
    manifest.mode === "hillclimb"
      ? `HILL-CLIMB (${manifest.score_direction})`
      : "COMPLETION DAG";
  $("active-spec-hash").textContent = detail.mission.spec_sha256.slice(0, 23) + "…";
  $("active-spec-hash").title = `Frozen spec hash: ${detail.mission.spec_sha256}`;
  $("active-title").textContent = manifest.title;
  $("active-desc").textContent = manifest.description || "";

  if (!state.selectedTaskId && detail.tasks.length > 0) {
    state.selectedTaskId = detail.frontier[0] || detail.tasks[0].def.id;
  }

  renderDag(detail);
  renderInspector(detail);
}

function computeLayers(tasks) {
  const byId = new Map(tasks.map((t) => [t.def.id, t]));
  const memo = new Map();

  function depth(id) {
    if (memo.has(id)) return memo.get(id);
    const t = byId.get(id);
    if (!t || !t.def.depends_on || t.def.depends_on.length === 0) {
      memo.set(id, 0);
      return 0;
    }
    const d = 1 + Math.max(...t.def.depends_on.map(depth));
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

function nodePalette(task) {
  if (task.status === "verified") {
    return {
      fill: "#EEF7F7",
      stroke: "#2A7D7F",
      badge: "VERIFIED",
      badgeColor: "#2A7D7F",
      titleColor: "#0D1B3D",
    };
  }
  if (!task.unlocked) {
    return {
      fill: "#F2EFE7",
      stroke: "#C8C0B0",
      badge: "BLOCKED",
      badgeColor: "#7A7E87",
      titleColor: "#5A5E66",
    };
  }
  if (task.active_lease) {
    return {
      fill: "#EDF1F8",
      stroke: "#0D1B3D",
      badge: "LEASED",
      badgeColor: "#0D1B3D",
      titleColor: "#0D1B3D",
    };
  }
  return {
    fill: "#FDFBF5",
    stroke: "#C6A15A",
    badge: "FRONTIER",
    badgeColor: "#9F7C38",
    titleColor: "#1B1D1F",
  };
}

function renderDag(detail) {
  const svg = $("dag-svg");
  const tasks = detail.tasks;
  const manifest = detail.mission.manifest;
  const layers = computeLayers(tasks);

  const nodeW = 246;
  const nodeH = 92;
  const colGap = 86;
  const rowGap = 24;
  const padX = 32;
  const padY = 28;

  const numCols = Math.max(1, layers.size);
  const maxRows = Math.max(1, ...Array.from(layers.values()).map((col) => col.length));
  const width = Math.max(780, padX * 2 + numCols * nodeW + (numCols - 1) * colGap);
  const height = Math.max(330, padY * 2 + maxRows * nodeH + (maxRows - 1) * rowGap);

  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.style.minHeight = `${Math.min(height, 560)}px`;

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

  let edgesHtml = `<defs>
    <marker id="arrow-muted" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#B5AC9A" />
    </marker>
    <marker id="arrow-teal" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#2A7D7F" />
    </marker>
  </defs>`;

  const byId = new Map(tasks.map((t) => [t.def.id, t]));
  for (const t of tasks) {
    const dst = pos.get(t.def.id);
    for (const depId of t.def.depends_on || []) {
      const src = pos.get(depId);
      const depTask = byId.get(depId);
      if (!src || !dst) continue;
      const x1 = src.x + nodeW;
      const y1 = src.y + nodeH / 2;
      const x2 = dst.x;
      const y2 = dst.y + nodeH / 2;
      const mx = (x1 + x2) / 2;
      const satisfied = depTask && depTask.status === "verified";
      const stroke = satisfied ? "#2A7D7F" : "#BDB5A5";
      const marker = satisfied ? "url(#arrow-teal)" : "url(#arrow-muted)";
      edgesHtml += `<path d="M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}"
        fill="none" stroke="${stroke}" stroke-width="${satisfied ? 2 : 1.4}"
        stroke-dasharray="${satisfied ? "" : "4 4"}" marker-end="${marker}" />`;
      edgesHtml += `<circle cx="${x1}" cy="${y1}" r="2.8" fill="${stroke}" />`;
    }
  }

  let nodesHtml = "";
  for (const t of tasks) {
    const p = pos.get(t.def.id);
    const c = nodePalette(t);
    const sel = t.def.id === state.selectedTaskId ? "selected" : "";
    const shortTitle =
      t.def.title.length > 31 ? t.def.title.slice(0, 30) + "…" : t.def.title;
    let footer = `${t.attempts} run${t.attempts === 1 ? "" : "s"}`;
    if (manifest.mode === "hillclimb" && t.best_score !== null && t.best_score !== undefined) {
      footer = `best: ${t.best_score} · ${footer}`;
    } else if (t.verified_by) {
      footer = `verified by ${t.verified_by}`;
    } else if (t.active_lease) {
      footer = `leased: ${t.active_lease.contributor}`;
    }

    nodesHtml += `
      <g class="dag-node ${sel}" data-task-id="${escapeHtml(t.def.id)}" transform="translate(${p.x},${p.y})">
        <rect class="node-box" width="${nodeW}" height="${nodeH}" rx="5"
              fill="${c.fill}" stroke="${c.stroke}" stroke-width="1.5" />
        <line x1="12" y1="29" x2="${nodeW - 12}" y2="29" stroke="${c.stroke}" stroke-opacity="0.24" stroke-width="1" />
        <text x="12" y="20" fill="${c.badgeColor}" font-size="9.5" font-weight="700" letter-spacing="0.08em" font-family="Inter, sans-serif">${c.badge}</text>
        <text x="${nodeW - 12}" y="20" text-anchor="end" fill="#6F747D" font-size="10" font-family="JetBrains Mono, monospace">${escapeHtml(t.def.id)}</text>
        <text x="12" y="51" fill="${c.titleColor}" font-size="15.5" font-weight="600" font-family="Cormorant Garamond, Georgia, serif">${escapeHtml(shortTitle)}</text>
        <text x="12" y="75" fill="#5A5E66" font-size="10.8" font-family="JetBrains Mono, monospace">${escapeHtml(footer)}</text>
      </g>
    `;
  }

  svg.innerHTML = edgesHtml + nodesHtml;
  svg.querySelectorAll(".dag-node").forEach((g) => {
    g.addEventListener("click", () => {
      state.selectedTaskId = g.dataset.taskId;
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

  el.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap">
      <div>
        <span style="font-family:var(--serif);font-size:21px;font-weight:600;color:var(--indigo)">${escapeHtml(task.def.title)}</span>
        <span class="muted small" style="margin-left:8px"><code>${escapeHtml(task.def.id)}</code></span>
      </div>
      <a class="small" style="color:var(--teal);font-weight:500;text-decoration:none" href="/api/missions/${encodeURIComponent(m.id)}/bundle.tar.gz">Download live bundle (.tar.gz) ↓</a>
    </div>
    ${task.def.description ? `<p class="muted small" style="margin:6px 0 0">${escapeHtml(task.def.description)}</p>` : ""}
    <div class="inspector-grid">
      <div class="kv">
        <div class="kv-label">Allowed target_files</div>
        <div class="kv-val">${escapeHtml((task.def.target_files || []).join(", "))}</div>
      </div>
      <div class="kv">
        <div class="kv-label">Verifier Image (network=none)</div>
        <div class="kv-val">${escapeHtml(m.verifier.image)}</div>
      </div>
      ${scoreHtml}
      <div class="kv">
        <div class="kv-label">Submit Endpoint</div>
        <div class="kv-val">POST ${escapeHtml(origin)}/api/missions/${escapeHtml(m.id)}/tasks/${escapeHtml(task.def.id)}/submit</div>
      </div>
    </div>
  `;
}

async function loadInitialFeedAndLeaderboard() {
  const [subs, lb] = await Promise.all([
    fetchJson("/api/submissions?limit=20"),
    fetchJson("/api/leaderboard"),
  ]);

  state.events = (subs.submissions || []).map((s) => ({
    kind: s.accepted ? "submission_accepted" : "submission_rejected",
    mission_id: s.mission_id,
    task_id: s.task_id,
    contributor: s.contributor,
    accepted: s.accepted,
    score: s.score,
    summary: s.summary,
    timestamp: s.created_at,
  }));
  renderEvents();
  renderLeaderboard(lb.leaderboard || []);
}

function renderEvents() {
  const ul = $("event-feed");
  if (state.events.length === 0) {
    ul.innerHTML = `<li class="muted small" style="padding:10px">No verifier runs yet. Point an agent at <code>/join.txt</code> to begin.</li>`;
    return;
  }
  ul.innerHTML = state.events
    .slice(0, 30)
    .map((ev) => {
      let cls = "verifying";
      let icon = "✦";
      if (ev.kind === "submission_accepted") { cls = "accepted"; icon = "✓"; }
      else if (ev.kind === "submission_rejected") { cls = "rejected"; icon = "✕"; }
      else if (ev.kind === "lease_claimed") { cls = "claimed"; icon = "●"; }
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
    .map(
      (e, idx) => `
      <div class="lb-row">
        <div><strong>#${idx + 1} ${escapeHtml(e.contributor)}</strong></div>
        <div class="small" style="font-family:var(--mono);color:var(--teal);font-weight:500">
          ${e.verified_tasks} verified · ${e.accepted_submissions}/${e.total_submissions}
        </div>
      </div>
    `
    )
    .join("");
}

function connectSse() {
  const es = new EventSource("/api/events");
  const ind = $("sse-indicator");
  es.onopen = () => {
    ind.textContent = "LIVE";
  };
  es.onerror = () => {
    ind.textContent = "RECONNECTING";
  };

  const handle = async (e) => {
    try {
      const ev = JSON.parse(e.data);
      state.events.unshift(ev);
      state.events = state.events.slice(0, 40);
      renderEvents();
      await loadMissions();
      const lb = await fetchJson("/api/leaderboard");
      renderLeaderboard(lb.leaderboard || []);
    } catch (err) {
      console.error("SSE parse error", err);
    }
  };

  ["lease_claimed", "verification_started", "submission_accepted", "submission_rejected"].forEach(
    (name) => es.addEventListener(name, handle)
  );
}

function setupJoinModal() {
  const modal = $("join-modal");
  const promptText = `Read ${window.location.origin}/join.txt and contribute a verified patch to an open task on Sunstead.`;
  $("agent-prompt").textContent = promptText;

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

  $("join-btn").addEventListener("click", open);
  $("hero-join-btn").addEventListener("click", open);
  $("close-join").addEventListener("click", close);
  $("join-backdrop").addEventListener("click", close);
  $("copy-prompt").addEventListener("click", async () => {
    await navigator.clipboard.writeText(promptText);
    $("copy-prompt").textContent = "Copied!";
    setTimeout(() => ($("copy-prompt").textContent = "Copy Prompt"), 1500);
  });
}

(async function init() {
  renderAttractorArt();
  setupJoinModal();
  await Promise.all([loadHealth(), loadMissions(), loadInitialFeedAndLeaderboard()]);
  connectSse();
})();
