#' Rebuild result metadata from a local cache
#'
#' Reads the `metadata.json` files that `jatos_download_results()` stores in
#' `<path>/batch_<id>/` and returns the same tibble that
#' [jatos_results_metadata()] returned when they were fetched, plus two
#' columns describing the data file on disk. No network is needed, so a
#' pipeline can be replayed offline. Each batch is read once, from its own
#' `batch_<id>/metadata.json`; a directory in another layout (a
#' `metadata.json` at the top level, `JATOS_DATA_<id>` folders) is refused,
#' see [jatos_download_results()].
#'
#' @param path The cache directory, one `batch_<id>` directory inside it, or
#'   the path of a single `metadata.json` file.
#' @param batch_id Optional ids to keep only some batches.
#'
#' @return A metadata tibble as documented in [jatos_flatten_metadata()],
#'   with `file` (path of the local `data.txt`, `NA` when it has not been
#'   downloaded) and `file_size` (its size in bytes, `NA` when absent).
#' @seealso [jatos_cache_status()] for a per-batch summary of the same cache.
#' @export
#' @examples
#' cache <- system.file("extdata", "JATOS_data", package = "jatosr")
#' meta <- jatos_read_metadata(cache)
#' meta[, c("study_result_id", "component_result_id", "data_size", "file_size")]
#' meta[is.na(meta$file) & meta$data_size > 0, ]   # still to download: none
jatos_read_metadata <- function(path, batch_id = NULL) {
  check_string(path)
  batch_id <- check_ids(batch_id, allow_null = TRUE)
  files <- cache_metadata_files(path)
  meta <- purrr::map(files, function(file) {
    one <- jatos_flatten_metadata(file)
    attach_local_files(one, batch_dir = dirname(file))
  }) |>
    purrr::list_rbind()
  if (!is.null(batch_id)) {
    meta <- meta[meta$batch_id %in% batch_id, ]
  }
  meta
}

#' Summarise a local cache batch by batch
#'
#' Reads every `metadata.json` of a cache, as [jatos_read_metadata()] does,
#' and reports per batch how many component results it lists, how many are
#' on disk, how many a run of [jatos_download_results()] would fetch, and
#' how many `data.txt` files sit in the batch directory without a metadata
#' row (orphans, counted inside that batch directory only; a fresh download
#' of the batch's metadata covers them). No request is made.
#'
#' @inheritParams jatos_read_metadata
#'
#' @return A tibble with one row per `metadata.json`: `batch_id` (`NA` when
#'   the file holds several batches), `path` (its directory), `n_results`
#'   (component results listed), `n_downloaded` (with a local file),
#'   `n_pending` (server size above `0` and no local file, or a local file
#'   smaller than the server's), `n_shrunk` (local file larger than the
#'   server's), `n_orphans` (data files without a metadata row) and `bytes`
#'   (size of the local data files). With `batch_id`, the counts cover the
#'   rows of those batches and a `metadata.json` without any of them is left
#'   out; `n_orphans` still compares the directory with every row of its
#'   `metadata.json`, so the files of another batch listed there are not
#'   orphans.
#' @export
#' @examples
#' cache <- system.file("extdata", "JATOS_data", package = "jatosr")
#' jatos_cache_status(cache)
#' jatos_cache_status(cache, batch_id = 34)
jatos_cache_status <- function(path, batch_id = NULL) {
  check_string(path)
  batch_id <- check_ids(batch_id, allow_null = TRUE)
  files <- cache_metadata_files(path)
  rows <- purrr::map(files, cache_status_one, batch_id = batch_id)
  rows <- purrr::compact(rows)
  if (length(rows) == 0) {
    return(empty_cache_status())
  }
  purrr::list_rbind(rows)
}

cache_status_one <- function(file, batch_id = NULL) {
  dir <- dirname(file)
  meta <- attach_local_files(jatos_flatten_metadata(file), batch_dir = dir)
  # orphans against every row of the file, before any batch is dropped
  on_disk <- list_data_files(dir)
  listed <- normalizePath(meta$file[!is.na(meta$file)], mustWork = FALSE)
  n_orphans <- length(setdiff(normalizePath(on_disk, mustWork = FALSE), listed))
  empty <- nrow(meta) == 0
  if (!is.null(batch_id)) {
    meta <- meta[meta$batch_id %in% batch_id, , drop = FALSE]
  }
  ids <- unique(meta$batch_id)
  if (empty && grepl(batch_dir_pattern, basename(dir))) {
    ids <- as.integer(sub(batch_dir_pattern, "\\1", basename(dir)))
  }
  # a batch filter drops a file with none of its rows, or an empty batch
  # directory whose id is not asked for
  if (!is.null(batch_id) && (if (empty) !any(ids %in% batch_id) else nrow(meta) == 0)) {
    return(NULL)
  }
  has_file <- !is.na(meta$file)
  # the same rule a download applies: pending is what it would fetch
  plan <- plan_fetch(server = meta$data_size, local = meta$file_size)
  tibble::tibble(
    batch_id = if (length(ids) == 1) ids else NA_integer_,
    path = dir,
    n_results = nrow(meta),
    n_downloaded = sum(has_file),
    n_pending = sum(plan$fetch),
    n_shrunk = sum(plan$status == "shrunk", na.rm = TRUE),
    n_orphans = n_orphans,
    bytes = sum(meta$file_size[has_file])
  )
}

empty_cache_status <- function() {
  tibble::tibble(
    batch_id = integer(), path = character(), n_results = integer(),
    n_downloaded = integer(), n_pending = integer(), n_shrunk = integer(),
    n_orphans = integer(), bytes = numeric()
  )
}

# The metadata.json files a cache path stands for (the cache root, one
# batch directory, or the file itself), or an error naming what was
# expected there.
cache_metadata_files <- function(path, call = rlang::caller_env()) {
  check_path_exists(path, call = call)
  if (!dir.exists(path)) {
    return(path)
  }
  if (grepl(batch_dir_pattern, basename(path)) && file.exists(metadata_file(path))) {
    return(metadata_file(path))
  }
  check_cache_layout(path, call = call)
  files <- list_metadata_files(path)
  if (length(files) == 0) {
    cli::cli_abort(
      c(
        "No metadata.json found under {.path {path}}.",
        "i" = "Expected {.path batch_<id>/metadata.json} directories as written by {.fn jatos_download_results}."
      ),
      call = call,
      class = "jatosr_cache_layout"
    )
  }
  files
}

# `file` and `file_size` of every row from the paths where its file would
# be: the path and its byte size when the file exists, NA otherwise.
# Shared by the data download, the file download and the cache reader.
attach_local <- function(x, expected) {
  if (nrow(x) == 0) {
    x$file <- character()
    x$file_size <- numeric()
    return(x)
  }
  exists <- file.exists(expected)
  x$file <- ifelse(exists, expected, NA_character_)
  x$file_size <- ifelse(exists, file.size(expected), NA_real_)
  x
}

attach_local_files <- function(meta, batch_dir) {
  attach_local(meta, local_data_path(batch_dir, meta$study_result_id, meta$component_result_id))
}
