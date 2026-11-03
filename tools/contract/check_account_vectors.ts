/**
 * Checks docs/vectors/account_v1.json (made by the Lua addon, tests/account_vectors.lua) with the
 * TypeScript reference tools/contract/account.ts: every code must decode to the same fields, every
 * invalid code must fail with the same error, and re-encoding must give the same text.
 *   bun tools/contract/check_account_vectors.ts docs/vectors/account_v1.json
 */
import { readFileSync } from "node:fs";
import {
  encodeLinkRequest, encodeProfile, makeWebCode, parseLinkRequest, parseProfile, parseWebCode, prettyWebCode,
  type LinkRequest, type ProfileSnapshot,
} from "./account.ts";

const path = process.argv[2] ?? "docs/vectors/account_v1.json";
const v = JSON.parse(readFileSync(path, "utf8"));
let pass = 0, fail = 0;
function expect(cond: boolean, what: string) {
  if (cond) pass++;
  else { fail++; console.log("FAIL " + what); }
}
/** deep equality, key order ignored (the Lua JSON writer sorts keys) */
const canon = (x: unknown): unknown =>
  Array.isArray(x) ? x.map(canon) : x && typeof x === "object"
    ? Object.fromEntries(Object.keys(x as object).sort().map((k) => [k, canon((x as Record<string, unknown>)[k])])) : x;
const same = (a: unknown, b: unknown) => JSON.stringify(canon(a)) === JSON.stringify(canon(b));

for (const w of v.webCodes) {
  expect(makeWebCode(w.seven) === w.code, `makeWebCode ${w.seven}`);
  expect(prettyWebCode(w.code) === w.pretty, `pretty ${w.code}`);
}
for (const w of v.webCodeInputs) {
  const r = parseWebCode(w.input);
  if (w.code !== null) expect(r.ok && r.code === w.code, `parseWebCode ${JSON.stringify(w.input)}`);
  else expect(!r.ok && r.error === w.error, `parseWebCode ${JSON.stringify(w.input)} -> ${w.error}, got ${JSON.stringify(r)}`);
}
for (const l of v.linkRequests) {
  const r = parseLinkRequest(l.code);
  expect(r.ok, `parse SRL1 ${l.code}`);
  if (r.ok) {
    const { ok: _ok, ...fields } = r;
    expect(same(fields, l.decoded), `SRL1 fields ${l.code}: ${JSON.stringify(fields)}`);
    const again = encodeLinkRequest({ ...fields, addon: fields.addon } as LinkRequest);
    expect(again === l.code, `SRL1 re-encode ${l.code} -> ${again}`);
  }
}
for (const l of v.linkRequestInvalid) {
  const r = parseLinkRequest(l.code);
  expect(!r.ok && r.error === l.error, `SRL1 invalid ${l.code.slice(0, 50)} -> ${l.error}, got ${JSON.stringify(r)}`);
}
for (const p of v.profiles) {
  const r = parseProfile(p.code);
  expect(r.ok, `parse SRP1 ${p.code.slice(0, 50)}`);
  if (r.ok) {
    const { ok: _ok, ...fields } = r;
    expect(same(fields, p.decoded), `SRP1 fields ${p.code.slice(0, 50)}:\n  ${JSON.stringify(fields)}\n  ${JSON.stringify(p.decoded)}`);
    expect(encodeProfile(fields as ProfileSnapshot) === p.code, `SRP1 re-encode ${p.code.slice(0, 50)}`);
  }
}
for (const p of v.profileInvalid) {
  const r = parseProfile(p.code);
  expect(!r.ok && r.error === p.error, `SRP1 invalid ${p.code.slice(0, 50)} -> ${p.error}, got ${JSON.stringify(r).slice(0, 80)}`);
}
console.log(`account vectors: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
