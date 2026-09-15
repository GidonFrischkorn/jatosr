#' Connect to a JATOS server
#'
#' Builds the connection object that every API function takes as its `conn`
#' argument. With no arguments, the host and token of the active credential
#' profile are looked up: the host from `JATOS_HOST` (or
#' `JATOS_HOST_<PROFILE>`) or the profile configuration file, the token from
#' `JATOS_TOKEN` (or `JATOS_TOKEN_<PROFILE>`) or the system credential store
#' (see [jatos_set_credentials()] and [jatos_credentials_sitrep()]). A named
#' profile is how you keep tokens for several accounts on one server, or for
#' several servers, side by side. Explicit `host` and `token` arguments take
#' precedence over both.
#'
#' Everything is resolved here rather than at the first request, so a missing
#' or unreadable token is an error where the connection is built, and a
#' credential store that has to be unlocked asks once. When
#' [jatos_token_info()] has seen that the token expires within seven days,
#' the next `jatos_connection()` warns once per session.
#'
#' @section The connection holds no token:
#' `conn` carries the profile name, the host and an opaque session id — not
#' the secret. The token itself stays in this R session, in an environment
#' the package owns, and is fetched only inside the request builder. So
#' `saveRDS(conn)`, `save.image()`, an `.RData` written at the end of a
#' session, a knitr cache or a targets store may hold a connection without
#' writing a token to disk. A connection read back in another session has a
#' dead id and resolves its profile afresh, so it keeps working if that
#' profile is still stored.
#'
#' This is a guarantee about this package's own objects. A token you assign
#' to a variable yourself, or pass as `token =` and keep, is an ordinary
#' string and is saved like one.
#'
#' @param profile Name of the credential profile, as given to
#'   [jatos_set_credentials()]. Defaults to the `JATOS_PROFILE` environment
#'   variable, or `"default"` when that is unset, so a single-account setup
#'   never passes it. Case-insensitive.
#' @param host Base URL of the JATOS server, e.g. `"https://jatos.example.org"`.
#'   Defaults to the profile's host.
#' @param token Personal access token. Defaults to the profile's stored
#'   token. Kept for this connection and for this session only.
#'
#' @return An object of class `jatos_connection` with elements `profile`,
#'   `host`, `api_url`, `id`, `auth_from` and `user_agent`. There is no
#'   `token` element.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' conn <- jatos_connection()
#' conn
#' admin <- jatos_connection("lab_admin")
#' jatos_studies(conn = admin)
#' }
jatos_connection <- function(profile = Sys.getenv("JATOS_PROFILE", "default"),
                             host = NULL,
                             token = NULL) {
  profile <- check_profile(profile)
  explicit_host <- !is.null(host)
  host <- normalise_host(jatos_host(profile, host))
  # Resolved here rather than at the first request, so that a missing token
  # is an error where the connection is built, the unlock prompt of a
  # credential store happens once and at a predictable moment, and the two
  # warnings below have something to look at.
  resolved <- resolve_token(profile, token)
  warn_if_unusual_token(reveal_secret(resolved$secret), once = TRUE)
  if (explicit_host && !identical(resolved$source, "argument")) {
    warn_host_mismatch(profile, host)
  }
  conn <- new_connection(
    host = host,
    profile = profile,
    token = if (identical(resolved$source, "argument")) reveal_secret(resolved$secret),
    auth_from = resolved$source
  )
  warn_expiring_token(conn)
  conn
}

# No RNG: drawing from the random stream inside a constructor would move a
# user's seed and make an analysis that builds a connection irreproducible.
new_connection_id <- function() {
  the$conn_counter <- the$conn_counter + 1L
  sprintf("cn_%d_%d", Sys.getpid(), the$conn_counter)
}

# The connection carries `id`, not the token. An explicit `token =` argument
# belongs to this one connection rather than to the profile, so it goes in a
# session-only store under that id; everything else is resolved from the
# profile when a request needs it. What a serialised connection holds is the
# id, which means nothing in any other session.
new_connection <- function(host,
                           profile = "default",
                           token = NULL,
                           auth_from = "keyring",
                           class = "jatos_connection") {
  id <- new_connection_id()
  if (!is.null(token)) {
    the$conn_tokens[[id]] <- new_secret(token)
  }
  structure(
    list(
      profile = profile,
      host = host,
      api_url = paste0(host, "/jatos/api/v1"),
      id = id,
      auth_from = auth_from,
      user_agent = jatos_user_agent()
    ),
    class = class
  )
}

# An explicit `host` with the profile's own token: the token of one server is
# about to be sent to another. That is right for a mirror or a renamed
# server and a leak for anything else, so it is said, once per profile and
# host in a session. Nothing to compare against when the profile has no host.
warn_host_mismatch <- function(profile, host, call = rlang::caller_env()) {
  configured <- configured_host(profile)
  if (is.na(configured) || identical(configured, host)) {
    return(invisible(NULL))
  }
  key <- paste(profile, host)
  if (key %in% the$host_warned) {
    return(invisible(NULL))
  }
  the$host_warned <- c(the$host_warned, key)
  cli::cli_warn(
    c(
      "{.arg host} {.url {host}} is not the host of profile {.val {profile}}, which is {.url {configured}}.",
      "i" = "The profile's token will be sent to {.url {host}}. If that server is a different one, pass its {.arg token} as well, or store it as a profile of its own with {.fn jatos_set_credentials}."
    ),
    call = call
  )
  invisible(NULL)
}

# The profile's host as jatos_connection() would normalise it, or NA when
# none is configured or the configured value is not a URL.
configured_host <- function(profile) {
  raw <- jatos_host(profile, missing = "na")
  if (is.na(raw)) {
    return(NA_character_)
  }
  tryCatch(
    suppressWarnings(normalise_host(raw)),
    error = function(cnd) NA_character_
  )
}

jatos_user_agent <- function() {
  paste0("jatosr/", utils::packageVersion("jatosr"))
}

normalise_host <- function(host, call = rlang::caller_env()) {
  check_string(host, arg = "host", call = call)
  host <- trimws(host)
  host <- sub("/+$", "", host)
  host <- sub("/jatos/api/v1(/.*)?$", "", host)
  host <- sub("/+$", "", host)
  if (!grepl("^https?://[^/]+", host)) {
    cli::cli_abort(
      "{.arg host} must be a URL starting with {.code https://}, got {.val {host}}.",
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  if (startsWith(host, "http://") && !grepl("^http://(localhost|127\\.0\\.0\\.1)", host)) {
    cli::cli_warn(
      c(
        "{.arg host} uses plain {.code http://}; the token will travel unencrypted.",
        "i" = "Use {.code https://} unless the server is on your own machine."
      ),
      call = call
    )
  }
  host
}

is_jatos_connection <- function(x) {
  inherits(x, "jatos_connection")
}

check_connection <- function(conn, call = rlang::caller_env()) {
  if (!is_jatos_connection(conn)) {
    cli::cli_abort(
      "{.arg conn} must be a {.cls jatos_connection}, created with {.fn jatos_connection}.",
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  invisible(conn)
}

#' @export
format.jatos_connection <- function(x, ...) {
  c(
    "<jatos_connection>",
    paste0("  profile: ", x$profile),
    paste0("  host:    ", x$host),
    paste0("  api:     ", x$api_url),
    paste0("  token:   ", token_source_label(x))
  )
}

# There is no token to print any more, so the line says where the one this
# connection will use comes from. That is the question a user printing a
# connection is actually asking.
token_source_label <- function(x) {
  switch(x$auth_from,
    argument = "supplied as an argument",
    env = paste0("from ", credential_var("TOKEN", x$profile)),
    keyring = "from the credential store",
    prompt = "entered in this session",
    "not resolved"
  )
}

#' @export
print.jatos_connection <- function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}
