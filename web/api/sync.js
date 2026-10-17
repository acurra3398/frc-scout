import { checkCode, newer, redis, since } from "./_lib.js";

// POST {event, since, matches, pits, rankings, prescouts}: stores records the server doesn't have (or older
// versions of), then returns every record saved after `since` plus where to start next time.
// Records are the iPad app's own JSON, so any device can merge them. Nothing is ever deleted here.
const UUID = /^[0-9A-Fa-f-]{36}$/;

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });
  if (!checkCode(req)) return res.status(401).json({ error: "Wrong team code" });
  const body = req.body ?? {};
  const event = String(body.event ?? "");
  if (!/^[a-z0-9]{2,32}$/.test(event)) return res.status(400).json({ error: "Bad event code" });
  const list = (x, ok) => (Array.isArray(x) && x.length <= 5000 && x.every((r) => r && typeof r === "object" && ok(r)) ? x : null);
  const matches = list(body.matches ?? [], (r) => UUID.test(r.id ?? "") && Number.isInteger(r.team));
  const rankings = list(body.rankings ?? [], (r) => UUID.test(r.id ?? "") && Array.isArray(r.order));
  const pits = list(body.pits ?? [], (r) => Number.isInteger(r.team) && r.team > 0);
  const prescouts = list(body.prescouts ?? [], (r) => Number.isInteger(r.team) && r.team > 0);
  if (!matches || !rankings || !pits || !prescouts) return res.status(400).json({ error: "Bad records" });

  const groups = [
    { key: `m:${event}`, items: matches.map((r) => [r.id, r]), date: "date" },
    { key: `r:${event}`, items: rankings.map((r) => [r.id, r]), date: "date" },
    { key: "p", items: pits.map((r) => [String(r.team), r]), date: "updated" }, // pit records follow a team everywhere
    { key: "s", items: prescouts.map((r) => [String(r.team), r]), date: "updated" }, // so do pre-scouts
  ].filter((g) => g.items.length > 0);

  try {
    const stored = await redis(groups.map((g) => ["HMGET", g.key, ...g.items.map(([id]) => id)]));
    const now = Date.now();
    const writes = groups
      .map((g, i) => [g.key, newer(g.items, stored[i], g.date)])
      .filter(([, keep]) => keep.length > 0)
      .map(([key, keep]) => ["HSET", key, ...keep.flatMap(([id, r]) => [id, JSON.stringify({ t: now, r })])]);
    // Writes and reads in one pipeline, so this device always sees what it just saved.
    const reads = [["HGETALL", `m:${event}`], ["HGETALL", `r:${event}`], ["HGETALL", "p"], ["HGETALL", "s"]];
    const [m, r, p, ps] = (await redis([...writes, ...reads])).slice(writes.length);
    const after = Number(body.since) || 0;
    // `next` overlaps by 15 s so a record another device saved mid-request is never skipped;
    // devices merge by id, so getting one twice is harmless.
    res.status(200).json({ next: now - 15000, matches: since(m, after), rankings: since(r, after), pits: since(p, after), prescouts: since(ps, after) });
  } catch (error) {
    res.status(502).json({ error: `Sync failed: ${error.message}` });
  }
}
