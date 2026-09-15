# A last belt against a test writing where a user's own credentials live.
#
# local_no_credentials() and local_fake_credentials() sandbox the profile
# configuration for the tests that call them; this makes the default for the
# whole run a temporary directory as well, so a test that forgets, or a new
# helper that does not know it has to, still cannot write into
# tools::R_user_dir("jatosr", "config").
#
# The credential store has its own guard, keyring_guard() in R/keyring.R,
# which aborts on any backend other than `env` during a test run.

config_root <- withr::local_tempdir(.local_envir = teardown_env())
withr::local_envvar(
  c(
    JATOSR_CONFIG_DIR = config_root,
    # The opt-out that lets a single test reach a real credential store is
    # cleared for the whole run, so that one left set in the session — by
    # data-raw/check-keyring.R, or by hand — cannot silently disarm
    # keyring_guard() for every test at once. The tests that need it set it
    # themselves, locally.
    JATOSR_REAL_KEYRING = NA
  ),
  .local_envir = teardown_env()
)

testthat::test_that("the test run cannot write to the real configuration", {
  expect_equal(config_dir(), config_root)
  expect_false(identical(config_dir(), tools::R_user_dir("jatosr", "config")))
})
