test_that("the configuration lives under JATOSR_CONFIG_DIR when it is set", {
  dir <- local_config_sandbox()

  expect_equal(config_dir(), dir)
  expect_equal(config_path(), file.path(dir, "profiles.json"))
})

test_that("the configuration defaults to the sanctioned user directory", {
  withr::local_envvar(c(JATOSR_CONFIG_DIR = NA))

  expect_equal(config_dir(), tools::R_user_dir("jatosr", "config"))
})

test_that("no file means no profiles, not an error", {
  local_config_sandbox()

  expect_equal(config_read(), list())
  expect_equal(config_profiles(), character())
  expect_null(config_host("default"))
})

test_that("a host round-trips through the configuration file", {
  local_config_sandbox()
  config_set_host("default", fake_host)

  expect_equal(config_host("default"), fake_host)
  expect_equal(config_profiles(), "default")
})

test_that("profiles are stored and read case-insensitively", {
  local_config_sandbox()
  config_set_host("Lab_Admin", fake_host)

  expect_equal(config_profiles(), "lab_admin")
  expect_equal(config_host("LAB_ADMIN"), fake_host)
})

test_that("writing one profile keeps the others", {
  local_config_sandbox()
  config_set_host("default", fake_host)
  config_set_host("lab_admin", "https://jatos.example.net")

  expect_setequal(config_profiles(), c("default", "lab_admin"))
  expect_equal(config_host("default"), fake_host)
  expect_equal(config_host("lab_admin"), "https://jatos.example.net")
})

test_that("dropping a profile reports whether it was there", {
  local_config_sandbox()
  config_set_host("default", fake_host)
  config_set_host("lab_admin", fake_host)

  expect_true(config_drop_profile("default"))
  expect_equal(config_profiles(), "lab_admin")
  expect_false(config_drop_profile("default"))
})

test_that("the file is written with the version and no token", {
  local_config_sandbox()
  config_set_host("default", fake_host)
  written <- jsonlite::read_json(config_path(), simplifyVector = FALSE)

  expect_equal(written$version, 1L)
  expect_equal(written$profiles$default$host, fake_host)
  expect_no_token(readLines(config_path(), warn = FALSE))
})

test_that("the file is not world-readable on unix", {
  skip_on_os("windows")
  local_config_sandbox()
  config_set_host("default", fake_host)
  mode <- as.character(file.info(config_path())$mode)

  expect_equal(mode, "600")
})

test_that("a corrupt configuration warns and is treated as empty", {
  # Every host resolution goes through config_read(). Aborting here would
  # turn one hand-edited trailing comma into "nothing in the package works".
  dir <- local_config_sandbox()
  writeLines('{"version": 1, "profiles": {', file.path(dir, "profiles.json"))

  expect_warning(profiles <- config_read(), "Could not read the profile configuration")
  expect_equal(profiles, list())
  expect_warning(expect_null(config_host("default")))
})

test_that("a well-formed file without profiles is treated as empty", {
  dir <- local_config_sandbox()
  writeLines('{"version": 1}', file.path(dir, "profiles.json"))

  expect_equal(config_read(), list())
  expect_equal(config_profiles(), character())
})

test_that("a hand-edited key in another case is the same profile", {
  # Profile names are case-insensitive everywhere else; a `Default` key used
  # to be listed as a profile that nothing could use or remove.
  dir <- local_config_sandbox()
  writeLines(
    sprintf('{"version": 1, "profiles": {"Default": {"host": "%s"}}}', fake_host),
    file.path(dir, "profiles.json")
  )

  expect_equal(config_profiles(), "default")
  expect_equal(config_host("default"), fake_host)
  expect_equal(config_host("DEFAULT"), fake_host)
  expect_true(config_drop_profile("default"))
  expect_equal(config_profiles(), character())
})

test_that("keys that could not be profile names are ignored", {
  dir <- local_config_sandbox()
  writeLines(
    sprintf(
      '{"version": 1, "profiles": {"1abc": {"host": "%s"}, "lab-admin": {"host": "%s"}, "ok": {"host": "%s"}}}',
      fake_host, fake_host, fake_host
    ),
    file.path(dir, "profiles.json")
  )

  expect_equal(config_profiles(), "ok")
  expect_null(config_host("1abc"))
})

test_that("the writers keep hand-edited keys they ignore and collapse spellings", {
  # What config_read() leaves out is not the package's to delete: a stray
  # `lab-admin` used to vanish at the next store. A second spelling of the
  # profile being written is replaced, so the file never holds two.
  dir <- local_config_sandbox()
  writeLines(
    sprintf(
      '{"version": 1, "profiles": {"lab-admin": {"host": "%s"}, "Default": {"host": "%s"}, "other": {"host": "%s"}}}',
      fake_host, "https://old.example", fake_host
    ),
    file.path(dir, "profiles.json")
  )

  config_set_host("default", fake_host)
  written <- jsonlite::read_json(config_path(), simplifyVector = FALSE)
  expect_setequal(names(written$profiles), c("lab-admin", "default", "other"))
  expect_equal(written$profiles$default$host, fake_host)
  expect_equal(config_host("default"), fake_host)

  expect_true(config_drop_profile("DEFAULT"))
  written <- jsonlite::read_json(config_path(), simplifyVector = FALSE)
  expect_setequal(names(written$profiles), c("lab-admin", "other"))
  expect_equal(config_profiles(), "other")
})

test_that("a file from a newer format version warns once and is still read", {
  local_token_state()
  dir <- local_config_sandbox()
  writeLines(
    sprintf('{"version": 2, "profiles": {"default": {"host": "%s"}}}', fake_host),
    file.path(dir, "profiles.json")
  )

  w <- expect_warning(profiles <- config_read(), "newer jatosr")
  expect_match(conditionMessage(w), "format version 2")
  expect_equal(profiles$default$host, fake_host)
  # once per session, not once per host resolution
  expect_no_warning(config_read())
  expect_no_warning(config_host("default"))
})

test_that("a profile entry without a host reads as no host", {
  dir <- local_config_sandbox()
  writeLines('{"version": 1, "profiles": {"default": {}}}', file.path(dir, "profiles.json"))

  expect_equal(config_profiles(), "default")
  expect_null(config_host("default"))
})

test_that("writing leaves no temporary file behind", {
  dir <- local_config_sandbox()
  config_set_host("default", fake_host)

  expect_equal(list.files(dir), "profiles.json")
})

# --- when the write fails --------------------------------------------------------

test_that("a directory that cannot be created is an error, not a silent return", {
  # The parent is a file, so dir.create() fails the same way on every
  # platform and for every user, root included. Both results used to be
  # ignored, and the write "succeeded" with nothing on disk.
  blocker <- withr::local_tempfile(lines = "not a directory")
  withr::local_envvar(c(JATOSR_CONFIG_DIR = file.path(blocker, "config")))

  err <- expect_error(
    config_set_host("default", fake_host),
    class = "jatosr_config_write_failed"
  )
  message <- cli::ansi_strip(paste(conditionMessage(err), collapse = "\n"))
  expect_match(message, "profiles.json", fixed = TRUE)
  expect_match(message, "JATOSR_CONFIG_DIR", fixed = TRUE)
  expect_match(message, "could not be created")
})

test_that("a failed move into place is an error and leaves no temporary file", {
  dir <- local_config_sandbox()
  local_mocked_bindings(move_file = function(from, to) cli::cli_abort("disk full"))

  err <- expect_error(
    config_set_host("default", fake_host),
    class = "jatosr_config_write_failed"
  )
  expect_match(conditionMessage(err), "disk full")
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), character())
  expect_equal(config_profiles(), character())
})

test_that("a failed write does not disturb the file that was there", {
  dir <- local_config_sandbox()
  config_set_host("default", fake_host)
  local_mocked_bindings(move_file = function(from, to) cli::cli_abort("disk full"))

  expect_error(config_set_host("lab_admin", fake_host), class = "jatosr_config_write_failed")
  expect_equal(config_profiles(), "default")
  expect_equal(list.files(dir), "profiles.json")
})
