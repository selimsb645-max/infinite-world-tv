"use strict";
// INFINITE WORLD TV — Phase 08 dashboard frontend.
// Vanilla JS, no dependencies. Every value shown comes from
// /api/status (real system data); nothing is simulated client-side.

const $ = (id) => document.getElementById(id);
let role = null;

function fmt(value, suffix) {
  if (value === null || value === undefined || value === "") return "—";
  return String(value) + (suffix || "");
}
function fmtDuration(sec) {
  if (sec === null || sec === undefined) return "—";
  sec = Math.floor(sec);
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60),
        s = sec % 60;
  return h > 0 ? `${h}h ${m}m` : (m > 0 ? `${m}m ${s}s` : `${s}s`);
}
function fmtTime(unix) {
  if (!unix) return "—";
  return new Date(unix * 1000).toLocaleString();
}
function setChip(id, label) {
  const el = $(id);
  el.textContent = label || "—";
  el.className = "chip " + (label || "").toLowerCase().replace(" ", "-");
}
function setText(id, value) { $(id).textContent = fmt(value); }

async function api(path, options) {
  const resp = await fetch(path, options || {});
  if (resp.status === 401) { showLogin(); throw new Error("unauthorized"); }
  return resp;
}

function showLogin() {
  $("login-view").classList.remove("hidden");
  $("app-view").classList.add("hidden");
  $("logout").classList.add("hidden");
}
function showApp() {
  $("login-view").classList.add("hidden");
  $("app-view").classList.remove("hidden");
  $("logout").classList.remove("hidden");
}

$("login-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("login-error").textContent = "";
  const resp = await fetch("/api/login", {
    method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify({token: $("login-token").value}),
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || !data.ok) {
    $("login-error").textContent =
      data.error === "login_rate_limited"
        ? "Too many failed attempts — login is temporarily locked."
        : "Invalid token.";
    return;
  }
  role = data.role;
  $("login-token").value = "";
  showApp();
  refresh();
});

$("logout").addEventListener("click", async () => {
  await fetch("/api/logout", {method: "POST"});
  role = null;
  showLogin();
});

$("theme-toggle").addEventListener("click", () => {
  const current = document.documentElement.getAttribute("data-theme");
  const next = current === "dark" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", next);
  try { localStorage.setItem("iwt-theme", next); } catch (e) { /* ignore */ }
});
try {
  const saved = localStorage.getItem("iwt-theme");
  if (saved) document.documentElement.setAttribute("data-theme", saved);
} catch (e) { /* ignore */ }

async function refresh() {
  let status;
  try {
    const resp = await api("/api/status");
    status = await resp.json();
  } catch (e) { return; }
  render(status);
  refreshAlerts();
}

function render(s) {
  setChip("ov-health", s.overall === "ONLINE" ? "ONLINE" : s.overall);
  setChip("ov-game", s.game.label);
  setChip("ov-ai", s.ai.label);
  setChip("ov-gen", s.generation.label);
  setChip("ov-render", s.rendering.label);
  setChip("ov-stream", s.streaming.label);
  setChip("ov-monitor", s.monitoring.label);
  setText("ov-runtime", fmtDuration(s.runtime.dashboard_uptime_sec));
  setText("ov-world", s.game.world);
  setText("ov-level", s.game.level_name);
  setText("ov-mode", s.game.mode);
  setText("ov-fps", s.game.fps);
  setText("ov-cpu", fmt(s.system.cpu_percent, "%"));
  setText("ov-ram", fmt(s.system.ram.used_percent, "%"));
  setText("ov-disk", fmt(s.system.disk.free_gb, " GB"));
  setText("ov-lasterror", s.last_error);
  setText("ov-lastrecovery", s.last_recovery);

  setText("g-state", s.game.state);
  setText("g-world", s.game.world);
  setText("g-level", s.game.level_name);
  setText("g-seed", s.game.level_seed);
  setText("g-mode", s.game.mode);
  setText("g-score", s.game.score);
  setText("g-progress",
          s.game.progress === undefined ? null
            : Math.round(s.game.progress * 100) + "%");
  setText("g-difficulty", s.game.difficulty_index);
  setText("g-fps", s.game.fps);
  setText("g-ai", s.ai.present ? (s.ai.enabled ? "RUNNING" : "STOPPED")
                               : "not started");
  setText("g-ai-decisions", s.ai.decisions);
  setText("g-ai-levels",
          s.ai.levels_completed === undefined ? null
            : `${s.ai.levels_completed} / ${s.ai.levels_attempted}`);
  setText("g-ai-success",
          s.ai.success_rate === undefined ? null
            : Math.round(s.ai.success_rate * 100) + "%");

  const st = s.streaming;
  setText("s-state", st.state || st.label);
  setText("s-uptime", fmtDuration(st.uptime_sec));
  setText("s-res", st.resolution);
  setText("s-fps", st.target_fps === undefined ? null
                   : `${st.target_fps} / ${st.measured_fps}`);
  setText("s-bitrate", st.target_video_kbps === undefined ? null
                   : `${st.target_video_kbps} / ${st.measured_video_kbps} kbps`);
  setText("s-ffmpeg", st.ffmpeg_pid === undefined ? null
                   : (st.ffmpeg_running ? `running (pid ${st.ffmpeg_pid})`
                                        : "not running"));
  setText("s-reconnects", st.reconnect_count);
  setText("s-dropped", st.dropped_frames);
  setText("s-lasterror", st.last_error);
  setText("s-lastconn", fmtTime(st.started_unix));
  setText("s-config", st.config_summary);
  if (st.auto_recovery !== undefined && st.auto_recovery !== null) {
    $("auto-recovery").checked = !!st.auto_recovery;
  }
}

async function refreshAlerts() {
  try {
    const resp = await api("/api/alerts");
    const data = await resp.json();
    const list = $("alert-list");
    list.innerHTML = "";
    const items = (data.recent || []).slice().reverse();
    if (!items.length) {
      list.innerHTML = '<li class="muted">No alerts recorded.</li>';
      return;
    }
    for (const entry of items) {
      const li = document.createElement("li");
      li.textContent = `[${entry.severity}] ${entry.message}`;
      list.appendChild(li);
    }
  } catch (e) { /* alerts are best-effort */ }
}

function showResult(data) {
  $("control-result").textContent =
    (data.ok ? "OK: " : "FAILED: ") + JSON.stringify(data);
}

async function postControl(payload) {
  const resp = await api("/api/control", {
    method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify(payload),
  });
  const data = await resp.json().catch(() => ({ok: false}));
  showResult(data);
  refresh();
  return data;
}

document.querySelectorAll("[data-control]").forEach((button) => {
  button.addEventListener("click", () =>
    postControl({action: button.dataset.control}));
});
document.querySelectorAll("[data-game-command]").forEach((button) => {
  button.addEventListener("click", () =>
    postControl({action: "game_command",
                 command: button.dataset.gameCommand}));
});
document.querySelectorAll("[data-stream-command]").forEach((button) => {
  button.addEventListener("click", () => {
    const command = button.dataset.streamCommand;
    const payload = {action: "stream_command", command};
    if (command === "start" || command === "restart") {
      payload.confirm_public = $("confirm-public").checked;
      if (payload.confirm_public &&
          !window.confirm("Start/restart a PUBLIC livestream?")) return;
    }
    postControl(payload);
  });
});
$("quality-apply").addEventListener("click", () =>
  postControl({action: "stream_command", command: "configure_quality",
               preset: $("quality-preset").value}));
$("auto-recovery").addEventListener("change", () =>
  postControl({action: "stream_command", command: "set_auto_recovery",
               enabled: $("auto-recovery").checked}));

async function refreshLogs() {
  const params = new URLSearchParams();
  const source = $("log-source").value;
  const severity = $("log-severity").value;
  const q = $("log-q").value;
  if (source) params.set("source", source);
  if (severity) params.set("severity", severity);
  if (q) params.set("q", q);
  params.set("limit", "200");
  const resp = await api("/api/logs?" + params.toString());
  if (resp.status === 403) {
    $("log-table").querySelector("tbody").innerHTML =
      '<tr><td colspan="5">Log access requires the admin role.</td></tr>';
    return;
  }
  const data = await resp.json();
  const tbody = $("log-table").querySelector("tbody");
  tbody.innerHTML = "";
  for (const entry of (data.entries || []).slice().reverse()) {
    const tr = document.createElement("tr");
    for (const cell of [
        entry.ts ? (typeof entry.ts === "number"
                      ? fmtTime(entry.ts) : entry.ts) : "—",
        entry.severity, entry.source, entry.module, entry.message]) {
      const td = document.createElement("td");
      td.textContent = cell;
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
}
$("log-refresh").addEventListener("click", refreshLogs);
$("log-export").addEventListener("click", () => {
  const params = new URLSearchParams();
  const source = $("log-source").value;
  const severity = $("log-severity").value;
  const q = $("log-q").value;
  if (source) params.set("source", source);
  if (severity) params.set("severity", severity);
  if (q) params.set("q", q);
  window.location = "/api/logs/export?" + params.toString();
});

// Boot: if a session cookie already exists, /api/status succeeds
// and the app view appears; otherwise the login form stays.
(async () => {
  try {
    const resp = await fetch("/api/status");
    if (resp.ok) { showApp(); refresh(); return; }
  } catch (e) { /* offline */ }
  showLogin();
})();
setInterval(() => {
  if (!$("app-view").classList.contains("hidden")) refresh();
}, 3000);
