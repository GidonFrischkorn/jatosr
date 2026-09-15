# Profiles: the name of one host-and-token pair, the two environment
# variable names it maps to, and the listing of every profile this machine
# knows. Nothing here reads a secret.
#
# A profile is a suffix on the two variable names: `JATOS_HOST_<PROFILE>` and
# `JATOS_TOKEN_<PROFILE>`. The reserved name "default" is the unsuffixed pair,
# so a single-account user never sees a suffix. Which profile a function uses
# when none is passed is decided by its default argument,
# `Sys.getenv("JATOS_PROFILE", "default")`, so the fallback is visible in the
# signature and testable through the environment.
#
# Convention shared with future sibling packages: `<PLATFORM>_HOST` and
# `<PLATFORM>_TOKEN`. Nothing in this file is JATOS-specific except the
# variable names passed in by the callers.

profile_pattern <- "^[A-Za-z][A-Za-z0-9_]*$"

default_profile <- function() {
  or_default_profile(Sys.getenv("JATOS_PROFILE", unset = ""))
}

# `JATOS_PROFILE=` (set but empty, as an .Renviron line can leave it) means
# the default profile, the same as unset. The one place that maps it.
or_default_profile <- function(profile) {
  if (rlang::is_string(profile) && !nzchar(profile)) "default" else profile
}

# Returns the profile name in lower case; names are case-insensitive because
# environment variable names are case-insensitive on Windows.
check_profile <- function(profile,
                          arg = rlang::caller_arg(profile),
                          call = rlang::caller_env()) {
  profile <- or_default_profile(profile)
  check_string(profile, arg = arg, call = call)
  if (grepl("^https?://", profile)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} looks like a URL: {.val {profile}}.",
        "i" = "Pass the server as {.code host = } and use {.arg {arg}} for a name listed by {.fn jatos_list_profiles}."
      ),
      call = call,
      class = "jatosr_bad_profile"
    )
  }
  if (!grepl(profile_pattern, profile)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must start with a letter and contain only letters, digits and underscores, got {.val {profile}}.",
        "i" = "The name becomes part of an environment variable name, {.envvar JATOS_TOKEN_<PROFILE>}."
      ),
      call = call,
      class = "jatosr_bad_profile"
    )
  }
  invisible(tolower(profile))
}

credential_var <- function(which = c("HOST", "TOKEN"), profile = "default") {
  which <- rlang::arg_match(which)
  if (identical(tolower(profile), "default")) {
    return(paste0("JATOS_", which))
  }
  paste0("JATOS_", which, "_", toupper(profile))
}

# --- helpers for users ---------------------------------------------------------

#' Are JATOS credentials available?
#'
#' Checks whether a host and a token can be found for a credential profile:
#' the host from `JATOS_HOST` (or `JATOS_HOST_<PROFILE>`) or the profile
#' configuration file, the token from `JATOS_TOKEN` (or
#' `JATOS_TOKEN_<PROFILE>`) or the system credential store. No secret is
#' retrieved and no request is made; use [jatos_token_info()] to find out
#' whether the token also works.
#'
#' @inheritParams jatos_connection
#' @return `TRUE` or `FALSE`.
#' @export
#' @examples
#' \dontrun{
#' # lists the machine's credential store
#' jatos_has_credentials()
#' jatos_has_credentials("lab_admin")
#' }
jatos_has_credentials <- function(profile = Sys.getenv("JATOS_PROFILE", "default")) {
  profile <- check_profile(profile)
  status <- keyring_status()
  has_host <- nzchar(Sys.getenv(credential_var("HOST", profile), unset = "")) ||
    !is.null(config_host(profile))
  has_token <- nzchar(Sys.getenv(credential_var("TOKEN", profile), unset = "")) ||
    (status$usable && !is.null(keyring_has(profile, status = status)))
  has_host && has_token
}

#' List the credential profiles on this machine
#'
#' A profile is a named pair of a host and a token, so that one machine can
#' hold credentials for several accounts on one server, or for several
#' servers, side by side. The profile `"default"` is the one used when none
#' is named.
#'
#' Profiles are collected from all three places the package reads: the
#' environment variables of this session (`JATOS_HOST_<PROFILE>` and
#' `JATOS_TOKEN_<PROFILE>`, or the unsuffixed pair for `"default"`), the
#' profile configuration file written by [jatos_set_credentials()], and the
#' system credential store. It makes no request, retrieves no secret, and
#' never returns a token — the credential store is asked for its entry names
#' only, so nothing is unlocked.
#'
#' @return A tibble with one row per profile: `profile` (lower-case name),
#'   `host` (`NA` when no host is known), `has_token`, `active` (`TRUE` for
#'   the profile that [jatos_connection()] uses when called without a
#'   `profile` argument, from `JATOS_PROFILE` or `"default"`), and
#'   `auth_from`, which of `"env"` or `"keyring"` a token would be taken
#'   from. The default profile comes first, the rest are sorted by name.
#'   Zero rows when nothing is set.
#'
#'   `active` is `FALSE` in *every* row on a machine that holds named
#'   profiles only: there is no unsuffixed `JATOS_HOST` / `JATOS_TOKEN`
#'   pair and `JATOS_PROFILE` is unset, so nothing is selected and a bare
#'   `jatos_connection()` has no credentials to read. That is a valid
#'   setup, not a fault; name a profile with `jatos_connection("<name>")`,
#'   or set `JATOS_PROFILE` to make one of them active.
#' @export
#' @examples
#' \dontrun{
#' # lists the machine's credential store
#' jatos_list_profiles()
#' }
jatos_list_profiles <- function() {
  list_profiles(keyring_status())
}

# The body of jatos_list_profiles(), taking the store status from the caller:
# the resolvers already hold one when they name the configured profiles in
# an abort, and reading the store again there put a second key_list() on
# every failed resolution.
list_profiles <- function(status) {
  env <- env_profiles()
  config <- config_read()
  stored <- if (status$usable) tolower(status$entries) else character()

  profiles <- unique(c(env$profile, names(config), stored))
  profiles <- c(intersect("default", profiles), sort(setdiff(profiles, "default")))

  env_host <- function(name) env$host[match(name, env$profile)]
  env_token <- function(name) !is.na(env$token[match(name, env$profile)])

  hosts <- purrr::map_chr(profiles, function(name) {
    from_env <- env_host(name)
    if (!is.na(from_env)) {
      return(from_env)
    }
    config[[name]]$host %||% NA_character_
  })
  in_env <- purrr::map_lgl(profiles, env_token)
  in_store <- profiles %in% stored
  # Assigned, not ifelse()d: ifelse() on zero rows returns logical(0), and
  # the column must be character whether or not there is a profile.
  auth_from <- rep(NA_character_, length(profiles))
  auth_from[in_store] <- "keyring"
  auth_from[in_env] <- "env"

  tibble::tibble(
    profile = profiles,
    host = hosts,
    has_token = in_env | in_store,
    active = profiles == tolower(default_profile()),
    auth_from = auth_from
  )
}

# The credential variables present in this session, one row per profile.
# What .Renviron defined at startup and what the platform injected are both
# here; this is the tier the package reads and never writes.
env_profiles <- function() {
  env <- Sys.getenv()
  env <- env[nzchar(env)]
  vars <- toupper(names(env))
  hits <- grepl("^JATOS_(HOST|TOKEN)(_[A-Z0-9_]+)?$", vars)
  vars <- vars[hits]
  values <- unname(env[hits])
  kind <- sub("^JATOS_(HOST|TOKEN).*$", "\\1", vars)
  suffix <- sub("^JATOS_(HOST|TOKEN)_?", "", vars)
  # Only suffixes that are profile names: a JATOS_TOKEN_1ABC is a variable
  # this package never reads, and listing it made usable_profiles() suggest
  # a name that check_profile() then rejected.
  named <- !nzchar(suffix) | grepl(profile_pattern, suffix)
  values <- values[named]
  kind <- kind[named]
  suffix <- suffix[named]
  profile <- ifelse(nzchar(suffix), tolower(suffix), "default")

  profiles <- unique(profile)
  lookup <- function(name, what) {
    idx <- which(profile == name & kind == what)
    if (length(idx) == 0) NA_character_ else values[[idx[[1]]]]
  }
  list(
    profile = profiles,
    host = purrr::map_chr(profiles, lookup, what = "HOST"),
    token = purrr::map_chr(profiles, lookup, what = "TOKEN")
  )
}

# The profiles that could serve a connection: both variables set, minus the
# one that has just failed to resolve. Used by read_credential() to name
# them instead of pointing at a default profile that does not exist.
usable_profiles <- function(exclude = NULL, status = keyring_status()) {
  profiles <- list_profiles(status)
  usable <- profiles$profile[!is.na(profiles$host) & profiles$has_token]
  setdiff(usable, tolower(exclude %||% character()))
}

# What to tell a user whose profile did not resolve: the profile that
# JATOS_PROFILE selects, the profiles that are configured, and the setter
# call for this one. Shared by the host abort in read_credential() and the
# token abort in abort_no_token(), which differ only in their first line and
# in what follows the setter.
profile_hints <- function(profile, status = keyring_status()) {
  setter <- if (identical(profile, "default")) {
    "jatosr::jatos_set_credentials()"
  } else {
    sprintf('jatosr::jatos_set_credentials(profile = "%s")', profile)
  }
  selected <- if (nzchar(Sys.getenv("JATOS_PROFILE", unset = ""))) {
    c("i" = cli::format_inline(
      "{.envvar JATOS_PROFILE} selects the profile {.val {profile}}; see {.fn jatos_list_profiles}."
    ))
  }
  # A machine that deliberately holds two named profiles and no default pair
  # (a setup this package recommends) used to get two hints that both said
  # to create a default profile. Name the profiles that do exist first.
  others <- usable_profiles(exclude = profile, status = status)
  configured <- if (length(others) > 0) {
    c("i" = cli::format_inline(
      '{cli::qty(length(others))}Configured profile{?s}: {.val {others}}; select one with {.code jatos_connection("<name>")} or {.envvar JATOS_PROFILE}.'
    ))
  }
  list(setter = setter, bullets = c(selected, configured))
}
