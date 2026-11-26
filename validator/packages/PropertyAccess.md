# Brief: property reads and writes

You are working in ree (roblox-engine-emulator), a Rust emulation of the Roblox engine that runs a game's Luau offline.
It is being turned into a code validator: a Luau snippet passes only if it would run without errors in Roblox. Read
`AGENTS.md` (repo rules) and `validator/HANDOFF.md` first. Branch `validator`, don't commit or push: leave the changes in
the working tree and report. **Starts after the ArgChecks brief has landed** (both touch `src/lua/raw.rs`).

## The problem

Measured in a Roblox 0.748 playtest: ~380 property writes give a different error than Roblox, and ~200 reads give a
different value type or an error Roblox doesn't.

```
roblox: M AdGui.Status w err Unable to assign property Status. EnumItem, number, or string expected, got table
ree:    M AdGui.Status w err Unable to assign property Status. Property is read only
roblox: M Animation.AnimationId w err Unable to assign property AnimationId. ContentId expected, got table
ree:    M Animation.AnimationId w err Unable to assign property AnimationId. string expected, got table
roblox: M BasePart.ResizeableFaces r Faces
ree:    M BasePart.ResizeableFaces r nil
roblox: M BoxHandleAdornment.DoubleSided r boolean
ree:    M BoxHandleAdornment.DoubleSided r err DoubleSided is not a valid member of BoxHandleAdornment "BoxHandleAdornment"
```

`r` reads the property and prints `typeof` of the result. `w` assigns `{}`, so every write must fail, and only the message
matters.

## The job

Find the general rules and fix them in one place each, never per property:

- **Writes** (`src/lua/raw.rs` `meta_newindex` ~1408, `newindex_fast`, `newindex_slow`): which check comes first (type
  vs read-only), the type name each property type reports (`ContentId`, `EnumItem, number, or string`, ...), and anything
  else the capture shows. Group `python validator/probe/surface_diff.py --list "M w"` by message shape before you write
  code.
- **Reads**: members that return nil where Roblox returns a value (often a datatype ree's getter doesn't build, e.g.
  `Faces`, `Axes`, `PhysicalProperties`), and members ree doesn't know at all. The unknown ones are mostly members
  added in 0.748 while `data/reflection.json` is 0.747. List them in the report and don't hand-add them: the dump bump is
  a separate step.
- Cite the capture (`Roblox Studio 0.748.0.7481526, validator/probe/expected`) in `docs/engine.md` where a rule changes.

## Constraints

- Hot paths read properties by interned id (`K::...`) and allocate nothing per access. Keep the fast paths fast: put the
  new checks on the error path wherever you can.
- A value a script reads must not change by accident (rur's golden tests depend on it). Only change what the capture
  proves.
- Don't touch method dispatch (`namecall_*`, already done by ArgChecks), `get_service`, or `validator/probe/*`.

## Verify

```sh
cargo build --release --locked --bin ree
python validator/probe/surface_diff.py              # "M w" and "M r" counts must drop; no other kind may rise
cargo test --release
node tools/parity/run.mjs && node tools/parity/run.mjs --server
```

Baseline before ArgChecks: server `M w 380`, `M r 214`, client `M w 385`, `M r 215`. Write down your own baseline when
you start. Add tests in `src/tests.rs` that fail without the change.

## Report

```
BRIEF: PropertyAccess
RULES: <what you found and fixed>
SURFACE: server w <before>-><after>, r <before>-><after>; client same; other kinds unchanged? <yes/no>
LEFT: <members that need the dump bump; anything else, with why>
TESTS: cargo test <pass/fail>, parity <pass/fail>
BLOCKED: <none | what>
```
