# Brief: method argument checks

You are working in ree (roblox-engine-emulator), a Rust emulation of the Roblox engine that runs a game's Luau offline.
It is being turned into a code validator: a Luau snippet passes only if it would run without errors in Roblox. Read
`AGENTS.md` (repo rules) and `validator/HANDOFF.md` first. Branch `validator`, don't commit or push: leave the changes in
the working tree and report.

## The problem

A real Roblox game script that calls an engine method with a missing or wrong-typed argument gets an error. ree calls the
method anyway (or its stub returns nil), so broken code passes. Measured in a Roblox 0.748 playtest, ~1,100 probe
lines differ for this reason alone, in both contexts. That includes methods ree implements, not only the unemulated ones.

```
roblox: M Actor.SendMessage c0 err Argument 1 missing or nil
ree:    M Actor.SendMessage c0 ok
roblox: M AdService.CreateAdRewardFromDevProductId cw err Unable to cast Array to int64
ree:    M AdService.CreateAdRewardFromDevProductId cw ok
```

`c0` is a call with no arguments, `cw` a call with a wrong-typed first argument (`{}` where the docs say string or number,
`"x"` otherwise). Each line runs on a fresh `Instance.new` instance or a service.

## The job

Make every reflected engine method check its arguments the way Roblox does, **before** its behaviour runs, whether that
behaviour is Rust, Luau (`services.luau` / `server.luau` / `src/lua/validator/*.luau` through `R.Method`) or the
unimplemented stub. One general mechanism driven by the reflection data, never a per-method list.

- Where calls go: `src/lua/raw.rs` (`meta_namecall` ~1565, `namecall_fast` / `namecall_general` / `namecall_index`,
  and `index_fast` / `index_slow`, which hand out the method function for `obj.Method(obj, ...)` and
  `local f = obj.Method; f(obj)`, so both call shapes must be checked), `src/lua/instance.rs` (`lua_methods`,
  `unimplemented_function` ~204).
- What to check against: `src/reflection/members.rs` `MethodInfo.parameters` (`ParameterInfo`: `type_info.script` /
  `.engine`, `default`) and `MethodInfo.permits` (capabilities). The doc comment there says it plainly: no default
  doesn't mean required. Which parameters really accept nil is something you **learn from the capture**, not from the
  dump.
- There's already a cast-name helper, `cast_name` in `src/animation/curves.rs:68` (`Array` / `Dictionary` / `double` /
  `bool`). Move it somewhere shared and reuse it, don't write a second one.

## Learn the rules from the data, not from memory

The Roblox output is `validator/probe/expected/surface_{server,client}.txt` (lines `M <Class.Method> c0|cw <result>`).
Before writing code, write a throwaway script that groups those lines and answers:

1. **Order:** which argument gets reported when several are missing? (`Actor.BindToMessage` with no args says
   `Argument 2 missing or nil`, not 1, so work out the real order.)
2. **Nil:** which engine types accept nil, by type (string? bool? Instance?) or by default value?
3. **Casts:** for each target type, which Lua values convert (number → string? string → number? number or string →
   Enum?) and which raise `Unable to cast X to Y`. Get the exact name of X and Y (`int64`, `ContentId`, `Array`,
   `Dictionary`, `double`).
4. **Capabilities:** which methods raise `The current thread cannot call 'X' (lacking capability Y)`, and does `permits`
   predict that?
5. **What it doesn't predict:** some lines are a method's own checks after casting (`Actor:SendMessage may only be called
   on Actors attached to the DataModel.`). Leave those to behaviour packages. Write the count in your report.

Turn the answers into a short rule table in `docs/engine.md` (a new "Argument casts" section), citing the capture
(`Roblox Studio 0.748.0.7481526, validator/probe/expected`).

## Constraints (wrong vs right)

```rust
// wrong: per-method special cases
if method_name == "SendMessage" && args.is_empty() { return raise("Argument 1 missing or nil") }

// right: one check driven by the method's reflected parameters, built once per (class, method) and cached
let plan = engine.arg_plan(class, method); // precomputed casts, no per-call allocation
plan.check(state, first_arg_index)?;       // raises Roblox's message, or lets the call through
```

- Hot path: the Instance API's fast paths stay in C metamethods (`lua/raw.rs`). Read properties by interned id. Allocate
  nothing per call. Methods with no recorded parameters (`MemberOrigin::Engine`) skip the check.
- Only check, don't convert, unless the capture shows Roblox converts and the behaviour behind it depends on it.
- Don't touch property get/set (another brief owns `newindex_*`), `services/mod.rs` `get_service`, or `validator/probe/*`.

## Verify

```sh
cargo build --release --locked --bin ree
python validator/probe/surface_diff.py                 # c0 / cw counts must drop; no other kind may rise
python validator/probe/surface_diff.py --list "M cw"   # what's left
cargo test --release
node tools/parity/run.mjs && node tools/parity/run.mjs --server   # no new failures vs main
```

Baseline before you start: server `M c0 557`, `M cw 537`, client `M c0 567`, `M cw 541`. Add tests in `src/tests.rs`
(script API) that fail without your change: a missing arg, a bad cast, an accepted conversion, a capability error, and
the `obj.Method(obj)` call shape.

## Report

```
BRIEF: ArgChecks
RULES: <the table you derived, 5-15 lines>
SURFACE: server c0 <before>-><after>, cw <before>-><after>; client same; other kinds unchanged? <yes/no + which>
LEFT: <count> lines that are method behaviour, not casts (examples)
TESTS: cargo test <pass/fail + count>, parity <pass/fail>
BLOCKED: <none | what>
```
