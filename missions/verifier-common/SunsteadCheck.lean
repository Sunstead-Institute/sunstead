/-
Sunstead trusted Lean checker (multi-toolchain: Lean 4.35.0, 4.36.0, ...).
Installed read-only at /opt/sunstead/ and compiled to a per-toolchain native
binary `/opt/sunstead/sunstead-check`, run as the `sunstead-checker` user after
every `sunstead-runner` process is dead.

It never elaborates contributor source and never loads environment extensions
(`loadExts := false`). It supports three verification modes (`mode=`):

Mode A — Classic standalone mission (`mode=verify`, `statement=<SunsteadStatements.task>`):
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

Mode B — Repo-Snapshot mission (`mode=verify`, `frozen-target-olean=<path>`):
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

Mode C — v2 Decomposition (`mode=decompose`) & Refutation (`mode=refute`):
- `mode=decompose`: reads `untrusted-decomp-modules` (`DecompStatements_*`,
  elaborated by `sunstead-runner`, never `sunstead-checker`) from
  `untrusted-decomp-lib`, rejects any non-frozen imports or axiom/opaque/unsafe
  declarations, replays them through `Kernel.Environment.replay` into the purely
  trusted environment, verifies 2–6 subgoal definitions `L_1 .. L_k : Prop`
  (safe, monomorphic, standard axioms only, none def-eq to `True`, `False`,
  parent `T`, or another `L_j`), replays the proposer's reduction module through
  `Kernel.Environment.replay`, confirms `L_1 → ... → L_k → T` with standard
  axioms only, and checks that the reduced proof term references every
  hypothesis `h_1 .. h_k`.
- `mode=refute`: replays any `untrusted-decomp-modules` (for subgoal refutations)
  and a contributor proof of `¬ <frozen statement>` (for either a root task or a
  spawned subgoal, in classic or repo-snapshot mode) with 0 `sorryAx` and
  standard axioms only.

Output: one JSON line on stdout, e.g. {"ok":true,"axioms":["propext"],"score":150}.
Any error fails closed with {"ok":false,"error":"..."}.
-/
import Lean
import Std.Data.HashMap
import Std.Data.HashSet

open Lean

inductive CheckMode where
  | verify
  | decompose
  | refute
  deriving BEq

structure Cfg where
  mode : CheckMode := .verify
  trustedLibs : List System.FilePath := []
  untrustedLib : System.FilePath := ""
  untrustedDecompLib : Option System.FilePath := none
  untrustedDecompModules : List Name := []
  libRoot : Name := .anonymous
  frozen : List Name := []
  untrustedModules : List Name := []
  frozenTargetOlean : Option System.FilePath := none
  targetModule : Name := .anonymous
  targetConst : Name := .anonymous
  statement : Name := .anonymous
  scoreConst : Option Name := none
  statementsModule : Name := .anonymous
  decompStatementsModule : Option Name := none
  subgoalConsts : List Name := []
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
      | "mode" =>
        match v with
        | "verify" => parseArgs rest { c with mode := .verify }
        | "decompose" => parseArgs rest { c with mode := .decompose }
        | "refute" => parseArgs rest { c with mode := .refute }
        | _ => .error s!"unknown mode {v}"
      | "trusted-lib" =>
        let paths := (v.splitOn ":").filter (!·.isEmpty) |>.map System.FilePath.mk
        parseArgs rest { c with trustedLibs := c.trustedLibs ++ paths }
      | "untrusted-lib" => parseArgs rest { c with untrustedLib := v }
      | "untrusted-decomp-lib" =>
        parseArgs rest { c with untrustedDecompLib := some (System.FilePath.mk v) }
      | "untrusted-decomp-modules" =>
        let mods := (v.splitOn ",").filter (!·.isEmpty) |>.map parseLeanName
        parseArgs rest { c with untrustedDecompModules := mods }
      | "lib-root" =>
        let root := parseLeanName v
        let stmtsMod := if c.statementsModule.isAnonymous then Name.mkStr root "SunsteadStatements" else c.statementsModule
        parseArgs rest { c with libRoot := root, statementsModule := stmtsMod }
      | "statements-module" =>
        parseArgs rest { c with statementsModule := parseLeanName v }
      | "decomp-statements-module" =>
        parseArgs rest { c with decompStatementsModule := some (parseLeanName v) }
      | "subgoal-consts" =>
        let consts := (v.splitOn ",").filter (!·.isEmpty) |>.map parseLeanName
        parseArgs rest { c with subgoalConsts := consts }
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

def Cfg.isUntrustedDecomp (c : Cfg) (m : Name) : Bool :=
  c.untrustedDecompModules.contains m

def Cfg.isUntrusted (c : Cfg) (m : Name) : Bool :=
  if m == c.statementsModule || c.decompStatementsModule == some m || c.isUntrustedDecomp m then
    false
  else if !c.untrustedModules.isEmpty then
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
  if c.isUntrustedDecomp m then
    -- Read from `untrustedDecompLib` and kernel-replayed explicitly before contributor code;
    -- never loaded via `importModules`.
    return
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

def isStandardAxiom (ax : Name) : Bool :=
  ax == ``propext || ax == ``Classical.choice || ax == ``Quot.sound

/-- Pure recursive check for whether `target` occurs free in `e`. -/
def exprHasFVar (target : FVarId) : Expr → Bool
  | .fvar id => id == target
  | .app f a => exprHasFVar target f || exprHasFVar target a
  | .lam _ ty body _ => exprHasFVar target ty || exprHasFVar target body
  | .forallE _ ty body _ => exprHasFVar target ty || exprHasFVar target body
  | .letE _ ty val body _ =>
    exprHasFVar target ty || exprHasFVar target val || exprHasFVar target body
  | .mdata _ inner => exprHasFVar target inner
  | .proj _ _ s => exprHasFVar target s
  | _ => false

structure UsageReduceState where
  steps : Nat := 0
  maxSteps : Nat := 6000
  nextProbe : Nat := 0

/-- Extract the body of a contributor `def` or `theorem` (unlike `ConstantInfo.value?`,
which defaults `allowOpaque := false` and returns `none` for `.thmInfo`). -/
def constBody? : ConstantInfo → Option Expr
  | .defnInfo dv => some dv.value
  | .thmInfo tv => some tv.value
  | _ => none

/-- Reduce a contributor glue proof term (beta, zeta, structure projection,
transparent combinators, single-constructor dead-branch elimination, and
cycle-guarded unfolding of contributor-defined constants ONLY) so dead-weight
uses like `let _ := h2; body`, `(fun _ => body) h2`, `(And.intro body h2).1`,
`And.rec (fun _ _ => body) h2`, or eta-contracted helper wrappers cannot hide
an unused subgoal hypothesis. -/
partial def reduceForUsage (env : Environment)
    (untrusted : Std.HashMap Name ConstantInfo)
    (unfolding : Std.HashSet Name)
    (e : Expr) : StateM UsageReduceState Expr := do
  let st ← get
  if st.steps >= st.maxSteps then return e
  set { st with steps := st.steps + 1 }
  match e with
  | .mdata _ inner => reduceForUsage env untrusted unfolding inner
  | .letE _ _ val body _ =>
    let val' ← reduceForUsage env untrusted unfolding val
    reduceForUsage env untrusted unfolding (body.instantiate1 val')
  | .lam n ty body bi =>
    let ty' ← reduceForUsage env untrusted unfolding ty
    let body' ← reduceForUsage env untrusted unfolding body
    return .lam n ty' body' bi
  | .proj sName idx s =>
    let s' ← reduceForUsage env untrusted unfolding s
    match s'.getAppFn with
    | .const ctorName _ =>
      match env.find? ctorName with
      | some (.ctorInfo cv) =>
        let args := s'.getAppArgs
        if cv.induct == sName && args.size == cv.numParams + cv.numFields && idx < cv.numFields then
          reduceForUsage env untrusted unfolding args[cv.numParams + idx]!
        else
          return .proj sName idx s'
      | _ => return .proj sName idx s'
    | _ => return .proj sName idx s'
  | .app .. =>
    let fn := e.getAppFn
    let args := e.getAppArgs
    match fn with
    | .mdata _ inner =>
      reduceForUsage env untrusted unfolding (mkAppN inner args)
    | .lam .. =>
      reduceForUsage env untrusted unfolding (fn.beta args)
    | .letE _ _ val body _ =>
      let val' ← reduceForUsage env untrusted unfolding val
      reduceForUsage env untrusted unfolding (mkAppN (body.instantiate1 val') args)
    | .const n ls =>
      if !unfolding.contains n then
        if let some ci := untrusted.get? n then
          if let some val := constBody? ci then
            let inst := val.instantiateLevelParams ci.levelParams ls
            return ← reduceForUsage env untrusted (unfolding.insert n) (mkAppN inst args)
      if n == ``id && args.size >= 2 then
        return ← reduceForUsage env untrusted unfolding (mkAppN args[1]! (args.extract 2 args.size))
      if n == ``Function.const && args.size >= 4 then
        return ← reduceForUsage env untrusted unfolding (mkAppN args[2]! (args.extract 4 args.size))
      if n == ``And.left && args.size >= 3 then
        let p ← reduceForUsage env untrusted unfolding args[2]!
        if p.getAppFn.isConstOf ``And.intro && p.getAppNumArgs == 4 then
          return ← reduceForUsage env untrusted unfolding (mkAppN p.getAppArgs[2]! (args.extract 3 args.size))
      if n == ``And.right && args.size >= 3 then
        let p ← reduceForUsage env untrusted unfolding args[2]!
        if p.getAppFn.isConstOf ``And.intro && p.getAppNumArgs == 4 then
          return ← reduceForUsage env untrusted unfolding (mkAppN p.getAppArgs[3]! (args.extract 3 args.size))
      if n == ``Prod.fst && args.size >= 3 then
        let p ← reduceForUsage env untrusted unfolding args[2]!
        if p.getAppFn.isConstOf ``Prod.mk && p.getAppNumArgs == 4 then
          return ← reduceForUsage env untrusted unfolding (mkAppN p.getAppArgs[2]! (args.extract 3 args.size))
      if n == ``Prod.snd && args.size >= 3 then
        let p ← reduceForUsage env untrusted unfolding args[2]!
        if p.getAppFn.isConstOf ``Prod.mk && p.getAppNumArgs == 4 then
          return ← reduceForUsage env untrusted unfolding (mkAppN p.getAppArgs[3]! (args.extract 3 args.size))
      if n == ``PProd.fst && args.size >= 3 then
        let p ← reduceForUsage env untrusted unfolding args[2]!
        if p.getAppFn.isConstOf ``PProd.mk && p.getAppNumArgs == 4 then
          return ← reduceForUsage env untrusted unfolding (mkAppN p.getAppArgs[2]! (args.extract 3 args.size))
      if n == ``PProd.snd && args.size >= 3 then
        let p ← reduceForUsage env untrusted unfolding args[2]!
        if p.getAppFn.isConstOf ``PProd.mk && p.getAppNumArgs == 4 then
          return ← reduceForUsage env untrusted unfolding (mkAppN p.getAppArgs[3]! (args.extract 3 args.size))
      if (n == ``And.rec || n == ``Exists.rec) && args.size >= 5 then
        let minor ← reduceForUsage env untrusted unfolding args[3]!
        let cur ← get
        let p1 := FVarId.mk (Name.mkNum `_sunstead_unused_probe cur.nextProbe)
        let p2 := FVarId.mk (Name.mkNum `_sunstead_unused_probe (cur.nextProbe + 1))
        set { cur with nextProbe := cur.nextProbe + 2 }
        let body ← reduceForUsage env untrusted unfolding (minor.beta #[.fvar p1, .fvar p2])
        if !exprHasFVar p1 body && !exprHasFVar p2 body then
          return ← reduceForUsage env untrusted unfolding (mkAppN body (args.extract 5 args.size))
      if (n == ``And.casesOn || n == ``Exists.casesOn || n == ``Exists.elim) && args.size >= 5 then
        let minor ← reduceForUsage env untrusted unfolding args[4]!
        let cur ← get
        let p1 := FVarId.mk (Name.mkNum `_sunstead_unused_probe cur.nextProbe)
        let p2 := FVarId.mk (Name.mkNum `_sunstead_unused_probe (cur.nextProbe + 1))
        set { cur with nextProbe := cur.nextProbe + 2 }
        let body ← reduceForUsage env untrusted unfolding (minor.beta #[.fvar p1, .fvar p2])
        if !exprHasFVar p1 body && !exprHasFVar p2 body then
          return ← reduceForUsage env untrusted unfolding (mkAppN body (args.extract 5 args.size))
      -- Best-effort reduction of trivial equality-transport wrappers (`congrArg (fun _ => T) _`,
      -- `Eq.mp`/`Eq.mpr`/`Eq.ndrec`/`Eq.rec` over `Eq.refl`) and constant-branch `ite`/`dite`.
      if n == ``congrArg && args.size == 6 then
        let fnArg ← reduceForUsage env untrusted unfolding args[4]!
        let eqArg ← reduceForUsage env untrusted unfolding args[5]!
        let cur ← get
        let p := FVarId.mk (Name.mkNum `_sunstead_unused_probe cur.nextProbe)
        set { cur with nextProbe := cur.nextProbe + 1 }
        let body ← reduceForUsage env untrusted unfolding (fnArg.beta #[.fvar p])
        if !exprHasFVar p body then
          return mkApp2 (mkConst ``Eq.refl (ls.tail)) args[1]! body
        if eqArg.getAppFn.isConstOf ``Eq.refl then
          let a1 ← reduceForUsage env untrusted unfolding args[2]!
          let fa1 ← reduceForUsage env untrusted unfolding (fnArg.beta #[a1])
          return mkApp2 (mkConst ``Eq.refl (ls.tail)) args[1]! fa1
      if (n == ``Eq.mp || n == ``Eq.mpr) && args.size >= 4 then
        let eqArg ← reduceForUsage env untrusted unfolding args[2]!
        if eqArg.getAppFn.isConstOf ``Eq.refl then
          return ← reduceForUsage env untrusted unfolding (mkAppN args[3]! (args.extract 4 args.size))
      if (n == ``Eq.ndrec || n == ``Eq.rec) && args.size >= 6 then
        let eqArg ← reduceForUsage env untrusted unfolding args[5]!
        if eqArg.getAppFn.isConstOf ``Eq.refl then
          return ← reduceForUsage env untrusted unfolding (mkAppN args[3]! (args.extract 6 args.size))
      if n == ``ite && args.size >= 5 then
        let tBranch ← reduceForUsage env untrusted unfolding args[3]!
        let eBranch ← reduceForUsage env untrusted unfolding args[4]!
        if tBranch == eBranch then
          return ← reduceForUsage env untrusted unfolding (mkAppN tBranch (args.extract 5 args.size))
      if n == ``dite && args.size >= 5 then
        let tFn ← reduceForUsage env untrusted unfolding args[3]!
        let eFn ← reduceForUsage env untrusted unfolding args[4]!
        let cur ← get
        let p1 := FVarId.mk (Name.mkNum `_sunstead_unused_probe cur.nextProbe)
        let p2 := FVarId.mk (Name.mkNum `_sunstead_unused_probe (cur.nextProbe + 1))
        set { cur with nextProbe := cur.nextProbe + 2 }
        let tBody ← reduceForUsage env untrusted unfolding (tFn.beta #[.fvar p1])
        let eBody ← reduceForUsage env untrusted unfolding (eFn.beta #[.fvar p2])
        if !exprHasFVar p1 tBody && !exprHasFVar p2 eBody && tBody == eBody then
          return ← reduceForUsage env untrusted unfolding (mkAppN tBody (args.extract 5 args.size))
      let args' ← args.mapM (reduceForUsage env untrusted unfolding)
      return mkAppN fn args'
    | _ =>
      let fn' ← reduceForUsage env untrusted unfolding fn
      let args' ← args.mapM (reduceForUsage env untrusted unfolding)
      if fn'.isLambda then
        reduceForUsage env untrusted unfolding (fn'.beta args')
      else
        return mkAppN fn' args'
  | .const n ls =>
    if !unfolding.contains n then
      if let some ci := untrusted.get? n then
        if let some val := constBody? ci then
          let inst := val.instantiateLevelParams ci.levelParams ls
          return ← reduceForUsage env untrusted (unfolding.insert n) inst
    return e
  | _ => return e

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
  if c.mode == .refute then
    if c.scoreConst.isSome then
      throwError "refute mode does not accept score-const"
    stmt := mkApp (mkConst ``Not) stmt
  else if let some k := c.scoreConst then
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
  let checkName := if c.mode == .refute then `_sunstead_refute_check else `_sunstead_check
  addDecl <| Declaration.thmDecl
    { name := checkName, levelParams := sci.levelParams, type := stmt, value := mkConst c.targetConst lvls, all := [checkName] }
  let axs ← collectAxioms checkName
  return Json.mkObj ([("ok", Json.bool true), ("axioms", toJson (axs.map toString))] ++ fields)

/-- Pure kernel definitional equality check (never invokes `MetaM` or
`Environment.realizeConst`, so it runs cleanly on `Environment.ofKernelEnv`
after `Kernel.Environment.replay` across Lean 4.31–4.36+). -/
def kernelIsDefEqM (a b : Expr) : CoreM Bool := do
  let env ← getEnv
  match Lean.Kernel.isDefEq env {} a b with
  | .ok eq => return eq
  | .error _ => throwError "kernel definitional equality check failed"

/-- Validate a single kernel-replayed subgoal statement definition `name` inside
the pre-contributor environment: must be a safe, monomorphic `Prop` `.defnInfo`
using standard axioms only (0 `sorryAx`). -/
def checkSafePropSubgoalDefM (subName : Name) : CoreM (DefinitionVal × Array Name) := do
  let kenv := (← getEnv).toKernelEnv
  let some sci := kenv.find? subName
    | throwError "subgoal statement {subName} not found"
  let dv ← match sci with
    | .defnInfo dv => pure dv
    | _ => throwError "subgoal {subName} must be a safe Prop definition"
  unless dv.levelParams.isEmpty do
    throwError "subgoal {subName} must not be universe polymorphic"
  unless dv.safety == .safe do
    throwError "subgoal {subName} must be safe"
  let isProp ← kernelIsDefEqM dv.type (Expr.sort Level.zero)
  unless isProp do
    throwError "subgoal {subName} must have type Prop"
  let axs ← collectAxioms subName
  for ax in axs do
    unless isStandardAxiom ax do
      throwError "subgoal statement {subName} uses forbidden axiom {ax}"
  return (dv, axs)

/-- Validate kernel-replayed subgoal definitions `L_1 .. L_k` BEFORE replaying
contributor code: each `L_i` must be a safe, monomorphic `Prop` definition with
standard axioms only (0 `sorryAx`), and none may be definitionally equal to
`True`, `False`, parent `T`, or another `L_j`. -/
def checkDecompSubgoalsM (c : Cfg) : CoreM (Array Name) := do
  let k := c.subgoalConsts.length
  unless k >= 2 && k <= 6 do
    throwError "decomposition requires 2 to 6 subgoals (got {k})"
  let env ← getEnv
  let kenv := env.toKernelEnv
  let some pci := kenv.find? c.statement
    | throwError "parent frozen statement {c.statement} not found"
  unless pci.levelParams.isEmpty do
    throwError "parent statement {c.statement} must not be universe polymorphic for decomposition"
  let mut allAxioms : Std.HashSet Name := {}
  if c.isUntrustedDecomp c.statementsModule then
    let (_, parentAxs) ← checkSafePropSubgoalDefM c.statement
    for ax in parentAxs do
      allAxioms := allAxioms.insert ax
  let parentExpr := mkConst c.statement []
  let parentBody := pci.value?.getD parentExpr
  let mut bodies : Array (Name × Expr) := #[]
  for subName in c.subgoalConsts do
    let (dv, axs) ← checkSafePropSubgoalDefM subName
    for ax in axs do
      allAxioms := allAxioms.insert ax
    let isTrue ← kernelIsDefEqM dv.value (mkConst ``True)
    if isTrue then
      throwError "subgoal {subName} is trivially definitionally equal to True"
    let isFalse ← kernelIsDefEqM dv.value (mkConst ``False)
    if isFalse then
      throwError "subgoal {subName} is vacuously definitionally equal to False"
    let isParentBody ← kernelIsDefEqM dv.value parentBody
    let isParent ← if isParentBody then pure true else kernelIsDefEqM (mkConst subName []) parentExpr
    if isParent then
      throwError "subgoal {subName} is trivially definitionally equal to parent statement {c.statement}"
    for (prevName, prevBody) in bodies do
      let isDup ← kernelIsDefEqM dv.value prevBody
      if isDup then
        throwError "subgoal {subName} is definitionally equal to earlier subgoal {prevName}"
    bodies := bodies.push (subName, dv.value)
  return allAxioms.toArray

/-- Check the replayed reduction theorem `L_1 → ... → L_k → T` and verify every
hypothesis `h_1 .. h_k` is genuinely referenced after reduction. -/
def checkDecompReductionM (c : Cfg) (untrusted : Std.HashMap Name ConstantInfo)
    (subgoalAxioms : Array Name) : CoreM Json := do
  let env ← getEnv
  let kenv := env.toKernelEnv
  let some tci := kenv.find? c.targetConst
    | throwError "reduction theorem {c.targetConst} not found"
  let tv ← match tci with
    | .thmInfo tv => pure tv
    | _ => throwError "reduction target {c.targetConst} must be a theorem or lemma"
  unless tv.levelParams.isEmpty do
    throwError "reduction theorem {c.targetConst} must not be universe polymorphic"
  let parentExpr := mkConst c.statement []
  let reductionGoal := c.subgoalConsts.foldr (init := parentExpr) fun subName acc =>
    Expr.forallE `_ (mkConst subName []) acc .default
  let checkName := `_sunstead_decomp_check
  addDecl <| Declaration.thmDecl
    { name := checkName
      levelParams := []
      type := reductionGoal
      value := mkConst c.targetConst []
      all := [checkName] }
  let axs ← collectAxioms checkName
  let mut axSet : Std.HashSet Name := {}
  for ax in subgoalAxioms do
    axSet := axSet.insert ax
  for ax in axs do
    axSet := axSet.insert ax
  -- Check that the reduction proof genuinely uses every subgoal hypothesis `h_1 .. h_k`.
  let mut hypIds : Array (Name × FVarId) := #[]
  let mut hypExprs : Array Expr := #[]
  let mut idx := 0
  for subName in c.subgoalConsts do
    let fid := FVarId.mk (Name.mkNum `_sunstead_hyp idx)
    hypIds := hypIds.push (subName, fid)
    hypExprs := hypExprs.push (Expr.fvar fid)
    idx := idx + 1
  let applied := mkAppN tv.value hypExprs
  let (reduced, _) := (reduceForUsage env untrusted {} applied).run {}
  let mut hIdx : Nat := 1
  for (subName, fid) in hypIds do
    unless exprHasFVar fid reduced do
      throwError "reduction proof does not use subgoal hypothesis #{hIdx} ({subName})"
    hIdx := hIdx + 1
  return Json.mkObj [
    ("ok", Json.bool true),
    ("axioms", toJson (axSet.toArray.map toString)),
    ("subgoals", toJson (c.subgoalConsts.map toString))
  ]

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
  let targetType :=
    if c.mode == .refute then
      mkApp (mkConst ``Not) frozenTargetCI.type
    else
      frozenTargetCI.type
  let checkName := if c.mode == .refute then `_sunstead_refute_check else `_sunstead_check
  addDecl <| Declaration.thmDecl
    { name := checkName
      levelParams := frozenTargetCI.levelParams
      type := targetType
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
    if c.mode == .decompose || !c.untrustedDecompModules.isEmpty then
      throw <| IO.userError "decompose mode is only supported for classic statement-based missions"
    unless (← frozenPath.pathExists) do
      throw <| IO.userError s!"missing frozen target .olean: {frozenPath}"
    let frozenParts ← readModulePartsChecked c.allowModuleSystem frozenPath (toString frozenPath)
    let mut frozenMap : Std.HashMap Name ConstantInfo := {}
    for (frozenMod, _) in frozenParts do
      for (n, ci) in frozenMod.constNames.zip frozenMod.constants do
        frozenMap := frozenMap.insert n ci
    let frozenConstName :=
      if c.mode == .refute && !c.statement.isAnonymous then c.statement else c.targetConst
    let some frozenTargetCI := frozenMap.get? frozenConstName
      | throw <| IO.userError s!"target constant {frozenConstName} not found in frozen upstream .olean"
    match frozenTargetCI with
    | .thmInfo _ => pure ()
    | _ => throw <| IO.userError s!"frozen upstream target {frozenConstName} is not a theorem/lemma"
    let frozenTypeDeps := collectFrozenTypeDeps frozenMap frozenConstName frozenTargetCI.type

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
    if c.mode == .decompose then
      match c.decompStatementsModule with
      | none => throw <| IO.userError "decompose mode requires decomp-statements-module"
      | some dm =>
        unless c.isUntrustedDecomp dm do
          throw <| IO.userError s!"decomp statements module {dm} must be listed in untrusted-decomp-modules for kernel replay"
    let mut trustedImports := a.trusted
    let mut seenTrusted : Std.HashSet Name := {}
    for imp in a.trusted do
      seenTrusted := seenTrusted.insert imp.module
    if !c.statementsModule.isAnonymous && !seenTrusted.contains c.statementsModule && !c.isUntrustedDecomp c.statementsModule then
      trustedImports := trustedImports.push { module := c.statementsModule, importAll := c.allowModuleSystem }
      seenTrusted := seenTrusted.insert c.statementsModule
    if let some dm := c.decompStatementsModule then
      if !dm.isAnonymous && !c.isUntrustedDecomp dm then
        throw <| IO.userError s!"decomp statements module {dm} must be listed in untrusted-decomp-modules for kernel replay"

    -- Load `sunstead-runner`-compiled `DecompStatements_*` modules from checker-owned
    -- snapshot storage without trusting them via `importModules`; every constant is
    -- checked for safety and kernel-replayed below before contributor proofs.
    let mut decompConsts : Std.HashMap Name ConstantInfo := {}
    let mut decompRegions : Array CompactedRegion := #[]
    if !c.untrustedDecompModules.isEmpty then
      let some decompLib := c.untrustedDecompLib
        | throw <| IO.userError "untrusted-decomp-modules requires untrusted-decomp-lib"
      for dm in c.untrustedDecompModules do
        if c.frozen.contains dm then
          throw <| IO.userError s!"decomp statements module {dm} must not be marked frozen"
        let path := modToFilePath decompLib dm "olean"
        unless (← path.pathExists) do
          throw <| IO.userError s!"missing build output for decomp statements module {dm}"
        let parts ← readModulePartsChecked false path (toString dm)
        for (_, reg) in parts do
          decompRegions := decompRegions.push reg
        for (mod, _) in parts do
          for imp in mod.imports do
            if c.libRoot.isPrefixOf imp.module && !c.frozen.contains imp.module then
              throw <| IO.userError s!"decomp statements module {dm} imports non-frozen module {imp.module}"
            if !seenTrusted.contains imp.module then
              trustedImports := trustedImports.push { module := imp.module, importAll := c.allowModuleSystem }
              seenTrusted := seenTrusted.insert imp.module
          for (n, ci) in mod.constNames.zip mod.constants do
            match ci with
            | .axiomInfo _ =>
              throw <| IO.userError s!"decomp statements module {dm} contains forbidden axiom {n}"
            | .opaqueInfo _ =>
              throw <| IO.userError s!"decomp statements module {dm} contains forbidden opaque {n}"
            | .quotInfo _ =>
              throw <| IO.userError s!"decomp statements module {dm} contains forbidden quotient {n}"
            | .defnInfo dv =>
              unless dv.safety == .safe do
                throw <| IO.userError s!"decomp statements module {dm} contains unsafe definition {n}"
            | .inductInfo iv =>
              if iv.isUnsafe then
                throw <| IO.userError s!"decomp statements module {dm} contains unsafe inductive {n}"
            | .ctorInfo cv =>
              if cv.isUnsafe then
                throw <| IO.userError s!"decomp statements module {dm} contains unsafe constructor {n}"
            | .recInfo rv =>
              if rv.isUnsafe then
                throw <| IO.userError s!"decomp statements module {dm} contains unsafe recursor {n}"
            | .thmInfo _ => pure ()
            if decompConsts.contains n then
              throw <| IO.userError s!"decomp statements constant {n} defined in more than one module"
            decompConsts := decompConsts.insert n ci

    let env ← importModules trustedImports {} 0 (loadExts := false)
    for (n, _) in decompConsts do
      if env.contains n then
        throw <| IO.userError s!"decomp statements module redefines trusted constant {n}"
    let env ← if decompConsts.isEmpty then pure env else sunsteadReplay decompConsts env
    for (n, _) in a.consts do
      if env.contains n then
        throw <| IO.userError s!"contributor module redefines trusted constant {n}"
    let ctx : Core.Context := { fileName := "<sunstead-check>", fileMap := default }
    if c.mode == .decompose then
      -- Validate kernel-replayed subgoal statements BEFORE replaying contributor code.
      let (subAxs, _) ← (checkDecompSubgoalsM c).toIO ctx { env := env }
      let env ← sunsteadReplay a.consts env
      let (j, _) ← (checkDecompReductionM c a.consts subAxs).toIO ctx { env := env }
      if a.regions.size + decompRegions.size == 0 then pure ()
      return j
    else
      if c.isUntrustedDecomp c.statementsModule then
        let _ ← (checkSafePropSubgoalDefM c.statement).toIO ctx { env := env }
      let env ← sunsteadReplay a.consts env
      let (j, _) ← (checkClassicM c).toIO ctx { env := env }
      if a.regions.size + decompRegions.size == 0 then pure ()
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
