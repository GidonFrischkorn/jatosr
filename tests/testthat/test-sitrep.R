test_that("the sitrep says so when there is nothing at all", {
  local_no_credentials()
  out <- cli::ansi_strip(capture_messages(report <- jatos_credentials_sitrep()))

  expect_equal(nrow(report), 0)
  expect_match(message_text(out), "No credential profile found")
})

test_that("the sitrep names the system a bug report needs", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  out <- cli::ansi_strip(capture_messages(jatos_credentials_sitrep()))
  text <- message_text(out)

  expect_match(text, paste0("jatosr ", utils::packageVersion("jatosr")), fixed = TRUE)
  expect_match(text, paste0("keyring ", utils::packageVersion("keyring")), fixed = TRUE)
  expect_match(text, R.version.string, fixed = TRUE)
  expect_match(text, "Operating system")
  expect_no_token(out)
})

test_that("the sitrep names the commit of a package installed from GitHub", {
  local_no_credentials()
  local_mocked_bindings(installed_remote_sha = function() "0123456789abcdef0123")
  out <- cli::ansi_strip(capture_messages(jatos_credentials_sitrep()))

  expect_match(message_text(out), "commit 0123456", fixed = TRUE)
  expect_no_match(message_text(out), "0123456789abcdef", fixed = TRUE)
})

test_that("the sitrep names the store and the configuration file", {
  local_no_credentials()
  out <- cli::ansi_strip(capture_messages(jatos_credentials_sitrep()))
  text <- message_text(out)

  expect_match(text, "Credential store")
  expect_match(text, basename(config_path()), fixed = TRUE)
  expect_match(text, "not written yet")
})

test_that("the sitrep reports a token in the credential store", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  out <- cli::ansi_strip(capture_messages(report <- jatos_credentials_sitrep()))
  text <- message_text(out)

  expect_equal(report$auth_from, "keyring")
  expect_equal(report$host_from, "config")
  expect_equal(report$host, fake_host)
  expect_false(report$shadowed)
  expect_match(text, "from the credential store")
  expect_no_token(out)
})

test_that("the sitrep reports a token in an environment variable", {
  local_no_credentials()
  withr::local_envvar(c(JATOS_HOST = fake_host, JATOS_TOKEN = fake_token))
  out <- cli::ansi_strip(capture_messages(report <- jatos_credentials_sitrep()))

  expect_equal(report$auth_from, "env")
  expect_equal(report$host_from, "env")
  expect_match(message_text(out), "JATOS_TOKEN")
  expect_no_token(out)
})

test_that("the sitrep marks a variable that hides a stored token", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  withr::local_envvar(c(JATOS_TOKEN = fake_tokens[["stale"]]))
  out <- cli::ansi_strip(capture_messages(report <- jatos_credentials_sitrep()))

  expect_true(report$shadowed)
  expect_match(message_text(out), "hides a token")
  expect_no_token(out)
})

test_that("the sitrep can be limited to one profile", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  suppressMessages(jatos_set_credentials(fake_host, fake_tokens[["admin"]],
    profile = "lab_admin", check = FALSE
  ))

  expect_equal(nrow(jatos_credentials_sitrep()), 2)
  report <- jatos_credentials_sitrep("lab_admin")
  expect_equal(report$profile, "lab_admin")
})

test_that("the sitrep marks the active profile", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token,
    profile = "lab_admin", check = FALSE
  ))
  withr::local_envvar(JATOS_PROFILE = "lab_admin")
  out <- cli::ansi_strip(capture_messages(report <- jatos_credentials_sitrep()))

  expect_true(report$active)
  expect_match(message_text(out), "active")
})

test_that("the sitrep returns no token in any column", {
  local_no_credentials()
  withr::local_envvar(c(JATOS_HOST = fake_host, JATOS_TOKEN = fake_token))
  suppressMessages(jatos_set_credentials(fake_host, fake_tokens[["admin"]],
    profile = "lab_admin", check = FALSE
  ))
  report <- jatos_credentials_sitrep()

  expect_no_token(unlist(report))
  expect_no_token(capture.output(print(report)))
})

# --- a variable set in .Renviron ----------------------------------------------

test_that("the sitrep names an .Renviron that defines the profile and shows its lines", {
  dir <- local_no_credentials()
  writeLines(
    c(
      "OTHER=1",
      sprintf('JATOS_HOST="%s"', fake_host),
      sprintf('JATOS_TOKEN="%s"', fake_token)
    ),
    file.path(dir, "user.Renviron")
  )
  withr::local_envvar(c(JATOS_HOST = fake_host, JATOS_TOKEN = fake_token))

  out <- cli::ansi_strip(capture_messages(report <- jatos_credentials_sitrep()))
  text <- message_text(out)

  expect_true(report$renviron_line)
  expect_equal(report$renviron_file, file.path(dir, "user.Renviron"))
  expect_match(text, "defines this profile")
  expect_match(text, "takes precedence over the credential store")
  expect_match(text, "delete these lines")
  expect_match(text, "never edits the file")
  # the lines are shown by name; the token's value is not, the sitrep's
  # promise being that no token reaches its output
  expect_match(text, 'JATOS_HOST="https://jatos.example.org"', fixed = TRUE)
  expect_match(text, "JATOS_TOKEN=<value hidden>", fixed = TRUE)
  expect_no_token(text)
})

test_that("the sitrep never edits .Renviron and never copies its token", {
  dir <- local_no_credentials()
  path <- file.path(dir, "user.Renviron")
  contents <- c("OTHER=1", sprintf('JATOS_TOKEN="%s"', fake_token))
  writeLines(contents, path)
  withr::local_envvar(c(JATOS_HOST = fake_host, JATOS_TOKEN = fake_token))
  withr::local_options(list(rlang_interactive = TRUE))
  local_mocked_bindings(menu = function(...) stop("no prompt expected"), .package = "utils")

  out <- cli::ansi_strip(capture_messages(jatos_credentials_sitrep()))

  expect_equal(readLines(path), contents)
  expect_equal(keyring_list(), character())
  expect_equal(config_profiles(), character())
  expect_match(message_text(out), "delete this line")
})

test_that("the sitrep only reports: its one argument is the profile", {
  expect_equal(names(formals(jatos_credentials_sitrep)), "profile")
})

test_that("the sitrep marks an .Renviron token that hides a stored one", {
  dir <- local_no_credentials()
  writeLines(sprintf('JATOS_TOKEN="%s"', fake_token), file.path(dir, "user.Renviron"))
  withr::local_envvar(c(JATOS_HOST = fake_host, JATOS_TOKEN = fake_token))
  keyring_set("default", fake_token)

  out <- cli::ansi_strip(capture_messages(report <- jatos_credentials_sitrep()))

  expect_true(report$shadowed)
  expect_true(report$renviron_line)
  expect_match(message_text(out), "hides a token")
  expect_no_token(out)
})

test_that("the sitrep lists the credential store once", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  reads <- 0L
  local_mocked_bindings(keyring_list = function() {
    reads <<- reads + 1L
    "default"
  })

  report <- suppressMessages(jatos_credentials_sitrep())

  expect_equal(report$auth_from, "keyring")
  expect_equal(reads, 1L)
})

test_that("the sitrep reports a credential store it cannot read", {
  local_no_credentials()
  local_locked_keyring(list(default = fake_token))
  local_mocked_bindings(keyring_list = function() stop("keyring is locked"))

  out <- cli::ansi_strip(capture_messages(jatos_credentials_sitrep()))

  expect_match(message_text(out), "could not be read")
  expect_match(message_text(out), "locked")
})

test_that("the sitrep says when no persistent store exists", {
  local_no_credentials()
  local_unusable_keyring()

  out <- cli::ansi_strip(capture_messages(jatos_credentials_sitrep()))
  text <- message_text(out)

  expect_match(text, "not persistent")
  expect_match(text, "backend_file$new()$keyring_create(\"system\")", fixed = TRUE)
})
