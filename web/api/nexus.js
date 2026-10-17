import { proxy } from "./_lib.js";

// GET /api/nexus?path=/event/2026mdbob — Nexus (live queue, pits, alliances) with the team's Pull API key.
export default (req, res) => proxy(req, res, "https://frc.nexus/api/v1", "Nexus-Api-Key", process.env.NEXUS_KEY);
