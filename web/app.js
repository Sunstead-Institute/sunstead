const state = {
  missions: [],
  activeMissionId: null,
  activeDetail: null,
  selectedTaskId: null,
  events: [],
  proofCache: new Map(), // "mission/task" -> accepted proof JSON
  collapsedDecomps: new Set(), // "mission:parent:decomp_id"
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

function isMissionCompleted(m) {
  return m && m.mode === "dag" && m.total_tasks > 0 && m.verified_tasks >= m.total_tasks;
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
  const pct = m.total_tasks > 0 ? Math.round((m.verified_tasks / m.total_tasks) * 100) : 0;
  const active = m.id === state.activeMissionId ? "active" : "";
  const doneClass = completed ? "mission-tab-completed" : "";
  const modeLabel = m.mode === "hillclimb" ? "HILL-CLIMB" : completed ? "COMPLETE" : "BLUEPRINT";
  const demoBadge = m.demo
    ? `<span class="badge-demo" title="Protocol sandbox: awards 0 leaderboard points">SANDBOX</span>`
    : "";
  return `
    <button class="mission-tab ${doneClass} ${active}" data-id="${escapeHtml(m.id)}">
      <div class="tab-top">
        <span style="display:inline-flex;align-items:center;gap:6px"><span class="badge-gold">Tier ${m.tier}</span>${demoBadge}</span>
        <span class="badge-teal">${modeLabel} · ${m.verified_tasks}/${m.total_tasks}</span>
      </div>
      <div class="tab-title">${escapeHtml(m.title)}</div>
      <div class="muted small" style="font-family:var(--mono)">${escapeHtml(m.id)}</div>
      <div class="progress-track"><div class="progress-fill" style="width:${pct}%"></div></div>
    </button>
  `;
}

function renderMissionTabs() {
  const activeContainer = $("mission-tabs");
  const completedSection = $("completed-missions-section");
  const completedContainer = $("completed-mission-tabs");
  const completedCount = $("completed-missions-count");

  const activeMissions = state.missions.filter((m) => !isMissionCompleted(m));
  const completedMissions = state.missions.filter((m) => isMissionCompleted(m));

  activeContainer.innerHTML = activeMissions.map((m) => renderMissionCardHtml(m, false)).join("");
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
        state.activeMissionId = btn.dataset.id;
        state.selectedTaskId = null;
        renderMissionTabs();
        loadMissionDetail(state.activeMissionId);
      });
    });
  };
  wire(activeContainer);
  wire(completedContainer);
}

async function loadMissionDetail(missionId) {
  const detail = await fetchJson(`/api/missions/${encodeURIComponent(missionId)}`);
  state.activeDetail = detail;

  const manifest = detail.mission.manifest;
  $("active-tier").textContent = `Tier ${manifest.tier}`;
  $("active-mode").textContent =
    manifest.mode === "hillclimb"
      ? `HILL-CLIMB (${manifest.score_direction})`
      : "PROOF BLUEPRINT";
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

  if (!state.selectedTaskId && detail.tasks.length > 0) {
    state.selectedTaskId = detail.frontier[0] || detail.tasks[0].def.id;
  }

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

function renderDag(detail) {
  const svg = $("dag-svg");
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
  const tasks = allTasks.filter((t) => !isHiddenByCollapse(t));
  const layers = computeLayers(tasks);

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

  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.style.minHeight = `${Math.min(height, 680)}px`;

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

  let defsHtml = `<defs>
    <marker id="arrow-muted" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#B5AC9A" />
    </marker>
    <marker id="arrow-teal" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1.5 L 9 5 L 0 8.5 z" fill="#2A7D7F" />
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
      const satisfied = depTask && depTask.status === "verified";
      const stroke = satisfied ? "#2A7D7F" : "#BDB5A5";
      const marker = satisfied ? "url(#arrow-teal)" : "url(#arrow-muted)";
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
    const activeChildDecomp = activeDecompByParent.get(t.def.id);
    const badgeLabel = isSub ? `${c.badge} · SUBGOAL` : c.badge;
    const shortTitle =
      t.def.title.length > 33 ? t.def.title.slice(0, 32) + "…" : t.def.title;
    const rawIdLabel = isSub && t.def.subgoal_id ? t.def.subgoal_id : t.def.id;
    const shortId =
      rawIdLabel.length > 20 ? rawIdLabel.slice(0, 19) + "…" : rawIdLabel;
    let footer = `${t.attempts} run${t.attempts === 1 ? "" : "s"}`;
    if (t.disputed_counterexample) {
      footer = `disputed ¬T by ${t.disputed_counterexample.refuter}`;
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
        <rect class="node-box" width="${nodeW}" height="${nodeH}" rx="5"
              fill="${c.fill}" stroke="${c.stroke}" stroke-width="1.5"
              ${isSub ? 'stroke-dasharray="4 2"' : ""} />
        <line x1="12" y1="29" x2="${nodeW - 12}" y2="29" stroke="${c.stroke}" stroke-opacity="0.24" stroke-width="1" />
        <text x="12" y="20" fill="${c.badgeColor}" font-size="9.5" font-weight="700" letter-spacing="0.08em" font-family="Inter, sans-serif">${escapeHtml(badgeLabel)}</text>
        <text x="${nodeW - 12}" y="20" text-anchor="end" fill="#6F747D" font-size="10" font-family="JetBrains Mono, monospace">${escapeHtml(shortId)}</text>
        <text x="12" y="51" fill="${c.titleColor}" font-size="15.5" font-weight="600" font-family="Cormorant Garamond, Georgia, serif">${escapeHtml(shortTitle)}</text>
        <text x="12" y="75" fill="#5A5E66" font-size="10.8" font-family="JetBrains Mono, monospace">${escapeHtml(footer)}</text>
      </g>
      ${collapsedPillHtml}
    `;
  }

  svg.innerHTML = defsHtml + clustersHtml + edgesHtml + nodesHtml;
  svg.querySelectorAll(".dag-node").forEach((g) => {
    g.addEventListener("click", () => {
      state.selectedTaskId = g.dataset.taskId;
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
  const bestKnownHtml =
    bk && typeof bk.value === "number"
      ? `<div class="kv"><div class="kv-label">Best Known Outside Sunstead${bk.proven_optimal ? " (proven optimal)" : ""}</div><div class="kv-val">${escapeHtml(bk.value)} · <a href="${escapeHtml(bk.url)}" target="_blank" rel="noopener" style="color:var(--teal);text-decoration:none" title="${escapeHtml(bk.source)}">source ↗</a><div class="muted" style="font-size:12px;margin-top:4px">Full points only for beating this; tying it pays 25.</div></div></div>`
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

  const disputedBannerHtml = task.disputed_counterexample
    ? `<div class="dispute-banner">
        <strong>Disputed Counterexample (¬ T):</strong>
        Kernel-verified refutation by <code>${escapeHtml(task.disputed_counterexample.refuter)}</code>
        (${escapeHtml(fmtUtc(task.disputed_counterexample.created_at))})
        ${task.disputed_counterexample.proof_id ? ` · <a class="proof-link" href="/proofs/${escapeHtml(task.disputed_counterexample.proof_id)}">inspect counterexample ↗</a>` : ""}
      </div>`
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
    ${disputedBannerHtml}
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
      <div class="kv">
        <div class="kv-label">Submit Endpoint</div>
        <div class="kv-val">POST ${escapeHtml(origin)}/api/missions/${escapeHtml(m.id)}/tasks/${escapeHtml(task.def.id)}/submit</div>
      </div>
      ${m.decomposition?.enabled && !task.def.decomp_id ? `<div class="kv"><div class="kv-label">v2 Decompose / Refute</div><div class="kv-val">POST .../tasks/${escapeHtml(task.def.id)}/decompose (allowlist) · /refute (open)</div></div>` : ""}
    </div>
    ${task.status === "verified" ? `<div class="proof-panel" id="proof-panel" aria-live="polite"><div class="muted small">Loading verified proof…</div></div>` : ""}
  `;
  el.querySelectorAll(".decomp-jump").forEach((btn) => {
    btn.addEventListener("click", () => {
      if (btn.dataset.jumpTask) {
        state.selectedTaskId = btn.dataset.jumpTask;
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
  if (task.status === "verified") loadProof(m.id, task.def.id);
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
  const task = taskUrl
    ? ` · <a class="proof-link" href="${escapeHtml(taskUrl)}" target="_blank" rel="noopener">upstream sorry ↗</a>`
    : "";
  return `${main}${up.license ? ` <span class="muted small">(${escapeHtml(up.license)})</span>` : ""}${task}`;
}

function contributorHtml(proof) {
  const name = proof.display_name || proof.contributor;
  return `<strong>${escapeHtml(name)}</strong> <span class="muted small"><code>${escapeHtml(proof.contributor)}</code></span>${renderSocialLinksHtml(proof)}`;
}

/** Diff, metadata and rebuild command for one accepted proof (task panel and ledger page). */
function proofDetailHtml(proof) {
  const specNote = proof.spec_is_current
    ? ""
    : `<div class="proof-warn small">Accepted under an earlier frozen spec than the one live now.</div>`;
  const proofId = String(proof.patch_sha256 || "").replace(/^sha256:/, "");
  const permalink = /^[0-9a-f]{64}$/.test(proofId) ? `<a class="proof-link" href="/proofs/${proofId}">permalink</a>` : "";
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
        <span class="kv-label">Accepted Lean 4 diff · ${escapeHtml((proof.files || []).join(", "))}</span>
        <button type="button" class="btn-outline-ink proof-copy" data-copy="patch" data-label="Copy diff">Copy diff</button>
      </div>
      <pre class="proof-diff" tabindex="0">${renderDiffHtml(proof.patch)}</pre>
    </div>
    <div class="proof-block">
      <div class="proof-block-head">
        <span class="kv-label">Rebuild and check it yourself (seed bundle + git am)</span>
        <button type="button" class="btn-outline-ink proof-copy" data-copy="rebuild" data-label="Copy command">Copy command</button>
      </div>
      <pre class="proof-cmd" tabindex="0">${escapeHtml(proof.how_to_rebuild)}</pre>
    </div>
    ${
      proof.verify_command
        ? `<div class="proof-block">
      <div class="proof-block-head">
        <span class="kv-label">Check it against upstream, without trusting Sunstead (<a class="proof-link" href="/proofs#verify-yourself">how</a>)</span>
        <button type="button" class="btn-outline-ink proof-copy" data-copy="verify" data-label="Copy command">Copy command</button>
      </div>
      <pre class="proof-cmd" tabindex="0">${escapeHtml(proof.verify_command)}</pre>
    </div>`
        : ""
    }
  `;
}

function wireProofCopyButtons(root, proof) {
  root.querySelectorAll(".proof-copy").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text =
        btn.dataset.copy === "patch"
          ? proof.patch
          : btn.dataset.copy === "verify"
            ? proof.verify_command
            : proof.how_to_rebuild;
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
  panel.innerHTML = `
    <div class="proof-head">
      <div>
        <div class="proof-kicker">Verified proof · commit #${escapeHtml(proof.seq)}</div>
        <div class="proof-by">${contributorHtml(proof)}</div>
      </div>
      <a class="btn-outline-ink" href="${escapeHtml(proof.history_mbox)}">history.mbox ↓</a>
    </div>
    ${proofDetailHtml(proof)}
  `;
  wireProofCopyButtons(panel, proof);
}

// ---------------- Verified Proofs Ledger (/proofs, /proofs/<sha256>) ----------------

function ledgerBadges(p) {
  const out = [];
  if (p.entry_kind === "refutation") {
    out.push(`<span class="ledger-badge ledger-badge-refute" title="Kernel-verified disproof (¬ statement)">refutation ¬</span>`);
  } else if (p.entry_kind === "subgoal") {
    out.push(`<span class="ledger-badge ledger-badge-decomp" title="Verified v2 decomposition subgoal">subgoal</span>`);
  } else if (p.entry_kind === "assembled") {
    out.push(`<span class="ledger-badge ledger-badge-ok" title="Auto-assembled decomposition proof verified via untouched ./verify">assembled ✓</span>`);
  }
  if (p.audit && p.audit.status === "passed") {
    out.push(`<span class="ledger-badge ledger-badge-ok" title="Independently replayed with stock Lean and leanchecker">audited ✓</span>`);
  } else if (p.audit && p.audit.status === "failed") {
    out.push(`<span class="ledger-badge ledger-badge-warn" title="Independent audit reported a failure">audit failed</span>`);
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
    if (d.target_kind === "root") parts.push(`root counterexample`);
  }
  if (Array.isArray(p.co_authors) && p.co_authors.length > 0) {
    const names = p.co_authors
      .map((ca) => `${escapeHtml(ca.display_name || ca.handle)}${ca.role ? ` (${escapeHtml(ca.role)})` : ""}`)
      .join(", ");
    parts.push(`co-authors: ${names}`);
  }
  return parts.length > 0 ? `<div class="muted small decomp-prov">${parts.join(" · ")}</div>` : "";
}

function renderAuditHtml(audit) {
  if (!audit) return "not run yet";
  const parts = [`<strong>${escapeHtml(audit.status)}</strong>`];
  if (audit.toolchain) parts.push(`<code>${escapeHtml(audit.toolchain)}</code>`);
  if (Array.isArray(audit.axioms)) {
    parts.push(`axioms: <code>${escapeHtml(audit.axioms.join(", ") || "none")}</code>`);
  }
  if (audit.audited_at) parts.push(escapeHtml(fmtUtc(audit.audited_at)));
  const runHref = safeHttpUrl(audit.run_url);
  if (runHref) {
    parts.push(`<a class="proof-link" href="${escapeHtml(runHref)}" target="_blank" rel="noopener">audit run ↗</a>`);
  }
  return parts.join(" · ");
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
  root.innerHTML = `
    <div class="card-header"><h3>All accepted proofs</h3><span id="ledger-count" class="muted small"></span></div>
    <ol id="ledger-list" class="ledger-list"></ol>
    <div class="ledger-more"><button type="button" id="ledger-more" class="btn-outline-ink hidden">Load older proofs</button></div>`;
  const list = $("ledger-list");
  const more = $("ledger-more");
  let before = null;
  const loadPage = async () => {
    more.disabled = true;
    try {
      const q = before === null ? "" : `&before=${encodeURIComponent(before)}`;
      const data = await fetchJson(`/api/proofs?limit=50${q}`);
      $("ledger-count").textContent = `${Number(data.total) || 0} total`;
      if (before === null && (!data.proofs || data.proofs.length === 0)) {
        list.innerHTML = `<li class="muted small">No proofs have been accepted yet.</li>`;
      } else {
        list.insertAdjacentHTML("beforeend", (data.proofs || []).map(ledgerRowHtml).join(""));
      }
      before = data.next_before ?? null;
      more.classList.toggle("hidden", before === null);
    } catch (e) {
      list.insertAdjacentHTML("beforeend", `<li class="muted small">Could not load the ledger (${escapeHtml(e.message)}).</li>`);
    } finally {
      more.disabled = false;
    }
  };
  more.addEventListener("click", loadPage);
  await loadPage();
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
  document.title = `${proof.task_title || proof.task_id} · Verified proof · Sunstead`;
  const also = (proof.also_accepted_as || [])
    .map((a) => `<li><code>${escapeHtml(a.mission_id)}/${escapeHtml(a.task_id)}</code> by <code>${escapeHtml(a.contributor)}</code>, ${escapeHtml(fmtUtc(a.accepted_at))}</li>`)
    .join("");
  root.innerHTML = `
    <p><a class="proof-link" href="/proofs">← All proofs</a></p>
    <div class="proof-head">
      <div>
        <div class="proof-kicker">Verified proof · ${escapeHtml(proof.mission_title || proof.mission_id)} · commit #${escapeHtml(proof.seq)} ${ledgerBadges(proof)}</div>
        <h2 class="serif-h2 ledger-proof-title">${escapeHtml(proof.task_title || proof.task_id)}</h2>
        <div class="proof-by">${contributorHtml(proof)}</div>
      </div>
      <a class="btn-outline-ink" href="${escapeHtml(proof.history_mbox)}">history.mbox ↓</a>
    </div>
    <div class="small ledger-upstream">Upstream: ${upstreamHtml(proof.upstream)}</div>
    ${renderDecompProvenanceHtml(proof)}
    <div class="small muted">Independent audit: ${renderAuditHtml(proof.audit)}</div>
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
      else if (ev.kind === "decomposition_refuted" || ev.kind === "task_refuted") { cls = "rejected"; icon = "¬"; }
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
      if (ev.kind === "submission_accepted" && ev.mission_id && ev.task_id) {
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

(async function init() {
  renderAttractorArt();
  setupJoinModal();
  const tasks = [loadHealth()];
  if ($("mission-tabs")) {
    tasks.push(loadMissions(), loadInitialFeedAndLeaderboard());
  }
  if ($("ledger-root")) {
    tasks.push(loadLedgerPage());
  }
  await Promise.all(tasks);
  if ($("event-feed")) {
    connectSse();
  }
})();
