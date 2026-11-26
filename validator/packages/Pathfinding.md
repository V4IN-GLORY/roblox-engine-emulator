# Package: Pathfinding

File: `src/lua/validator/Pathfinding.luau`. Specs: `validator/specs/Pathfinding/`. Read `validator/HANDOFF.md` first.

~500 rows. `PathfindingService:CreatePath` / `FindPathAsync` are unemulated on the **client** (check whether the server side already works: run a spec in both contexts before writing anything, and reuse it if it does).

## Members

| member | must do |
|---|---|
| `CreatePath(params?)` | Path object; validate the agent params table keys (`AgentRadius`, `AgentHeight`, `AgentCanJump`, `AgentCanClimb`, `WaypointSpacing`, `Costs`, `PathSettings`), wrong value types error |
| `Path:ComputeAsync(start, finish)` | Vector3 args (error otherwise); straight-line waypoints spaced by `WaypointSpacing` (default 4) is enough; `Status = Enum.PathStatus.Success`; raycast for a blocking part between them → `NoPath` |
| `Path:GetWaypoints()` | array of `PathWaypoint` (`PathWaypoint.new(pos, Enum.PathWaypointAction.Walk, label)`) |
| `Path:CheckOcclusionAsync(start)` | -1 when clear |
| `Path.Blocked` / `Path.Unblocked` | real signals (never fire is fine) |
| `FindPathAsync(start, finish)` | deprecated wrapper: CreatePath + ComputeAsync |

## Misuse cases to spec

- `path:ComputeAsync(part, goal)` (Instance instead of Vector3) → cast error.
- `CreatePath({ AgentRadius = "big" })` → error.
- Reading `path:GetWaypoints()[1].Position` after a successful compute → ok.
