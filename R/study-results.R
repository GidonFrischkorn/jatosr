#' One row per study result
#'
#' Collapses a metadata tibble (one row per component result) to one row
#' per study result, which is the unit that means "one run by one
#' participant". Counts of people, duplicate detection and quality flags
#' belong at this level; a participant who reloaded a component has several
#' component results but one study result.
#'
#' Columns that are not part of the metadata contract (for example
#' `participant_id` added by `jatos_extract_fields()`, or a column you
#' joined yourself) are carried over with their first non-`NA` value per
#' study result. When the component results of one study result disagree
#' on such a column, the value becomes `NA`, the column name is listed in
#' `conflicts`, and a warning names the study results concerned. The
#' `<field>_status` columns of [jatos_extract_fields()] (recorded in the
#' `jatosr_extracted` attribute) and the local `file`, `file_size` and
#' `status` columns are left out.
#'
#' Prolific returners and reloaded links produce several study results per
#' person. When a participant key is available, `n_runs` counts the study
#' results per key value, so duplicates are visible before N is counted:
#' `participant` names the column (a `query_*` column from
#' [jatos_url_query()], a field from [jatos_extract_fields()], or
#' `worker_id`); with `participant = NULL` the column `query_prolific_pid`
#' is used when present, and `n_runs` is left out otherwise. A message
#' reports how many keys have more than one run.
#'
#' @param metadata A metadata tibble from [jatos_results_metadata()],
#'   [jatos_read_metadata()] or [jatos_flatten_metadata()].
#' @param participant Name of the column that identifies a participant,
#'   for `n_runs`; `NULL` uses `query_prolific_pid` when present.
#'
#' @return A tibble with the study and study-result columns of `metadata`,
#'   plus `n_component_results`, `n_components` (distinct component ids),
#'   `n_finished` (component results in state `FINISHED`), `data_size`
#'   (bytes, summed), `n_files`, `first_component_start`,
#'   `last_component_end`, `n_runs` (when a participant key is available;
#'   `NA` where the key is `NA`), any extra columns of `metadata`, and
#'   `conflicts` (list of column names; only present when `metadata` has
#'   extra columns).
#' @export
#' @examples
#' meta <- jatos_flatten_metadata(
#'   system.file("extdata", "metadata.json", package = "jatosr")
#' )
#' jatos_study_results(meta)[, c("study_result_id", "n_component_results", "data_size")]
#' jatos_study_results(meta, participant = "worker_id")[, c("study_result_id", "worker_id", "n_runs")]
jatos_study_results <- function(metadata, participant = NULL) {
  check_metadata(metadata)
  if (!is.null(participant)) {
    check_string(participant)
    check_metadata(metadata, needs = participant, contract = FALSE)
  }
  study_cols <- intersect(metadata_study_columns(), names(metadata))
  extra <- setdiff(names(metadata), c(metadata_columns(), metadata_local_columns(metadata)))
  key <- participant %||% intersect("query_prolific_pid", names(metadata))
  if (length(key) == 1 && !key %in% c(study_cols, extra)) {
    cli::cli_abort(c(
      "{.arg participant} must name a study-result column or a column joined per study result, not {.field {key}}.",
      "i" = "Columns such as {.field file} or {.field status} vary per component result and cannot identify a participant."
    ), class = "jatosr_bad_argument")
  }

  out <- collapse_study_results(metadata, study_cols, extra)
  out <- add_n_runs(out, key)

  if (length(extra) > 0) {
    n_conflicts <- lengths(out$conflicts)
    if (any(n_conflicts > 0)) {
      cols <- unique(unlist(out$conflicts))
      ids <- out$study_result_id[n_conflicts > 0]
      cli::cli_warn(c(
        "{sum(n_conflicts > 0)} study result{?s} ha{?s/ve} component results that disagree on {.field {cols}}.",
        "i" = "{cli::qty(length(ids))}Study result id{?s}: {ids}. The value is {.code NA} there; see the {.field conflicts} column."
      ))
    }
  }
  out
}

# Study results per participant key, after `last_component_end`; nothing
# when there is no key.
add_n_runs <- function(out, key) {
  if (length(key) != 1) {
    return(out)
  }
  values <- out[[key]]
  if (is.list(values)) {
    cli::cli_abort("{.arg participant} must name an atomic column, not the list column {.field {key}}.", class = "jatosr_bad_argument")
  }
  n_runs <- rep(NA_integer_, nrow(out))
  known <- !is.na(values)
  counts <- table(as.character(values[known]))
  n_runs[known] <- as.integer(counts[as.character(values[known])])
  out <- tibble::add_column(out, n_runs = n_runs, .after = "last_component_end")
  n_dup <- sum(counts > 1)
  if (n_dup > 0) {
    cli::cli_inform(c(
      "i" = "{n_dup} value{?s} of {.field {key}} {?has/have} more than one study result; see {.field n_runs}."
    ))
  }
  out
}

# Columns added by the local-cache, download and extraction functions; per
# component result, so they are neither study columns nor extracted fields.
# The `<field>_status` columns are those of the fields recorded in the
# `jatosr_extracted` attribute, never guessed from a name.
metadata_local_columns <- function(x) {
  fixed <- c("file", "file_size", "status")
  c(fixed, paste0(extracted_fields(x), "_status"))
}

# The collapse, column by column over the groups of rows per study result
# (one tibble per study result took 5.5 s for 9,000 of them). The study
# columns come from each group's first row; every aggregate is one
# vapply() over the group indices; an extra column keeps its first value
# when the group agrees, a typed NA otherwise, with the disagreeing
# columns listed per study result in `conflicts`.
collapse_study_results <- function(x, study_cols, extra) {
  id <- x$study_result_id
  first <- match(unique(id), id)
  groups <- split(seq_len(nrow(x)), factor(id, levels = unique(id)))
  by_group <- function(fun, type) vapply(groups, fun, type, USE.NAMES = FALSE)
  n_files <- x$n_files %||% rep(0L, nrow(x))
  out <- tibble::as_tibble(x[first, study_cols, drop = FALSE])
  out$n_component_results <- unname(lengths(groups))
  out$n_components <- by_group(function(i) length(unique(x$component_id[i])), integer(1))
  out$n_finished <- by_group(function(i) sum(x$component_state[i] == "FINISHED", na.rm = TRUE), integer(1))
  out$data_size <- by_group(function(i) sum(x$data_size[i], na.rm = TRUE), numeric(1))
  out$n_files <- by_group(function(i) sum(n_files[i], na.rm = TRUE), integer(1))
  out$first_component_start <- as_utc_time(by_group(function(i) range_num(x$component_start_time[i], min), numeric(1)))
  out$last_component_end <- as_utc_time(by_group(function(i) range_num(x$component_end_time[i], max), numeric(1)))
  if (length(extra) == 0) {
    return(out)
  }
  conflicts <- rep(list(character()), length(groups))
  for (col in extra) {
    values <- x[[col]]
    pick <- by_group(function(i) {
      v <- values[i]
      known <- i[!is.na(v)]
      distinct <- unique(values[known])
      if (length(distinct) == 1) known[[1]] else NA_integer_
    }, integer(1))
    conflict <- by_group(function(i) {
      v <- values[i]
      length(unique(v[!is.na(v)])) > 1
    }, logical(1))
    out[[col]] <- values[pick]
    conflicts[conflict] <- lapply(conflicts[conflict], c, col)
  }
  out$conflicts <- conflicts
  out
}

# The earliest or latest time of a group as seconds since the epoch, NA
# when the group has none.
range_num <- function(x, fun) {
  x <- as.numeric(x)
  if (all(is.na(x))) NA_real_ else fun(x, na.rm = TRUE)
}

as_utc_time <- function(seconds) {
  as.POSIXct(seconds, origin = "1970-01-01", tz = "UTC")
}
