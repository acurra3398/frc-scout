// node --test: the merge rules every device relies on.
import assert from "node:assert/strict";
import { test } from "node:test";
import { newer, since } from "../api/_lib.js";

test("keeps new records and newer edits, drops older ones", () => {
  const stored = [null, JSON.stringify({ t: 1, r: { date: 10 } }), JSON.stringify({ t: 1, r: { date: 10 } })];
  const incoming = [["a", { date: 5 }], ["b", { date: 11 }], ["c", { date: 9 }]];
  assert.deepEqual(newer(incoming, stored, "date").map(([id]) => id), ["a", "b"]);
});

test("returns only what was saved after the device's last sync", () => {
  const flat = ["a", JSON.stringify({ t: 100, r: { id: "a" } }), "b", JSON.stringify({ t: 200, r: { id: "b" } })];
  assert.deepEqual(since(flat, 150), [{ id: "b" }]);
  assert.equal(since(flat, 0).length, 2);
  assert.deepEqual(since(null, 0), []);
});
