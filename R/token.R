#' Check the token and show its metadata
#'
#' Calls `GET /admin/token`, which any token may use to inspect itself. This
#' is the cheapest way to verify that the host and token of a profile work:
#' a wrong token gives a 401 error, a wrong host a 404 or an HTML page.
#'
#' @param conn A [jatos_connection()].
#'
#' @return A one-row tibble with `token_id`, `name`, `username`, `user_id`,
#'   `created`, `expires` (both POSIXct, UTC; `expires` is `NA` for tokens
#'   without expiry), `expired`, `active`, and `roles` (list column).
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_token_info()
#' }
jatos_token_info <- function(conn = jatos_connection()) {
  body <- jatos_req(conn, "admin/token") |> perform_json()
  info <- parse_token_info(body$data)
  remember_token_expiry(conn, info$expires, info$expired)
  info
}

# Session state, all of it, in one place so that it is visible what outlives
# a call and what the test helpers have to reset.
#
# `token_expiry` and `expiry_warned`: the expiry and the server's own
# `isExpired` flag that jatos_token_info() saw per token, and whether
# jatos_connection() has warned about it. Keyed by a hash of the token,
# never by the token.
#
# `token_cache` and `conn_tokens`: the tokens themselves, as masked secrets,
# for the life of the session and no longer. Nothing here is ever written to
# disk; this environment is what the connection object used to be.
#
# `env_token_checked`, `config_warned`, `host_warned` and `unusual_warned`:
# the once-per-session warnings, by what they have warned about. A warning
# that would otherwise fire on every jatos_connection(), which is the default
# argument of nearly every export, fires once here.
the <- new.env(parent = emptyenv())
the$token_expiry <- list()
the$expiry_warned <- character()
the$token_cache <- list()
the$conn_tokens <- list()
the$env_token_checked <- character()
the$config_warned <- character()
the$host_warned <- character()
the$unusual_warned <- character()
the$conn_counter <- 0L

token_key <- function(conn) {
  rlang::hash(reveal_secret(conn_token(conn)))
}

remember_token_expiry <- function(conn, expires, expired = NA) {
  the$token_expiry[[token_key(conn)]] <- list(expires = expires, expired = expired)
  invisible(NULL)
}

# One warning per token and session when the last token check saw an
# expiry within seven days (or in the past), or the server's own `isExpired`
# flag set without a date it could be checked against.
warn_expiring_token <- function(conn, call = rlang::caller_env()) {
  key <- token_key(conn)
  seen <- the$token_expiry[[key]]
  if (is.null(seen) || key %in% the$expiry_warned) {
    return(invisible(NULL))
  }
  if (is.na(seen$expires)) {
    # No date to reason about. The flag is the server's direct answer, and
    # it used to be skipped here along with the date it did not have.
    if (!isTRUE(seen$expired)) {
      return(invisible(NULL))
    }
    the$expiry_warned <- c(the$expiry_warned, key)
    cli::cli_warn(
      c(
        "The server reports the token of profile {.val {conn$profile}} as expired.",
        "i" = "Create a new token in JATOS and store it with {.fn jatos_set_credentials}."
      ),
      call = call
    )
    return(invisible(NULL))
  }
  expires <- seen$expires
  days <- as.numeric(difftime(expires, Sys.time(), units = "days"))
  if (days > 7) {
    return(invisible(NULL))
  }
  # A date in the past on a token the server itself reports as not expired
  # is a contradiction, and the server's flag is the more direct answer:
  # some JATOS versions spell "never expires" as a sentinel date rather
  # than as an absent field (apiVersion 1.0.1 sends `expirationDate` 0).
  # parse_token_info() reads the sentinels it knows; this keeps the next
  # one from telling a user that a working token expired.
  if (days < 0 && isFALSE(seen$expired)) {
    return(invisible(NULL))
  }
  the$expiry_warned <- c(the$expiry_warned, key)
  stamp <- format(expires, "%Y-%m-%d %H:%M", tz = "UTC")
  when <- if (days < 0) "expired on {stamp} UTC" else "expires on {stamp} UTC ({round(days, 1)} day{?s} from now)"
  cli::cli_warn(
    c(
      paste0("The token of profile {.val {conn$profile}} ", when, "."),
      "i" = "Create a new token in JATOS and store it with {.fn jatos_set_credentials}."
    ),
    call = call
  )
}

parse_token_info <- function(x) {
  expires_ms <- purrr::pluck(x, "expirationDate")
  expires_after <- purrr::pluck(x, "expiresAfter")
  # "No expiry" is spelled three ways across JATOS versions: the field
  # absent, `expiresAfter` 0 (the OpenAPI spec), or `expirationDate` 0
  # (apiVersion 1.0.1, which sends no `expiresAfter` at all). A zero
  # epoch millisecond is 1970-01-01 and never a real expiry, so it is
  # read as the sentinel it is rather than as a date in the past.
  no_expiry <- is.null(expires_ms) ||
    isTRUE(as.numeric(expires_ms) <= 0) ||
    (!is.null(expires_after) && isTRUE(as.numeric(expires_after) <= 0))
  tibble::tibble(
    token_id = pluck_int(x, "id"),
    name = pluck_chr(x, "name"),
    username = pluck_chr(x, "username"),
    user_id = pluck_int(x, "userId"),
    created = pluck_time(x, "creationDate"),
    expires = if (no_expiry) as.POSIXct(NA, tz = "UTC") else pluck_time(x, "expirationDate"),
    expired = pluck_lgl(x, "isExpired"),
    active = pluck_lgl(x, "active"),
    roles = list(as.character(unlist(purrr::pluck(x, "roles"))))
  )
}
