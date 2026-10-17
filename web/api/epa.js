import { inflateSync } from "node:zlib";

// GET /api/epa?year=2026 → {team: season EPA}. Read from Statbotics' public backup copy (its API has
// been down); public data, so no team code. Cached for 6 hours.
export default async function handler(req, res) {
  const year = Number(req.query.year) || new Date().getFullYear();
  const upstream = await fetch(`https://storage.googleapis.com/site_v1/team_years/${year}`);
  if (!upstream.ok) return res.status(502).json({ error: `Statbotics said ${upstream.status}` });
  const { team_years } = JSON.parse(inflateSync(Buffer.from(await upstream.arrayBuffer())).toString());
  const epa = Object.fromEntries(team_years.map((t) => [t.team, t.epa.total_points?.mean ?? t.epa.total_points]));
  res.setHeader("Cache-Control", "public, s-maxage=21600, stale-while-revalidate=86400");
  res.status(200).json(epa);
}
