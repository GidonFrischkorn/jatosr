#' Copy the raw result files, one per participant
#'
#' Copies every local `data.txt` of a metadata tibble byte for byte to
#' `<path>/<name>.json`, named by a column of the metadata (the study result
#' id by default, or `worker_id`, `query_prolific_pid`, or a field from
#' [jatos_extract_fields()]), which is the layout labs share raw JSON in.
#' Nothing is parsed or rewritten. A study result with several files (one
#' per component) gets `<name>_<component_result_id>.json` for each. When
#' two different study results share a name, for example a participant who
#' ran twice, nothing is written and the error lists the name and the study
#' result ids, so that duplicates are resolved on purpose rather than
#' silently. Each copy is written under a temporary name in `path` and
#' renamed into place, so a copy that fails never sits under the real
#' name.
#'
#' @param metadata A metadata tibble with the `file` column, from
#'   [jatos_download_results()] or [jatos_read_metadata()]. Rows without a
#'   local file are left out with a message.
#' @param path Directory to write into; created when missing.
#' @param name_by Name of the metadata column whose value names each file.
#'   `NA` values are refused, and so is a value that could leave `path`:
#'   one holding a slash or a backslash, or equal to `.` or `..`. The
#'   values may come from the participants themselves (a Prolific id in
#'   the URL, a field of the result data), so they are never trusted as
#'   paths.
#' @param overwrite If `TRUE`, existing files in `path` are replaced.
#'
#' @return A tibble with `study_result_id`, `component_result_id`, `file`
#'   (the source) and `path` (the copy), invisibly; a message reports the
#'   count.
#' @seealso [jatos_export_archive()] for the server's own zip of the same
#'   files.
#' @export
#' @examples
#' cache <- system.file("extdata", "JATOS_data", package = "jatosr")
#' meta <- jatos_read_metadata(cache)
#'
#' out <- tempfile("jatosr-example-")
#' jatos_write_raw(meta, out, name_by = "worker_id")
#' list.files(out)
#' unlink(out, recursive = TRUE)
jatos_write_raw <- function(metadata, path, name_by = "study_result_id", overwrite = FALSE) {
  check_string(path)
  check_string(name_by)
  check_flag(overwrite)
  check_metadata(metadata, needs = c("file", name_by), contract = FALSE)
  check_metadata(metadata, needs = c("study_result_id", "component_result_id"), contract = FALSE)

  have <- !is.na(metadata$file)
  if (any(!have)) {
    cli::cli_inform(c("i" = "{sum(!have)} row{?s} {?has/have} no local file."))
  }
  rows <- metadata[have, , drop = FALSE]
  names <- raw_file_names(rows, name_by)
  paths <- file.path(path, paste0(names, ".json", recycle0 = TRUE))

  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }
  refuse_existing(paths, overwrite)
  # through a temporary name in `path`, like every other writer, so a copy
  # that fails halfway never leaves a truncated file under the real name
  call <- rlang::current_env()
  for (k in seq_along(paths)) {
    write_atomically(paths[[k]], function(tmp) {
      ok <- file.copy(rows$file[[k]], tmp, overwrite = TRUE)
      if (!ok) {
        cli::cli_abort("Could not write {.path {paths[[k]]}}.", call = call)
      }
    })
  }
  n <- length(paths)
  cli::cli_inform(c("v" = "Wrote {n} file{?s} to {.path {path}}."))
  invisible(tibble::tibble(
    study_result_id = rows$study_result_id,
    component_result_id = rows$component_result_id,
    file = rows$file,
    path = paths
  ))
}

# One name per row: the `name_by` value, suffixed with the component result
# id where one study result has several files; a name shared by different
# study results is an error.
raw_file_names <- function(rows, name_by, call = rlang::caller_env()) {
  values <- rows[[name_by]]
  if (is.list(values)) {
    cli::cli_abort("{.arg name_by} must name an atomic column, not the list column {.field {name_by}}.", call = call, class = "jatosr_bad_argument")
  }
  missing <- which(is.na(values))
  if (length(missing) > 0) {
    ids <- rows$component_result_id[missing]
    cli::cli_abort(
      c(
        "{.field {name_by}} is {.code NA} for {length(missing)} row{?s} with a file.",
        "i" = "{cli::qty(length(ids))}Component result id{?s}: {ids}. Drop {cli::qty(length(ids))}{?that row/those rows} or choose another {.arg name_by}."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  values <- as.character(values)
  # A value is a file name, never a path: a separator or a dot name would
  # place the file outside `path` (seen with `../../escaped`, 2026-09-14).
  unsafe <- which(grepl("[/\\\\]", values) | values %in% c(".", ".."))
  if (length(unsafe) > 0) {
    ids <- rows$component_result_id[unsafe]
    cli::cli_abort(
      c(
        "{.field {name_by}} holds a slash, a backslash, {.code .} or {.code ..} in {length(unsafe)} row{?s} with a file, which would name a path outside {.arg path}.",
        "i" = "{cli::qty(length(ids))}Component result id{?s}: {ids}. Clean {cli::qty(length(ids))}{?that value/those values} or choose another {.arg name_by}."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  names <- values
  for (value in unique(values[duplicated(values)])) {
    at <- which(values == value)
    study_results <- unique(rows$study_result_id[at])
    if (length(study_results) > 1) {
      cli::cli_abort(
        c(
          "The name {.val {value}} ({.field {name_by}}) belongs to {length(study_results)} study results, so their files would collide.",
          "i" = "Study result ids: {study_results}. Name by another column, or drop the duplicate runs first."
        ),
        call = call,
        class = "jatosr_bad_argument"
      )
    }
    names[at] <- paste0(value, "_", rows$component_result_id[at])
  }
  names
}
