# The operating system credential store, reached through the keyring package.
#
# Everything that calls `keyring::` lives in the five wrappers at the top of
# this file, one statement each. All of the decisions sit below them, where
# they are ordinary R code that the tests exercise directly. The split has a
# purpose beyond tidiness: the wrappers are the only place a wrong service
# name or a wrong `username =` argument can hide. The tests run those five
# against keyring's `env` backend, and data-raw/check-keyring.R runs them
# against the real store of an operating system.
#
# The keyring username is the profile name, so profiles and keyring entries
# map one to one and `keyring::key_list()` enumerates them without unlocking
# a single item.

keyring_service <- "jatosr"

# --- the tripwire --------------------------------------------------------------
#
# During a test run the only backend a `keyring::` call may reach is `env`,
# which keeps its values in environment variables for the life of the
# session. Any other backend means a test lost its sandbox and is one step
# away from writing into the developer's login keychain, so fail loudly
# rather than quietly succeed. `JATOSR_REAL_KEYRING=true` switches the
# tripwire off; data-raw/check-keyring.R sets it, and setup.R clears it before
# a test run.
#
# `TESTTHAT` is set by testthat and is empty in a user's session, so in
# production this is one `Sys.getenv()` and a return.
keyring_guard <- function(call = rlang::caller_env()) {
  if (!identical(Sys.getenv("TESTTHAT"), "true")) {
    return(invisible(NULL))
  }
  if (identical(Sys.getenv("JATOSR_REAL_KEYRING"), "true")) {
    return(invisible(NULL))
  }
  backend <- tryCatch(keyring::default_backend()$name, error = function(cnd) NA_character_)
  if (identical(backend, "env")) {
    return(invisible(NULL))
  }
  cli::cli_abort(
    c(
      "A test reached the {.val {backend}} keyring backend.",
      "i" = "Tests must call {.fn local_fake_keyring} or {.fn local_no_credentials} first."
    ),
    call = call,
    class = "jatosr_keyring_guard",
    .internal = TRUE
  )
}

# --- the wrappers --------------------------------------------------------------

keyring_backend <- function() {
  keyring_guard()
  keyring::default_backend()$name
}

keyring_get <- function(profile) {
  keyring_guard()
  keyring::key_get(keyring_service, username = profile)
}

keyring_set <- function(profile, token) {
  keyring_guard()
  keyring::key_set_with_value(keyring_service, username = profile, password = token)
}

keyring_delete <- function(profile) {
  keyring_guard()
  keyring::key_delete(keyring_service, username = profile)
}

keyring_list <- function() {
  keyring_guard()
  keyring::key_list(service = keyring_service)$username
}

# --- what the rest of the package asks ----------------------------------------

# The state of the credential store in one call, for the resolver, the setter
# and jatos_credentials_sitrep(). `readable` and an empty `entries` are
# different answers: nothing stored falls through to the prompt, a store that
# cannot be read at all is worth saying out loud.
keyring_status <- function() {
  backend <- tryCatch(keyring_backend(), error = function(cnd) {
    rethrow_keyring_guard(cnd)
    NA_character_
  })
  entries <- tryCatch(keyring_list(), error = function(cnd) {
    rethrow_keyring_guard(cnd)
    structure(NA_character_, reason = conditionMessage(cnd))
  })
  readable <- !anyNA(entries)
  list(
    backend = backend,
    # `env` holds its values for this session only. Storing there looks like
    # it worked and is gone at the next start of R, so the setter refuses it
    # and the resolver skips it (vignette("credentials"), "Headless machines").
    usable = !is.na(backend) && !identical(backend, "env"),
    readable = readable,
    entries = if (readable) entries else character(),
    reason = if (readable) NA_character_ else attr(entries, "reason") %||% NA_character_
  )
}

# The guard is an internal assertion, not a condition to be handled. Any
# tryCatch() around a wrapper has to let it through or the tripwire is dead.
rethrow_keyring_guard <- function(cnd) {
  if (inherits(cnd, "jatosr_keyring_guard")) {
    rlang::cnd_signal(cnd)
  }
  invisible(NULL)
}

# Every spelling under which the store holds this profile. No secret is
# retrieved: key_list() returns usernames, so no item is unlocked and no
# dialog can appear.
#
# Profiles are case-insensitive, credential stores are not: key_get(),
# key_set_with_value() and key_delete() take the username verbatim. So the
# match is made here, once, and the callers pass the returned names on.
# Matching case-insensitively and then passing the profile name to the
# wrappers meant that a hand-made `Lab_Admin` entry was listed as usable,
# could not be read ("unlock the store"), was shadowed rather than replaced
# by the setter, and survived jatos_remove_credentials() saying "Deleted".
keyring_matches <- function(profile, status = keyring_status()) {
  entries <- status$entries
  entries[tolower(entries) == tolower(profile)]
}

# The one name to read or write under, or NULL when the store has none. When
# the store holds more than one spelling: the exact one asked for, else the
# lower-case one the setter writes, else the first in sorted order, so the
# answer does not depend on the order key_list() happens to return.
keyring_has <- function(profile, status = keyring_status()) {
  hits <- keyring_matches(profile, status = status)
  if (length(hits) == 0) {
    return(NULL)
  }
  if (profile %in% hits) {
    return(profile)
  }
  if (tolower(profile) %in% hits) {
    return(tolower(profile))
  }
  sort(hits)[[1]]
}

# Read one token. Reaching here means keyring_has() already said the entry is
# there, so a failure is a locked or broken store and not a miss; saying
# "run jatos_set_credentials()" at this point would send the user to store a
# token they have already stored.
keyring_token <- function(profile, call = rlang::caller_env()) {
  tryCatch(
    new_secret(keyring_get(profile), call = call),
    error = function(cnd) {
      rethrow_keyring_guard(cnd)
      # As in report_token_check(): the text comes from another system and
      # may hold braces, so it is interpolated as a value, never rendered as
      # a cli template.
      reason <- conditionMessage(cnd)
      backend <- keyring_backend()
      cli::cli_abort(
        c(
          "Could not read the token of profile {.val {profile}} from the {.val {backend}} credential store.",
          "x" = "{reason}",
          "i" = "Unlock the credential store and try again, or store the token anew with {.run jatosr::jatos_set_credentials()}."
        ),
        call = call,
        class = "jatosr_keyring_unreadable"
      )
    }
  )
}
