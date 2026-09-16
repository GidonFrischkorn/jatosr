#' Result metadata, one row per component result
#'
#' Calls `POST /results/metadata` with the ids as a JSON body, so any number
#' of ids fits in one request. Results the token cannot see are left out by
#' the server without an error. The answer is flattened with
#' [jatos_flatten_metadata()]; see there for the columns.
#'
#' Every id argument accepts one or more integer ids; `study_id` and
#' `component_id` also accept uuid strings, which survive a study's export
#' and import on another server while its id changes. At least one must be
#' given; several are combined as the server combines them (the union of
#' everything selected). A message reports the host, the number of study
#' results and component results, and how many component results are not
#' `FINISHED`; silence it with `options(rlib_message_verbosity = "quiet")`
#' or `suppressMessages()`.
#'
#' @param study_id,component_id Ids (integer) or uuids (string) to select
#'   results by, one kind per argument; `NULL` (the default) means no
#'   restriction on that dimension. Uuids go to the server as `studyUuids`
#'   and `componentUuids`.
#' @param batch_id,study_result_id,component_result_id,group_id
#'   Ids to select results by. `NULL` (the default) means no restriction on
#'   that dimension. The server takes no uuid for these.
#' @param conn A [jatos_connection()].
#'
#' @return A metadata tibble, one row per component result, with the
#'   columns documented in [jatos_flatten_metadata()].
#' @seealso [jatos_study_results()] for one row per study result,
#'   [jatos_read_metadata()] to rebuild the same tibble from a local cache.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' meta <- jatos_results_metadata(study_id = 12)
#' meta[meta$component_state == "FINISHED" & meta$data_size > 0, ]
#' }
jatos_results_metadata <- function(study_id = NULL,
                                   batch_id = NULL,
                                   component_id = NULL,
                                   study_result_id = NULL,
                                   component_result_id = NULL,
                                   group_id = NULL,
                                   conn = jatos_connection()) {
  body <- result_ids_body(
    study_id = study_id, batch_id = batch_id, component_id = component_id,
    study_result_id = study_result_id, component_result_id = component_result_id,
    group_id = group_id
  )
  parsed <- jatos_req(conn, "results/metadata") |>
    jatos_query(download = "false") |>
    httr2::req_body_json(body) |>
    perform_json()
  meta <- jatos_flatten_metadata(parsed)
  report_metadata(meta, conn$host)
  meta
}

# The JSON body of the /results endpoints (verified against jatos-api.yaml,
# `ResultIdsJsonBody`): ids under `<name>Ids`, uuids under `studyUuids` and
# `componentUuids`; batch, group, study result and component result take ids
# only. NULL arguments are left out; the caller gets an error when nothing
# is left.
result_ids_body <- function(study_id,
                            batch_id,
                            component_id,
                            study_result_id,
                            component_result_id,
                            group_id,
                            call = rlang::caller_env()) {
  study <- check_ids_or_uuids(study_id, arg = "study_id", call = call)
  component <- check_ids_or_uuids(component_id, arg = "component_id", call = call)
  body <- list(
    studyIds = study$ids,
    studyUuids = study$uuids,
    batchIds = check_ids(batch_id, arg = "batch_id", call = call, allow_null = TRUE),
    componentIds = component$ids,
    componentUuids = component$uuids,
    studyResultIds = check_ids(study_result_id, arg = "study_result_id", call = call, allow_null = TRUE),
    componentResultIds = check_ids(component_result_id, arg = "component_result_id", call = call, allow_null = TRUE),
    groupIds = check_ids(group_id, arg = "group_id", call = call, allow_null = TRUE)
  )
  body <- drop_null(body)
  if (length(body) == 0) {
    cli::cli_abort(
      c(
        "Supply at least one id to select results by.",
        "i" = "Use {.arg study_id}, {.arg batch_id}, {.arg component_id}, {.arg study_result_id}, {.arg component_result_id} or {.arg group_id}."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  # I() keeps a single id as a JSON array; the server accepts both.
  purrr::map(body, I)
}

report_metadata <- function(meta, host) {
  n_study_results <- length(unique(meta$study_result_id))
  n_component_results <- nrow(meta)
  n_unfinished <- sum(is.na(meta$component_state) | meta$component_state != "FINISHED")
  cli::cli_inform(c(
    "i" = "{.url {host}}: {n_study_results} study result{?s}, {n_component_results} component result{?s} ({n_unfinished} not FINISHED)."
  ))
}

#' Flatten a `/results/metadata` answer into a tibble
#'
#' Turns the nested JSON of `POST /results/metadata` (studies, their study
#' results, their component results) into a flat tibble with one row per
#' component result. Study-level and study-result-level values repeat down
#' their component results; every column name says which level it belongs
#' to, so `length(unique(meta$study_result_id))` counts participants while
#' `nrow(meta)` counts component results. Column names are snake case,
#' times are `POSIXct` in UTC, sizes are bytes.
#'
#' @param metadata The metadata as the server sent it, not yet a tibble: a
#'   parsed answer (the whole envelope or its `data` element) as returned by
#'   `jsonlite::read_json(simplifyVector = FALSE)`, or the path of a
#'   `metadata.json` file. A data frame is refused, the flat metadata tibble
#'   included: that tibble is what this function returns, and every other
#'   metadata function takes it as it is.
#'
#' @return A tibble with, per study: `study_id`, `study_uuid`, `study_title`;
#'   per study result: `study_result_id`, `study_result_uuid`, `study_code`,
#'   `worker_id`, `worker_type`, `batch_id`, `batch_uuid`, `batch_title`,
#'   `group_id`, `study_state`, `study_start_time`, `study_end_time`,
#'   `study_duration` (minutes), `last_seen`, `comment`, `study_message`
#'   (the text shown when a run was aborted or failed), `confirmation_code`
#'   (MTurk), `quota_reached`, `url_query` (list of the URL query parameters
#'   the worker arrived with); per component
#'   result: `component_result_id`, `component_id`, `component_uuid`,
#'   `component_state`, `component_start_time`, `component_end_time`,
#'   `component_duration` (minutes), `path` (location inside a result zip),
#'   `data_size` (bytes on the server; 0 for reloads and unfinished runs),
#'   `data_file`, `n_files` and `files` (list of attached-file entries).
#' @export
#' @examples
#' meta <- jatos_flatten_metadata(
#'   system.file("extdata", "metadata.json", package = "jatosr")
#' )
#' meta[, c("study_result_id", "component_result_id", "component_state", "data_size")]
jatos_flatten_metadata <- function(metadata) {
  studies <- metadata_studies(metadata)
  rows <- metadata_rows(studies)
  if (length(rows) == 0) {
    return(empty_metadata())
  }
  build_metadata(rows)
}

# Accept the envelope, its data element, or a file path.
metadata_studies <- function(metadata, call = rlang::caller_env()) {
  if (rlang::is_string(metadata)) {
    check_path_exists(metadata, call = call)
    metadata <- jsonlite::read_json(metadata, simplifyVector = FALSE)
  }
  # A data frame is a list, so it passes the guard below and is then mapped
  # over column by column: an atomic first column errors inside purrr, and a
  # frame of list columns returns zero rows in silence. This is the flat
  # tibble arriving where the parsed answer belongs, the mirror image of what
  # check_metadata() refuses, so name the confusion instead.
  if (is.data.frame(metadata)) {
    cli::cli_abort(
      c(
        "{.arg metadata} must be a parsed {.code /results/metadata} answer or the path of a metadata.json file, not a data frame.",
        "i" = "The flat tibble is what {.fn jatos_flatten_metadata} returns: the one from {.fn jatos_results_metadata} or {.fn jatos_read_metadata} needs no flattening, and every other metadata function takes it as it is."
      ),
      call = call,
      class = "jatosr_bad_metadata"
    )
  }
  if (!is.list(metadata)) {
    cli::cli_abort(
      "{.arg metadata} must be a parsed {.code /results/metadata} answer or the path of a metadata.json file.",
      call = call,
      class = "jatosr_bad_metadata"
    )
  }
  if (!is.null(names(metadata)) && "data" %in% names(metadata)) {
    metadata <- metadata$data
  }
  metadata %||% list()
}

# One entry per component result, holding the parsed study, study result
# and component result it belongs to (references, not copies).
metadata_rows <- function(studies) {
  rows <- purrr::map(studies, function(study) {
    purrr::map(study$studyResults %||% list(), function(sr) {
      purrr::map(sr$componentResults %||% list(), function(cr) {
        list(study = study, sr = sr, cr = cr)
      })
    }) |> unlist(recursive = FALSE)
  }) |> unlist(recursive = FALSE)
  rows %||% list()
}

# The tibble is built column by column from the rows, not row by row: one
# tibble per component result took 43 s for 9,246 rows (2026-09-06), this
# takes under a second.
build_metadata <- function(rows) {
  chr <- function(part, ...) vapply(rows, function(r) pluck_chr(r[[part]], ...), character(1))
  int <- function(part, ...) vapply(rows, function(r) pluck_int(r[[part]], ...), integer(1))
  dbl <- function(part, ...) vapply(rows, function(r) pluck_dbl(r[[part]], ...), numeric(1))
  lgl <- function(part, ...) vapply(rows, function(r) pluck_lgl(r[[part]], ...), logical(1))
  time <- function(part, ...) ms_to_posixct(lapply(rows, function(r) purrr::pluck(r[[part]], ...)))
  study_start <- time("sr", "startDate")
  study_end <- time("sr", "endDate")
  component_start <- time("cr", "startDate")
  component_end <- time("cr", "endDate")
  files <- lapply(rows, function(r) r$cr$files %||% list())
  tibble::tibble(
    study_id = int("study", "studyId"),
    study_uuid = chr("study", "studyUuid"),
    study_title = chr("study", "studyTitle"),
    study_result_id = int("sr", "id"),
    study_result_uuid = chr("sr", "uuid"),
    study_code = chr("sr", "studyCode"),
    worker_id = int("sr", "workerId"),
    worker_type = chr("sr", "workerType"),
    batch_id = int("sr", "batchId"),
    batch_uuid = chr("sr", "batchUuid"),
    batch_title = chr("sr", "batchTitle"),
    group_id = int("sr", "groupId"),
    study_state = chr("sr", "studyState"),
    study_start_time = study_start,
    study_end_time = study_end,
    study_duration = difftime(study_end, study_start, units = "mins"),
    last_seen = time("sr", "lastSeenDate"),
    comment = chr("sr", "comment"),
    study_message = chr("sr", "message"),
    confirmation_code = chr("sr", "confirmationCode"),
    quota_reached = lgl("sr", "isQuotaReached"),
    url_query = lapply(rows, function(r) r$sr$urlQueryParameters %||% list()),
    component_result_id = int("cr", "id"),
    component_id = int("cr", "componentId"),
    component_uuid = chr("cr", "componentUuid"),
    component_state = chr("cr", "componentState"),
    component_start_time = component_start,
    component_end_time = component_end,
    component_duration = difftime(component_end, component_start, units = "mins"),
    path = chr("cr", "path"),
    data_size = dbl("cr", "data", "size"),
    data_file = chr("cr", "data", "filename"),
    n_files = lengths(files),
    files = files
  )
}

empty_metadata <- function() {
  build_metadata(list())
}

metadata_columns <- function() {
  names(empty_metadata())
}

# Columns that describe the study or the study result, i.e. that are
# constant within a study result.
metadata_study_columns <- function() {
  c(
    "study_id", "study_uuid", "study_title",
    "study_result_id", "study_result_uuid", "study_code", "worker_id",
    "worker_type", "batch_id", "batch_uuid", "batch_title", "group_id",
    "study_state", "study_start_time", "study_end_time", "study_duration",
    "last_seen", "comment", "study_message", "confirmation_code", "quota_reached",
    "url_query"
  )
}
