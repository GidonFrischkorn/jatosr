#' Download result data into a local cache
#'
#' Fetches the `data.txt` of each component result in `metadata` that is not
#' yet on disk, or that has grown on the server, and stores it under
#' `<path>/batch_<batch_id>/study_result_<id>/comp-result_<id>/data.txt`. The
#' comparison is in raw bytes on both sides: `data_size` from the metadata
#' against `file.size()` of the local file. Component results are requested
#' from `POST /results/data` in chunks of `chunk_size` ids, one zip per
#' chunk, with a progress bar over the chunks, and every batch that received
#' data gets a fresh `metadata.json` afterwards (one `POST /results/metadata`
#' per batch) so that [jatos_read_metadata()] can rebuild the tibble offline
#' later. That `batch_<id>/` layout is the only one the package reads or
#' writes: a directory holding a `metadata.json` at its top level or
#' `JATOS_DATA_<id>` folders (what smartr left behind) is refused, since the
#' server is the source of truth and the data is downloaded again into a
#' fresh directory; a zip exported from the JATOS GUI is imported with
#' [jatos_import_results()].
#'
#' The incremental rule is asymmetric:
#'
#' * server size `0`: nothing is requested, status `empty`, whether or not
#'   a 0-byte local file exists (a larger local file makes it `shrunk`, see
#'   below);
#' * no local file and server size above `0`, or server larger than local:
#'   fetched, status `fetched`;
#' * equal sizes above `0`: status `unchanged`, no request;
#' * server *smaller* than local: the local file stays, status `shrunk`,
#'   because it may be the last copy of that participant's data. Only
#'   `overwrite = TRUE` replaces it.
#'
#' A row that was requested but not part of the server's answer has status
#' `missing` and a warning names it. A request that fails (a transport
#' error, an HTTP error, an answer that is not a zip file, or a zip that
#' cannot be unpacked in full) does not stop
#' the run: its rows get status `failed`, the remaining chunks are fetched,
#' and one warning at the end reports the count and the first error. After
#' a `401` or `403` no further request is made, since every one of them
#' would fail the same way. Files are written to a temporary name inside
#' the batch directory and renamed into place, so a partial download never
#' sits under the real name.
#'
#' Files that participants uploaded during a run (drawings, recordings) are
#' not part of the result data; [jatos_download_files()] fetches them with
#' the same rule, file by file.
#'
#' @param metadata A metadata tibble from [jatos_results_metadata()]. A
#'   tibble from [jatos_read_metadata()] carries the sizes of the cached
#'   `metadata.json`, so it finds nothing new; fetch fresh metadata first.
#' @param path The cache directory. Created when missing.
#' @param incremental If `FALSE`, every component result with a server size
#'   above `0` is fetched again, except `shrunk` ones unless `overwrite = TRUE`.
#' @param chunk_size Component result ids per request.
#' @param overwrite If `TRUE`, `shrunk` rows are fetched and replaced.
#' @param dry_run If `TRUE`, no request is made and nothing is written: the
#'   rows that a real run would fetch get status `pending`, and a message
#'   per batch reports their count, their size on the server and the number
#'   of requests. `conn` is not needed.
#' @param conn A [jatos_connection()].
#'
#' @return `metadata` with three columns added (replaced when present):
#'   `file` (path of the local `data.txt`, `NA` when absent after the run),
#'   `file_size` (its size in bytes, `NA` when absent) and `status` (one of
#'   `fetched`, `unchanged`, `empty`, `shrunk`, `missing`, `failed`, or
#'   `pending` in a dry run).
#' @seealso [jatos_read_metadata()] to rebuild the metadata from the cache,
#'   [jatos_cache_status()] to summarise it, [jatos_read_results()] to read
#'   the downloaded files, [jatos_download_files()] for uploaded files.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' meta <- jatos_results_metadata(study_id = 12)
#' jatos_download_results(meta, "JATOS_data", dry_run = TRUE)   # what would be fetched
#' meta <- jatos_download_results(meta, "JATOS_data")
#' table(meta$status)
#' }
jatos_download_results <- function(metadata,
                                   path,
                                   incremental = TRUE,
                                   chunk_size = 50,
                                   overwrite = FALSE,
                                   dry_run = FALSE,
                                   conn = jatos_connection()) {
  check_metadata(metadata)
  download_planned(
    metadata, path,
    server = metadata$data_size,
    locate = function(dirs) local_data_path(dirs, metadata$study_result_id, metadata$component_result_id),
    fetch_one = fetch_chunk,
    unit = "component result",
    labels = metadata$component_result_id,
    incremental = incremental, chunk_size = chunk_size, overwrite = overwrite,
    dry_run = dry_run, conn = conn
  )
}

# The download shared by result data and uploaded files: argument checks,
# the cache layout, the plan against the local files (`locate(dirs)` gives
# the expected path of every row), the dry run, the loop, and the
# closing report. `fetch_one(rows, batch_dir, conn)` makes one request for
# a chunk; `labels` names rows in messages; `keys` groups rows into chunks.
download_planned <- function(x, path, server, locate, fetch_one, unit, labels,
                             incremental, chunk_size, overwrite, dry_run, conn,
                             keys = seq_len(nrow(x))) {
  check_string(path)
  check_flag(incremental)
  check_flag(overwrite)
  check_flag(dry_run)
  chunk_size <- check_count(chunk_size)
  check_cache_layout(path)
  if (!dry_run) {
    check_connection(conn)
    if (!dir.exists(path)) {
      dir.create(path, recursive = TRUE)
    }
  }

  dirs <- batch_dir(path, x$batch_id)
  local <- attach_local(x, locate(dirs))
  plan <- plan_fetch(server = server, local = local$file_size, incremental = incremental, overwrite = overwrite)
  out <- local
  out$status <- plan$status
  out$status[plan$fetch] <- "pending"
  if (dry_run) {
    report_plan(plan$fetch, x$batch_id, server, chunk_size, unit = unit, keys = keys)
    return(out)
  }

  fetch <- function(rows, batch_dir) fetch_one(x[rows, ], batch_dir, conn = conn)
  run <- run_download(
    fetch = plan$fetch, batch_ids = x$batch_id, batch_dirs = dirs,
    chunk_size = chunk_size, fetch_fun = fetch, conn = conn, unit = unit, keys = keys
  )
  out$status[plan$fetch] <- run$status
  out <- attach_local(out, locate(dirs))
  report_download(out$status, labels, run, unit = unit)
  out
}

# The incremental rule, the one copy: `server` and `local` are byte counts
# (NA local = no file). `status` holds the final status of every row that
# needs no request (`empty`, `shrunk`, `unchanged`) and NA where a request
# is needed; `fetch` is that NA.
plan_fetch <- function(server, local, incremental = TRUE, overwrite = FALSE) {
  server[is.na(server)] <- 0
  has_file <- !is.na(local)
  shrunk <- has_file & server < local
  status <- rep(NA_character_, length(server))
  if (incremental) {
    status[has_file & server == local] <- "unchanged"
  }
  status[shrunk & !(overwrite & server > 0)] <- "shrunk"
  # Server size 0 is never requested, whatever is on disk: a 0-byte local
  # file (an imported archive keeps one) is `empty`, not `unchanged` and
  # not a request that comes back `missing`; a larger local file stayed
  # `shrunk` above, with or without `overwrite`, since there is nothing to
  # fetch in its place.
  status[server == 0 & !shrunk] <- "empty"
  list(fetch = is.na(status), status = status)
}

# Rows to fetch, grouped by batch and split into chunks of at most
# `chunk_size` distinct `keys` (row indices by default, so one row is one
# key; the file download keys on the component result, so that the files of
# one result stay in one request).
chunk_rows <- function(fetch, batch_ids, chunk_size, keys = seq_along(fetch)) {
  batches <- unique(batch_ids[fetch])
  chunks <- purrr::map(batches, function(batch_id) {
    rows <- which(fetch & batch_ids == batch_id)
    k <- keys[rows]
    group <- match(k, unique(k))
    split(rows, ceiling(group / chunk_size))
  })
  list(batches = batches, chunks = chunks)
}

# The dry-run report: one line per batch with rows, bytes and requests.
report_plan <- function(fetch, batch_ids, sizes, chunk_size, unit, keys = seq_along(fetch)) {
  planned <- chunk_rows(fetch, batch_ids, chunk_size, keys = keys)
  if (length(planned$batches) == 0) {
    cli::cli_inform(c("i" = "Nothing to fetch; every {unit} with data is on disk."))
    return(invisible(NULL))
  }
  for (b in seq_along(planned$batches)) {
    batch_id <- planned$batches[[b]]
    rows <- unlist(planned$chunks[[b]], use.names = FALSE)
    n_rows <- length(rows)
    bytes <- format_bytes(sum(sizes[rows], na.rm = TRUE))
    n_requests <- length(planned$chunks[[b]])
    # `{unit}` is a string, so the count is restated before each `{?s}`
    cli::cli_inform(c(
      "i" = "Batch {batch_id}: {n_rows} {unit}{cli::qty(n_rows)}{?s} ({bytes}) to fetch in {n_requests} request{?s}."
    ))
  }
  invisible(NULL)
}

# The download loop shared by data and files: batch by batch, chunk by
# chunk, with a progress bar. `fetch_fun(rows, batch_dir)` makes one request
# for the row indices given and returns a logical per row (in the answer or
# not). A failed chunk marks its rows `failed` and the run goes on; after a
# 401 or 403 the loops stop and every row not yet requested is `failed`.
# Every batch with at least one successful chunk gets its metadata.json
# refreshed afterwards. Returns the status of the rows marked in `fetch`,
# in their order, plus the failures.
run_download <- function(fetch, batch_ids, batch_dirs, chunk_size, fetch_fun, conn, unit,
                         keys = seq_along(fetch)) {
  planned <- chunk_rows(fetch, batch_ids, chunk_size, keys = keys)
  status <- rep(NA_character_, length(fetch))
  failures <- list()
  halted <- FALSE
  n_chunks <- sum(lengths(planned$chunks))
  if (n_chunks > 0) {
    cli::cli_progress_bar(paste("Downloading", if (unit == "file") "result files" else "result data"), total = n_chunks)
  }
  for (b in seq_along(planned$batches)) {
    if (halted) {
      break
    }
    batch_id <- planned$batches[[b]]
    batch_dir <- batch_dirs[[match(batch_id, batch_ids)]]
    n_rows <- sum(lengths(planned$chunks[[b]]))
    n_fetched <- 0L
    n_ok <- 0L
    n_failed <- 0L
    for (chunk in planned$chunks[[b]]) {
      got <- tryCatch(fetch_fun(chunk, batch_dir), error = function(cnd) cnd)
      if (rlang::is_condition(got)) {
        failures <- c(failures, list(got))
        status[chunk] <- "failed"
        n_failed <- n_failed + 1L
        halted <- inherits(got, c("httr2_http_401", "httr2_http_403"))
      } else {
        status[chunk] <- ifelse(got, "fetched", "missing")
        n_fetched <- n_fetched + sum(got)
        n_ok <- n_ok + 1L
      }
      cli::cli_progress_update()
      if (halted) {
        break
      }
    }
    if (n_ok > 0) {
      refresh_batch_metadata(batch_id, batch_dir, conn)
    }
    failed_note <- if (n_failed > 0) " ({n_failed} request{?s} failed)" else ""
    cli::cli_inform(c(
      "v" = paste0(
        "Batch {batch_id}: fetched {n_fetched} of {n_rows} {unit}{cli::qty(n_rows)}{?s} in {n_ok + n_failed} request{?s}",
        failed_note, "."
      )
    ))
  }
  if (n_chunks > 0) {
    cli::cli_progress_done()
  }
  # rows planned but never requested (after a halt) failed as well
  status[fetch & is.na(status)] <- "failed"
  list(status = status[fetch], failures = failures, halted = halted)
}

# The closing warnings: rows the server did not answer, and failed chunks.
report_download <- function(status, ids, run, unit) {
  missing <- ids[status == "missing"]
  if (length(missing) > 0) {
    n_missing <- length(missing)
    label <- if (unit == "file") "File" else "Component result id"
    cli::cli_warn(c(
      "{n_missing} requested {unit}{cli::qty(n_missing)}{?s} {?was/were} not in the server's answer.",
      "i" = "{label}{cli::qty(n_missing)}{?s}: {missing}. Status is {.code missing}."
    ))
  }
  failures <- run$failures
  if (length(failures) > 0) {
    n_failed_rows <- sum(status == "failed")
    reason <- conditionMessage(failures[[1]])
    advice <- if (run$halted) {
      "No request was made after the authentication error; run the call again once the token works."
    } else {
      "Run the call again to retry them; fetched files are kept."
    }
    cli::cli_warn(c(
      "{n_failed_rows} {unit}{cli::qty(n_failed_rows)}{?s} could not be fetched ({length(failures)} failed request{?s}); status is {.code failed}.",
      "x" = "First error: {reason}",
      "i" = advice
    ))
  }
  invisible(NULL)
}

# One POST /results/data for the rows given; only the data.txt of the
# requested component results are moved into place. An entry counts only
# under its full `study_result_<sr>/comp-result_<cr>/data.txt` suffix, so an
# uploaded file named `data.txt` under `files/` is never taken for result
# data. Returns a logical per row: was its data.txt in the answer?
fetch_chunk <- function(rows, batch_dir, conn) {
  fetch_entries(
    c("results", "data"), rows, batch_dir, conn,
    pattern = data_entry_pattern,
    key_cols = c("study_result_id", "component_result_id")
  )
}

# The request shared by result data and uploaded files: one POST to a
# zip-returning endpoint for the component results of `rows`, of whose
# answer only the entries keyed like one of the rows (`key_cols`) are moved
# into place. Returns a logical per row: was its entry in the answer?
fetch_entries <- function(endpoint, rows, batch_dir, conn, pattern, key_cols) {
  entry_key <- function(x) do.call(paste, unname(as.list(x[key_cols])))
  wanted <- entry_key(rows)
  entries <- fetch_zip_entries(
    endpoint, unique(rows$component_result_id), batch_dir, conn,
    pattern = pattern,
    keep = function(entries) entry_key(entries) %in% wanted
  )
  wanted %in% entry_key(entries)
}

# POST one of the zip-returning results endpoints with component result ids
# in the body, unpack the answer into a staging directory inside `batch_dir`
# and move the entries that match `pattern` (see match_entries()) and pass
# `keep`, a function of the matched entries returning a logical per row,
# into place. Returns the entries moved.
fetch_zip_entries <- function(endpoint, ids, batch_dir, conn, pattern, keep) {
  zip <- tempfile("results-", fileext = ".zip")
  on.exit(unlink(zip), add = TRUE)
  resp <- jatos_req(conn, endpoint, accept = "application/zip") |>
    httr2::req_body_json(list(componentResultIds = I(ids))) |>
    perform_file(path = zip)
  route <- paste0("POST /", paste(endpoint, collapse = "/"))
  check_zip_answer(zip, resp, route)

  if (!dir.exists(batch_dir)) {
    dir.create(batch_dir, recursive = TRUE)
  }
  # a staging directory that a killed run left behind is never read again
  # (the reader looks for data.txt under study_result_ folders only); swept
  # here so the batch directory does not collect them
  unlink(list.files(batch_dir, pattern = "^\\.staging-", all.files = TRUE, full.names = TRUE), recursive = TRUE)
  staging <- tempfile(".staging-", tmpdir = batch_dir)
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  unpacked <- unzip_to_staging(
    zip, staging,
    subject = cli::format_inline("The zip that {.code {route}} answered with"),
    advice = "The rows of this request are retried by the next call."
  )

  entries <- match_entries(unpacked$rel, pattern)
  entries <- entries[keep(entries), , drop = FALSE]
  place_entries(unpacked$paths[entries$index], entry_targets(entries, batch_dir))
  entries
}

# Unpack a zip into `staging` (unzip_answer() says what counts as a failure)
# and list what came out: the extracted paths, and the same paths relative
# to `staging` for matching.
unzip_to_staging <- function(zip, staging, subject, advice, call = rlang::caller_env()) {
  unzip_answer(zip, staging, subject = subject, advice = advice, call = call)
  paths <- list.files(staging, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  list(paths = paths, rel = substring(paths, nchar(staging) + 2))
}

# The entries among `rel` that match one of the two cache-layout patterns,
# located by their suffix so a top-level folder in the zip does not matter.
# One row per match: its index into `rel`, the ids read from the path and,
# for a file entry, the file name (NA for a data file).
match_entries <- function(rel, pattern) {
  m <- regmatches(rel, regexec(pattern, rel))
  matched <- which(lengths(m) > 1)
  group <- function(k) vapply(m[matched], function(e) if (length(e) > k) e[[k + 1]] else NA_character_, character(1))
  data.frame(
    index = matched,
    study_result_id = as.integer(group(2)),
    component_result_id = as.integer(group(3)),
    filename = group(4),
    stringsAsFactors = FALSE
  )
}

# Where each matched entry belongs: the data file or the uploaded file of
# its component result under `batch_dir` (one directory, or one per entry).
entry_targets <- function(entries, batch_dir) {
  # load-bearing: batch_dir(path, integer(0)) is one path, not none
  if (nrow(entries) == 0) {
    return(character())
  }
  ifelse(
    is.na(entries$filename),
    local_data_path(batch_dir, entries$study_result_id, entries$component_result_id),
    local_file_path(batch_dir, entries$study_result_id, entries$component_result_id, entries$filename)
  )
}

# Move unpacked entries to their targets, creating the directories.
place_entries <- function(sources, targets) {
  for (k in seq_along(sources)) {
    dir.create(dirname(targets[[k]]), recursive = TRUE, showWarnings = FALSE)
    move_file(sources[[k]], targets[[k]])
  }
  invisible(targets)
}

# A 200 whose body is not a zip (a JSON error envelope, an HTML page) would
# otherwise unzip to nothing and report every row as `missing`.
check_zip_answer <- function(zip, resp, route, call = rlang::caller_env()) {
  if (is_zip_file(zip)) {
    return(invisible(TRUE))
  }
  type <- httr2::resp_content_type(resp)
  preview <- file_preview(zip)
  cli::cli_abort(
    c(
      "The server did not answer {.code {route}} with a zip file.",
      "i" = "Content type {.val {type}}; the body begins with: {preview}"
    ),
    call = call,
    class = "jatosr_zip_unreadable"
  )
}

is_zip_file <- function(path) {
  size <- file.size(path)
  !is.na(size) && size >= 4 && identical(readBin(path, "raw", n = 2), charToRaw("PK"))
}

# The entry names of a zip that would leave the directory it is unpacked
# into: a `..` component (with either separator) or an absolute name. They
# come from the archive, so they are scrubbed before they reach a message.
# A zip whose listing fails is left to the extraction, which reports it.
zip_escaping_entries <- function(zip) {
  names <- tryCatch(
    suppressWarnings(utils::unzip(zip, list = TRUE)$Name),
    error = function(cnd) character()
  )
  parent <- purrr::map_lgl(strsplit(names, "[/\\\\]"), function(parts) any(parts == ".."))
  absolute <- grepl("^([/\\\\]|[A-Za-z]:)", names)
  scrub_secrets(names[parent | absolute])
}

# An archive without entries is its end-of-central-directory record alone.
is_empty_zip <- function(path) {
  identical(readBin(path, "raw", n = 4), as.raw(c(0x50, 0x4b, 0x05, 0x06)))
}

# Unpack a zip the server answered with, or abort. `utils::unzip()` reports
# a truncated or corrupt archive (one that still starts with `PK`) with a
# warning and an empty return, which left every requested row `missing`
# ("not in the server's answer") instead of `failed` with the advice to run
# the call again. That warning is therefore the failure of this request.
# An entry whose name leaves `exdir` (a `..` component, an absolute name) is
# refused before anything is extracted: R's own unzip skips a `../` entry
# only from R 4.5.1 on and writes it outside `exdir` before that, and no
# answer of the server holds one. An archive that unpacks without a warning
# and yields no file (directory entries only, or no entries at all) is a
# valid answer that holds nothing for the rows asked for: they are
# `missing`, and a retry would get the same archive. `subject` names the
# archive in the message (already formatted), `advice` says what to do.
# Returns the extracted paths invisibly.
unzip_answer <- function(zip, exdir, subject, advice, call = rlang::caller_env()) {
  escaping <- zip_escaping_entries(zip)
  if (length(escaping) > 0) {
    n <- length(escaping)
    cli::cli_abort(
      c(
        "{subject} could not be unpacked.",
        "x" = "{n} entr{?y/ies} would leave the target directory: {.path {escaping}}.",
        "i" = "Nothing from the archive was written; no answer of a JATOS server holds such an entry."
      ),
      class = "jatosr_zip_unreadable",
      call = call
    )
  }
  warned <- NULL
  extracted <- withCallingHandlers(
    utils::unzip(zip, exdir = exdir),
    warning = function(w) {
      warned <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )
  # an archive without entries makes R's unzip warn as well ("error 1"),
  # and is the server's answer for ids it has nothing for
  if (is_empty_zip(zip)) {
    return(invisible(character()))
  }
  if (is.null(warned)) {
    return(invisible(extracted))
  }
  size <- format_bytes(file.size(zip))
  cli::cli_abort(
    c(
      "{subject} could not be unpacked.",
      "x" = "{warned}",
      "i" = "The archive has {size}; a download cut short looks like this. {advice}"
    ),
    class = "jatosr_zip_unreadable",
    call = call
  )
}

# The first bytes of a file as printable text, for an error message.
file_preview <- function(path, n = 200) {
  size <- file.size(path)
  if (is.na(size) || size == 0) {
    return("<empty body>")
  }
  bytes <- readBin(path, "raw", n = min(n, size))
  text <- rawToChar(bytes[bytes != as.raw(0)])
  text <- iconv(text, "UTF-8", "UTF-8", sub = "?")
  gsub("\\s+", " ", trimws(text))
}

# Rename within one file system; copy-and-delete is the fallback (a cache
# on another volume than the staging directory cannot happen, since staging
# lives inside the batch directory, but a rename can still fail on some
# network shares). The rename goes through rename_file() so that the tests
# can stand in for it and reach the fallback.
move_file <- function(from, to) {
  ok <- rename_file(from, to)
  if (!ok) {
    ok <- file.copy(from, to, overwrite = TRUE)
    if (!ok) {
      cli::cli_abort("Could not write {.path {to}}.")
    }
    unlink(from)
  }
  invisible(to)
}

rename_file <- function(from, to) {
  suppressWarnings(file.rename(from, to))
}

# The batch's metadata.json after its files were written. A failure is a
# warning, not an error: the files are in place, and the next call
# refreshes the file again.
refresh_batch_metadata <- function(batch_id, batch_dir, conn) {
  refresh <- tryCatch(write_batch_metadata(batch_id, batch_dir, conn), error = function(cnd) cnd)
  if (rlang::is_condition(refresh)) {
    reason <- conditionMessage(refresh)
    cli::cli_warn(c(
      "The {.path metadata.json} of batch {batch_id} could not be refreshed; the files were written.",
      "x" = "{reason}"
    ))
  }
  invisible(NULL)
}

# The server's own answer for the batch, stored byte for byte so the cached
# file is what POST /results/metadata returned, not a re-serialisation.
write_batch_metadata <- function(batch_id, batch_dir, conn) {
  if (!dir.exists(batch_dir)) {
    dir.create(batch_dir, recursive = TRUE)
  }
  write_atomically(metadata_file(batch_dir), function(tmp) {
    jatos_req(conn, "results/metadata") |>
      jatos_query(download = "false") |>
      httr2::req_body_json(list(batchIds = I(batch_id))) |>
      perform_file(path = tmp)
  })
}

# Write through a temporary name in the target directory and rename into
# place, so a partial file never sits under the real name. `fn(tmp)` does
# the writing; its value is returned.
write_atomically <- function(path, fn) {
  tmp <- tempfile(paste0(".", basename(path), "-"), tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  value <- fn(tmp)
  move_file(tmp, path)
  invisible(value)
}
