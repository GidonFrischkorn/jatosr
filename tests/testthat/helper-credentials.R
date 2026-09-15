# Fake credentials for tests. Every token-like string in the repository is
# defined here: `fake_token` is the one the mocked server accepts, the
# others stand for a second profile, an old .Renviron line and so on where
# a test needs a distinguishable value. `expect_no_token()` asserts that
# none of them appears in a print, message or error path.
fake_host <- "https://jatos.example.org"
fake_token <- "jap_test000"
fake_tokens <- c(
  default = fake_token,
  admin = "jap_admin0",
  other = "jap_other0",
  explicit = "jap_explicit",
  zebra = "jap_zebra00",
  orphan = "jap_orphan0",
  old = "jap_old0000",
  stale = "jap_stale00",
  # the token a hypothetical server echoes back into an error body. The
  # error path now passes the server's own text through, so this one exists
  # to be scrubbed out of it again (see `scrub_secrets()` in R/request.R
  # and the test in test-legacy-server.R)
  echoed = "jap_echoed0",
  # a token that is deliberately not one of this connection's: the scrubber
  # must redact a token-shaped string whoever it belongs to
  foreign = "jap_someoneelses1",
  # tokens without the jap_ prefix, for the warning paths; `short` has
  # three characters and a tilde, so that it cannot occur inside a random
  # temporary path (a plain "abc" did, once, under R CMD check)
  plain = "abcdef",
  name_not_token = "notatoken",
  short = "q~z"
)

# The tokens long enough for a match in a binary file to mean something.
#
# `expect_no_token_in_file()` in test-canary.R greps whole files, and an rds
# is a compressed byte stream: any three-byte sequence turns up in one of
# those by chance about once in seven hundred files of the size this package
# writes (2^-24 per position). `short` is three bytes, so it produced a
# failure on CI that no leak explained - the uncompressed serialisation held
# neither it nor any token. Six bytes is 2^-48 per position, which never
# happens. The text-level `expect_no_token()` keeps the whole list; there a
# short match is a real find.
scannable_tokens <- fake_tokens[nchar(fake_tokens) >= 6]

# `profile = "default"` sets JATOS_HOST / JATOS_TOKEN; any other name sets the
# suffixed pair. JATOS_PROFILE is cleared so the active profile is "default"
# unless a test sets it. The session record of token expiries is emptied
# for the test, so a token check in one test never warns in another.
# Returns the .Renviron sandbox directory (see local_renviron_sandbox()).
local_fake_credentials <- function(host = fake_host,
                                   token = fake_token,
                                   profile = "default",
                                   .env = parent.frame()) {
  vars <- rlang::set_names(
    c(host, token, NA),
    c(credential_var("HOST", profile), credential_var("TOKEN", profile), "JATOS_PROFILE")
  )
  withr::local_envvar(vars, .local_envir = .env)
  # The credential store, the profile configuration and the two .Renviron
  # locations are sandboxed here too, not only in local_no_credentials():
  # anything that lists profiles consults every place the package reads, so
  # a test that set up only the environment would read the developer's own
  # keychain, or print a line of the developer's own ~/.Renviron.
  local_config_sandbox(.env = .env)
  local_fake_keyring(.env = .env)
  local_token_state(.env = .env)
  invisible(local_renviron_sandbox(.env = .env))
}

# No credentials anywhere: not in the environment, not in the credential
# store, not in the profile configuration, not in an .Renviron.
#
# Every JATOS_* variable is unset, not just the default pair: the developer's
# own ~/.Renviron is read when the test session starts, and a real named
# profile there would otherwise show up in `jatos_list_profiles()`. The same
# reasoning covers the other stores, which is why the empty keyring, the
# empty configuration directory and the empty .Renviron sandbox are part of
# this helper rather than something each test remembers to add. Returns the
# sandbox directory, so a test can write a `user.Renviron` into it.
local_no_credentials <- function(.env = parent.frame()) {
  present <- grep("^JATOS_", names(Sys.getenv()), value = TRUE, ignore.case = TRUE)
  vars <- union(c("JATOS_HOST", "JATOS_TOKEN", "JATOS_PROFILE"), present)
  withr::local_envvar(
    rlang::set_names(rep(NA_character_, length(vars)), vars),
    .local_envir = .env
  )
  local_config_sandbox(.env = .env)
  local_fake_keyring(.env = .env)
  local_token_state(.env = .env)
  invisible(local_renviron_sandbox(.env = .env))
}

# Every piece of session state, saved and emptied for the test.
#
# The token cache belongs here as much as the expiry record does: a token
# cached by one test would otherwise satisfy the next test's resolver and the
# tier-order tests would pass without ever reaching the tier they name.
local_token_state <- function(.env = parent.frame()) {
  slots <- c(
    "token_expiry", "expiry_warned",
    "token_cache", "conn_tokens",
    "env_token_checked", "config_warned", "host_warned", "unusual_warned"
  )
  old <- rlang::set_names(lapply(slots, function(slot) the[[slot]]), slots)
  the$token_expiry <- list()
  the$expiry_warned <- character()
  the$token_cache <- list()
  the$conn_tokens <- list()
  the$env_token_checked <- character()
  the$config_warned <- character()
  the$host_warned <- character()
  the$unusual_warned <- character()
  withr::defer(
    {
      for (slot in slots) {
        the[[slot]] <- old[[slot]]
      }
    },
    envir = .env
  )
}

# Puts both candidate .Renviron files (the user-level one named by
# R_ENVIRON_USER and the project one in the working directory) inside a
# temporary directory, so that a test which looks for credentials in the
# other scope never reads the developer's own ~/.Renviron. Returns the
# directory. Part of local_no_credentials() and local_fake_credentials();
# the working directory moves with it, which is why the paths below are
# pinned while the helpers are sourced.
local_renviron_sandbox <- function(.env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = .env)
  withr::local_dir(dir, .local_envir = .env)
  withr::local_envvar(
    c(R_ENVIRON_USER = file.path(dir, "user.Renviron")),
    .local_envir = .env
  )
  dir
}

# Absolute, taken once while the helpers are sourced: testthat::test_path()
# is relative to the working directory, and every credential test moves that
# into its .Renviron sandbox.
fixtures_dir <- normalizePath(testthat::test_path("fixtures"), mustWork = TRUE)
package_root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)

fixture_path <- function(...) {
  file.path(fixtures_dir, ...)
}

read_fixture_json <- function(name) {
  jsonlite::read_json(fixture_path(name), simplifyVector = FALSE)
}

expect_no_token <- function(x) {
  found <- vapply(fake_tokens, function(token) any(grepl(token, x, fixed = TRUE)), logical(1))
  testthat::expect_equal(names(fake_tokens)[found], character())
}
