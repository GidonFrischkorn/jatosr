#' Files uploaded during a run, one row per file
#'
#' Widens the `files` list column of a metadata tibble into one row per
#' attached file, so that what a study's participants uploaded (drawings,
#' audio recordings, anything sent with `jatos.uploadResultFile()`) can be
#' listed, filtered and planned before a download. Component results
#' without files contribute no row.
#'
#' @param metadata A metadata tibble from [jatos_results_metadata()],
#'   [jatos_read_metadata()] or [jatos_flatten_metadata()]. Only its id
#'   columns and `files` are used.
#'
#' @return A tibble with `study_result_id`, `component_result_id`,
#'   `component_id`, `batch_id`, `filename` and `size` (bytes on the server).
#' @seealso [jatos_download_files()] to fetch them.
#' @export
#' @examples
#' meta <- jatos_flatten_metadata(
#'   system.file("extdata", "metadata.json", package = "jatosr")
#' )
#' jatos_result_files(meta)
jatos_result_files <- function(metadata) {
  check_metadata(metadata, needs = result_files_id_columns(), contract = FALSE)
  # every file entry once, with the row it came from repeated by its count
  # (one tibble per row took 6.5 s for 13,500 rows)
  files <- lapply(metadata$files, function(f) if (is.list(f)) f else list())
  entries <- unlist(files, recursive = FALSE)
  rows <- rep(seq_len(nrow(metadata)), lengths(files))
  tibble::tibble(
    study_result_id = as.integer(metadata$study_result_id[rows]),
    component_result_id = as.integer(metadata$component_result_id[rows]),
    component_id = as.integer(metadata$component_id[rows]),
    batch_id = as.integer(metadata$batch_id[rows]),
    filename = vapply(entries, pluck_chr, character(1), "filename"),
    size = vapply(entries, pluck_dbl, numeric(1), "size")
  )
}

result_files_id_columns <- function() {
  c("study_result_id", "component_result_id", "component_id", "batch_id", "files")
}

#' Download the files uploaded during runs into the cache
#'
#' Fetches every file listed by [jatos_result_files()] that is not yet on
#' disk, or that has grown on the server, and stores it next to the result
#' data as
#' `<path>/batch_<batch_id>/study_result_<id>/comp-result_<id>/files/<filename>`,
#' which is the layout the server uses inside its result zips. The rule is
#' the one of [jatos_download_results()], applied per file: a file is
#' fetched when it is missing locally and has a size above `0` on the
#' server, or when the server's copy is larger; equal sizes are
#' `unchanged`; a server copy that is *smaller* than the local file leaves
#' the local file alone with status `shrunk` unless `overwrite = TRUE`. A
#' file whose size the metadata does not give counts as `0`, so it is not
#' fetched, and a warning names it.
#'
#' Files are requested from `POST /results/files` with the component result
#' ids in the body, up to `chunk_size` component results per request (the
#' files of one component result always travel in one request), one zip per
#' chunk, with a progress bar. Only the files that were planned are taken
#' out of a zip. A planned file that the server's answer does not contain
#' has status `missing`; a request that fails marks its files `failed` and
#' the run goes on, with one warning at the end; after a `401` or `403` no
#' further request is made. Every batch that received files gets a fresh
#' `metadata.json`, as in [jatos_download_results()].
#'
#' @param metadata A metadata tibble with the `files` column, from
#'   [jatos_results_metadata()] or [jatos_read_metadata()]. A tibble that
#'   [jatos_result_files()] already widened is not accepted; pass the
#'   metadata.
#' @inheritParams jatos_download_results
#' @param chunk_size Component results per request.
#'
#' @return The tibble of [jatos_result_files()] with `file` (local path,
#'   `NA` when absent after the run), `file_size` (bytes, `NA` when absent)
#'   and `status` (`fetched`, `unchanged`, `empty`, `shrunk`, `missing`,
#'   `failed`, or `pending` in a dry run) added. With `dry_run = TRUE` the
#'   same tibble says, without a request, which files are on disk.
#' @seealso [jatos_result_files()], [jatos_download_results()].
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' meta <- jatos_results_metadata(study_id = 12)
#' jatos_download_files(meta, "JATOS_data", dry_run = TRUE)
#' files <- jatos_download_files(meta, "JATOS_data")
#' files[files$status == "fetched", c("component_result_id", "filename", "file")]
#' }
jatos_download_files <- function(metadata,
                                 path,
                                 incremental = TRUE,
                                 chunk_size = 50,
                                 overwrite = FALSE,
                                 dry_run = FALSE,
                                 conn = jatos_connection()) {
  files <- jatos_result_files(metadata)
  unknown <- is.na(files$size)
  if (any(unknown)) {
    n <- sum(unknown)
    labels <- file_labels(files)[unknown]
    cli::cli_warn(c(
      "{n} file{?s} {?has/have} no size in the metadata and {?is/are} not fetched (status {.code empty}, or {.code shrunk} where a local copy exists).",
      "i" = "{cli::qty(n)}File{?s}: {labels}. Fetch fresh metadata; a file the server cannot size is unusual."
    ))
  }
  download_planned(
    files, path,
    server = files$size,
    locate = function(dirs) local_file_path(dirs, files$study_result_id, files$component_result_id, files$filename),
    fetch_one = fetch_files_chunk,
    unit = "file",
    labels = file_labels(files),
    incremental = incremental, chunk_size = chunk_size, overwrite = overwrite,
    dry_run = dry_run, conn = conn,
    keys = files$component_result_id
  )
}

# How a file is named in messages: its component result and its name.
file_labels <- function(files) {
  paste0(files$component_result_id, "/", files$filename)
}

# One POST /results/files for the component results of the rows given; only
# the planned files are moved into place. Returns a logical per row: was the
# file in the answer?
fetch_files_chunk <- function(rows, batch_dir, conn) {
  fetch_entries(
    c("results", "files"), rows, batch_dir, conn,
    pattern = file_entry_pattern,
    key_cols = c("study_result_id", "component_result_id", "filename")
  )
}
