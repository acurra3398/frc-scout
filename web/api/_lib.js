// Shared by the API functions. Keys and the team code live in Vercel environment variables,
// never in the repo or the browser.
import { timingSafeEqual } from "node:crypto";

/** Every data request needs the team code, so strangers can't read or write the team's scouting. */
export function checkCode(req) {
  const given = Buffer.from(String(req.headers["x-team-code"] ?? ""));
  const real = Buffer.from(process.env.SYNC_CODE ?? "");
  return real.length > 0 && given.length === real.length && timingSafeEqual(given, real);
}

/** Upstash Redis over REST: one round trip for a list of commands. */
export async function redis(commands) {
  if (commands.length === 0) return [];
  const url = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN;
  const res = await fetch(`${url}/pipeline`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(commands),
  });
  if (!res.ok) throw new Error(`database said ${res.status}`);
  const out = await res.json();
  const failed = out.find((r) => r.error);
  if (failed) throw new Error(failed.error);
  return out.map((r) => r.result);
}

/**
 * Which incoming records to keep: new ones, and newer edits of known ones (by the record's own
 * date). `stored` holds what the database has for the same ids, as {t, r} JSON or null.
 */
export function newer(incoming, stored, dateKey) {
  return incoming.filter(([, record], i) => {
    if (!stored[i]) return true;
    const old = JSON.parse(stored[i]).r;
    return (record[dateKey] ?? 0) > (old?.[dateKey] ?? 0);
  });
}

/** HGETALL's flat [field, value, ...] list → records saved after `since` (server time, ms). */
export function since(flat, after) {
  const out = [];
  for (let i = 1; i < (flat ?? []).length; i += 2) {
    const { t, r } = JSON.parse(flat[i]);
    if (t > after) out.push(r);
  }
  return out;
}

/** Forwards a GET to TBA or Nexus with the server's key; only plain API paths are allowed. */
export async function proxy(req, res, base, header, key) {
  if (!checkCode(req)) return res.status(401).json({ error: "Wrong team code" });
  const path = String(req.query.path ?? "");
  if (!/^\/[A-Za-z0-9_/.-]{1,200}$/.test(path) || path.includes("..")) return res.status(400).json({ error: "Bad path" });
  const upstream = await fetch(base + path, { headers: { [header]: key ?? "" } });
  res.status(upstream.status);
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "private, max-age=20");
  res.send(await upstream.text());
}
