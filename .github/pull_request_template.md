<!-- Link the issue this pull request closes, e.g. "Closes #12". -->

## What this changes

<!-- One or two sentences. What the user can do afterwards that they could not do before, or what stops going wrong. -->

## Checks run in this branch

- [ ] `devtools::document()`, and the regenerated `NAMESPACE` and `man/` are committed
- [ ] `devtools::test()` passes
- [ ] `devtools::check()` passes with 0 errors, 0 warnings, 0 notes
- [ ] `NEWS.md` has a bullet, if the change is user-facing

## Rules this branch keeps

- [ ] No API token literal anywhere; test tokens come from `fake_tokens` in `tests/testthat/helper-credentials.R`
- [ ] `httr2::request()` is still called only in `jatos_req()` (`R/request.R`)
- [ ] No live network in tests; new HTTP is mocked with `local_jatos_mock()`
- [ ] No dplyr, stringr or tidyr added to `Imports`

<!-- If a box is deliberately unticked, say why here rather than removing it. -->
