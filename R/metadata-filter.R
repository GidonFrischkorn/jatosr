#' Keep the study results that belong in a dataset
#'
#' Drops rows of a metadata tibble by study state, worker type, start time
#' and explicit exclusions, the filters every export makes before the
#' trials are read: unfinished runs (`study_state != "FINISHED"`), the
#' researcher's own test runs from the JATOS GUI (`worker_type ==
#' "Jatos"`), runs before the study went live or after a wave closed, and
#' known test runs by their study result or worker id. The filters work on
#' the study result, the run of one participant, so every component result
#' of a dropped run goes with it. A message reports how many study results
#' each filter removed; no message when no filter is given.
#'
#' @param metadata A metadata tibble from [jatos_results_metadata()] or
#'   [jatos_read_metadata()].
#' @param states Study states to keep, for example `"FINISHED"`. `NULL`
#'   keeps every state. JATOS states are `PRE`, `STARTED`, `DATA_RETRIEVED`,
#'   `FINISHED`, `ABORTED` and `FAIL`.
#' @param worker_types Worker types to keep, for example
#'   `c("PersonalSingle", "GeneralMultiple")`. `NULL` keeps every type; the
#'   GUI test runs are `"Jatos"`.
#' @param since Keep study results that started at or after this time: a
#'   `POSIXct`, a `Date`, or a string such as `"2025-08-24"` or
#'   `"2025-08-24 12:00:00"`, read in the time zone `tz`. Rows without a
#'   start time are dropped when `since` is given.
#' @param until Keep study results that started *before* this time, given
#'   like `since`; `since` and `until` together select a half-open
#'   interval, so `since = "2025-08-24", until = "2025-08-25"` is one day.
#'   Rows without a start time are dropped when `until` is given.
#' @param exclude_study_result_id,exclude_worker_id Study result ids, or
#'   worker ids, whose study results are dropped; for the researcher's own
#'   runs through a real link, which `worker_types` cannot tell apart.
#' @param tz Time zone in which date strings in `since` and `until` are
#'   read, and in which the message shows them. `"UTC"` by default, the
#'   zone the server reports times in; `Sys.timezone()` for local time.
#'
#' @return `metadata` without the dropped rows.
#' @seealso [jatos_export_results()], which applies the same filters
#'   before the download.
#' @export
#' @examples
#' meta <- jatos_flatten_metadata(
#'   system.file("extdata", "metadata.json", package = "jatosr")
#' )
#' jatos_filter_metadata(meta, states = "FINISHED", since = "2025-08-24")
#' jatos_filter_metadata(meta, until = "2025-08-24 02:00", exclude_worker_id = 503)
jatos_filter_metadata <- function(metadata,
                                  states = NULL,
                                  worker_types = NULL,
                                  since = NULL,
                                  until = NULL,
                                  exclude_study_result_id = NULL,
                                  exclude_worker_id = NULL,
                                  tz = "UTC") {
  check_metadata(
    metadata,
    needs = c("study_result_id", "study_state", "worker_type", "study_start_time", "worker_id"),
    contract = FALSE
  )
  check_column_names(states, allow_null = TRUE, what = "study states")
  check_column_names(worker_types, allow_null = TRUE, what = "worker types")
  tz <- check_tz(tz)
  since <- check_since(since, tz)
  until <- check_since(until, tz)
  exclude_study_result_id <- check_ids(exclude_study_result_id, allow_null = TRUE)
  exclude_worker_id <- check_ids(exclude_worker_id, allow_null = TRUE)
  filters <- list(states, worker_types, since, until, exclude_study_result_id, exclude_worker_id)
  if (all(vapply(filters, is.null, logical(1)))) {
    return(metadata)
  }

  n_before <- length(unique(metadata$study_result_id))
  keep <- rep(TRUE, nrow(metadata))
  # each line is rendered when its count is computed: a stored template
  # that named the loop variable reported the last filter's count for all
  report <- character()
  add <- function(drop, text) {
    n <- count_study_results(metadata, drop)
    report <<- c(report, cli::format_inline(paste("{n}", text)))
    keep <<- keep & !drop
  }
  if (!is.null(states)) {
    add(keep & !(metadata$study_state %in% states), "by study state (kept {.val {states}})")
  }
  if (!is.null(worker_types)) {
    add(keep & !(metadata$worker_type %in% worker_types), "by worker type (kept {.val {worker_types}})")
  }
  if (!is.null(since)) {
    stamp <- format(since, "%Y-%m-%d %H:%M:%S", tz = tz)
    add(keep & (is.na(metadata$study_start_time) | metadata$study_start_time < since), "that started before {stamp} {tz}")
  }
  if (!is.null(until)) {
    stamp <- format(until, "%Y-%m-%d %H:%M:%S", tz = tz)
    add(keep & (is.na(metadata$study_start_time) | metadata$study_start_time >= until), "that started at or after {stamp} {tz}")
  }
  if (!is.null(exclude_study_result_id)) {
    add(keep & metadata$study_result_id %in% exclude_study_result_id, "by study result id ({length(exclude_study_result_id)} excluded)")
  }
  if (!is.null(exclude_worker_id)) {
    add(keep & metadata$worker_id %in% exclude_worker_id, "by worker id ({length(exclude_worker_id)} excluded)")
  }
  out <- metadata[keep, , drop = FALSE]
  n_after <- length(unique(out$study_result_id))
  n_dropped <- n_before - n_after
  cli::cli_inform(c(
    "i" = "Excluded {n_dropped} of {n_before} study result{?s}; {n_after} remain{?s/}.",
    rlang::set_names(cli_literal(report), rep("*", length(report)))
  ))
  out
}

count_study_results <- function(x, rows) {
  length(unique(x$study_result_id[rows]))
}

# A time as POSIXct, or NULL: a POSIXct as given, a Date as midnight in
# `tz`, a string read in `tz`.
check_since <- function(since, tz = "UTC", arg = rlang::caller_arg(since), call = rlang::caller_env()) {
  if (is.null(since)) {
    return(NULL)
  }
  # the instant is kept, the zone attribute becomes UTC, the zone the
  # metadata times carry, so comparisons do not warn about mixed zones
  if (inherits(since, "POSIXct") && length(since) == 1 && !is.na(since)) {
    return(as_utc(since))
  }
  if (inherits(since, "Date") && length(since) == 1 && !is.na(since)) {
    return(as_utc(as.POSIXct(format(since), tz = tz)))
  }
  if (rlang::is_string(since)) {
    parsed <- tryCatch(as.POSIXct(since, tz = tz), error = function(e) NA)
    if (!is.na(parsed)) {
      return(as_utc(parsed))
    }
  }
  cli::cli_abort(
    c(
      "{.arg {arg}} must be a single {.cls POSIXct}, a {.cls Date} or a date string such as {.val 2025-08-24}.",
      "x" = "Got {.obj_type_friendly {since}}."
    ),
    call = call,
    class = "jatosr_bad_argument"
  )
}

as_utc <- function(x) {
  attr(x, "tzone") <- "UTC"
  x
}

check_tz <- function(tz, arg = rlang::caller_arg(tz), call = rlang::caller_env()) {
  check_string(tz, arg = arg, call = call)
  if (!tz %in% c("UTC", "GMT", OlsonNames())) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a time zone name known to this system, got {.val {tz}}.",
        "i" = "See {.fn OlsonNames}; {.code Sys.timezone()} gives the local one."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  invisible(tz)
}

#' Widen the URL query parameters into columns
#'
#' The `url_query` column of a metadata tibble holds, per study result, the
#' query parameters the worker arrived with, which for a Prolific study link
#' are `PROLIFIC_PID`, `STUDY_ID` and `SESSION_ID`. This turns them into one
#' character column per parameter, named in snake case with `prefix` in
#' front (`query_prolific_pid`, `query_study_id`, `query_session_id`), so
#' that the tibble joins to a Prolific export without unnesting. Study
#' results without a parameter get `NA`; a tibble without any parameter is
#' returned unchanged. Two parameters that differ only in case or
#' separators (`PROLIFIC_PID` and `prolific_pid`) would share a column
#' name; the second gets a numeric suffix and a warning names both keys.
#'
#' @param metadata A metadata tibble with a `url_query` list column.
#' @param prefix Prefix of the new column names. The default keeps
#'   `STUDY_ID` from colliding with the `study_id` column.
#'
#' @return `metadata` with one column per parameter appended; `url_query` stays.
#' @export
#' @examples
#' meta <- jatos_flatten_metadata(
#'   system.file("extdata", "metadata.json", package = "jatosr")
#' )
#' jatos_url_query(meta)[, c("study_result_id", "query_prolific_pid", "query_session_id")]
jatos_url_query <- function(metadata, prefix = "query_") {
  check_metadata(metadata, needs = "url_query", contract = FALSE)
  if (!rlang::is_string(prefix) || is.na(prefix)) {
    cli::cli_abort("{.arg prefix} must be a single string.", class = "jatosr_bad_argument")
  }
  params <- purrr::map(metadata$url_query, function(q) if (is.list(q) || is.character(q)) as.list(q) else list())
  keys <- unique(unlist(purrr::map(params, names)))
  keys <- keys[!is.na(keys) & nzchar(keys)]
  if (length(keys) == 0) {
    return(metadata)
  }
  base <- paste0(prefix, snake_case(keys))
  cols <- make.unique(base, sep = "_")
  warn_query_collisions(keys, base, cols)
  clash <- intersect(cols, names(metadata))
  if (length(clash) > 0) {
    cli::cli_abort(c(
      "{.arg metadata} already has the column{?s} {.field {clash}}.",
      "i" = "{cli::qty(length(clash))}Choose another {.arg prefix}, or drop {?it/them} first."
    ), class = "jatosr_bad_argument")
  }
  for (j in seq_along(keys)) {
    key <- keys[[j]]
    metadata[[cols[[j]]]] <- purrr::map_chr(params, function(q) {
      value <- q[[key]]
      if (is.null(value) || length(value) == 0) {
        NA_character_
      } else {
        paste(as.character(unlist(value)), collapse = ",")
      }
    })
  }
  metadata
}

# Two query keys that snake-case to one column name (`PROLIFIC_PID` and
# `prolific_pid`) are told apart by make.unique()'s suffix only; say which
# key went where, since the suffix follows the order of appearance.
warn_query_collisions <- function(keys, base, cols) {
  shared <- unique(base[duplicated(base)])
  if (length(shared) == 0) {
    return(invisible(NULL))
  }
  lines <- vapply(shared, function(b) {
    at <- which(base == b)
    cli::format_inline("{.val {keys[at]}} became {.field {cols[at]}}")
  }, character(1))
  cli::cli_warn(c(
    "{length(shared)} column name{?s} {?is/are} shared by query parameters that differ only in case or separators.",
    rlang::set_names(lines, rep("i", length(lines))),
    "i" = "The suffix follows the order in which the keys first appear."
  ))
}
