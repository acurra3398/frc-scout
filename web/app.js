// FRC Scout on the web (iPhone, Android, desktop). Same records as the iPad app (same JSON), saved on
// the device first and synced through /api/sync so several devices can scout different robots at once.

// ---------- storage ----------
const load = (key, fallback) => { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } };
const S = load("settings", { name: "", code: "", event: "", eventName: "", ourTeam: 0, station: 0, whole: false, type: "Qual", tab: "match" });
const DB = load("db", {});
// Older saves predate some of these; fill them in so nothing is lost.
Object.assign(DB, { matches: [], pits: [], rankings: [], prescouts: [], info: null, since: 0, eventNames: {}, ...DB });
DB.dirty = { m: [], p: [], s: [], ...(DB.dirty ?? {}) };
const saveAll = () => { localStorage.setItem("settings", JSON.stringify(S)); localStorage.setItem("db", JSON.stringify(DB)); };

// Swift's JSON dates count seconds from 2001-01-01, so both apps agree on "newer".
const now = () => Date.now() / 1000 - 978307200;
const uuid = () => crypto.randomUUID().toUpperCase();

// ---------- game ----------
const TYPES = ["Practice", "Qual", "Playoff"];
const STARTS = ["Depot", "Center", "Outpost"];
const ROLES = ["Scorer", "Passer", "Defense", "Mixed"];
const TOWER = [0, 10, 20, 30];
const TIERS = ["–", "Tier 1 · elite", "Tier 2 · strong", "Tier 3 · solid", "Tier 4 · weak"];
const TIER_COLOR = ["#999", "#16A34A", "var(--tele)", "#F59E0B", "var(--red)"];
const SEAT = (i) => `${i < 3 ? "R" : "B"}${(i % 3) + 1}`;
const SEAT_COLOR = ["--r1", "--r2", "--r3", "--b1", "--b2", "--b3"].map((v) => `var(${v})`);

function newMatch(fields = {}) {
  return { id: uuid(), event: "", scout: "", type: "Qual", match: 0, team: 0, alliance: "Red",
    autoClimb: false, autoNeutral: false, shootsOnMove: false, shots: [], accuracy: 0, driver: 0, defense: 0,
    died: false, tipped: false, eStopped: false, aStopped: false, noShoot: false,
    weaknesses: "", breaks: "", notes: "", date: now(), ...fields };
}
function newPit(team) {
  return { team, robustness: 0, drivetrain: "Swerve", hopper: 0, trench: false, bump: false, maxClimb: 0, autoClimb: false,
    shootsOnMove: false, floorIntake: false, outpostIntake: false, depotIntake: false, turret: false, range: 0, shotRate: 0,
    canPass: false, climbSeconds: 0, sideClimb: false, autoCount: 0, autoFuelClaim: 0, autoNeutral: false, autoConsistency: 0,
    role: "Scorer", driverYears: 0, worries: "", notes: "", updated: now() };
}
const towerPts = (m) => (m.autoClimb ? 15 : 0) + TOWER[Math.min(Math.max(m.climb ?? 0, 0), 3)];
const points = (m) => (m.autoFuel ?? 0) + (m.teleFuel ?? 0) + towerPts(m);
const hasData = (m) => ["autoFuel", "teleFuel", "passes", "climb", "startPos", "role"].some((k) => m[k] != null)
  || ["autoClimb", "autoNeutral", "shootsOnMove", "died", "tipped", "eStopped", "aStopped", "noShoot"].some((k) => m[k])
  || m.accuracy > 0 || m.driver > 0 || m.defense > 0 || m.shots.length > 0 || m.notes || m.weaknesses || m.breaks;
const label = (m) => `${m.type === "Qual" ? "Q" : m.type === "Playoff" ? "P" : "Pr"}${m.match}`;

const avg = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
/** Scouted numbers: null = never scouted (a dash); a real 0 shows as 0. */
const opt = (xs) => (xs.length ? avg(xs) : null);
const f1 = (x) => (x == null ? "–" : x.toFixed(1));
const nz = (x) => (x ? x : null);   // TBA/Statbotics numbers use 0 for missing

/** Per-team averages; blanks (not scored) stay out of each part's average, like the iPad. */
function stats() {
  const info = DB.info?.key === S.event ? DB.info : null;
  const here = DB.matches.filter((m) => m.event === S.event);
  const teams = new Set([...here.map((m) => m.team), ...Object.keys(info?.names ?? {}).map(Number)]);
  return [...teams].filter((t) => t > 0).map((team) => {
    const ms = here.filter((m) => m.team === team);
    const vals = (k) => ms.map((m) => m[k]).filter((v) => v != null);
    const auto = opt(vals("autoFuel")), tele = opt(vals("teleFuel"));
    const tower = ms.length ? avg(ms.map((m) => (m.autoClimb ? 15 : 0))) + (opt(vals("climb").map((c) => TOWER[Math.min(Math.max(c, 0), 3)])) ?? 0) : null;
    return { team, name: info?.names?.[team] ?? "", matches: ms.length, auto, tele, tower,
      points: ms.length ? (auto ?? 0) + (tele ?? 0) + (tower ?? 0) : null,
      passes: opt(vals("passes")), epa: info?.epa?.[team] ?? 0, opr: info?.opr?.[team] ?? 0, rank: info?.rank?.[team] ?? 0,
      died: ms.length ? avg(ms.map((m) => (m.died ? 1 : 0))) : null,
      robust: DB.pits.find((p) => p.team === team)?.robustness ?? 0,
      tier: DB.prescouts.find((p) => p.team === team)?.tier ?? 0 };
  });
}

/** What we know about a team so far: pit data, and how often it's been match scouted here. */
function status(team) {
  if (!team) return [];
  const n = DB.matches.filter((m) => m.event === S.event && m.team === team).length;
  return [!DB.pits.some((p) => p.team === team) && ["No pit data", "#F59E0B"], n === 0 ? ["First match", "var(--tele)"] : [`${n} match${n === 1 ? "" : "es"}`, null]].filter(Boolean);
}

// ---------- network ----------
async function api(path, options = {}) {
  const res = await fetch(path, { ...options, headers: { "x-team-code": S.code, "Content-Type": "application/json" } });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `server said ${res.status}`);
  return body;
}
const tba = (path) => api(`/api/tba?path=${encodeURIComponent(path)}`);
const nexus = (path) => api(`/api/nexus?path=${encodeURIComponent(path)}`);

const ORDER = (type, match) => TYPES.indexOf(type) * 1000 + match;
const fromTBA = (m) => {
  const n = m.comp_level === "qm" ? ["Qual", m.match_number] : m.comp_level === "sf" ? ["Playoff", m.set_number]
    : m.comp_level === "f" ? ["Playoff", 13 + m.match_number] : null;
  const team = (k) => Number(String(k).replace(/\D/g, "")) || 0;
  return n && { type: n[0], match: n[1], red: m.alliances.red.team_keys.map(team), blue: m.alliances.blue.team_keys.map(team) };
};
const fromNexus = (m) => {
  const [word, num, extra] = m.label.split(" ");
  const n = Number(num);
  if (extra || !n) return null;   // replays and odd labels
  const type = { Practice: "Practice", Qualification: "Qual", Playoff: "Playoff", Final: "Playoff" }[word];
  const nums = (xs) => (xs ?? []).map((t) => Number(t) || 0);
  return type && { type, match: word === "Final" ? 13 + n : n, red: nums(m.redTeams), blue: nums(m.blueTeams) };
};

/** Downloads names, schedule, rankings, OPR, EPA, pits and the live queue for the event. */
async function refreshEvent(quiet) {
  if (!S.event || !S.code) return;
  const key = S.event;
  const info = DB.info?.key === key ? DB.info : { key, names: {}, schedule: [], epa: {}, opr: {}, rank: {}, pits: {}, nowQueuing: "" };
  const notes = [];
  try {
    const teams = await tba(`/event/${key}/teams/simple`);
    info.names = Object.fromEntries(teams.map((t) => [t.team_number, t.nickname ?? ""]));
    info.schedule = (await tba(`/event/${key}/matches/simple`)).map(fromTBA).filter(Boolean);
    const ranks = await tba(`/event/${key}/rankings`).catch(() => null);
    if (ranks?.rankings) info.rank = Object.fromEntries(ranks.rankings.map((r) => [r.team_key.replace(/\D/g, ""), r.rank]));
    const oprs = await tba(`/event/${key}/oprs`).catch(() => null);
    if (oprs?.oprs) info.opr = Object.fromEntries(Object.entries(oprs.oprs).map(([k, v]) => [k.replace(/\D/g, ""), v]));
    notes.push(`${teams.length} teams, ${info.schedule.length} matches`);
  } catch (e) { notes.push(`TBA: ${e.message}`); }
  try {
    const live = await nexus(`/event/${key}`);
    info.nowQueuing = live.nowQueuing ?? "";
    const byMatch = new Map(info.schedule.map((m) => [ORDER(m.type, m.match), m]));
    for (const m of live.matches.map(fromNexus).filter(Boolean)) byMatch.set(ORDER(m.type, m.match), m);
    info.schedule = [...byMatch.values()].sort((a, b) => ORDER(a.type, a.match) - ORDER(b.type, b.match));
    info.pits = await nexus(`/event/${key}/pits`).catch(() => info.pits);
  } catch { /* events that don't queue with Nexus */ }
  try {
    const epa = await fetch(`/api/epa?year=${key.slice(0, 4)}`).then((r) => r.json());
    for (const t of Object.keys(info.names)) if (epa[t] != null) info.epa[t] = epa[t];
  } catch { /* Statbotics backup unreachable; try next time */ }
  DB.info = info;
  saveAll();
  if (!quiet) toast(notes.join(" · "));
  if (crew.every((c) => !hasData(c))) snapToSchedule();
  render();
}

let syncing = false;
let lastSync = "not yet";
/** Uploads what changed here and pulls what changed elsewhere since the last sync. */
async function sync(quiet = true) {
  if (!S.code || !S.event || syncing) return;
  syncing = true;
  try {
    const sent = { m: [...DB.dirty.m], p: [...DB.dirty.p], s: [...DB.dirty.s] };
    const out = await api("/api/sync", { method: "POST", body: JSON.stringify({
      event: S.event, since: DB.since,
      matches: DB.matches.filter((m) => sent.m.includes(m.id)),
      pits: DB.pits.filter((p) => sent.p.includes(p.team)),
      prescouts: DB.prescouts.filter((p) => sent.s.includes(p.team)),
    }) });
    const before = DB.matches.length + DB.pits.length + DB.prescouts.length;
    merge(DB.matches, out.matches, "id", "date");
    merge(DB.pits, out.pits, "team", "updated");
    merge(DB.rankings, out.rankings, "id", "date");
    merge(DB.prescouts, out.prescouts, "team", "updated");
    for (const k of ["m", "p", "s"]) DB.dirty[k] = DB.dirty[k].filter((x) => !sent[k].includes(x));   // keep anything saved mid-sync
    DB.since = out.next;
    lastSync = new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
    saveAll();
    if (!quiet) toast("Synced");
    if (out.matches.length || out.pits.length || out.prescouts?.length || before !== DB.matches.length + DB.pits.length + DB.prescouts.length) render();
  } catch (e) {
    lastSync = `failed (${e.message})`;
    if (!quiet) toast(`Sync failed: ${e.message}. Saved on this device.`);
  } finally { syncing = false; }
}
function merge(list, incoming, key, dateKey) {
  for (const r of incoming ?? []) {
    const i = list.findIndex((x) => x[key] === r[key]);
    if (i < 0) list.push(r);
    else if ((r[dateKey] ?? 0) > (list[i][dateKey] ?? 0)) list[i] = r;
  }
}

// ---------- tiny DOM helper ----------
function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs ?? {})) {
    if (v == null || v === false) continue;
    if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : String(kid));
  return el;
}
let toastTimer;
function toast(text) {
  const el = document.getElementById("toast");
  el.textContent = text;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 2600);
}
const section = (title, icon, color, onClear, ...kids) => h("section", { class: "card" },
  h("div", { class: "sec" }, h("span", { class: "icon", style: { background: color } }, icon), h("h2", { class: "grow" }, title),
    onClear && h("button", { class: "clear", onclick: () => { onClear(); render(); } }, "Clear")), ...kids);
function choice(options, value, set, color = "var(--accent)") {
  return h("div", { class: "choice" }, options.map(([v, text]) => h("button", {
    class: v === value ? "on" : "", style: v === value ? { background: color } : null, "aria-pressed": String(v === value),
    onclick: () => { set(v); render(); } }, text)));
}
const chip = (text, on, toggle, color) => h("button", { class: `chip${on ? " on" : ""}`, style: on ? { background: color } : null,
  "aria-pressed": String(on), onclick: () => { toggle(); render(); } }, text);
const badge = ([text, color]) => h("span", { class: "pill", style: { background: color ?? "#8E8E93" } }, text);
function counter(title, value, set, steps, color) {
  return h("div", { class: "counter" },
    h("div", { class: "top" }, h("b", {}, title),
      value != null && h("button", { class: "x", "aria-label": `Clear ${title}`, onclick: () => { set(undefined); render(); } }, "✕"),
      value != null ? h("span", { class: "num" }, value) : h("span", { class: "blank" }, "not scored")),
    h("div", { class: "btns" },
      h("button", { class: "minus", onclick: () => { set(Math.max(0, (value ?? 1) - 1)); render(); } }, value == null ? "0" : "−"),
      steps.map((n) => h("button", { style: { background: color }, onclick: () => { set((value ?? 0) + n); render(); } }, `+${n}`))));
}
function rating(title, value, set, color = "var(--accent)") {
  return h("div", { class: "rating" }, h("div", { class: "row" }, h("b", {}, title)),
    h("div", { class: "opts" }, [1, 2, 3, 4, 5].map((n) => h("button", {
      class: value >= n ? "on" : "", style: value >= n ? { background: color, opacity: n === value ? 1 : 0.55 } : null,
      onclick: () => { set(value === n ? 0 : n); render(); } }, n))));
}
const robustColor = (v) => (v === 0 ? "#bbb" : v <= 2 ? "var(--red)" : v === 3 ? "#F59E0B" : "#16A34A");

// ---------- match ----------
let crew = [];          // one robot, or all six (R1-R3, B1-B3), each its own record
let current = 0;
let seats = {};         // one-robot mode: each station keeps its own record this match
function freshCrew(match = 0) {
  const n = S.whole ? 6 : 1;
  crew = Array.from({ length: n }, (_, i) => newMatch({ type: S.type, match, alliance: (S.whole ? i : S.station) < 3 ? "Red" : "Blue" }));
  current = S.whole ? S.station : 0;
  seats = {};
  snapToSchedule();
  autofill();
}
const r = () => crew[Math.min(current, crew.length - 1)];
const schedule = () => (DB.info?.key === S.event ? DB.info.schedule ?? [] : []).filter((s) => s.type === r().type).sort((a, b) => a.match - b.match);
function setMatch(v) { crew.forEach((c) => (c.match = v)); seats = {}; autofill(); }
/** With a schedule, only real matches: the next one after what's been scouted, by default. */
function snapToSchedule() {
  const list = schedule();
  if (!list.length || list.some((s) => s.match === r().match)) return;
  const scouted = Math.max(0, ...DB.matches.filter((m) => m.event === S.event && m.type === r().type).map((m) => m.match));
  const target = r().match || scouted + 1;
  setMatch((list.find((s) => s.match >= target) ?? list.at(-1)).match);
}
function autofill() {
  if (DB.info?.key !== S.event) return;   // never fill from another event's schedule
  const m = DB.info.schedule?.find((s) => s.type === r().type && s.match === r().match);
  if (!m) return;
  const teams = [...m.red, ...m.blue];
  if (S.whole) crew.forEach((c, i) => { if (teams[i]) c.team = teams[i]; });
  else if (teams[S.station]) r().team = teams[S.station];
}
const edit = (change) => { const x = r(); change(x); x.date = now(); };
function teamLabel(m) {
  const info = DB.info?.key === S.event ? DB.info : null;
  return m.team ? info?.names?.[m.team] ?? "Not on this event's list" : schedule().length ? "Pick the match" : "Type the match number";
}

function matchView() {
  if (crew.length === 0) freshCrew();
  const m = r();
  const info = DB.info?.key === S.event ? DB.info : null;
  const multi = S.whole;
  const seatName = multi ? SEAT(current) : SEAT(S.station);
  const list = schedule();
  const at = list.findIndex((s) => s.match === m.match);
  // Typed numbers are saved on every keystroke and only the name/robots update in place: redrawing
  // the whole screen as a box loses focus would swallow the scout's next tap (like a +5).
  const setTeam = (e) => { r().team = Number(e.target.value.replace(/\D/g, "")) || 0; patchHeader(); };
  const matchBox = list.length
    ? h("div", { class: "picker" },
      h("button", { "aria-label": "Previous match", disabled: at <= 0 || null, onclick: () => { setMatch(list[at - 1].match); render(); } }, "‹"),
      h("div", { class: "pickbox" }, h("span", {}, m.match || "–"),
        h("select", { "aria-label": "Match", onchange: (e) => { setMatch(Number(e.target.value)); render(); } },
          list.map((s) => h("option", { value: s.match, selected: s.match === m.match || null }, `${label(s)}: ${s.red.join(" ")} vs ${s.blue.join(" ")}`)))),
      h("button", { "aria-label": "Next match", disabled: at >= list.length - 1 || null, onclick: () => { setMatch(list[at + 1].match); render(); } }, "›"))
    : h("input", { id: "in-match", inputmode: "numeric", value: m.match || "", placeholder: "–",
      oninput: (e) => { setMatch(Number(e.target.value.replace(/\D/g, "")) || 0); patchHeader(); } });
  const header = h("div", { class: "hero" },
    h("div", { class: "big" },
      h("div", {}, h("label", {}, "MATCH"), matchBox),
      h("div", {}, h("label", {}, `TEAM · ${seatName}`), h("input", { id: "in-team", inputmode: "numeric", value: m.team || "", placeholder: "–", oninput: setTeam })),
      h("div", { class: "est" }, h("b", {}, points(m)), h("small", {}, "PTS"))),
    h("div", { class: "teamline" }, h("b", { id: "in-name" }, teamLabel(m)), h("span", { id: "in-status" }, status(m.team).filter((s) => s[1]).map(badge))),
    choice(TYPES.map((t) => [t, t]), m.type, (t) => { S.type = t; crew.forEach((c) => (c.type = t)); snapToSchedule(); autofill(); saveAll(); }),
    choice([[false, "One robot"], [true, "Whole match"]], S.whole, (w) => { S.whole = w; saveAll(); freshCrew(m.match); }, "var(--navy)"),
    !multi && choice([0, 1, 2, 3, 4, 5].map((i) => [i, SEAT(i)]), S.station, (i) => {
      seats[S.station] = m;            // every seat is its own robot
      S.station = i; saveAll();
      crew = [seats[i] ?? newMatch({ type: m.type, match: m.match, alliance: i < 3 ? "Red" : "Blue" })];
      autofill();
    }, S.station < 3 ? "var(--red)" : "var(--blue)"),
    info?.nowQueuing && h("div", { class: "small", style: { fontWeight: 700, color: "var(--navy)" } }, `🕒 Now queuing: ${info.nowQueuing}`));

  const robots = multi && h("div", { class: "robots" }, crew.map((c, i) => h("button", {
    class: `robot${i === current ? " on" : ""}`, style: { color: SEAT_COLOR[i] }, onclick: () => { current = i; render(); } },
    h("span", { class: "tag", style: { background: SEAT_COLOR[i] } }, SEAT(i)),
    h("b", { id: `robot-${i}` }, c.team || "–"),
    h("small", {}, hasData(c) ? `${points(c)} pts entered` : status(c.team).map((s) => s[0]).join(" · ") || "–"))));

  const problems = h("div", { class: "grid2" },
    chip("Died / no-show", m.died, () => edit((x) => (x.died = !x.died)), "var(--red)"),
    chip("Tipped over", m.tipped, () => edit((x) => (x.tipped = !x.tipped)), "var(--red)"),
    chip("E-stopped", m.eStopped, () => edit((x) => (x.eStopped = !x.eStopped)), "var(--red)"),
    chip("A-stopped", m.aStopped, () => edit((x) => (x.aStopped = !x.aStopped)), "var(--auto)"),
    h("div", { style: { gridColumn: "span 2" } }, chip("Didn't shoot / drive only", m.noShoot, () => edit((x) => (x.noShoot = !x.noShoot)), "var(--red)")));
  const towerChoice = (color) => choice([[undefined, "–"], [0, "None"], [1, "L1"], [2, "L2"], [3, "L3"]], m.climb, (v) => edit((x) => (x.climb = v)), color);
  const roleChoice = (color) => choice([[undefined, "–"], ...ROLES.map((x) => [x, x])], m.role, (v) => edit((x) => (x.role = v)), color);
  const text = (title, key, placeholder) => h("label", { class: "field" }, h("span", {}, title),
    h("textarea", { placeholder, oninput: (e) => edit((x) => (x[key] = e.target.value)) }, m[key]));

  const form = m.type === "Playoff" ? [
    section("Playoff quick form", "🏆", "var(--end)", () => edit((x) => Object.assign(x, { role: undefined, climb: undefined,
      died: false, tipped: false, eStopped: false, aStopped: false, noShoot: false, defense: 0, teleFuel: undefined })),
      h("b", {}, "Role they played"), roleChoice("var(--end)"), h("b", {}, "Tower"), towerChoice("var(--end)"), problems,
      rating("Defense", m.defense, (v) => edit((x) => (x.defense = v)), "var(--end)"),
      counter("Fuel scored (optional)", m.teleFuel, (v) => edit((x) => (x.teleFuel = v)), [1, 5, 10], "var(--end)")),
    section("For the strategists", "💬", "#8E8E93", () => edit((x) => Object.assign(x, { weaknesses: "", breaks: "", notes: "" })),
      text("Weaknesses we can use", "weaknesses", "Slow intake, can't play through defense…"),
      text("Breaks or surprises", "breaks", "Lost the shooter, new auto…"),
      text("Defense and strategy notes", "notes", "Who they defended, where they shot from…")),
  ] : [
    section("Auto", "⏱", "var(--auto)", () => edit((x) => Object.assign(x, { startPos: undefined, autoFuel: undefined, autoClimb: false, autoNeutral: false })),
      choice([[undefined, "–"], ...STARTS.map((x) => [x, x])], m.startPos, (v) => edit((x) => (x.startPos = v)), "var(--auto)"),
      counter("Fuel scored", m.autoFuel, (v) => edit((x) => (x.autoFuel = v)), [1, 5], "var(--auto)"),
      h("div", { class: "grid2", style: { marginTop: "10px" } },
        chip("Climbed L1 · 15", m.autoClimb, () => edit((x) => (x.autoClimb = !x.autoClimb)), "var(--auto)"),
        chip("Neutral zone", m.autoNeutral, () => edit((x) => (x.autoNeutral = !x.autoNeutral)), "var(--auto)"))),
    section("Teleop", "🎮", "var(--tele)", () => edit((x) => Object.assign(x, { teleFuel: undefined, passes: undefined, role: undefined, shootsOnMove: false, shots: [] })),
      h("div", { class: "small" }, "Count fuel into the ACTIVE hub only."),
      counter("Fuel scored", m.teleFuel, (v) => edit((x) => (x.teleFuel = v)), [1, 5, 10], "var(--tele)"),
      counter("Passes (volleys)", m.passes, (v) => edit((x) => (x.passes = v)), [1], "var(--tele)"),
      roleChoice("var(--tele)"),
      chip("Shoots while moving", m.shootsOnMove, () => edit((x) => (x.shootsOnMove = !x.shootsOnMove)), "var(--tele)"),
      shotMap(m, multi)),
    section("End game", "🏁", "var(--end)", () => edit((x) => (x.climb = undefined)), towerChoice("var(--end)")),
    section("Problems", "⚠️", "var(--red)", () => edit((x) => Object.assign(x, { died: false, tipped: false, eStopped: false, aStopped: false, noShoot: false })), problems),
    section("Ratings", "⭐", "var(--accent)", () => edit((x) => Object.assign(x, { accuracy: 0, driver: 0, defense: 0 })),
      rating("Accuracy", m.accuracy, (v) => edit((x) => (x.accuracy = v))),
      rating("Driver", m.driver, (v) => edit((x) => (x.driver = v))),
      rating("Defense (blank if they didn't)", m.defense, (v) => edit((x) => (x.defense = v)))),
    section("Notes", "💬", "#8E8E93", () => edit((x) => (x.notes = "")),
      h("textarea", { placeholder: "Playstyle, weaknesses, breaks…", oninput: (e) => edit((x) => (x.notes = e.target.value)) }, m.notes)),
  ];

  const toSave = crew.filter((c) => c.team > 0 && (!multi || hasData(c)));
  return h("div", {}, h("h1", {}, "Match scouting"), header, robots, h("div", { class: "cols" }, ...form),
    h("button", { class: "save", disabled: !(m.match > 0 && toSave.length) || null, onclick: () => saveMatch(toSave) },
      multi ? `Save ${toSave.length} robot${toSave.length === 1 ? "" : "s"}` : "Save match"),
    h("button", { class: "danger", onclick: () => {
      if (confirm(`Clear everything scored for ${m.team || "this robot"}? The team and match stay.`)) {
        crew[current] = newMatch({ id: m.id, type: m.type, match: m.match, team: m.team, alliance: m.alliance }); render();
      } } }, `Clear ${seatName}'s answers`));
}

/** Updates the team box, name, status, and robot buttons without redrawing (see matchView). */
function patchHeader() {
  const team = document.getElementById("in-team");
  if (team && document.activeElement !== team) team.value = r().team || "";
  const name = document.getElementById("in-name");
  if (name) name.textContent = teamLabel(r());
  document.getElementById("in-status")?.replaceChildren(...status(r().team).filter((s) => s[1]).map(badge));
  crew.forEach((c, i) => { const el = document.getElementById(`robot-${i}`); if (el) el.textContent = c.team || "–"; });
}

function shotMap(m, multi) {
  const field = h("div", { class: "fieldmap", role: "img", "aria-label": "Field: tap where the robot shoots from", onclick: (e) => {
    const box = e.currentTarget.getBoundingClientRect();
    edit((x) => x.shots.push([+((e.clientX - box.left) / box.width).toFixed(3), +((e.clientY - box.top) / box.height).toFixed(3)]));
    render();
  } }, crew.flatMap((c, i) => (multi || c === m ? c.shots.map(([x, y]) => h("span", { class: "dot",
    style: { left: `${x * 100}%`, top: `${y * 100}%`, background: multi ? SEAT_COLOR[i] : "var(--fuel)" } }, multi ? SEAT(i) : "")) : [])));
  return h("div", { style: { marginTop: "12px" } },
    h("div", { class: "row" }, h("b", { style: { flex: 3 } }, "Where they shoot from"),
      h("span", { class: "small", style: { textAlign: "right" } }, `${m.shots.length} spots`),
      h("button", { class: "clear", style: { flex: "none" }, onclick: () => { edit((x) => x.shots.pop()); render(); } }, "Undo"),
      h("button", { class: "clear", style: { flex: "none" }, onclick: () => { edit((x) => (x.shots = [])); render(); } }, "Clear")),
    multi && choice(crew.map((_, i) => [i, SEAT(i)]), current, (i) => (current = i), SEAT_COLOR[current]),
    field);
}

function saveMatch(list) {
  for (const c of list) {
    Object.assign(c, { event: S.event, scout: S.name, date: now() });
    if (!S.whole) c.alliance = S.station < 3 ? "Red" : "Blue";
    merge(DB.matches, [structuredClone(c)], "id", "date");
    if (!DB.dirty.m.includes(c.id)) DB.dirty.m.push(c.id);
  }
  saveAll();
  toast(`Saved ${list.map((c) => c.team).join(", ")}`);
  freshCrew(r().match + 1);     // then snaps to the next real match when there's a schedule
  render();
  scrollTo(0, 0);
  sync(false);
}

// ---------- pit ----------
let pitTeam = null;
let pitDraft = null;
let pitTodo = false;
function pitView() {
  if (pitTeam != null) return pitForm();
  const info = DB.info?.key === S.event ? DB.info : null;
  const teams = [...new Set([...Object.keys(info?.names ?? {}).map(Number), ...DB.pits.map((p) => p.team)])].sort((a, b) => a - b);
  const done = teams.filter((t) => DB.pits.some((p) => p.team === t)).length;
  const shown = teams.filter((t) => !pitTodo || !DB.pits.some((p) => p.team === t));
  return h("div", {}, h("h1", {}, "Pit scouting"),
    h("div", { class: "card" }, h("b", {}, `${done} of ${teams.length} pit scouted`),
      h("div", { class: "bar" }, h("span", { style: { width: `${teams.length ? (done / teams.length) * 100 : 0}%` } })),
      h("div", { class: "row", style: { marginTop: "10px" } },
        h("input", { inputmode: "numeric", placeholder: "Team number", id: "pitnum" }),
        h("button", { class: "clear", style: { flex: "none", padding: "12px 16px" }, onclick: () => {
          const t = Number(document.getElementById("pitnum").value) || 0; if (t) openPit(t); } }, "Open")),
      chip("To do only", pitTodo, () => (pitTodo = !pitTodo), "var(--navy)")),
    teams.length === 0 && h("p", { class: "small" }, "Pick your event in Setup to list every team."),
    h("div", { class: "list grid" }, shown.map((t) => {
      const p = DB.pits.find((x) => x.team === t);
      return h("button", { class: "item", onclick: () => openPit(t) },
        h("span", { class: "num" }, t), h("span", { class: "name" }, info?.names?.[t] ?? ""),
        p ? h("span", { class: "badge", style: { background: robustColor(p.robustness) } }, p.robustness || "–") : h("span", { class: "small" }, "To do"));
    })));
}
function openPit(team) {
  pitTeam = team;
  pitDraft = structuredClone(DB.pits.find((p) => p.team === team) ?? newPit(team));
  render();
  scrollTo(0, 0);
}
function pitForm() {
  const p = pitDraft;
  const set = (k, v) => { p[k] = v; };
  const toggle = (text, k) => chip(text, p[k], () => set(k, !p[k]), "var(--accent)");
  const num = (text, k) => h("label", { class: "field" }, h("span", {}, text),
    h("input", { id: `pit-${k}`, inputmode: "numeric", value: p[k] || "", placeholder: "–", oninput: (e) => set(k, Number(e.target.value.replace(/\D/g, "")) || 0) }));
  const pick = (text, k, options) => h("label", { class: "field" }, h("span", {}, text),
    h("select", { onchange: (e) => set(k, typeof p[k] === "string" ? e.target.value : Number(e.target.value)) },
      options.map(([v, l]) => h("option", { value: v, selected: v === p[k] || null }, l))));
  const RUBRIC = ["–", "1 · Expect it to fail; likely DNP", "2 · Looks unreliable, maybe fixable", "3 · Normal robot, fine for elims",
    "4 · Sturdy and well built", "5 · Looks indestructible"];
  const name = DB.info?.names?.[p.team];
  return h("div", {},
    h("button", { class: "link", onclick: () => { pitTeam = null; render(); } }, "‹ All teams"),
    h("h1", {}, `${p.team}${name ? ` · ${name}` : ""}`),
    h("div", { class: "cols" },
      section("Robustness (1678 rubric)", "🛠", "#8E8E93", null,
        choice([0, 1, 2, 3, 4, 5].map((v) => [v, v || "–"]), p.robustness, (v) => set("robustness", v), robustColor(p.robustness)),
        h("div", { class: "small" }, RUBRIC[p.robustness])),
      section("Drivetrain", "🚗", "#8E8E93", null,
        pick("Drivetrain", "drivetrain", ["Swerve", "Tank", "Mecanum", "Other"].map((x) => [x, x])),
        h("div", { class: "grid2" }, toggle("Fits under trench", "trench"), toggle("Over the bump", "bump"))),
      section("Intake", "🟡", "var(--auto)", null,
        h("div", { class: "grid3" }, toggle("Floor", "floorIntake"), toggle("Outpost", "outpostIntake"), toggle("Depot", "depotIntake")),
        num("Fuel it holds (count it yourself)", "hopper")),
      section("Shooting", "🎯", "var(--tele)", null,
        pick("Range", "range", [[0, "Not sure"], [1, "At the hub"], [2, "Anywhere in our zone"], [3, "From the neutral zone"]]),
        num("Shot rate (fuel / second, claimed)", "shotRate"),
        h("div", { class: "grid2" }, toggle("Turret", "turret"), toggle("Shoots while moving", "shootsOnMove"),
          h("div", { style: { gridColumn: "span 2" } }, toggle("Passes fuel from midfield to its side", "canPass")))),
      section("Tower", "🏁", "var(--end)", null,
        choice([0, 1, 2, 3].map((v) => [v, v ? `L${v}` : "None"]), p.maxClimb, (v) => set("maxClimb", v), "var(--end)"),
        num("Seconds to climb", "climbSeconds"),
        h("div", { class: "grid2" }, toggle("Climbs on the side", "sideClimb"), toggle("L1 in auto", "autoClimb"))),
      section("Auto", "⏱", "var(--auto)", null,
        num("Autos they can run", "autoCount"), num("Fuel in their best auto", "autoFuelClaim"),
        toggle("Goes to the neutral zone", "autoNeutral"),
        pick("How often their auto works", "autoConsistency", ["Not asked", "Still testing / rarely", "About half the time", "Most matches", "Every match"].map((l, i) => [i, l]))),
      section("Team", "👥", "#8E8E93", null,
        pick("Role they want", "role", ROLES.map((x) => [x, x])),
        pick("Driver experience", "driverYears", [[0, "Not sure"], [1, "1st year"], [2, "2nd year"], [3, "3+ years"]])),
      section("Notes", "💬", "#8E8E93", null,
        h("textarea", { placeholder: "What's broken or worrying them?", oninput: (e) => set("worries", e.target.value) }, p.worries),
        h("textarea", { placeholder: "Architecture, autos, anything odd…", style: { marginTop: "8px" }, oninput: (e) => set("notes", e.target.value) }, p.notes))),
    h("button", { class: "save", onclick: () => {
      p.updated = now();
      merge(DB.pits, [structuredClone(p)], "team", "updated");
      if (!DB.dirty.p.includes(p.team)) DB.dirty.p.push(p.team);
      saveAll(); toast(`Saved pit · ${p.team}`); pitTeam = null; render(); sync(false);
    } }, "Save pit record"));
}

// ---------- teams ----------
let teamSort = "points";
let openTeam = null;
let unscoutedOnly = false;
function teamsView() {
  if (openTeam != null) return teamDetail(openTeam);
  const keyOf = (s) => (teamSort === "team" ? -s.team : teamSort === "rank" ? -(s.rank || 999) : s[teamSort] ?? -1);
  const rows = stats().filter((s) => !unscoutedOnly || s.matches === 0).sort((a, b) => keyOf(b) - keyOf(a));
  const unit = { points: "pts", epa: "EPA", tower: "tower", auto: "auto", tele: "tele", rank: "rank", team: "pts" }[teamSort];
  const value = (s) => (teamSort === "rank" ? s.rank || "–" : teamSort === "epa" ? f1(nz(s.epa)) : f1(teamSort === "team" ? s.points : s[teamSort]));
  return h("div", {}, h("h1", {}, "Teams"),
    h("div", { class: "row" },
      h("label", { class: "field" }, h("span", {}, "Sort by"),
        h("select", { onchange: (e) => { teamSort = e.target.value; render(); } },
          [["points", "Scouted points"], ["epa", "Season EPA"], ["tower", "Tower points"], ["auto", "Auto fuel"], ["tele", "Teleop fuel"], ["rank", "Rank"], ["team", "Team number"]]
            .map(([v, l]) => h("option", { value: v, selected: v === teamSort || null }, l)))),
      h("div", { style: { paddingTop: "20px" } }, chip("Not scouted yet", unscoutedOnly, () => (unscoutedOnly = !unscoutedOnly), "var(--navy)"))),
    rows.length === 0 && h("p", { class: "small" }, unscoutedOnly ? "Every team has been scouted at least once." : "Pick your event in Setup, or scout a match."),
    h("div", { class: "list grid" }, rows.map((s) => h("button", { class: "item", onclick: () => { openTeam = s.team; render(); scrollTo(0, 0); } },
      h("span", { class: "num" }, s.team, s.tier ? h("small", { class: "tier", style: { color: TIER_COLOR[s.tier] } }, ` T${s.tier}`) : ""),
      h("span", { class: "name" }, `${s.name}${s.matches ? ` · ${s.matches}m` : " · not scouted"}`),
      h("span", { class: "val" }, value(s), h("div", { class: "small" }, unit))))));
}
function teamDetail(team) {
  const s = stats().find((x) => x.team === team) ?? { team };
  const all = DB.matches.filter((m) => m.team === team).sort((a, b) => ORDER(b.type, b.match) - ORDER(a.type, a.match));
  const ms = all.filter((m) => m.event === S.event);
  const elsewhere = Object.entries(all.filter((m) => m.event !== S.event).reduce((g, m) => ((g[m.event] ??= []).push(m), g), {}));
  const pit = DB.pits.find((p) => p.team === team);
  const pre = structuredClone(DB.prescouts.find((p) => p.team === team) ?? { team, tier: 0, notes: "", updated: 0 });
  const tile = (title, v) => h("div", { class: "tile" }, h("b", {}, v), h("small", {}, title));
  const said = (m) => [m.weaknesses && `weakness: ${m.weaknesses}`, m.breaks && `broke: ${m.breaks}`, m.notes].filter(Boolean);
  return h("div", {},
    h("button", { class: "link", onclick: () => { openTeam = null; render(); } }, "‹ All teams"),
    h("h1", {}, `${team}${s.name ? ` · ${s.name}` : ""}`),
    h("div", { class: "card tiles" }, tile("Avg points", f1(s.points)), tile("Season EPA", f1(nz(s.epa))), tile("OPR", f1(nz(s.opr))),
      tile("Auto fuel", f1(s.auto)), tile("Tele fuel", f1(s.tele)), tile("Tower", f1(s.tower)),
      tile("Rank", s.rank || "–"), tile("Died", s.died == null ? "–" : `${Math.round(s.died * 100)}%`), tile("Robust", pit?.robustness || "–")),
    h("div", { class: "cols" },
      section("Pre-scout", "🔭", TIER_COLOR[pre.tier] ?? "#8E8E93", null,
        choice(TIERS.map((_, i) => [i, i ? `T${i}` : "–"]), pre.tier, (v) => { savePre({ ...pre, tier: v }); }, TIER_COLOR[pre.tier]),
        h("div", { class: "small" }, TIERS[pre.tier]),
        h("textarea", { placeholder: "What did you see in videos, TBA, or past events?", style: { marginTop: "8px" },
          onchange: (e) => savePre({ ...pre, notes: e.target.value }) }, pre.notes)),
      pit && section("Pit", "🔧", "#8E8E93", null,
        h("p", { class: "small" }, [pit.drivetrain, pit.hopper ? `holds ${pit.hopper}` : null, pit.maxClimb ? `climbs L${pit.maxClimb}` : null,
          pit.turret ? "turret" : null, pit.canPass ? "passes" : null].filter(Boolean).join(" · ")),
        pit.worries && h("p", {}, `⚠️ ${pit.worries}`), pit.notes && h("p", {}, pit.notes))),
    section("Matches", "📋", "#8E8E93", null,
      ms.length === 0 && h("p", { class: "small" }, "Not scouted yet at this event."),
      ms.map((m) => h("div", { class: "match" },
        h("b", {}, `${m.type} ${m.match} · ${m.alliance} · ${points(m)} pts`),
        h("div", { class: "small" }, `auto ${m.autoFuel ?? "–"} · tele ${m.teleFuel ?? "–"} · ${m.climb != null ? (m.climb ? `L${m.climb}` : "no climb") : "climb –"}${m.died ? " · DIED" : ""}${m.eStopped ? " · E-STOP" : ""}${m.noShoot ? " · NO SHOTS" : ""}`),
        said(m).map((t) => h("div", {}, t)),
        h("div", { class: "small" }, m.scout)))),
    elsewhere.length > 0 && section("Other events", "🕘", "#8E8E93", null,
      elsewhere.map(([key, list]) => h("div", { class: "match" },
        h("b", {}, DB.eventNames[key] ? `${DB.eventNames[key]} (${key})` : key),
        h("div", { class: "small" }, `${list.length} matches scouted · ${f1(opt(list.filter(hasData).map(points)))} avg pts`),
        list.flatMap((m) => said(m).map((t) => h("div", {}, `${label(m)}: ${t}`)))))));
}
function savePre(p) {
  p.updated = now();
  merge(DB.prescouts, [p], "team", "updated");
  if (!DB.dirty.s.includes(p.team)) DB.dirty.s.push(p.team);
  saveAll(); render(); sync();
}

// ---------- setup ----------
let events = null;
let eventSearch = "";
let installPrompt = null;
addEventListener("beforeinstallprompt", (e) => { e.preventDefault(); installPrompt = e; render(); });
const standalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone;
const ios = /iPhone|iPad|iPod/.test(navigator.userAgent);
function setupView() {
  const input = (title, key, attrs = {}) => h("label", { class: "field" }, h("span", {}, title),
    h("input", { id: `set-${key}`, value: S[key] || "", ...attrs, oninput: (e) => { S[key] = attrs.inputmode ? Number(e.target.value) || 0 : e.target.value.trim(); saveAll(); } }));
  const found = (events ?? []).filter((e) => !eventSearch || `${e.name} ${e.key} ${e.city ?? ""}`.toLowerCase().includes(eventSearch.toLowerCase())).slice(0, 40);
  const mine = [...new Set(DB.matches.map((m) => m.event).filter(Boolean))].sort();
  return h("div", {}, h("h1", {}, "Setup"),
    !standalone && h("div", { class: "card install" }, h("h2", {}, "Install FRC Scout"),
      installPrompt
        ? [h("p", { class: "small" }, "Adds FRC Scout to your home screen or app list. It opens like an app and works offline."),
          h("button", { class: "save", onclick: async () => { installPrompt.prompt(); await installPrompt.userChoice; installPrompt = null; render(); } }, "Install app")]
        : ios
          ? h("p", {}, "In Safari, tap ", h("b", {}, "Share"), " (the square with the arrow), then ", h("b", {}, "Add to Home Screen"), ". FRC Scout then opens like an app and works offline.")
          : h("p", { class: "small" }, "In Chrome or Edge, use the install icon in the address bar (or ⋮ › Install app). On Android: ⋮ › Add to Home screen.")),
    h("div", { class: "card" },
      input("Your name", "name", { autocomplete: "name" }),
      input("Team code (ask your lead scout)", "code", { type: "password", autocomplete: "off" }),
      input("Our team number", "ourTeam", { inputmode: "numeric" }),
      h("p", { class: "small" }, S.event ? `Event: ${S.eventName || S.event} (${S.event})` : "No event picked yet."),
      h("div", { class: "grid2" },
        h("button", { class: "clear", style: { padding: "12px" }, onclick: findMine }, "Find our event"),
        h("button", { class: "clear", style: { padding: "12px" }, onclick: loadEvents }, "Pick an event"))),
    events && h("div", { class: "card" },
      h("input", { placeholder: "Search events", value: eventSearch, oninput: (e) => { eventSearch = e.target.value; render(); }, id: "evsearch" }),
      h("div", { class: "list" }, found.map((e) => h("button", { class: "item", onclick: () => chooseEvent(e) },
        h("span", { class: "name", style: { color: "var(--text)" } }, h("b", {}, e.name), h("div", { class: "small" }, `${e.key} · ${e.start_date ?? ""}`)))))),
    mine.length > 0 && h("div", { class: "card" }, h("h2", {}, "Events on this device"),
      h("p", { class: "small" }, "Scouting from every competition stays here. Tap one to look at it again."),
      h("div", { class: "list" }, mine.map((key) => h("button", { class: "item", disabled: key === S.event || null, onclick: () => chooseEvent({ key, name: DB.eventNames[key] ?? "" }) },
        h("span", { class: "name", style: { color: "var(--text)" } }, h("b", {}, DB.eventNames[key] ?? key), h("div", { class: "small" }, key)),
        h("span", { class: "small" }, key === S.event ? "current" : `${DB.matches.filter((m) => m.event === key).length} matches`))))),
    h("div", { class: "card" }, h("h2", {}, "Sync"),
      h("p", { class: "small" }, `Last sync: ${lastSync}. Every save syncs right away, and the app checks for other devices' scouting every 20 seconds.`),
      h("p", { class: "small" }, `${DB.matches.filter((m) => m.event === S.event).length} match records · ${DB.pits.length} pit records · ${DB.dirty.m.length + DB.dirty.p.length + DB.dirty.s.length} waiting to upload`),
      h("div", { class: "grid2" },
        h("button", { class: "clear", style: { padding: "12px" }, onclick: () => sync(false) }, "Sync now"),
        h("button", { class: "clear", style: { padding: "12px" }, onclick: () => refreshEvent(false) }, "Refresh event data"))),
    h("div", { class: "card" }, h("h2", {}, "Android app"),
      h("p", { class: "small" }, "Prefer a real Android app? Download it, open the file, and allow installing from your browser when asked."),
      h("a", { class: "link", href: "/android/frc-scout.apk", download: true }, "Download FRC Scout for Android")));
}
async function findMine() {
  if (!S.ourTeam || !S.code) return toast("Enter the team code and your team number first.");
  try {
    const year = new Date().getFullYear();
    const mine = (await tba(`/team/frc${S.ourTeam}/events/${year}/simple`)).sort((a, b) => a.start_date.localeCompare(b.start_date));
    const today = new Date().toLocaleDateString("en-CA");   // yyyy-mm-dd, local time
    const e = mine.find((x) => x.start_date <= today && today <= x.end_date) ?? mine.find((x) => x.start_date > today) ?? mine.at(-1);
    if (e) chooseEvent(e); else toast(`No ${year} events for team ${S.ourTeam}.`);
  } catch (err) { toast(err.message); }
}
async function loadEvents() {
  if (!S.code) return toast("Enter the team code first.");
  try { events = (await tba(`/events/${new Date().getFullYear()}/simple`)).sort((a, b) => a.start_date.localeCompare(b.start_date)); render(); }
  catch (err) { toast(err.message); }
}
function chooseEvent(e) {
  Object.assign(S, { event: e.key, eventName: e.name || DB.eventNames[e.key] || "" });
  if (S.eventName) DB.eventNames[e.key] = S.eventName;
  DB.since = 0;              // pull this event's scouting from the start
  events = null; saveAll();
  freshCrew();
  render();
  toast(`Event: ${S.eventName || e.key}`);
  refreshEvent(true).then(() => sync());
}

// ---------- setup link ----------
// The iPad's "Set up a phone" QR opens /#code=…&event=…&name=…&team=… so scouts don't type anything.
// It's after the #, so it never reaches the server; it's removed from the address bar right away.
const link = new URLSearchParams(location.hash.slice(1));
if (link.get("code")) {
  S.code = link.get("code");
  if (link.get("event") && link.get("event") !== S.event) { S.event = link.get("event"); S.eventName = link.get("name") ?? ""; DB.since = 0; }
  if (S.event && S.eventName) DB.eventNames[S.event] = S.eventName;
  if (link.get("team")) S.ourTeam = Number(link.get("team")) || S.ourTeam;
  S.tab = S.name ? "match" : "setup";
  history.replaceState(null, "", location.pathname);
  saveAll();
}

// ---------- shell ----------
const views = { match: matchView, pit: pitView, teams: teamsView, setup: setupView };
function render() {
  const view = document.getElementById("view");
  const y = scrollY;
  const active = document.activeElement;
  const focusId = active?.id, caret = active?.selectionStart;
  view.replaceChildren(views[S.tab]());
  scrollTo(0, y);
  // Redrawing replaces the inputs; put the cursor back where the scout was typing.
  const again = focusId && document.getElementById(focusId);
  if (again) { again.focus({ preventScroll: true }); try { again.setSelectionRange(caret, caret); } catch { /* not a text input */ } }
  document.querySelectorAll("#tabs button").forEach((b) => b.classList.toggle("on", b.dataset.tab === S.tab));
}
document.querySelectorAll("#tabs button").forEach((b) => b.addEventListener("click", () => {
  S.tab = b.dataset.tab; saveAll(); render(); scrollTo(0, 0);
}));
if (!S.code || !S.event) S.tab = "setup";
freshCrew();
render();
sync().then(() => refreshEvent(true));   // sync first, so "the next match" knows what teammates scouted
setInterval(() => sync(), 20000);                         // other devices' scouting
setInterval(() => refreshEvent(true), 5 * 60 * 1000);     // schedule, rankings, EPA
if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js");
