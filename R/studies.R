#' List the studies a token can see
#'
#' Calls `GET /studies/properties`. Each row is one study; its components
#' and batches are nested as list columns of tibbles, so
#' `tidyr::unnest(studies, batches)` gives one row per batch.
#'
#' @param with_components,with_batches Include full component and batch
#'   properties (`TRUE`, the default) or only their ids and uuids.
#' @param conn A [jatos_connection()].
#'
#' @return A tibble with one row per study: `study_id`, `study_uuid`,
#'   `title`, `description`, `active`, `locked`, `group_study`,
#'   `linear_study`, `allow_preview`, `dir_name`, `end_redirect_url`,
#'   `members` (list of usernames), `components` and `batches` (list columns
#'   of tibbles in the shape returned by [jatos_components()] and
#'   [jatos_batches()]).
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' studies <- jatos_studies()
#' studies[grepl("Binding", studies$title), ]
#' }
jatos_studies <- function(with_components = TRUE,
                          with_batches = TRUE,
                          conn = jatos_connection()) {
  check_flag(with_components)
  check_flag(with_batches)
  body <- jatos_req(conn, "studies/properties") |>
    jatos_query(
      withComponentProperties = tolower(with_components),
      withBatchProperties = tolower(with_batches)
    ) |>
    perform_json()
  rows_to_tibble(body$data, parse_study)
}

#' Properties of one study
#'
#' Calls `GET /studies/{id}/properties` with components and batches included.
#'
#' @param study_id Study id (integer) or uuid (string).
#' @inheritParams jatos_studies
#'
#' @return A one-row tibble in the shape of [jatos_studies()].
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_study(12)
#' }
jatos_study <- function(study_id, conn = jatos_connection()) {
  ref <- check_ref(study_id)
  body <- jatos_req(conn, c("studies", ref, "properties")) |>
    jatos_query(withComponentProperties = "true", withBatchProperties = "true") |>
    perform_json()
  parse_study(body$data)
}

#' Components of a study
#'
#' Calls `GET /studies/{id}/components`.
#'
#' @inheritParams jatos_study
#'
#' @return A tibble with `component_id`, `component_uuid`, `title`,
#'   `html_file_path`, `active`, `reloadable`, `study_id`.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_components(12)
#' }
jatos_components <- function(study_id, conn = jatos_connection()) {
  ref <- check_ref(study_id)
  body <- jatos_req(conn, c("studies", ref, "components")) |> perform_json()
  rows_to_tibble(body$data, parse_component, study_id = ref_as_id(ref))
}

#' Batches of a study
#'
#' Calls `GET /studies/{id}/batches`.
#'
#' @section Server support:
#' This endpoint does not exist on every JATOS. On a server whose API
#' reports `apiVersion` 1.0.1 it answers 404 for a study that
#' [jatos_studies()] has just listed, and the error says so. There is no
#' version endpoint to check in advance; `apiVersion` in the envelope of
#' any successful answer is the only signal.
#'
#' `jatos_studies(with_batches = TRUE)` (the default) is the way round it,
#' and is cheaper anyway: it returns every study's batches as a nested
#' `batches` column in one request rather than one request per study.
#'
#' @inheritParams jatos_study
#'
#' @return A tibble with `batch_id`, `batch_uuid`, `title`, `active`,
#'   `max_total_workers`, `max_active_members`, `max_total_members`,
#'   `allowed_worker_types` (list column), `study_id`.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_batches(12)
#' }
jatos_batches <- function(study_id, conn = jatos_connection()) {
  ref <- check_ref(study_id)
  # The way round the route being absent, said where the user meets it (see
  # the Server support section) and not only in the documentation.
  hint <- "`jatos_studies(with_batches = TRUE)` returns every study's batches in one request, without this endpoint."
  body <- jatos_req(conn, c("studies", ref, "batches"), hint = hint) |> perform_json()
  rows_to_tibble(body$data, parse_batch, study_id = ref_as_id(ref))
}

#' Properties of one batch
#'
#' Calls `GET /batches/{id}`.
#'
#' @param batch_id Batch id (integer) or uuid (string).
#' @inheritParams jatos_studies
#'
#' @return A one-row tibble in the shape of [jatos_batches()]; `study_id`
#'   is `NA` because the endpoint does not report it.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_batch(34)
#' }
jatos_batch <- function(batch_id, conn = jatos_connection()) {
  ref <- check_ref(batch_id)
  body <- jatos_req(conn, c("batches", ref)) |> perform_json()
  parse_batch(body$data, study_id = NA_integer_)
}

#' Groups of a batch (group studies only)
#'
#' Calls `GET /batches/{id}/groups`.
#'
#' @section Server support:
#' Like [jatos_batches()], this is a nested route under a resource, and the
#' one server where those were tested (`apiVersion` 1.0.1) has none of
#' them. It was not confirmed for this endpoint — no group study was
#' available there — so treat a 404 as a possible missing route rather than
#' a wrong batch id; the error distinguishes the two from the server's own
#' wording.
#'
#' @inheritParams jatos_batch
#'
#' @return A tibble with `group_id`, `group_state`, `n_active`, `n_history`,
#'   `n_results`, `active_members`, `history_members` (list columns of study
#'   result ids), `start_time`, `end_time`, `batch_id`.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_groups(34)
#' }
jatos_groups <- function(batch_id, conn = jatos_connection()) {
  ref <- check_ref(batch_id)
  body <- jatos_req(conn, c("batches", ref, "groups")) |> perform_json()
  rows_to_tibble(body$data, parse_group, batch_id = ref_as_id(ref))
}

#' Recent entries of a study log
#'
#' Calls `GET /studies/{id}/log?download=false&entryLimit=`. JATOS streams
#' the log as newline-delimited JSON; each line becomes one row. Column
#' names follow the log entry fields (converted to snake case), which vary
#' between JATOS versions and entry types, so downstream code should select
#' columns by name defensively.
#'
#' @inheritParams jatos_study
#' @param limit Maximum number of most recent log lines to return.
#'
#' @return A tibble with one row per log entry and a `study_id` column.
#'   Nested values are kept as list columns.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_study_log(12, limit = 20)
#' }
jatos_study_log <- function(study_id, limit = 100, conn = jatos_connection()) {
  ref <- check_ref(study_id)
  limit <- check_count(limit)
  resp <- jatos_req(conn, c("studies", ref, "log"), accept = "application/x-ndjson, application/json") |>
    jatos_query(download = "false", entryLimit = limit) |>
    perform()
  parse_ndjson(httr2::resp_body_string(resp), study_id = ref_as_id(ref))
}

parse_ndjson <- function(text, study_id) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]
  if (length(lines) == 0) {
    return(tibble::tibble(study_id = integer()))
  }
  rows <- purrr::map(lines, function(line) {
    entry <- jsonlite::fromJSON(line, simplifyVector = FALSE)
    entry <- purrr::map(entry, function(v) if (is.list(v) || length(v) != 1) list(v) else v)
    names(entry) <- snake_case(names(entry))
    tibble::as_tibble(entry)
  })
  out <- purrr::list_rbind(rows)
  out$study_id <- as.integer(study_id)
  if ("timestamp" %in% names(out) && is.numeric(out$timestamp)) {
    out$timestamp <- ms_to_posixct(as.list(out$timestamp))
  }
  out
}

# --- parsers -------------------------------------------------------------------

# Apply a row parser to a list of JSON objects; keep the columns when empty.
rows_to_tibble <- function(rows, parser, ...) {
  rows <- rows %||% list()
  if (length(rows) == 0) {
    return(parser(NULL, ...)[0, ])
  }
  purrr::map(rows, parser, ...) |> purrr::list_rbind()
}

parse_study <- function(x) {
  study_id <- pluck_int(x, "id")
  tibble::tibble(
    study_id = study_id,
    study_uuid = pluck_chr(x, "uuid"),
    title = pluck_chr(x, "title"),
    description = pluck_chr(x, "description"),
    active = pluck_lgl(x, "active"),
    locked = pluck_lgl(x, "locked"),
    group_study = pluck_lgl(x, "groupStudy"),
    linear_study = pluck_lgl(x, "linearStudy"),
    allow_preview = pluck_lgl(x, "allowPreview"),
    dir_name = pluck_chr(x, "dirName"),
    end_redirect_url = pluck_chr(x, "endRedirectUrl"),
    members = list(purrr::map_chr(x$members %||% list(), pluck_chr, "username")),
    components = list(rows_to_tibble(x$components, parse_component, study_id = study_id)),
    batches = list(rows_to_tibble(x$batches, parse_batch, study_id = study_id))
  )
}

parse_component <- function(x, study_id) {
  tibble::tibble(
    component_id = pluck_int(x, "id"),
    component_uuid = pluck_chr(x, "uuid"),
    title = pluck_chr(x, "title"),
    html_file_path = pluck_chr(x, "htmlFilePath"),
    active = pluck_lgl(x, "active"),
    reloadable = pluck_lgl(x, "reloadable"),
    study_id = as.integer(study_id)
  )
}

parse_batch <- function(x, study_id) {
  tibble::tibble(
    batch_id = pluck_int(x, "id"),
    batch_uuid = pluck_chr(x, "uuid"),
    title = pluck_chr(x, "title"),
    active = pluck_lgl(x, "active"),
    max_total_workers = pluck_int(x, "maxTotalWorkers"),
    max_active_members = pluck_int(x, "maxActiveMembers"),
    max_total_members = pluck_int(x, "maxTotalMembers"),
    allowed_worker_types = list(as.character(unlist(x$allowedWorkerTypes))),
    study_id = as.integer(study_id)
  )
}

parse_group <- function(x, batch_id) {
  tibble::tibble(
    group_id = pluck_int(x, "id"),
    group_state = pluck_chr(x, "groupState"),
    n_active = pluck_int(x, "activeMemberCount"),
    n_history = pluck_int(x, "historyMemberCount"),
    n_results = pluck_int(x, "resultCount"),
    active_members = list(as.integer(unlist(x$activeMemberList))),
    history_members = list(as.integer(unlist(x$historyMemberList))),
    start_time = pluck_time(x, "startDate"),
    end_time = pluck_time(x, "endDate"),
    batch_id = as.integer(batch_id)
  )
}

# Study and batch endpoints accept either a numeric id or a uuid string. The
# reference ends up in the URL path, so a string is accepted only when it is
# an id in digits or a uuid (8-4-4-4-12 hexadecimal groups, as
# java.util.UUID prints them); anything else, a path fragment or a query,
# is refused before a request is built.
uuid_pattern <- "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

check_ref <- function(x, arg = rlang::caller_arg(x), call = rlang::caller_env()) {
  if (rlang::is_string(x) && !is.na(x)) {
    if (grepl("^[0-9]+$", x) && as.numeric(x) > 0) {
      return(sub("^0+", "", x))
    }
    if (grepl(uuid_pattern, x)) {
      return(x)
    }
  }
  if (rlang::is_scalar_integerish(x) && !is.na(x) && x > 0) {
    return(as.character(as.integer(x)))
  }
  cli::cli_abort(
    c(
      "{.arg {arg}} must be a single positive id or a uuid string.",
      "i" = "A uuid has 36 characters in five hexadecimal groups (8-4-4-4-12)."
    ),
    call = call,
    class = "jatosr_bad_argument"
  )
}

ref_as_id <- function(ref) {
  if (grepl("^[0-9]+$", ref)) as.integer(ref) else NA_integer_
}
