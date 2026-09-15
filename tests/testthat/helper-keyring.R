# A credential store for tests that is the real thing.
#
# keyring's `env` backend keeps its values in environment variables named
# "<service>:<username>" and implements the whole interface the package uses
# — set, get, list, delete — so the tests run through the actual
# `keyring::key_*()` calls rather than around them. That matters: mocking the
# five wrappers in R/keyring.R everywhere would leave a wrong service name or
# a wrong `username =` argument untested, and this package has been bitten
# before by a helper the tests mocked and therefore never ran.
#
# The one thing the env backend cannot be is persistent, and the package
# treats "env" as the signal that there is nowhere durable to store a token.
# So the backend *name* is mocked to something else while the calls stay
# real. keyring_guard() reads the true backend, not the mocked name, so the
# tripwire against the developer's login keychain stays armed.

# Every environment variable the env backend owns for our service.
keyring_env_vars <- function() {
  grep(
    paste0("^", keyring_service, ":"),
    names(Sys.getenv()),
    value = TRUE
  )
}

local_fake_keyring <- function(entries = NULL,
                               backend = "fake",
                               .env = parent.frame()) {
  withr::local_options(list(keyring_backend = "env"), .local_envir = .env)

  # Sys.getenv() with a zero-length argument returns the whole environment,
  # so an empty store has to be handled before the call, not after it.
  # Sys.getenv() drops the names when asked for exactly one variable, so
  # they are put back rather than assumed.
  owned <- keyring_env_vars()
  before <- if (length(owned) > 0) {
    as.list(rlang::set_names(Sys.getenv(owned), owned))
  } else {
    list()
  }
  withr::defer(
    {
      Sys.unsetenv(keyring_env_vars())
      if (length(before) > 0) {
        do.call(Sys.setenv, before)
      }
    },
    envir = .env
  )
  if (length(owned) > 0) {
    Sys.unsetenv(owned)
  }

  testthat::local_mocked_bindings(
    keyring_backend = function() backend,
    .env = .env
  )

  for (profile in names(entries)) {
    keyring_set(profile, entries[[profile]])
  }
  invisible(NULL)
}

# No durable store: the resolver must skip the keyring tier and the setter
# must refuse rather than appear to store something that vanishes.
local_unusable_keyring <- function(entries = NULL, .env = parent.frame()) {
  local_fake_keyring(entries = entries, backend = "env", .env = .env)
}

# The entry is there but cannot be read — a locked keychain, or one whose
# access the user denied. The distinction from "no entry" is the whole point
# of the keyring_has() / keyring_token() split: this must say "unlock", not
# "store a token you have already stored".
local_locked_keyring <- function(entries = NULL, .env = parent.frame()) {
  local_fake_keyring(entries = entries, .env = .env)
  testthat::local_mocked_bindings(
    keyring_get = function(profile) {
      stop("User interaction is not allowed (-25308).")
    },
    .env = .env
  )
}

# The profile configuration file, in a temporary directory. Paired with
# local_fake_keyring() by local_no_credentials(), so that no test reads or
# writes the developer's own R_user_dir().
local_config_sandbox <- function(.env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = .env)
  withr::local_envvar(c(JATOSR_CONFIG_DIR = dir), .local_envir = .env)
  dir
}
