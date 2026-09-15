# Contributing to jatosr

## Before you start

Open an issue at <https://github.com/GidonFrischkorn/jatosr/issues> for
anything larger than a typo. There is a form for each of the three kinds:
a bug, which asks for the JATOS version and the function that fails; a
feature, which asks for the workflow it serves; and a sibling package for
another hosting platform, which asks for the platform's name and a link to
its API documentation. The package follows one workflow, JATOS with
Prolific, so an issue first saves work on both sides.

A bug report must not contain an API token. A token can appear in an error
message, in an `httr2` verbose log and in the output of `Sys.getenv()`;
replace it with `<token>` before pasting. If one has already been posted,
revoke it in the JATOS user interface.

## Branches and pull requests

Two branches are long-lived and protected, and nothing is pushed to either
directly:

- **`main`** is what is on CRAN. It changes only when a release or a hotfix
  is merged into it.
- **`develop`** is the default branch: reviewed work that is not on CRAN
  yet. `pak::pak("GidonFrischkorn/jatosr")` installs this version.

Everything else is a short-lived branch that arrives through a pull request:

| Branch | Cut from | Pull request into | Merged by |
| --- | --- | --- | --- |
| `feat/*`, `fix/*`, `docs/*`, `test/*`, `chore/*`, `refactor/*` | `develop` | `develop` | squash |
| `release/X.Y.Z` | `develop` | `main` | merge commit |
| `hotfix/X.Y.Z` | `main` | `main` | merge commit |
| `sync/vX.Y.Z` | `develop` (then merge `main` in) | `develop` | merge commit |

Squash merges keep `develop` at one commit per unit of work. Merge commits
are used wherever `main` and `develop` meet, so that `develop` always
contains `main`: a squashed or rebased release or sync copies the changes
without the commits, and every later release then conflicts. The
`branch-policy` check rejects a pull request into `main` from any other kind
of branch, and a pull request whose source is `main` or `develop` itself.

```sh
git switch -c fix/metadata-columns origin/develop   # one branch per issue
# work, commit
git push -u origin fix/metadata-columns
gh pr create --base develop --fill
```

A pull request is merged when the required checks pass on a branch that is
up to date with its target, every review thread is resolved, and the
checklist in the pull request template is ticked or the unticked boxes are
explained. Merged branches are deleted automatically.

### Who can merge

Each protected branch has two rulesets in `.github/rulesets/`:

- a **gate** (`main-gate.json`, `develop-gate.json`): pull request required,
  required checks passing on an up-to-date branch, review threads resolved,
  the allowed merge method, no force-push, no deletion. Nobody can bypass
  it.
- a **review** (`main-review.json`, `develop-review.json`): one approving
  review, from a code owner (`.github/CODEOWNERS`).

GitHub does not let anyone approve their own pull request, so while the
package has a single developer, the maintainer merges their own branches by
bypassing the review ruleset, which the repository-admin role may do on a
pull request and nowhere else. The gate still applies to that merge. A
contributor's pull request waits for the maintainer's approval.

### Checks that must pass

Six checks gate a merge into `main` or `develop`:

| Check | What it covers |
| --- | --- |
| `ubuntu-latest (release)` | `R CMD check` on the reference platform |
| `macos-latest (release)` | `R CMD check` on macOS |
| `windows-latest (release)` | `R CMD check` on Windows |
| `ubuntu-latest (4.1)` | `R CMD check` on the minimum R in `Depends` |
| `test-coverage` | the suite under `covr` |
| `branch-policy` | the pull request's source branch may merge into its target |

The `ubuntu-latest (devel)` and `ubuntu-latest (oldrel-1)` jobs and
`pkgdown` run on every pull request but do not block a merge. A failure on
R devel is worth an issue, and is often not caused by anything in this
package.

**If you rename a job or a matrix entry that is a required check, update
`.github/rulesets/main-gate.json` and `develop-gate.json` in the same pull
request**, and run `.github/apply-repo-protection.sh` after the merge.
Required checks are matched by name, for `R CMD check` in the form
`os (r)`. A renamed check that the rulesets still require never reports,
and every later pull request waits for it.

## Releasing

A release moves `develop` onto `main` and CRAN. The maintainer runs these
steps.

1. **Cut the release branch.** `git switch -c release/X.Y.Z origin/develop`,
   then `usethis::use_version()` to set `X.Y.Z` and the `NEWS.md` heading.
   Update `cran-comments.md`. Run `data-raw/check-keyring.R` on each
   operating system, `devtools::check(remote = TRUE, manual = TRUE)`,
   `devtools::check_win_devel()` and `rhub::rhub_check()` on the branch.
2. **Merge into `main`.** Open a pull request from `release/X.Y.Z` into
   `main` and merge it with a merge commit once the checks pass. The
   pkgdown site is deployed from `main`, so it now shows the release.
3. **Submit.** Locally, with `main` identical to `origin/main`:
   `devtools::submit_cran()`. It writes `CRAN-SUBMISSION` with the submitted
   commit; leave that file uncommitted, since `main` only takes merges.
4. **If CRAN asks for changes**, cut `hotfix/X.Y.Z` from `main`, fix, merge
   the pull request into `main` with a merge commit, and submit again from
   `main`.
5. **On acceptance**, with `main` still identical to `origin/main`:
   `usethis::use_github_release()`. It tags `vX.Y.Z` at the commit recorded
   in `CRAN-SUBMISSION`, publishes the GitHub release, and deletes the file.
6. **Bring `main` back into `develop`.**

   ```sh
   git switch -c sync/vX.Y.Z origin/develop
   git merge --no-ff origin/main
   ```

   Resolve conflicts in `DESCRIPTION` to `main`'s version, run
   `usethis::use_dev_version()` so the version reads `X.Y.Z.9000`, check
   that `NEWS.md` starts with a single `# jatosr (development version)`
   heading, and commit. Open a pull request into `develop` and merge it with
   a **merge commit**. If it is squashed by mistake, the `sync-ancestry`
   workflow fails on the merge; repeat this step with a new `sync/` branch.

A hotfix follows steps 4 to 6: merge into `main`, submit, release, sync.
Tags matching `v*` cannot be moved or deleted
(`.github/rulesets/release-tags.json`).

### When a required check is broken

If a required check fails for reasons outside the package (a runner image,
a CRAN mirror) and a merge cannot wait for it to be fixed or re-run, a
repository admin sets the gate ruleset's enforcement to *Disabled* in
Settings → Rules, merges, and sets it back to *Active* straight away. Say in
the pull request that this was done and why.

### Repository administration

`.github/rulesets/` holds the branch and tag protection as JSON, and
`.github/apply-repo-protection.sh` applies it, together with the merge
settings and the default branch, so the remote configuration is reviewable
in a diff rather than only in Settings. Run the script after changing a
ruleset file; `--dry-run` shows what would change.

## Development cycle

```r
devtools::load_all()   # never library(jatosr) while developing
devtools::document()   # before every check; NAMESPACE and man/ are generated
devtools::test()
devtools::check()
```

`NAMESPACE` and `man/` are generated by roxygen2; edit the roxygen comments,
not the generated files. Every user-facing change gets a bullet in
`NEWS.md`.

## Rules

- Tokens live in the operating system's credential store, reached through
  `keyring` under the service name `jatosr`; the host lives in
  `profiles.json` under `tools::R_user_dir()`. `JATOS_HOST` and
  `JATOS_TOKEN` are read, and take precedence, but nothing in the package
  writes them, and nothing writes a token to a file.
- No token literal anywhere in the repository: not in vignettes, not in
  fixtures, not in test bodies. The fake tokens the tests need are defined
  once, in the `fake_tokens` vector of
  `tests/testthat/helper-credentials.R`; `expect_no_token()` asserts that
  none of them appears in a print, message or error path, and
  `tests/testthat/test-canary.R` greps the sources and the documentation
  for a token-shaped literal.
- The connection object carries no token. If you add a field to it, or a
  file the package writes, the canary test must still pass — it scans every
  artefact byte by byte.
- No test touches a real credential store. `local_no_credentials()` and
  `local_fake_credentials()` force `keyring`'s `env` backend, `setup.R`
  points the configuration at `tempdir()`, and `keyring_guard()` aborts on
  any other backend. Before a release, run `data-raw/check-keyring.R` by
  hand on each platform: it is the only thing that exercises the real
  store.
- `httr2::request()` is called in exactly one place, `jatos_req()` in
  `R/request.R`. Every endpoint goes through it.
- No live network in tests. HTTP is mocked with `local_jatos_mock()`
  (`tests/testthat/helper-mock.R`). Fixtures live in
  `tests/testthat/fixtures/`; the zip fixtures are regenerated with
  `data-raw/make-fixtures.R`, never edited by hand.
- Style: native pipe, explicit `pkg::fun()`, typed `purrr::map_*()`,
  roxygen2 on every export, `cli::cli_abort()` for errors, no dplyr,
  stringr or tidyr in `Imports`.
- Metadata is a plain tibble with a column-name contract, one row per
  component result; functions check it with `check_metadata()` at entry.

## Sibling packages

A package that does for another platform what `jatosr` does for JATOS is
welcome, and this repository is meant to be its template. The section
"Using jatosr as a template" of `vignette("developer-notes")` lists what
to copy unchanged, what to replace, and in which order to build.
