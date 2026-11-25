/-
Sunstead trusted Lean checker (multi-toolchain: Lean 4.35.0, 4.36.0, ...).
Installed read-only at /opt/sunstead/ and compiled to a per-toolchain native
binary `/opt/sunstead/sunstead-check`, run as the `sunstead-checker` user after
every `sunstead-runner` process is dead.

It never elaborates contributor source and never loads environment extensions
(`loadExts := false`). It supports two verification modes:

Mode A — Classic standalone mission (`statement=<SunsteadStatements.task>`):
1. Loads the frozen modules (`<Lib>.Spec`, `<Lib>.SunsteadStatements`) from a
   trusted build directory, plus core (`Init`, ...) from the toolchain and any
   read-only prebuilt libraries (e.g. Mathlib at /opt/mathlib) listed in
   `trusted-lib=p1:p2:...`.
2. Reads the contributor's compiled `.olean` files for the target module and
   every non-frozen `<Lib>.*` module it imports, rejects Lean 4 `module`
   outputs (`.olean.private` / `mod.isModule`), and re-checks every constant in
   them with the Lean kernel (`Kernel.Environment.replay`).
3. Asks the kernel to accept `theorem _sunstead_check : <frozen statement> := <target>`,
   requiring definitional equality against the frozen statement.
4. Collects the axioms `_sunstead_check` depends on, and (for hill-climb tasks)
   reduces the score constant to a natural-number literal.

Mode B — Repo-Snapshot mission (`frozen-target-olean=<path>`):
1. Reads the pinned upstream commit's frozen target `.olean` (built read-only at
   image-build time, never placed on `LEAN_PATH`) via `readModuleData`,
   extracting the exact pinned `ConstantInfo` for `target-const` (must be
   `thmInfo`) and the transitive set `FrozenTypeDeps(M, T)` of all declarations
   defined inside the target module that `frozenTargetCI.type` depends on.
2. Reads ONLY the explicitly designated `untrusted-modules=` from
   `untrusted-lib` (every sibling/dependency module is loaded strictly from
   root-owned `trusted-lib` with `loadExts := false`), rejects `mod.isModule` /
   `.olean.private`, rejects any constant redefining a trusted constant, and
   replays all untrusted constants through `Kernel.Environment.replay`.
3. Verifies every constant in `FrozenTypeDeps(M, T)` is structurally identical
   in the contributor's replayed environment (exact `name`, `levelParams`,
   `type`, `value`/`safety`/inductive fields; never `axiomInfo` or
   `opaqueInfo`), preventing local `def`/`abbrev` weakening inside writable
   target files.
4. Requires `target-const` to be `thmInfo`, asks the kernel to accept
   `Declaration.thmDecl` proving `frozenTargetCI.type` from `target-const`, and
   collects all axioms of `_sunstead_check`.

Output: one JSON line on stdout, e.g. {"ok":true,"axioms":["propext"],"score":150}.
Any error fails closed with {"ok":false,"error":"..."}.
-/
import Lean
import Std.Data.HashMap
import Std.Data.HashSet

open Lean

structure Cfg where
  trustedLibs : List System.FilePath := []
  untrustedLib : System.FilePath := ""
  libRoot : Name := .anonymous
  frozen : List Name := []
  untrustedModules : List Name := []
  frozenTargetOlean : Option System.FilePath := none
  targetModule : Name := .anonymous
  targetConst : Name := .anonymous
  statement : Name := .anonymous
  scoreConst : Option Name := none
  statementsModule : Name := .anonymous
  allowModuleSystem : Bool := false

/-- Strip surrounding French guillemets (`«AES-GCM»` → `"AES-GCM"`) using pure
list ops so the helper compiles without warnings across Lean 4.31–4.37+. -/
def stripGuillemets (raw : String) : String :=
  match raw.toList with
  | '«' :: rest =>
    match rest.reverse with
    | '»' :: mid => String.ofList mid.reverse
    | _ => raw
  | _ => raw

/-- Parse a dotted Lean module/constant name, stripping French guillemets
(`«AES-GCM»` → `"AES-GCM"`) so `modToFilePath` resolves escaped directory names
such as `Proofs/AES-GCM/AESGCMEncKernelSym.olean`. -/
def parseLeanName (s : String) : Name :=
  if s.isEmpty then
    .anonymous
  else
    let segs := s.splitOn "."
    segs.foldl (init := .anonymous) fun acc raw =>
      Name.mkStr acc (stripGuillemets raw)

/-- Arguments are `key=value` tokens (no leading dashes: `lean --run` would
otherwise try to parse them as its own options). -/
partial def parseArgs : List String → Cfg → Except String Cfg
  | [], c => .ok c
  | a :: rest, c =>
    match a.splitOn "=" with
    | k :: vs =>
      let v := "=".intercalate vs
      match k with
      | "trusted-lib" =>
        let paths := (v.splitOn ":").filter (!·.isEmpty) |>.map System.FilePath.mk
        parseArgs rest { c with trustedLibs := c.trustedLibs ++ paths }
      | "untrusted-lib" => parseArgs rest { c with untrustedLib := v }
      | "lib-root" =>
        let root := parseLeanName v
        parseArgs rest { c with libRoot := root, statementsModule := Name.mkStr root "SunsteadStatements" }
      | "frozen" =>
        let mods := (v.splitOn ",").filter (!·.isEmpty) |>.map parseLeanName
        parseArgs rest { c with frozen := mods }
      | "untrusted-modules" =>
        let mods := (v.splitOn ",").filter (!·.isEmpty) |>.map parseLeanName
        parseArgs rest { c with untrustedModules := mods }
      | "frozen-target-olean" =>
        parseArgs rest { c with frozenTargetOlean := some (System.FilePath.mk v) }
      | "target-module" => parseArgs rest { c with targetModule := parseLeanName v }
      | "target-const" => parseArgs rest { c with targetConst := parseLeanName v }
      | "statement" => parseArgs rest { c with statement := parseLeanName v }
      | "score-const" => parseArgs rest { c with scoreConst := some (parseLeanName v) }
      | "allow-module-system" =>
        let enabled := v == "1" || v == "true"
        parseArgs rest { c with allowModuleSystem := enabled }
      | _ => .error s!"unknown argument {a}"
    | [] => .error s!"unknown argument {a}"

def Cfg.isUntrusted (c : Cfg) (m : Name) : Bool :=
  if !c.untrustedModules.isEmpty then
    c.untrustedModules.contains m
  else
    c.libRoot.isPrefixOf m && !c.frozen.contains m

structure VisitAcc where
  visited : Std.HashSet Name := {}
  trusted : Array Import := #[]
  consts : Std.HashMap Name ConstantInfo := {}
  untrustedMods : Array Name := #[]
  regions : Array CompactedRegion := #[]

/-- Read `.olean` (and, when `allowModuleSystem := true`, chained `.olean.server`
+ `.olean.private` via `readModuleDataParts`), keeping all `CompactedRegion`s
returned so callers keep them alive until kernel replay completes. Fails closed
if `allowModuleSystem := false` and `.olean.private` / `mod.isModule` is seen,
or if `allowModuleSystem := true` and a `module` file is missing `.olean.private`. -/
def readModulePartsChecked (allowModuleSystem : Bool) (path : System.FilePath)
    (label : String) : IO (Array (ModuleData × CompactedRegion)) := do
  let privPath : System.FilePath := path.toString ++ ".private"
  let serverPath : System.FilePath := path.toString ++ ".server"
  if !allowModuleSystem then
    if (← privPath.pathExists) then
      throw <| IO.userError s!"module-system `.olean.private` output is not allowed for {label}"
    let (mod, region) ← readModuleData path
    if mod.isModule then
      throw <| IO.userError s!"Lean 4 `module` files are not allowed for {label}"
    return #[(mod, region)]
  else
    if (← privPath.pathExists) then
      let mut partPaths : Array System.FilePath := #[path]
      if (← serverPath.pathExists) then
        partPaths := partPaths.push serverPath
      partPaths := partPaths.push privPath
      readModuleDataParts partPaths
    else
      let (mod, region) ← readModuleData path
      if mod.isModule then
        throw <| IO.userError s!"Lean 4 `module` file is missing required `.olean.private` for {label}"
      return #[(mod, region)]

partial def visit (c : Cfg) (acc : IO.Ref VisitAcc) (m : Name) : IO Unit := do
  if (← acc.get).visited.contains m then return
  acc.modify fun a => { a with visited := a.visited.insert m }
  if c.isUntrusted m then
    let path := modToFilePath c.untrustedLib m "olean"
    unless (← path.pathExists) do
      throw <| IO.userError s!"missing build output for {m}"
    let parts ← readModulePartsChecked c.allowModuleSystem path (toString m)
    -- Keep compacted regions alive and visit all public, server, and private imports.
    acc.modify fun a =>
      let regs := parts.foldl (init := a.regions) fun r (_, reg) => r.push reg
      { a with regions := regs }
    for (mod, _) in parts do
      for imp in mod.imports do
        visit c acc imp.module
    -- Merge parts for THIS module in order (`.olean` -> `.olean.server` -> `.olean.private`)
    -- so private proof terms (`.thmInfo`) and unexposed defs overwrite public interface stubs,
    -- while still rejecting any duplicate constant defined across distinct untrusted modules.
    let mut modConsts : Std.HashMap Name ConstantInfo := {}
    for (mod, _) in parts do
      for (n, ci) in mod.constNames.zip mod.constants do
        modConsts := modConsts.insert n ci
    let a ← acc.get
    let mut cs := a.consts
    for (n, ci) in modConsts do
      if cs.contains n then
        throw <| IO.userError s!"constant {n} defined in more than one module"
      cs := cs.insert n ci
    acc.set { a with consts := cs, untrustedMods := a.untrustedMods.push m }
  else
    acc.modify fun a => { a with trusted := a.trusted.push { module := m, importAll := c.allowModuleSystem } }

/-- Explicit `QuotKind` equality so this file compiles without `BEq QuotKind`
(absent in Lean 4.31, added in later releases). -/
def quotKindEq : QuotKind → QuotKind → Bool
  | .type, .type => true
  | .ctor, .ctor => true
  | .lift, .lift => true
  | .ind, .ind => true
  | _, _ => false

/-- Structural kernel equality for local frozen type dependencies (`FrozenTypeDeps(M, T)`).
Compares exact declaration kind, name, universe parameters, type, and value/inductive
fields while ignoring declaration-order `ReducibilityHints` heights so adding helper
lemmas above a frozen `abbrev`/`def` does not cause false rejections. Rejects
`axiomInfo` and `opaqueInfo` unconditionally. -/
def constInfoStructEq (a b : ConstantInfo) : Bool :=
  match a, b with
  | .defnInfo x, .defnInfo y =>
    x.name == y.name && x.levelParams == y.levelParams &&
    x.type == y.type && x.value == y.value && x.safety == y.safety
  | .thmInfo x, .thmInfo y =>
    x.name == y.name && x.levelParams == y.levelParams && x.type == y.type
  | .inductInfo x, .inductInfo y =>
    x.name == y.name && x.levelParams == y.levelParams && x.type == y.type &&
    x.numParams == y.numParams && x.numIndices == y.numIndices &&
    x.all == y.all && x.ctors == y.ctors && x.isRec == y.isRec &&
    x.isUnsafe == y.isUnsafe && x.isReflexive == y.isReflexive
  | .ctorInfo x, .ctorInfo y =>
    x.name == y.name && x.levelParams == y.levelParams && x.type == y.type &&
    x.induct == y.induct && x.cidx == y.cidx &&
    x.numParams == y.numParams && x.numFields == y.numFields && x.isUnsafe == y.isUnsafe
  | .recInfo x, .recInfo y =>
    x.name == y.name && x.levelParams == y.levelParams && x.type == y.type &&
    x.all == y.all && x.numParams == y.numParams && x.numIndices == y.numIndices &&
    x.numMotives == y.numMotives && x.numMinors == y.numMinors &&
    x.k == y.k && x.isUnsafe == y.isUnsafe && x.rules.length == y.rules.length
  | .quotInfo x, .quotInfo y =>
    x.name == y.name && x.levelParams == y.levelParams && x.type == y.type && quotKindEq x.kind y.kind
  | _, _ => false

/-- Compute the transitive closure of constants defined inside `frozenMap`
(excluding `targetConst`) that `frozenTargetType` depends on. -/
def collectFrozenTypeDeps (frozenMap : Std.HashMap Name ConstantInfo)
    (targetConst : Name) (frozenTargetType : Expr) : Std.HashSet Name := Id.run do
  let mut deps : Std.HashSet Name := {}
  let mut queue : Array Name := frozenTargetType.getUsedConstants
  let mut idx := 0
  while idx < queue.size do
    let u := queue[idx]!
    idx := idx + 1
    if u == targetConst || deps.contains u then
      continue
    if let some ci := frozenMap.get? u then
      deps := deps.insert u
      queue := queue ++ ci.type.getUsedConstants
      if let some v := ci.value? then
        queue := queue ++ v.getUsedConstants
      match ci with
      | .inductInfo iv =>
        queue := queue ++ iv.all.toArray ++ iv.ctors.toArray
      | .ctorInfo cv =>
        queue := queue.push cv.induct
      | .recInfo rv =>
        queue := queue ++ rv.all.toArray
      | _ => pure ()
  return deps

def requireTheoremConst (name : Name) (ci : ConstantInfo) : CoreM Unit := do
  match ci with
  | .thmInfo _ => pure ()
  | _ => throwError "target constant {name} must be a theorem or lemma"

def checkClassicM (c : Cfg) : CoreM Json := do
  let env ← getEnv
  let kenv := env.toKernelEnv
  let some tci := kenv.find? c.targetConst
    | throwError "target constant {c.targetConst} not found"
  requireTheoremConst c.targetConst tci
  let some sci := kenv.find? c.statement
    | throwError "frozen statement {c.statement} not found"
  unless tci.levelParams.length == sci.levelParams.length do
    throwError "universe parameter count mismatch: got {tci.levelParams.length}, expected {sci.levelParams.length}"
  let lvls := sci.levelParams.map Level.param
  let mut stmt := mkConst c.statement lvls
  let mut fields : List (String × Json) := []
  if let some k := c.scoreConst then
    unless sci.levelParams.isEmpty do
      throwError "hill-climb statement must not be universe polymorphic"
    let some kci := kenv.find? k | throwError "score constant {k} not found"
    unless kci.type == mkConst ``Nat do
      throwError "score constant {k} must have type Nat"
    let n ← Meta.MetaM.run' do
      let e ← Meta.whnf (mkConst k)
      match e with
      | .lit (.natVal n) => pure n
      | _ =>
        match (← Meta.evalNat e) with
        | some n => pure n
        | none => throwError "score constant {k} does not reduce to a numeral"
    stmt := mkApp stmt (mkNatLit n)
    fields := fields ++ [("score", toJson n)]
  let checkName := `_sunstead_check
  addDecl <| Declaration.thmDecl
    { name := checkName, levelParams := sci.levelParams, type := stmt, value := mkConst c.targetConst lvls, all := [checkName] }
  let axs ← collectAxioms checkName
  return Json.mkObj ([("ok", Json.bool true), ("axioms", toJson (axs.map toString))] ++ fields)

def checkSnapshotM (c : Cfg) (frozenTargetCI : ConstantInfo)
    (frozenMap : Std.HashMap Name ConstantInfo)
    (frozenTypeDeps : Std.HashSet Name) : CoreM Json := do
  let kenv := (← getEnv).toKernelEnv
  let some tci := kenv.find? c.targetConst
    | throwError "target constant {c.targetConst} not found"
  requireTheoremConst c.targetConst tci
  for u in frozenTypeDeps do
    let some fci := frozenMap.get? u
      | throwError "internal error: missing frozen type dependency {u}"
    let some cci := kenv.find? u
      | throwError "frozen local type dependency {u} missing from contributor module"
    unless constInfoStructEq cci fci do
      throwError "frozen local type dependency {u} was modified by contributor"
  unless tci.levelParams.length == frozenTargetCI.levelParams.length do
    throwError "universe parameter count mismatch: got {tci.levelParams.length}, expected {frozenTargetCI.levelParams.length}"
  let lvls := frozenTargetCI.levelParams.map Level.param
  let checkName := `_sunstead_check
  addDecl <| Declaration.thmDecl
    { name := checkName
      levelParams := frozenTargetCI.levelParams
      type := frozenTargetCI.type
      value := mkConst c.targetConst lvls
      all := [checkName] }
  let axs ← collectAxioms checkName
  return Json.mkObj [("ok", Json.bool true), ("axioms", toJson (axs.map toString))]

/-- Version-portable kernel replay across Lean 4.31 (`Lean.Environment.replay`)
and Lean 4.35+ (`Lean.Kernel.Environment.replay`). -/
local elab "sunsteadReplay" consts:term:max env:term:max : term => do
  let curEnv ← getEnv
  let kReplay := `Lean.Kernel.Environment.replay
  if curEnv.contains kReplay then
    let id := mkIdent kReplay
    Elab.Term.elabTerm (← `(Lean.Environment.ofKernelEnv <$> ($id:ident $consts ($env).toKernelEnv))) none
  else
    let id := mkIdent `Lean.Environment.replay
    Elab.Term.elabTerm (← `($id:ident $consts $env)) none

def run (args : List String) : IO Json := do
  let c ← match parseArgs args {} with
    | .ok c => pure c
    | .error e => throw <| IO.userError e
  initSearchPath (← findSysroot) c.trustedLibs
  let acc ← IO.mkRef ({} : VisitAcc)
  visit c acc c.targetModule
  let a ← acc.get
  unless a.untrustedMods.contains c.targetModule do
    throw <| IO.userError s!"target module {c.targetModule} is not a contributor module"
  unless a.consts.contains c.targetConst do
    throw <| IO.userError s!"{c.targetConst} is not defined in the contributor's modules"

  match c.frozenTargetOlean with
  | some frozenPath =>
    unless (← frozenPath.pathExists) do
      throw <| IO.userError s!"missing frozen target .olean: {frozenPath}"
    let frozenParts ← readModulePartsChecked c.allowModuleSystem frozenPath (toString frozenPath)
    let mut frozenMap : Std.HashMap Name ConstantInfo := {}
    for (frozenMod, _) in frozenParts do
      for (n, ci) in frozenMod.constNames.zip frozenMod.constants do
        frozenMap := frozenMap.insert n ci
    let some frozenTargetCI := frozenMap.get? c.targetConst
      | throw <| IO.userError s!"target constant {c.targetConst} not found in frozen upstream .olean"
    match frozenTargetCI with
    | .thmInfo _ => pure ()
    | _ => throw <| IO.userError s!"frozen upstream target {c.targetConst} is not a theorem/lemma"
    let frozenTypeDeps := collectFrozenTypeDeps frozenMap c.targetConst frozenTargetCI.type

    let env ← importModules a.trusted {} 0 (loadExts := false)
    for (n, _) in a.consts do
      if env.contains n then
        throw <| IO.userError s!"contributor module redefines trusted constant {n}"
    let env ← sunsteadReplay a.consts env
    let ctx : Core.Context := { fileName := "<sunstead-check>", fileMap := default }
    let (j, _) ← (checkSnapshotM c frozenTargetCI frozenMap frozenTypeDeps).toIO ctx { env := env }
    -- Keep compacted regions alive past kernel replay and checkSnapshotM.
    if a.regions.size + frozenParts.size == 0 then pure ()
    return j
  | none =>
    let env ← importModules (a.trusted.push { module := c.statementsModule, importAll := c.allowModuleSystem }) {} 0 (loadExts := false)
    for (n, _) in a.consts do
      if env.contains n then
        throw <| IO.userError s!"contributor module redefines trusted constant {n}"
    let env ← sunsteadReplay a.consts env
    let ctx : Core.Context := { fileName := "<sunstead-check>", fileMap := default }
    let (j, _) ← (checkClassicM c).toIO ctx { env := env }
    if a.regions.size == 0 then pure ()
    return j

def main (args : List String) : IO UInt32 := do
  if args == ["selftest"] then
    IO.println "{\"selftest\":\"ok\"}"
    return 0
  try
    let j ← run args
    IO.println j.compress
    return 0
  catch e =>
    IO.println (Json.mkObj [("ok", Json.bool false), ("error", Json.str (toString e))]).compress
    return 1
