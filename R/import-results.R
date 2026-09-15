#' Import a JATOS results zip into the cache
#'
#' Unpacks a zip that JATOS itself produced, from the GUI's "Export Results"
#' or from [jatos_export_archive()], into the cache layout that
#' [jatos_download_results()] writes: `metadata.json` at the zip root and
#' `study_result_<id>/comp-result_<id>/data.txt` (plus `files/<name>` for
#' uploads) become `<path>/batch_<id>/metadata.json` and
#' `<path>/batch_<id>/study_result_<id>/comp-result_<id>/...`, one batch
#' folder per batch id in the zip's `metadata.json`, each with a
#' `metadata.json` holding only that batch's study results. This is the
#' one way data that did not come through the package enters a cache; the
#' reader, [jatos_cache_status()] and later incremental downloads then
#' treat it like any other cache. Entries whose study result the
#' `metadata.json` does not list are left out with a message.
#'
#' A batch folder that already exists in `path` is refused unless
#' `overwrite = TRUE`, which replaces its `metadata.json` and every file the
#' zip carries and leaves other files in place.
#'
#' @param zip Path of the zip file.
#' @param path The cache directory. Created when missing; must be empty or
#'   in the package layout.
#' @param overwrite If `TRUE`, files of a batch that is already in the
#'   cache are replaced.
#'
#' @return The metadata tibble of the imported batches as
#'   [jatos_read_metadata()] returns it, invisibly; a message reports the
#'   batches, component results and files imported.
#' @seealso [jatos_export_archive()] to fetch such a zip from the server,
#'   [jatos_read_metadata()] and [jatos_export_results()] with
#'   `download = FALSE` to work from the cache.
#' @export
#' @examples
#' zip <- system.file("extdata", "results.zip", package = "jatosr")
#'
#' cache <- tempfile("jatosr-example-")
#' jatos_import_results(zip, cache)
#' jatos_cache_status(cache)
#' unlink(cache, recursive = TRUE)
jatos_import_results <- function(zip, path, overwrite = FALSE) {
  check_string(zip)
  check_string(path)
  check_flag(overwrite)
  check_path_exists(zip)
  if (!is_zip_file(zip)) {
    cli::cli_abort("{.path {zip}} is not a zip file.", class = "jatosr_zip_unreadable")
  }
  check_cache_layout(path)

  staging <- tempfile("import-")
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  # the same unpacking as a downloaded chunk: a zip cut short on its way
  # from the GUI would otherwise read as "holds no metadata.json"
  unpacked <- unzip_to_staging(
    zip, staging,
    subject = cli::format_inline("{.path {zip}}"),
    advice = "Export the results from the server again."
  )
  rel <- unpacked$rel

  root_metadata <- find_root_metadata(rel, zip)
  parsed <- jsonlite::read_json(unpacked$paths[[root_metadata]], simplifyVector = FALSE)
  meta <- jatos_flatten_metadata(parsed)
  if (nrow(meta) == 0) {
    cli::cli_abort("The {.path metadata.json} in {.path {zip}} lists no component result.", class = "jatosr_bad_metadata")
  }
  without_batch <- sum(is.na(meta$batch_id))
  if (without_batch > 0) {
    cli::cli_abort(c(
      "The {.path metadata.json} in {.path {zip}} lists {without_batch} component result{?s} without a batch id.",
      "i" = "The cache is laid out by batch; a results zip from the JATOS GUI or {.fn jatos_export_archive} names one per study result."
    ), class = "jatosr_bad_metadata")
  }
  batch_of <- unique(meta[, c("study_result_id", "batch_id")])
  batches <- sort(unique(batch_of$batch_id))

  # what the zip holds, data files and uploaded files, with the batch its
  # study result belongs to (NA when the metadata does not list it)
  entries <- purrr::list_rbind(list(
    match_entries(rel, data_entry_pattern),
    match_entries(rel, file_entry_pattern)
  ))
  entries$batch_id <- batch_of$batch_id[match(entries$study_result_id, batch_of$study_result_id)]
  n_unknown <- sum(is.na(entries$batch_id))
  entries <- entries[!is.na(entries$batch_id), , drop = FALSE]

  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }
  dirs <- batch_dir(path, batches)
  existing <- dirs[dir.exists(dirs)]
  if (length(existing) > 0 && !overwrite) {
    cli::cli_abort(c(
      "{cli::qty(length(existing))}The batch folder{?s} {.path {existing}} already exist{?s/}.",
      "i" = "{cli::qty(length(existing))}Set {.code overwrite = TRUE} to replace {?its/their} files with the zip's."
    ), class = "jatosr_file_exists")
  }

  for (b in seq_along(batches)) {
    dir.create(dirs[[b]], showWarnings = FALSE, recursive = TRUE)
    write_atomically(metadata_file(dirs[[b]]), function(tmp) {
      write_metadata_subset(parsed, batches[[b]], tmp)
    })
  }
  place_entries(
    unpacked$paths[entries$index],
    entry_targets(entries, batch_dir(path, entries$batch_id))
  )

  out <- jatos_read_metadata(path, batch_id = batches)
  n_data <- sum(is.na(entries$filename))
  n_uploads <- sum(!is.na(entries$filename))
  cli::cli_inform(c(
    "v" = "Imported {cli::qty(length(batches))}batch{?es} {batches} into {.path {path}}: {nrow(out)} component result{?s} listed, {n_data} data file{?s} and {n_uploads} uploaded file{?s} written.",
    if (n_unknown > 0) c("i" = "{n_unknown} entr{?y/ies} of the zip belong{?s/} to no study result in its {.path metadata.json} and {?was/were} left out.")
  ))
  invisible(out)
}

# The one metadata.json at the root of the zip (or, when the zip wraps
# everything in one folder, at the shallowest level).
find_root_metadata <- function(rel, zip, call = rlang::caller_env()) {
  candidates <- which(basename(rel) == "metadata.json")
  if (length(candidates) == 0) {
    cli::cli_abort(
      c(
        "{.path {zip}} holds no {.path metadata.json}.",
        "i" = "A results zip from the JATOS GUI (\"Export Results\") or from {.fn jatos_export_archive} has one at its root."
      ),
      call = call,
      class = "jatosr_bad_metadata"
    )
  }
  depth <- lengths(strsplit(rel[candidates], "/", fixed = TRUE))
  top <- candidates[depth == min(depth)]
  if (length(top) > 1) {
    cli::cli_abort(
      c(
        "{.path {zip}} holds {length(top)} {.path metadata.json} files at the same level.",
        "i" = "Import one results zip at a time."
      ),
      call = call,
      class = "jatosr_bad_metadata"
    )
  }
  top
}

# The root metadata.json reduced to one batch: studies keep only the study
# results of that batch, studies left without one are dropped. Written the
# way jsonlite read it (null stays null, numbers keep their digits).
write_metadata_subset <- function(parsed, batch_id, file) {
  studies <- metadata_studies(parsed)
  studies <- lapply(studies, function(study) {
    study$studyResults <- Filter(
      function(sr) identical(as.integer(sr$batchId), as.integer(batch_id)),
      study$studyResults %||% list()
    )
    study
  })
  studies <- Filter(function(study) length(study$studyResults) > 0, studies)
  envelope <- list(apiVersion = parsed$apiVersion %||% "1.1.0", data = studies)
  jsonlite::write_json(envelope, file, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE)
  invisible(file)
}
