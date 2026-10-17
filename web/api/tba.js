import { proxy } from "./_lib.js";

// GET /api/tba?path=/event/2026mdbob/matches — The Blue Alliance with the team's key (kept on the server).
export default (req, res) => proxy(req, res, "https://www.thebluealliance.com/api/v3", "X-TBA-Auth-Key", process.env.TBA_KEY);
