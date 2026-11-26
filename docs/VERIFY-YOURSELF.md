# Checking a Sunstead proof without trusting Sunstead

Sunstead's verifier checks proofs against frozen copies of open `sorry`s taken
from real Lean projects. That is a claim about Sunstead's own infrastructure. The
public verifier, `scripts/sunstead_verify.py`, served unchanged at
<https://sunstead.org/verify.py>, lets anyone check the stronger claim, "this
proof closes that `sorry` in the upstream project", using only the upstream
repository and stock Lean.

```bash
curl -fsSLO https://sunstead.org/verify.py
python3 verify.py <proof id>            # the hex in /proofs/<id>
```

Each ledger entry carries a structured `verification` object (`mission_replay`
for `bundle.tar.gz?base=seed` + `git am history.mbox`, and `upstream_replay`
for `/verify.py` when `upstream.anchor_kind` is `in_place_sorry` or
`challenge_node`), plus top-level `verify_command` for compatibility. Demo and
retired missions, hill-climb optimization tracks (`optimization_spec`),
extracted lemmas (`extracted_lemma`), decomposition subgoals, and refutations
have `upstream_replay: null` (`verify_command: null`), because they have no
single upstream declaration to splice into automatically.

## What it does

1. `GET /api/proofs/<id>`, then requires `sha256(patch)` to equal the id you asked for.
2. Downloads the mission's public seed bundle (`bundle.tar.gz?base=seed`) and
   extracts regular files only (no links, no `..` or absolute paths, and the
   bundled `.git` is dropped). Nothing in it is executed: the task's theorem
   name is read from the `verify` script's `TASKS` table with `ast`.
3. Applies the accepted patch (it may only change the task's target file, with
   no mode changes or symlinks), and extracts the proof, any helper lemmas added
   above it and any new imports. Nothing may contain `sorry`. Only the proof is
   taken: if the accepted file restates the theorem in different words (say, a
   shorter name inside a `namespace`), the upstream statement is used anyway.
4. Clones the upstream repository from GitHub at the pinned 40-character commit,
   finds the declaration at the task's `upstream_url`, and requires its name and
   statement to match (comments, whitespace and attributes ignored). The ledger
   and the bundle must name the same upstream repo and commit.
5. Puts the proof in place of the upstream `sorry`, runs `lake exe cache get`
   and `lake build <module>` with the upstream project's own `lean-toolchain`,
   requires no `sorry` warning in the spliced lines, and lists the theorem's
   axioms with a standalone checker that loads the compiled environment with
   `importModules (loadExts := false)` and `collectAxioms`, so no elaborator in
   the upstream or contributed code can rewrite the report. Only `propext`,
   `Classical.choice` and `Quot.sound` pass.
6. Builds a second, `sorry`'d copy of the pristine upstream statement
   (`<namespace>.sunsteadRefStatement`) in the same file, *above* the
   contributed helpers, and requires the spliced theorem's type to be
   identical to it. A helper `instance` or a `def` that shadows a name could
   otherwise change what the upstream statement means. The reference copy is
   only there during the build.

Exit status: 0 verified, 1 a check failed, 2 usage or environment problem,
3 not checkable automatically (the upstream `sorry` sits inside a larger
declaration that the mission split out as its own theorem, as in the ArkLib
mission). `--no-build` stops after step 4 and never reports "verified".
`--json` prints a machine-readable result and `--keep DIR` keeps the patched
upstream checkout.

For a compatibility check, pass `--upstream-commit <40-hex SHA>` after reviewing
the upstream revision. The replay fails if the target file differs byte-for-byte
from the ledger pin, so the pinned line anchor remains valid. Other files and
dependencies may have changed: a pass verifies the proof at the tested commit
only; it does not attest that the target is unclaimed or that imported definitions
have retained their meaning. JSON names the tested and pinned commits separately.

## What you trust when it passes

The upstream repository at that commit (the statement and everything it
depends on), GitHub for serving it, and the Lean toolchain elan installs for
it. Not Sunstead's verifier, hub or source code: the hub only supplies the
candidate proof, and a hub that lied about the statement, the upstream pin or
the theorem would make the check fail, not pass.

## Safety

Building Lean code runs it. Tactics and macros execute at compile time, and so
does the upstream project's lakefile. The script refuses contributed code that
adds metaprogramming (`elab`, `macro`, `syntax`, `run_tac`, `initialize`,
`@[implemented_by]` and similar) unless you pass `--allow-metaprogramming`.
Even so, run it in a disposable VM or container if you would not run
`lake build` on the upstream project itself.

## Daily public run

`.github/workflows/upstream-verify.yml` runs `verify.py` with a full build on
every upstream-linked ledger proof each day (and on demand for one proof id),
on GitHub's public runners with no secrets, and posts a summary table to the
run page. Exit 3 (not upstream-checkable) is reported but does not fail the run.
On manual runs, `upstream_commit` requires one `proof_id`. Scheduled runs
continue to use the ledger pins.

## For maintainers

The Lean declaration parser in `scripts/sunstead_verify.py` is copied from
`scripts/scout-upstream.py` to keep `verify.py` a single stdlib-only file;
`scripts/test_sunstead_verify.py` fails if the two drift apart, and
`scripts/e2e.py` checks that `/verify.py` is served byte for byte from this
repository.

Tests: `python3 scripts/test_sunstead_verify.py -v` (offline tests run without
Lean; `PublicBuildTests` runs `lake build`, reference-statement comparison, and
the standalone `AXIOM_CHECKER` whenever `lake` is on `PATH`).
