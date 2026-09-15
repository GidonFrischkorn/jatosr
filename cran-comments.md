## Release summary

First submission of jatosr 0.1.0, an R client for the REST API of JATOS
(Just Another Tool for Online Studies).

## Test environments

* local: macOS 26.6.2, R 4.6.1, 2026-09-15.
  `devtools::check(args = c("--as-cran", "--no-manual"))` with
  `_R_CHECK_XREFS_PKGS_ARE_DECLARED_=TRUE`: 0 errors, 0 warnings, 0 notes;
  examples, tests and vignettes run.
* GitHub Actions (2026-09-15), notes treated as errors: macOS,
  Windows and Ubuntu on R-release, Ubuntu on R-devel and R-oldrel-1 all
  pass. Ubuntu on R 4.1, the declared minimum, passes with 1 note: arrow
  (Suggests) needs R >= 4.2 and is not installed there, so its tests skip.
* local, `devtools::check(remote = TRUE, manual = TRUE)`: TODO Gidon, run
  and paste the result here.
* win-builder R-devel, `devtools::check_win_devel()`: TODO Gidon, paste the
  result here.
* win-builder R-release, `devtools::check_win_release()`: TODO Gidon, paste
  the result here.
* R-hub, `rhub::rhub_check()` (at least the Linux and Windows platforms):
  TODO Gidon, paste the result here.

## R CMD check results

0 errors | 0 warnings | 0 notes on the local check above. The incoming check
is expected to add the "New submission" note.

## Notes for the reviewer

* No example, test or vignette reaches the network. Every HTTP call in the
  test suite is served by `httr2::local_mocked_responses()` from fixtures
  under `tests/testthat/fixtures/`.
* The examples of the offline functions (`jatos_read_json()`,
  `jatos_read_results()`, `jatos_read_metadata()`, `jatos_cache_status()`,
  `jatos_extract_fields()`, `jatos_write_results()`, `jatos_write_raw()`,
  `jatos_import_results()`, and the metadata helpers) run on a small
  synthetic cache shipped under `inst/extdata/`, and write into `tempdir()`
  only, removing what they wrote.
* The 23 examples in `\dontrun{}` cannot run on a check machine, and each
  says why in its first line: 19 need a JATOS server and a personal API
  token (`# needs a JATOS server and a stored API token`), and 4 read or
  change the machine's credential store (`# lists the machine's credential
  store`, `# changes the machine's credential store`), which on a check
  machine could prompt to unlock a keychain.
* No example, test or vignette touches a real credential store. The
  examples that would are the four in `\dontrun{}` above. The test suite
  forces keyring onto its `env` backend, which keeps values in environment
  variables for the life of the session, and sets `JATOSR_CONFIG_DIR` to a
  directory in `tempdir()`; an internal guard aborts if a test reaches any
  other backend.
* Nothing is written outside `tempdir()` by examples, tests or vignettes.
  The only files the package writes at all, outside paths the user names,
  are the API token, into the credential store of the operating system, and
  the server's URL, into `tools::R_user_dir("jatosr", "config")` — both only
  when the user calls `jatos_set_credentials()`.
* The test suite asserts that no token reaches a print, message, error or
  saved file (including decompressed `rds` and `RData`); those tests run on
  CRAN. One further test greps the package sources for token-shaped
  literals; it needs the source tree and is developer-side
  (`skip_on_cran()`).
* The vignette output shown in `vignette("jatosr")` and
  `vignette("credentials")` was produced against the mocked server; all
  server chunks are `eval = FALSE`.
* `httr2 (>= 1.2.0)`: from 1.2.0 on, httr2 does not serialise redacted
  headers (httr2 NEWS), which a test relies on: a request object saved with
  `saveRDS()` holds no token. `keyring (>= 1.4.0)`: from 1.4.0 on, keyring
  selects its file backend by default only when a file keyring exists
  (keyring NEWS). On a machine without a system keyring the default is then
  the `env` backend, on which `jatos_set_credentials()` refuses with
  instructions, as `vignette("credentials")` describes.
* `keyring` is in Imports because it is the default place a token is kept,
  not an extra. It installs without a system keyring present, and
  `jatos_set_credentials()` refuses, with instructions, rather than
  pretending to store a token that would not persist.
* `arrow` is in Suggests and guarded by `rlang::check_installed()`; the
  parquet tests skip when it is not installed and run on GitHub Actions,
  where it is.
* `urlchecker::url_check()`: the `URL` and `BugReports` entries
  (`github.com/GidonFrischkorn/jatosr`) answer 404 while the repository is
  private. TODO Gidon: re-run once the repository is public, before
  submission.
* `spelling::spell_check_package()` is clean against `inst/WORDLIST`
  (`Language: en-GB`).
* The Description names the 'smartr' package (Chenyu Li, MIT,
  <https://github.com/chenyu-psy/smartr>, not on CRAN) because the JATOS
  retrieval workflow is modelled on its JATOS functions. No code is copied or
  derived from it: jatosr was written anew, and none of the 183 distinct code
  lines of `smartr/R/jatos-helper.R` (at least 25 characters, whitespace
  ignored) occurs in `R/`. For that reason Chenyu Li is not in
  `Authors@R`; he was consulted and agreed that an acknowledgement is
  sufficient.

## Open before submission (Gidon)

* Three checks against a live JATOS server are still open and do not affect
  the check, but should be run once before submission: `data.size` grows
  after `jatos.appendResultData()`; `POST /results/data` accepts
  `componentResultIds` in the body; the zip entry names of
  `POST /results/data`, `POST /results/files` (the `files/` folder) and
  `POST /results`. The download refuses an answer that is not a zip file
  loudly, so the live test cannot corrupt a cache.
