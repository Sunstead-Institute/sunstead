/-
Sunstead trusted Lean checker. Installed read-only at /opt/sunstead/ and run with
`lean --run` as the `sunstead-checker` user, after every contributor process is dead.

It never elaborates contributor source. It:
1. Loads the frozen modules (`<Lib>.Spec`, `<Lib>.SunsteadStatements`) from a
   trusted build directory, plus core (`Init`, ...) from the toolchain.
2. Reads the contributor's compiled `.olean` files for the target module and
   every non-frozen `<Lib>.*` module it imports, and re-checks every constant in
   them with the Lean kernel (`Environment.replay`). Nothing in those files runs:
   no `initialize`, no elaborators, no `#eval`.
3. Asks the kernel to accept `theorem _sunstead_check : <frozen statement> := <target>`,
   so the target must prove exactly the frozen statement (definitional equality).
4. Collects the axioms `_sunstead_check` depends on, and (for hill-climb tasks)
   reduces the score constant to a natural-number literal.

Output: one JSON line on stdout, e.g. {"ok":true,"axioms":["propext"],"score":150}.
Any error fails closed with {"ok":false,"error":"..."}.
-/
import Lean
import Std.Data.HashMap
import Std.Data.HashSet

open Lean

structure Cfg where
  trustedLib : System.FilePath := ""
  untrustedLib : System.FilePath := ""
  libRoot : Name := .anonymous
  frozen : List Name := []
  targetModule : Name := .anonymous
  targetConst : Name := .anonymous
  statement : Name := .anonymous
  scoreConst : Option Name := none
  statementsModule : Name := .anonymous

partial def parseArgs : List String → Cfg → Except String Cfg
  | [], c => .ok c
  | "--trusted-lib" :: v :: rest, c => parseArgs rest { c with trustedLib := v }
  | "--untrusted-lib" :: v :: rest, c => parseArgs rest { c with untrustedLib := v }
  | "--lib-root" :: v :: rest, c =>
      parseArgs rest { c with libRoot := v.toName, statementsModule := (v ++ ".SunsteadStatements").toName }
  | "--frozen" :: v :: rest, c =>
      parseArgs rest { c with frozen := (v.splitOn ",").map String.toName }
  | "--target-module" :: v :: rest, c => parseArgs rest { c with targetModule := v.toName }
  | "--target-const" :: v :: rest, c => parseArgs rest { c with targetConst := v.toName }
  | "--statement" :: v :: rest, c => parseArgs rest { c with statement := v.toName }
  | "--score-const" :: v :: rest, c => parseArgs rest { c with scoreConst := some v.toName }
  | a :: _, _ => .error s!"unknown argument {a}"

def Cfg.isUntrusted (c : Cfg) (m : Name) : Bool :=
  c.libRoot.isPrefixOf m && !c.frozen.contains m

structure Acc where
  visited : Std.HashSet Name := {}
  trusted : Array Import := #[]
  consts : Std.HashMap Name ConstantInfo := {}
  untrustedMods : Array Name := #[]

partial def visit (c : Cfg) (acc : IO.Ref Acc) (m : Name) : IO Unit := do
  if (← acc.get).visited.contains m then return
  acc.modify fun a => { a with visited := a.visited.insert m }
  if c.isUntrusted m then
    let path := modToFilePath c.untrustedLib m "olean"
    unless (← path.pathExists) do
      throw <| IO.userError s!"missing build output for {m}"
    let (mod, _region) ← readModuleData path
    for imp in mod.imports do
      visit c acc imp.module
    let a ← acc.get
    let mut cs := a.consts
    for (n, ci) in mod.constNames.zip mod.constants do
      if cs.contains n then
        throw <| IO.userError s!"constant {n} defined in more than one module"
      cs := cs.insert n ci
    acc.set { a with consts := cs, untrustedMods := a.untrustedMods.push m }
  else
    acc.modify fun a => { a with trusted := a.trusted.push { module := m } }

def allowedAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

def checkM (c : Cfg) : CoreM Json := do
  let env ← getEnv
  let some tci := env.find? c.targetConst
    | throwError "target constant {c.targetConst} not found"
  unless tci.levelParams.isEmpty do
    throwError "target constant must not be universe polymorphic"
  let mut stmt := mkConst c.statement
  let mut fields : List (String × Json) := []
  if let some k := c.scoreConst then
    let some kci := env.find? k | throwError "score constant {k} not found"
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
    { name := checkName, levelParams := [], type := stmt, value := mkConst c.targetConst, all := [checkName] }
  let axs ← collectAxioms checkName
  return Json.mkObj ([("ok", Json.bool true), ("axioms", toJson (axs.map toString))] ++ fields)

def run (args : List String) : IO Json := do
  let c ← match parseArgs args {} with
    | .ok c => pure c
    | .error e => throw <| IO.userError e
  initSearchPath (← findSysroot) [c.trustedLib]
  let acc ← IO.mkRef ({} : Acc)
  visit c acc c.targetModule
  let a ← acc.get
  unless a.untrustedMods.contains c.targetModule do
    throw <| IO.userError s!"target module {c.targetModule} is not a contributor module"
  unless a.consts.contains c.targetConst do
    throw <| IO.userError s!"{c.targetConst} is not defined in the contributor's modules"
  let env ← importModules (a.trusted.push { module := c.statementsModule }) {} 0
  for (n, _) in a.consts do
    if env.contains n then
      throw <| IO.userError s!"contributor module redefines trusted constant {n}"
  let env ← env.replay a.consts
  let ctx : Core.Context := { fileName := "<sunstead-check>", fileMap := default }
  let (j, _) ← (checkM c).toIO ctx { env := env }
  return j

def main (args : List String) : IO UInt32 := do
  if args == ["--selftest"] then
    IO.println "{\"selftest\":\"ok\"}"
    return 0
  try
    let j ← run args
    IO.println j.compress
    return 0
  catch e =>
    IO.println (Json.mkObj [("ok", Json.bool false), ("error", Json.str (toString e))]).compress
    return 1
