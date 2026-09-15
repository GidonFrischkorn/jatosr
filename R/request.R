# The single place that builds HTTP requests. Every endpoint wrapper calls
# jatos_req() and then one of the perform_*() helpers. `accept` is the
# Accept header: JSON by default, `application/zip` for the endpoints that
# answer with a zip (the JATOS API page sends that in its examples), so the
# request asks for what the wrapper will check the answer against.
#
# `retry` is TRUE for every request that only reads (a 429 or 503 is then
# tried again, up to three times) and FALSE for the one that creates
# something on the server: a second POST /studies/{id}/studyCodes after an
# ambiguous answer would create a second set of codes.

jatos_req <- function(conn, path, accept = "application/json", hint = NULL,
                      retry = TRUE, call = rlang::caller_env()) {
  check_connection(conn, call = call)
  req <- httr2::request(conn$api_url) |>
    httr2::req_url_path_append(path) |>
    httr2::req_auth_bearer_token(reveal_secret(conn_token(conn, call = call))) |>
    httr2::req_headers(Accept = accept) |>
    httr2::req_user_agent(conn$user_agent)
  if (retry) {
    req <- httr2::req_retry(req, max_tries = 3)
  }
  # A closure, because req_error() passes the response only: this is the
  # one place where the connection is in scope, so it is the one place
  # from which an error message can name the profile it used.
  httr2::req_error(
    req,
    is_error = jatos_is_error,
    body = function(resp) jatos_error_body(resp, conn = conn, hint = hint)
  )
}

# Repeatable query parameters, e.g. ?batchId=1&batchId=2, skipping NULLs.
jatos_query <- function(req, ...) {
  params <- drop_null(rlang::list2(...))
  if (length(params) == 0) {
    return(req)
  }
  httr2::req_url_query(req, !!!params, .multi = "explode")
}

perform_json <- function(req, call = rlang::caller_env()) {
  resp <- perform(req, call = call)
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

# httr2 streams a real response to `path`. A mocked response
# (httr2::local_mocked_responses()) never touches `path`: the mock handler
# does not see it, and req_perform() returns the mock's raw body as is.
# Writing that body here keeps every download test on the same code path
# as production without a live server.
perform_file <- function(req, path, call = rlang::caller_env()) {
  resp <- perform(req, path = path, call = call)
  if (is.raw(resp$body)) {
    writeBin(resp$body, path)
  }
  invisible(resp)
}

# httr2 errors (HTTP status, transport failures) carry their own classes and
# our redacted bullets, so they pass through untouched. Anything else is
# wrapped with the URL minus its query string. The transport message is
# interpolated as a value, never as a cli template: it may hold braces.
perform <- function(req, path = NULL, call = rlang::caller_env()) {
  tryCatch(
    httr2::req_perform(req, path = path),
    error = function(cnd) {
      if (inherits(cnd, "httr2_error")) {
        rlang::cnd_signal(cnd)
      }
      reason <- conditionMessage(cnd)
      cli::cli_abort(
        c("Request to {.url {redact_url(req$url)}} failed.", "x" = "{reason}"),
        call = call,
        parent = NA
      )
    }
  )
}

redact_url <- function(url) {
  sub("\\?.*$", "?...", url)
}

# JATOS answers auth failures on misconfigured servers with a 200 HTML login
# page, so a successful status is not enough.
jatos_is_error <- function(resp) {
  httr2::resp_is_error(resp) || is_html_response(resp)
}

is_html_response <- function(resp) {
  type <- httr2::resp_content_type(resp)
  !is.na(type) && identical(type, "text/html")
}

# Bullets appended to the httr2 error; must never include the token. httr2
# raises them with rlang::abort(), which renders no cli markup, so the
# static hints are formatted here and the server's text is passed as is.
# `conn` is what the closure in jatos_req() supplies and is what lets the
# error name the profile; it defaults to NULL because a direct call (and a
# test) has no connection to name. `hint` is an endpoint's own sentence for
# the case where this JATOS does not have the route, written as plain text
# with literal backticks (rlang::abort() renders no cli markup).
jatos_error_body <- function(resp, conn = NULL, hint = NULL) {
  if (is_html_response(resp)) {
    return(c(
      "i" = "The server answered with an HTML page instead of JSON.",
      "i" = cli::format_inline("Usually the token was rejected or {.arg host} is not a JATOS server."),
      profile_bullet(conn)
    ))
  }
  message <- server_message(resp, conn)
  reason <- if (!is.null(message)) c("x" = paste0("Server message: ", message))
  c(reason, status_hint(resp, message, hint), profile_bullet(conn))
}

# The server's own sentence, whether it arrives as JSON or as text, scrubbed
# of anything token-shaped. NULL when the body holds no usable message.
server_message <- function(resp, conn = NULL) {
  message <- json_error_message(resp) %||% text_error_message(resp)
  if (is.null(message)) {
    return(NULL)
  }
  scrub_secrets(message, conn)
}

json_error_message <- function(resp) {
  body <- tryCatch(
    httr2::resp_body_json(resp, simplifyVector = FALSE),
    error = function(e) NULL
  )
  message <- purrr::pluck(body, "error", "message") %||%
    purrr::pluck(body, "message") %||%
    purrr::pluck(body, "error")
  if (is.character(message) && length(message) == 1 && nzchar(message)) {
    return(message)
  }
  NULL
}

# A JATOS at apiVersion 1.0.1 answers every error with text/plain, not JSON
# ("Invalid api token", "Couldn't find study with ID 999999"), so without
# this the most specific thing the server said was thrown away. Only a short
# body is taken: anything longer is a page, not a message. text/html is
# diverted by is_html_response() before this is reached, so a login page
# does not arrive here.
text_error_message <- function(resp) {
  type <- httr2::resp_content_type(resp)
  if (is.na(type) || !startsWith(type, "text/")) {
    return(NULL)
  }
  text <- tryCatch(httr2::resp_body_string(resp), error = function(e) NULL)
  if (!is.character(text) || length(text) != 1) {
    return(NULL)
  }
  text <- trimws(gsub("[[:space:]]+", " ", text))
  if (!nzchar(text) || nchar(text) > 500) {
    return(NULL)
  }
  text
}

# Server text ends up in a condition message, and from there in whatever log
# or bug report the user pastes. The package's guarantee that no token
# reaches a message has to be a property of this function rather than of the
# server: a JATOS that echoed the rejected credential into an error body
# ("Invalid api token: jap_...") would otherwise hand it straight on. The
# observed 1.0.1 server does not do that, but that is one server, not the
# protocol. Asserted by expect_no_token() in the test suite.
scrub_secrets <- function(text, conn = NULL) {
  # conn_token_peek(), never conn_token(): this runs inside an error handler,
  # where resolving would reach a locked credential store, or prompt. When it
  # comes back empty the pattern below is still the guarantee.
  secret <- if (!is.null(conn)) conn_token_peek(conn)
  if (!is.null(secret)) {
    token <- reveal_secret(secret)
    if (nzchar(token)) {
      text <- gsub(token, "<token redacted>", text, fixed = TRUE)
    }
  }
  gsub("jap_[A-Za-z0-9_-]+", "<token redacted>", text)
}

# The static hint for a status code. A 404 is two different failures that
# JATOS words differently: a route this server does not have (an endpoint
# added in a later JATOS) against an id that does not exist. Telling the
# first to "check the id" sent a user hunting for a correct id, so the two
# are separated here, and where the server named the problem itself no
# generic hint is added on top.
status_hint <- function(resp, message = NULL, hint = NULL) {
  status <- as.character(httr2::resp_status(resp))
  if (identical(status, "404")) {
    if (is.null(message)) {
      return(c("i" = "Nothing at this path. Check the id and the connection's host."))
    }
    if (grepl("^Requested page .* couldn't be found", message)) {
      return(c(
        "i" = "A missing route, not a missing id: this JATOS has no such endpoint and may be older than the API jatosr was built against.",
        if (!is.null(hint)) c("i" = hint)
      ))
    }
    return(NULL)
  }
  switch(
    status,
    "401" = c(
      "i" = cli::format_inline(
        "Authentication failed. The token was rejected; check the profile with {.fn jatos_list_profiles} and {.fn jatos_token_info}."
      ),
      # A token is read from the credential store once per session and kept
      # in memory, so one rotated in Keychain Access or seahorse since this
      # session started is not the one being sent.
      "i" = cli::format_inline(
        "If you changed the token in the credential store since this session started, restart R."
      )
    ),
    "403" = c("i" = "The token is valid but not allowed to access this resource."),
    "429" = c("i" = "The server is limiting the rate of requests. Wait a moment and try again."),
    NULL
  )
}

# One host can hold two accounts as two profiles, so a call aimed at the
# wrong profile is not a transport failure: it is a valid request against a
# different catalogue. The profile name is the fact that identifies it.
# Wording follows warn_expiring_token().
profile_bullet <- function(conn) {
  if (is.null(conn) || is.null(conn$profile)) {
    return(NULL)
  }
  c("i" = cli::format_inline("Profile {.val {conn$profile}} on {.url {conn$host}}."))
}
