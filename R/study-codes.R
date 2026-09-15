#' Generate study codes for a batch
#'
#' Calls `POST /studies/{id}/studyCodes`. A study code is what JATOS puts at
#' the end of a study link (`<host>/publix/<code>`); each code belongs to one
#' batch and one worker type. For the personal types (`PersonalSingle`,
#' `PersonalMultiple`) the server creates `n` new codes, each with its own
#' worker and the optional `comment`. For the general types (`GeneralSingle`,
#' `GeneralMultiple`, `MTurk`) a batch has exactly one code, which the server
#' creates on first request and returns unchanged afterwards; `n` must be `1`
#' and `comment` `NULL` for them, checked before any request is made.
#'
#' The server answers with the codes only (verified against `jatos-api.yaml`,
#' 2026-09-05). Whether a code is active, and its batch when `batch_id` was
#' not given, come from [jatos_study_code()].
#'
#' @param study_id Study id (integer) or uuid (string).
#' @param batch_id Batch id. `NULL` (the default) uses the study's default
#'   batch; the returned `batch_id` is then `NA` because the server does not
#'   report which batch that is.
#' @param n Number of codes to generate, `1` to `1000` (the server's limit);
#'   personal types only.
#' @param type Worker type of the codes. One of `"PersonalSingle"`,
#'   `"PersonalMultiple"`, `"GeneralSingle"`, `"GeneralMultiple"`, `"MTurk"`.
#' @param comment Optional comment stored with each worker; personal types
#'   only. Plain text up to 255 characters, no HTML.
#' @param conn A [jatos_connection()].
#'
#' @return A tibble with one row per code: `study_code`, `study_id` (`NA`
#'   when `study_id` was a uuid), `batch_id`, `type`, `comment`, and
#'   `study_link`, the run URL built by [jatos_study_links()].
#' @seealso [jatos_study_code()] for the properties of a code,
#'   [jatos_deactivate_study_code()] to close one, [jatos_study_links()] for
#'   the run URLs.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' codes <- jatos_create_study_codes(12, batch_id = 34, n = 20, comment = "wave 2")
#' writeLines(codes$study_link)
#' }
jatos_create_study_codes <- function(study_id,
                                     batch_id = NULL,
                                     n = 1,
                                     type = c(
                                       "PersonalSingle", "PersonalMultiple",
                                       "GeneralSingle", "GeneralMultiple", "MTurk"
                                     ),
                                     comment = NULL,
                                     conn = jatos_connection()) {
  ref <- check_ref(study_id)
  if (!is.null(batch_id)) {
    batch_id <- check_id(batch_id)
  }
  n <- check_count(n, max = 1000)
  type <- rlang::arg_match(type)
  if (!is.null(comment)) {
    check_comment(comment)
  }
  check_connection(conn)

  personal <- type %in% c("PersonalSingle", "PersonalMultiple")
  if (!personal && (n != 1 || !is.null(comment))) {
    cli::cli_abort(c(
      "{.arg n} and {.arg comment} apply only to {.val PersonalSingle} and {.val PersonalMultiple} codes.",
      "i" = "A batch has exactly one {.val {type}} code; the server returns it as is."
    ), class = "jatosr_bad_argument")
  }

  request_body <- drop_null(list(
    type = type,
    batchId = batch_id,
    amount = as.integer(n),
    comment = comment
  ))
  # The one request in the package that creates something: no retry, since
  # a second POST after an ambiguous answer would create a second set of
  # codes (and workers) that the first answer never reported.
  body <- jatos_req(conn, c("studies", ref, "studyCodes"), retry = FALSE) |>
    httr2::req_body_json(request_body) |>
    perform_json()
  codes <- as.character(unlist(body$data))

  cli::cli_inform(c(
    "v" = "Received {length(codes)} {type} study {cli::qty(length(codes))}code{?s} for study {ref}."
  ))
  tibble::tibble(
    study_code = codes,
    study_id = ref_as_id(ref),
    batch_id = batch_id %||% NA_integer_,
    type = type,
    comment = comment %||% NA_character_,
    study_link = study_links(codes, conn$host)
  )
}

#' Properties of study codes
#'
#' Calls `GET /studyCodes/{code}` once per code. The server reports the link
#' paths relative to its base path (`studyLinkPath`, `studyEntryPath` in
#' `jatos-api.yaml`); they are joined to the origin of `conn$host` to give
#' full URLs.
#'
#' @param code One or more study codes, as returned by
#'   [jatos_create_study_codes()] or shown in the JATOS GUI.
#' @inheritParams jatos_create_study_codes
#'
#' @return A tibble with one row per code: `study_code`, `batch_id`, `type`,
#'   `comment`, `active`, `study_link` (`<origin>/publix/<code>`) and
#'   `study_entry_link` (`<origin>/publix/run?code=<code>`, the form JATOS
#'   uses for its own study entry page).
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_study_code("8kw0pFV5M1e")
#' }
jatos_study_code <- function(code, conn = jatos_connection()) {
  codes <- check_codes(code)
  check_connection(conn)
  purrr::map(codes, function(x) {
    body <- jatos_req(conn, c("studyCodes", x)) |> perform_json()
    parse_study_code(body$data, host = conn$host)
  }) |>
    purrr::list_rbind()
}

#' Activate or deactivate study codes
#'
#' Calls `PATCH /studyCodes/{code}` with `{"active": true}` or
#' `{"active": false}` once per code. A deactivated code no longer admits a
#' participant; the study link stays valid and can be activated again.
#'
#' @inheritParams jatos_study_code
#'
#' @return A tibble in the shape of [jatos_study_code()] with the new state.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' codes <- jatos_create_study_codes(12, n = 5, type = "PersonalMultiple")
#' jatos_deactivate_study_code(codes$study_code)
#' }
jatos_activate_study_code <- function(code, conn = jatos_connection()) {
  set_study_code_active(code, active = TRUE, conn = conn)
}

#' @rdname jatos_activate_study_code
#' @export
jatos_deactivate_study_code <- function(code, conn = jatos_connection()) {
  set_study_code_active(code, active = FALSE, conn = conn)
}

set_study_code_active <- function(code, active, conn, call = rlang::caller_env()) {
  codes <- check_codes(code, call = call)
  check_connection(conn, call = call)
  purrr::map(codes, function(x) {
    body <- jatos_req(conn, c("studyCodes", x), call = call) |>
      httr2::req_method("PATCH") |>
      httr2::req_body_json(list(active = active)) |>
      perform_json(call = call)
    parse_study_code(body$data, host = conn$host)
  }) |>
    purrr::list_rbind()
}

#' Run URLs for study codes
#'
#' Turns study codes into the links participants open, `<host>/publix/<code>`.
#' No request is made. The pattern is the `GET /publix/:studyCode` route of
#' the JATOS publix module (`modules/publix/conf/publix.routes` in the JATOS
#' repository, and the `studyLinkPath` field of `GET /studyCodes/{code}` in
#' `jatos-api.yaml`, both read 2026-09-05). Any base path under which JATOS
#' is served is part of `host`.
#'
#' @param code One or more study codes.
#' @param host Base URL of the JATOS server. Defaults to the host variable of
#'   the credential profile (`JATOS_HOST` for the default profile); the token
#'   is not needed.
#' @inheritParams jatos_connection
#'
#' @return A character vector of URLs, one per code.
#' @export
#' @examples
#' jatos_study_links(c("8kw0pFV5M1e", "Qm3xYtb9Lc2"), host = "https://jatos.example.org")
jatos_study_links <- function(code,
                              host = NULL,
                              profile = Sys.getenv("JATOS_PROFILE", "default")) {
  codes <- check_codes(code)
  profile <- check_profile(profile)
  host <- normalise_host(jatos_host(profile, host))
  study_links(codes, host)
}

study_links <- function(codes, host) {
  paste0(host, "/publix/", codes)
}

# --- parsers and checks ----------------------------------------------------------

parse_study_code <- function(x, host) {
  origin <- host_origin(host)
  tibble::tibble(
    study_code = pluck_chr(x, "studyCode"),
    batch_id = pluck_int(x, "batchId"),
    type = pluck_chr(x, "type"),
    comment = pluck_chr(x, "comment"),
    active = pluck_lgl(x, "active"),
    study_link = join_origin(origin, pluck_chr(x, "studyLinkPath")),
    study_entry_link = join_origin(origin, pluck_chr(x, "studyEntryPath"))
  )
}

# Scheme and authority of a normalised host, without any base path: the
# server's link paths already include its base path (play.http.context).
host_origin <- function(host) {
  sub("^(https?://[^/]+).*$", "\\1", host)
}

join_origin <- function(origin, path) {
  if (is.na(path)) NA_character_ else paste0(origin, path)
}

# JATOS study codes are 11 random alphanumerics (StudyLink.java); anything
# else would end up inside a URL path, so reject it early. The pattern
# admits `-` and `_` as well, the two other characters safe in a path
# segment, and the message says so.
check_codes <- function(x,
                        arg = rlang::caller_arg(x),
                        call = rlang::caller_env()) {
  ok <- is.character(x) && length(x) >= 1 && !anyNA(x) &&
    all(grepl("^[A-Za-z0-9_-]+$", x))
  if (!ok) {
    cli::cli_abort(
      "{.arg {arg}} must be one or more study codes (letters, digits, {.code -} and {.code _}) without missing values.",
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  invisible(x)
}

# The server stores the comment on each worker: at most 255 characters and
# no HTML (jatos-api.yaml). Checked here so a long comment costs no request
# and no half-created set of codes.
check_comment <- function(comment,
                          arg = rlang::caller_arg(comment),
                          call = rlang::caller_env()) {
  check_string(comment, arg = arg, call = call)
  if (nchar(comment) > 255) {
    cli::cli_abort(
      "{.arg {arg}} must be at most 255 characters, got {nchar(comment)}.",
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  if (grepl("<[^>]*>", comment)) {
    cli::cli_abort(
      c("{.arg {arg}} must not contain HTML.", "i" = "The server stores it as plain text."),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  invisible(comment)
}
