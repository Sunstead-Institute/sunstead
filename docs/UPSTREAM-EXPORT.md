# Sending a verified proof upstream

`scripts/export-upstream.py` turns one accepted Sunstead proof into a bundle a
maintainer can review before proposing it to the upstream project. It never
pushes, opens a pull request, or writes inside this repository. Sending anything
upstream stays a maintainer's decision, made after reading the bundle.

```bash
python3 scripts/export-upstream.py --proof-id <ledger id> --out /tmp/export-<id>
```

The checks below are the same code anyone outside the project runs through
[`/verify.py`](VERIFY-YOURSELF.md): `scripts/sunstead_verify.py` is the engine and
this script adds the mission files from this checkout and the PR bundle.

`<ledger id>` is the hex in a `/proofs/<id>` permalink. The proof is read with
`GET /api/proofs/<id>` from `--hub` (default `https://sunstead.org`, read only).
`--proof-json` takes a saved copy of that response instead.

## What it checks

1. The mission is live and not a demo, the proof was accepted under the current
   frozen spec (`--allow-stale-spec` overrides after checking it by hand), and the
   task's `upstream_url` points into the commit pinned in `UPSTREAM.json`.
2. The accepted patch changes only the task's target file, keeps the frozen
   statement unchanged, and leaves no `sorry` in the proof or in any helper
   declaration added above it.
3. The full upstream repository is fetched at the pinned 40-character commit
   into a temporary directory. The declaration at the task's `sorry` must have
   the same name and the same statement as the mission's copy (comments,
   whitespace and attributes such as `@[simp]` are ignored).
4. Its proof is replaced by the Sunstead proof. Helper declarations go directly
   above it, and `import` lines the file does not already have go after its
   imports. The accepted patch may not change file modes or create symlinks, and
   every git call runs with `core.hooksPath=/dev/null`.
5. Unless `--no-build`: `lake exe cache get`, then `lake build <module>` on the
   full checkout. The bundle is refused if the build fails, if the declaration or
   a helper still reports `sorry`, if the declaration is not a theorem, or if it
   depends on any axiom besides `propext`, `Classical.choice` and `Quot.sound`.
   Axioms are read by a standalone checker (`lake env lean --run`, importing only
   `Lean`) that loads the built module with `importModules` and calls
   `collectAxioms`; it never elaborates source, so `elab_rules` or `macro_rules`
   cannot rewrite the report the way they can rewrite `#print axioms` output.
   Each `--lint-cmd` (for example
   the upstream's own style linter) runs in the checkout and its result is
   recorded.

## The bundle

| File | Contents |
|---|---|
| `upstream.patch` | `git diff` against the pinned commit |
| `PR_BODY.md` | Attribution, Sunstead permalink, and the checks that ran |
| `metadata.json` | Ids, upstream file and declaration, helpers, imports, checks, warnings |
| `build.log` | Every command run in the upstream checkout and its output (also written, alone, when a check fails) |

The `--out` directory must be outside this repository, because the bundle
contains a solution. The tool refuses otherwise.

## What it leaves to a person

- **Names.** Helpers and proofs were written inside the mission namespace (for
  example `PntFoundations`). Unqualified names usually resolve upstream, but
  explicit `PntFoundations.` references produce a warning and need renaming.
- **`open` lines** added by the contributor are reported, not copied.
- **Declarations added after the theorem** are reported, not copied.
- **Tasks extracted from inside a bigger proof**, such as
  `arklib-near-capacity-primes`, where the upstream `sorry` is one step of
  `exists_rs_epsCa_large_near_capacity`. Automatic export refuses these; they
  need a hand-written upstream lemma.
- **Rebasing.** The patch is against the pinned commit; rebase onto upstream
  `main` and re-run its CI before proposing it.

## Tests

`python3 scripts/test_export_upstream.py` runs offline against throwaway git
repositories. Without `lake` on `PATH` it skips the build tests. CI's
`Upstream export (core Lean build)` job installs the pinned toolchain (core
Lean only, no Mathlib) and runs them too, covering a successful build, a proof
that does not compile (its compiler output must reach the error and
`build.log`), a helper `axiom` that the checker rejects, and the same axiom
behind an `elab_rules` that spoofs `#print axioms`.
