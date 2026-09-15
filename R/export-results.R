#' Fetch, read and save the trials of a study in one call
#'
#' Runs the whole pipeline: [jatos_results_metadata()] for the ids given,
#' [jatos_filter_metadata()] with `states`, `worker_types`, `since`,
#' `until` and the two exclusion lists,
#' [jatos_download_results()] into `cache`, [jatos_url_query()],
#' [jatos_extract_fields()] when `fields` is given, [jatos_read_results()]
#' with the metadata joined, and [jatos_write_results()] to `file`. Nothing
#' happens here that those functions do not do on their own; run them
#' separately when a step needs an argument this wrapper does not pass on
#' (`chunk_size` of the download, `flatten` of the reader). `reader`,
#' `split`, `coerce` and `on_error` go to the reader as they are; with
#' `on_error = "skip"` a file the reader cannot read is left out of the
#' trials with a warning, and the final message and the provenance count
#' only the files that were read. Files that
#' participants uploaded are not part of a trials dataset; fetch them with
#' [jatos_download_files()].
#'
#' With `download = FALSE` the same dataset is built from the cache alone:
#' the metadata comes from the cache's `metadata.json` files through
#' [jatos_read_metadata()] (restricted to `study_id` and `batch_id` when
#' given, the whole cache otherwise), no request is made and no connection
#' is needed, and the provenance record says `offline: true` and lists the
#' metadata files with their modification times. That is the path for an
#' analysis machine without credentials, for CI, or for rebuilding a
#' dataset after the study left the server; rows whose data file is not in
#' the cache are skipped with a message, as [jatos_read_results()] does.
#' `archive_study` needs the server and is refused offline.
#'
#' Three files come out of one call, one more each with `archive_study =
#' TRUE` and `archive_results = TRUE`. The trials file holds one row per
#' trial with the ids, `batch_id`, `component_id`, `worker_id`,
#' `worker_type`, `study_state`, `study_start_time`, the URL query
#' parameters as `query_*` columns and the extracted `fields` in front of
#' the trial columns. The metadata file (`<stem>_metadata.<ext>` by default)
#' holds one row per study result from [jatos_study_results()],
#' which is where exclusions, payments and the participant count of a
#' methods section come from; it covers the same study results as the
#' trials file. The provenance file (`<stem>_export.json`) records host,
#' ids, filters, package version, time and the counts of the export.
#'
#' Run it again later and only new or grown results are downloaded; the
#' files are then rewritten from the whole cache, which is why `overwrite`
#' exists. `file`, `format`, the target directory, the sidecar paths and
#' `fields` are checked before the first request, so a mistake there costs
#' no download; every path the call will write (with `split = "component"`
#' the part files, whose names come from the component ids of the
#' metadata) is checked once more right after the metadata answer, before
#' the download. A component result whose download failed, or that the
#' server's answer did not contain, stops the export before anything is
#' written, since the dataset would be incomplete; the files fetched so far
#' stay in the cache for the next run.
#'
#' @inheritParams jatos_results_metadata
#' @inheritParams jatos_filter_metadata
#' @inheritParams jatos_read_results
#' @param study_id,batch_id One or more ids to select results by; at least
#'   one of the two must be given for a download. Passed to
#'   [jatos_results_metadata()]; `study_id` may also be one or more uuid
#'   strings. With `download = FALSE` both may be `NULL`, which exports the
#'   whole cache.
#' @param ... Must be empty.
#' @param cache The local cache directory, see [jatos_download_results()].
#' @param file Path of the trials file to write, see [jatos_write_results()].
#'   Its directory must exist.
#' @param download If `FALSE`, nothing is requested: the metadata is read
#'   from the cache and the dataset is built from the files already there.
#' @param fields JSON keys to extract with [jatos_extract_fields()] and
#'   join to every trial row. For values that do not sit at the top level
#'   of the trial objects, for example inside a survey response; a field
#'   that already is a trial column is reported as a clash by
#'   [jatos_read_results()].
#' @param metadata_cols Metadata columns joined to every trial row after
#'   the ids, see [jatos_read_results()]; the `query_*` columns and the
#'   extracted `fields` are added to whatever is given here. `NULL` joins
#'   only those.
#' @param format Format of the trials file, passed to
#'   [jatos_write_results()]; `NULL` infers it from the extension of
#'   `file`. The default metadata file shares it; a metadata file given as
#'   a path takes its format from its own extension.
#' @param split `"none"` writes one trials file. `"component"` reads and
#'   writes one file per component id (`<stem>_component_<id>.<ext>`), see
#'   [jatos_read_results()]; the metadata file is written once.
#' @param metadata_file `TRUE` writes the study-result table next to `file`
#'   as `<stem>_metadata.<ext>`; a path writes it there, in the format of
#'   that path's extension (a `.csv` next to an `.rds` trials file is
#'   fine); `FALSE` skips it.
#' @param provenance If `TRUE`, write `<stem>_export.json` with the host,
#'   profile, ids, filters, fields, cache, package version, time, counts and
#'   the paths written.
#' @param archive_study If `TRUE`, the study archive is downloaded with
#'   [jatos_export_study()] and written next to the dataset: as
#'   `<stem>_study.jzip` for the one study named in `study_id`, as
#'   `<stem>_study_<id>.jzip` per study when several are named or when only
#'   `batch_id` is given and the studies come from the metadata. The
#'   archive records the experiment that produced the data; the provenance
#'   record lists it.
#' @param archive_results If `TRUE`, the results archive that the server
#'   builds for the same ids (`POST /results`: every `data.txt`, the
#'   uploaded files and the `metadata.json`, see [jatos_export_archive()])
#'   is written next to the dataset as `<stem>_results.zip`, and the
#'   provenance record lists it with its size and md5 checksum. An
#'   archival copy, fetched in full each time; the incremental download
#'   into `cache` is unchanged.
#' @param overwrite Passed to [jatos_write_results()] for every file
#'   written. The download keeps its own guard for local files larger than
#'   the server's copy.
#' @param conn A [jatos_connection()]; not used with `download = FALSE`.
#'
#' @return The trials tibble, invisibly (with `split = "component"` a named
#'   list of tibbles); a message reports the row count and the paths
#'   written.
#' @seealso [jatos_filter_metadata()], [jatos_url_query()],
#'   [jatos_study_results()] for the pieces this adds to the five steps.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' trials <- jatos_export_results(
#'   study_id = 12, cache = "JATOS_data", file = "data/study12.rds",
#'   states = "FINISHED"
#' )
#'
#' # one batch, as csv, without the researcher's own GUI runs, with a field
#' # that sits inside a survey response
#' jatos_export_results(
#'   batch_id = 34, cache = "JATOS_data", file = "data/batch34.csv",
#'   worker_types = c("PersonalSingle", "GeneralMultiple"),
#'   fields = "age", overwrite = TRUE
#' )
#'
#' # the same dataset from the cache alone, without credentials
#' jatos_export_results(
#'   study_id = 12, cache = "JATOS_data", file = "data/study12.rds",
#'   states = "FINISHED", download = FALSE, overwrite = TRUE
#' )
#' }
jatos_export_results <- function(study_id = NULL,
                                 batch_id = NULL,
                                 ...,
                                 cache,
                                 file,
                                 download = TRUE,
                                 fields = NULL,
                                 states = NULL,
                                 worker_types = NULL,
                                 since = NULL,
                                 until = NULL,
                                 exclude_study_result_id = NULL,
                                 exclude_worker_id = NULL,
                                 tz = "UTC",
                                 reader = NULL,
                                 coerce = c("error", "character"),
                                 on_error = c("abort", "skip"),
                                 metadata_cols = default_metadata_cols(),
                                 format = NULL,
                                 split = c("none", "component"),
                                 metadata_file = TRUE,
                                 provenance = TRUE,
                                 archive_study = FALSE,
                                 archive_results = FALSE,
                                 overwrite = FALSE,
                                 conn = jatos_connection()) {
  # ---- phase 1: the arguments, and every path the call may write ----
  rlang::check_dots_empty()
  check_string(cache)
  check_flag(download)
  split <- rlang::arg_match(split)
  coerce <- rlang::arg_match(coerce)
  on_error <- rlang::arg_match(on_error)
  check_flag(provenance)
  check_flag(archive_study)
  check_flag(archive_results)
  if (archive_study && !download) {
    cli::cli_abort("{.arg archive_study} needs the server; it cannot be combined with {.code download = FALSE}.", class = "jatosr_bad_argument")
  }
  if (archive_results && !download) {
    cli::cli_abort("{.arg archive_results} needs the server; it cannot be combined with {.code download = FALSE}.", class = "jatosr_bad_argument")
  }
  format <- check_write_target(file, format, overwrite, check_existing = FALSE)
  if (!is.null(fields)) {
    check_fields(fields)
  }
  check_column_names(states, allow_null = TRUE, what = "study states")
  check_column_names(worker_types, allow_null = TRUE, what = "worker types")
  tz <- check_tz(tz)
  since <- check_since(since, tz)
  until <- check_since(until, tz)
  exclude_study_result_id <- check_ids(exclude_study_result_id, allow_null = TRUE)
  exclude_worker_id <- check_ids(exclude_worker_id, allow_null = TRUE)
  if (!is.null(reader)) {
    check_reader(reader)
  }
  check_column_names(metadata_cols, allow_null = TRUE)
  sidecar <- resolve_metadata_file(file, metadata_file, format)
  provenance_path <- if (provenance) provenance_file_name(file) else NULL
  # the archives of named studies are known now; those of a batch-only
  # export only once the metadata says which studies it holds
  archive_ids <- if (archive_study && !is.null(study_id)) study_id else NULL
  archive_paths <- if (!is.null(archive_ids)) study_archive_names(file, archive_ids) else NULL
  results_archive <- if (archive_results) results_archive_name(file) else NULL
  # what can be checked before the first request
  refuse_existing(
    export_targets(file, split, NULL, sidecar$path, provenance_path, c(archive_paths, results_archive)),
    overwrite
  )
  check_cache_layout(cache, arg = "cache")

  # ---- phase 2: the metadata, from the server or from the cache ----
  started <- Sys.time()
  if (!download) {
    # the provenance record reads "offline" from this
    conn <- NULL
  }
  got <- acquire_metadata(download, study_id, batch_id, cache, conn)
  metadata <- got$metadata
  source <- got$source
  if (archive_study && is.null(archive_ids)) {
    archive_ids <- unique(metadata$study_id)
    archive_paths <- study_archive_names(file, archive_ids, named = FALSE)
  }

  # ---- phase 3: filter, then the targets again with the component ids known ----
  metadata <- jatos_filter_metadata(
    metadata,
    states = states, worker_types = worker_types, since = since, until = until,
    exclude_study_result_id = exclude_study_result_id, exclude_worker_id = exclude_worker_id, tz = tz
  )
  # every path the call will write, now that the component ids are known
  refuse_existing(
    export_targets(file, split, unique(metadata$component_id), sidecar$path, provenance_path, c(archive_paths, results_archive)),
    overwrite
  )
  # ---- phase 4: download, and insist that it is complete ----
  if (download) {
    metadata <- jatos_download_results(metadata, cache, conn = conn)
    check_download_complete(metadata$status, cache)
  }

  # ---- phase 5: the query columns and the extracted fields join the trials ----
  before <- names(metadata)
  metadata <- jatos_url_query(metadata)
  join_cols <- c(metadata_cols, setdiff(names(metadata), before))
  if (!is.null(fields)) {
    metadata <- jatos_extract_fields(metadata, fields)
    join_cols <- c(join_cols, fields)
  }

  # ---- phase 6: read ----
  read <- read_export_trials(metadata, join_cols, reader, split, coerce, on_error)
  trials <- read$trials
  n_read <- read$n_read

  # ---- phase 7: write ----
  # the archives come before the data files: an archive the token may not
  # fetch (viewer role) then stops the export with nothing else written
  for (k in seq_along(archive_ids)) {
    jatos_export_study(archive_ids[[k]], archive_paths[[k]], overwrite = overwrite, conn = conn)
  }
  if (!is.null(results_archive)) {
    jatos_export_archive(study_id = study_id, batch_id = batch_id, file = results_archive, overwrite = overwrite, conn = conn)
  }
  written <- write_export_trials(trials, file, split, format, overwrite)
  paths <- written$paths
  n_trials <- written$n_trials
  if (!is.null(sidecar)) {
    # the query columns are already on `metadata` and ride along as extras
    jatos_write_results(
      jatos_study_results(metadata), sidecar$path,
      format = sidecar$format, object = "metadata", overwrite = overwrite
    )
  }
  if (!is.null(provenance_path)) {
    write_provenance(
      provenance_path,
      conn = conn, study_id = study_id, batch_id = batch_id,
      filters = list(
        states = states, worker_types = worker_types,
        since = format_utc(since), until = format_utc(until),
        exclude_study_result_id = exclude_study_result_id, exclude_worker_id = exclude_worker_id,
        tz = if (!is.null(since) || !is.null(until)) tz
      ),
      fields = fields,
      cache = cache, started = started, source = source,
      exported = list(
        study_results = length(unique(metadata$study_result_id)),
        component_results = nrow(metadata),
        files_read = n_read,
        trials = n_trials
      ),
      paths = paths, metadata_path = sidecar$path, archive_paths = archive_paths,
      results_archive = results_archive
    )
  }

  sidecars <- c(sidecar$path, provenance_path, archive_paths, results_archive)
  cli::cli_inform(c(
    "v" = "Wrote {n_trials} trial{?s} from {n_read} component result{?s} to {.path {paths}}.",
    if (length(sidecars) > 0) c("i" = "Also wrote {.path {sidecars}}.")
  ))
  invisible(trials)
}

# Phase 2 of the export: the metadata from the server, or from the cache
# when `download = FALSE`, with the record of where it came from that the
# provenance file keeps.
acquire_metadata <- function(download, study_id, batch_id, cache, conn, call = rlang::caller_env()) {
  if (download) {
    check_connection(conn, call = call)
    metadata <- jatos_results_metadata(study_id = study_id, batch_id = batch_id, conn = conn)
    source <- list(
      on_server = list(
        study_results = length(unique(metadata$study_result_id)),
        component_results = nrow(metadata)
      )
    )
  } else {
    metadata <- offline_metadata(cache, study_id, batch_id)
    source <- list(
      in_cache = list(
        study_results = length(unique(metadata$study_result_id)),
        component_results = nrow(metadata),
        metadata_files = cache_metadata_record(cache)
      )
    )
  }
  list(metadata = metadata, source = source)
}

# Phase 6 of the export: the trials, and the number of files actually read,
# which under `on_error = "skip"` is smaller than the number listed.
read_export_trials <- function(metadata, join_cols, reader, split, coerce, on_error) {
  n_files <- sum(!is.na(metadata$file))
  cli::cli_inform(c("i" = "Reading {n_files} file{?s}."))
  n_skipped <- 0L
  trials <- withCallingHandlers(
    jatos_read_results(
      metadata,
      metadata_cols = join_cols, reader = reader, split = split,
      coerce = coerce, on_error = on_error
    ),
    # the warning goes on to the user; the count is what the record needs
    jatosr_files_skipped = function(cnd) n_skipped <<- length(cnd$files)
  )
  list(trials = trials, n_read = n_files - n_skipped)
}

# Phase 7 of the export, the trials: one file, or one per component. Returns
# the paths written and the number of trials.
write_export_trials <- function(trials, file, split, format, overwrite) {
  if (split == "component") {
    paths <- component_file_names(file, names(trials))
    n_trials <- sum(vapply(trials, nrow, integer(1)))
  } else {
    paths <- file
    n_trials <- nrow(trials)
  }
  cli::cli_inform(c("i" = "Writing {n_trials} trial{?s} to {.path {paths}}."))
  if (split == "component") {
    # a loop, so that a writer error reaches the user without an "In index" wrapper
    for (k in seq_along(trials)) {
      jatos_write_results(trials[[k]], paths[[k]], format = format, overwrite = overwrite)
    }
  } else {
    jatos_write_results(trials, file, format = format, overwrite = overwrite)
  }
  list(paths = paths, n_trials = n_trials)
}

# The cache's own metadata, restricted the way the server would restrict
# an answer: the union of what `study_id` (ids or uuids) and `batch_id`
# select, everything when both are NULL.
offline_metadata <- function(cache, study_id, batch_id, call = rlang::caller_env()) {
  study <- check_ids_or_uuids(study_id, arg = "study_id", call = call)
  batch <- check_ids(batch_id, arg = "batch_id", call = call, allow_null = TRUE)
  meta <- jatos_read_metadata(cache)
  if (is.null(study_id) && is.null(batch)) {
    keep <- rep(TRUE, nrow(meta))
  } else {
    keep <- rep(FALSE, nrow(meta))
    if (!is.null(study$ids)) {
      keep <- keep | meta$study_id %in% study$ids
    }
    if (!is.null(study$uuids)) {
      keep <- keep | meta$study_uuid %in% study$uuids
    }
    if (!is.null(batch)) {
      keep <- keep | meta$batch_id %in% batch
    }
  }
  meta <- meta[keep, , drop = FALSE]
  n_study_results <- length(unique(meta$study_result_id))
  n_component_results <- nrow(meta)
  cli::cli_inform(c(
    "i" = "{.path {cache}}: {n_study_results} study result{?s}, {n_component_results} component result{?s} in the cached metadata; no request made."
  ))
  meta
}

# The metadata.json files an offline export was built from, with their
# modification times, for the provenance record.
cache_metadata_record <- function(cache) {
  files <- list_metadata_files(cache)
  purrr::map(files, function(f) {
    list(
      file = normalizePath(f, mustWork = FALSE),
      modified = format_utc(file.mtime(f))
    )
  })
}

# Every path an export writes: the trials file, or with `split =
# "component"` one part per component id (known once the metadata is in;
# `component_ids = NULL` before that), then the sidecars. One
# `refuse_existing()` over this vector is the guard.
export_targets <- function(file, split, component_ids = NULL, metadata_path = NULL,
                           provenance_path = NULL, archive_paths = NULL) {
  trials <- if (split == "none") {
    file
  } else if (!is.null(component_ids)) {
    component_file_names(file, component_ids)
  } else {
    character()
  }
  c(trials, metadata_path, provenance_path, archive_paths)
}

# `metadata_file` is TRUE (default path and the trials format), FALSE (none)
# or a path, whose own extension decides its format.
resolve_metadata_file <- function(file, metadata_file, format, call = rlang::caller_env()) {
  if (isFALSE(metadata_file)) {
    return(NULL)
  }
  if (isTRUE(metadata_file)) {
    return(list(path = metadata_file_name(file), format = format))
  }
  if (rlang::is_string(metadata_file) && nzchar(metadata_file)) {
    own <- check_write_target(metadata_file, NULL, overwrite = TRUE, check_existing = FALSE, call = call)
    return(list(path = metadata_file, format = own))
  }
  cli::cli_abort(
    "{.arg metadata_file} must be {.code TRUE}, {.code FALSE} or a file path.",
    call = call,
    class = "jatosr_bad_argument"
  )
}

# A dataset is written only when every planned component result arrived:
# `failed` rows (a request failed) and `missing` rows (requested, not in the
# server's answer) both stop the export.
check_download_complete <- function(status, cache, call = rlang::caller_env()) {
  n_failed <- sum(status == "failed")
  n_missing <- sum(status == "missing")
  n <- n_failed + n_missing
  if (n == 0) {
    return(invisible(NULL))
  }
  cli::cli_abort(
    c(
      "{n} component result{?s} could not be downloaded ({n_failed} failed, {n_missing} missing from the server's answer), so the dataset would be incomplete.",
      "i" = "Nothing was written. The files fetched so far are in {.path {cache}}; run the call again."
    ),
    call = call,
    class = "jatosr_incomplete_download"
  )
}

# What produced the files: enough to redo or cite the export. `conn` is
# NULL for an offline export, which records `offline: true` and the cached
# metadata files instead of host and profile.
write_provenance <- function(path, conn, study_id, batch_id, filters,
                             fields, cache, started, source, exported, paths,
                             metadata_path, archive_paths = NULL, results_archive = NULL) {
  record <- list(
    package = "jatosr",
    version = as.character(utils::packageVersion("jatosr")),
    exported_at = format_utc(started),
    offline = if (is.null(conn)) TRUE,
    host = conn$host,
    profile = conn$profile,
    study_id = study_id,
    batch_id = batch_id,
    filters = filters,
    fields = fields,
    cache = normalizePath(cache, mustWork = FALSE),
    counts = c(source, list(exported = exported)),
    files = list(
      trials = paths, metadata = metadata_path, study_archive = archive_paths,
      results_archive = if (!is.null(results_archive)) archive_record(results_archive)
    )
  )
  record$filters <- drop_null(record$filters)
  record$files <- drop_null(record$files)
  record <- drop_null(record)
  jsonlite::write_json(record, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
  invisible(path)
}

# A time as ISO 8601 in UTC for the provenance record; NULL stays NULL.
format_utc <- function(x) {
  if (is.null(x)) NULL else format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}
