# The download mock and its request filters live in helper-download.R.

test_that("jatos_download_results unpacks into the cache layout and reports status", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()

  out <- suppressMessages(jatos_download_results(meta, root))

  expect_equal(names(out), c(metadata_columns(), "file", "file_size", "status"))
  expect_equal(out$component_result_id, meta$component_result_id)
  expect_equal(out$status, c("fetched", "empty", "fetched", "empty", "fetched", "fetched"))
  expect_equal(out$file_size, c(2048, NA, 1536, NA, 300, 700))

  expected <- file.path(
    root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt"
  )
  expect_true(file.exists(expected))
  expect_equal(normalizePath(out$file[1]), normalizePath(expected))
  expect_true(file.exists(file.path(root, "batch_36", "study_result_9004", "comp-result_7006", "data.txt")))
  expect_true(is.na(out$file[2]))
  # bytes, not characters: the file holds "Zürich"
  expect_equal(file.size(expected), 2048)
  expect_lt(nchar(read_text_file(expected)), 2048)

  # no staging leftovers, and a metadata.json per touched batch
  expect_false(any(grepl("staging|metadata-", list.files(root, recursive = TRUE, all.files = TRUE))))
  expect_true(file.exists(file.path(root, "batch_34", "metadata.json")))
  expect_true(file.exists(file.path(root, "batch_36", "metadata.json")))

  # one data request per batch, one metadata request per batch
  data_reqs <- data_requests(rec)
  expect_length(data_reqs, 2)
  bodies <- lapply(data_reqs, request_json_body)
  expect_equal(unlist(bodies[[1]]$componentResultIds), c(7001L, 7003L))
  expect_equal(unlist(bodies[[2]]$componentResultIds), c(7005L, 7006L))
  expect_equal(names(bodies[[1]]), "componentResultIds")
  expect_equal(mock_method(data_reqs[[1]]), "POST")
  # the zip endpoint is asked for a zip, the metadata endpoint for JSON
  expect_equal(data_reqs[[1]]$headers$Accept, "application/zip")
  meta_reqs <- metadata_requests(rec)
  expect_length(meta_reqs, 2)
  expect_equal(meta_reqs[[1]]$headers$Accept, "application/json")
  expect_equal(unlist(request_json_body(meta_reqs[[1]])$batchIds), 34L)
  expect_equal(request_query(meta_reqs[[1]])$download, "false")
})

test_that("the per-batch metadata.json replays offline through jatos_read_metadata", {
  local_download_mock()
  root <- withr::local_tempdir()
  suppressMessages(jatos_download_results(fixture_metadata(), root))

  replay <- jatos_read_metadata(root)
  expect_equal(sort(replay$component_result_id), c(7001L, 7002L, 7003L, 7004L, 7005L, 7006L))
  expect_equal(replay$batch_id[replay$component_result_id == 7005L], 36L)
  expect_equal(sum(!is.na(replay$file)), 4)
  expect_equal(replay$file_size[replay$component_result_id == 7003L], 1536)
  # the batch file holds only its batch
  one <- jatos_flatten_metadata(file.path(root, "batch_34", "metadata.json"))
  expect_equal(unique(one$batch_id), 34L)
})

test_that("a second incremental call issues zero requests", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  suppressMessages(jatos_download_results(meta, root))
  n_before <- length(rec$requests)

  out <- expect_silent(jatos_download_results(meta, root))
  expect_length(rec$requests, n_before)
  expect_equal(out$status, c("unchanged", "empty", "unchanged", "empty", "unchanged", "unchanged"))
  expect_equal(out$file_size, c(2048, NA, 1536, NA, 300, 700))
})

test_that("a larger server size triggers exactly one chunk for that row", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  suppressMessages(jatos_download_results(meta, root))
  n_before <- length(rec$requests)

  grown <- meta
  grown$data_size[grown$component_result_id == 7005L] <- 999
  out <- suppressMessages(jatos_download_results(grown, root))
  data_reqs <- data_requests(rec)[-(1:2)]
  expect_length(data_reqs, 1)
  expect_equal(unlist(request_json_body(data_reqs[[1]])$componentResultIds), 7005L)
  expect_length(rec$requests, n_before + 2) # one data chunk, one metadata refresh
  expect_equal(out$status[out$component_result_id == 7005L], "fetched")
  expect_equal(out$status[out$component_result_id == 7006L], "unchanged")
})

test_that("a smaller server size triggers no request and reports shrunk", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  suppressMessages(jatos_download_results(meta, root))
  n_before <- length(rec$requests)
  file <- file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")
  before <- readBin(file, "raw", file.size(file))

  shrunk <- meta
  shrunk$data_size[shrunk$component_result_id == 7001L] <- 100
  out <- expect_silent(jatos_download_results(shrunk, root))
  expect_length(rec$requests, n_before)
  expect_equal(out$status[1], "shrunk")
  expect_equal(out$file_size[1], 2048)
  expect_identical(readBin(file, "raw", file.size(file)), before)

  # a server size of 0 next to a local file is a shrink too, never a request
  shrunk$data_size[shrunk$component_result_id == 7001L] <- 0
  out0 <- expect_silent(jatos_download_results(shrunk, root))
  expect_equal(out0$status[1], "shrunk")
  expect_length(rec$requests, n_before)
})

test_that("a server size of 0 is never requested, whatever sits on disk", {
  # the documented rule, row by row: no file, a 0-byte file, a larger file
  for (incremental in c(TRUE, FALSE)) {
    plan <- plan_fetch(server = c(0, 0, 0, NA, NA), local = c(NA, 0, 10, NA, 0), incremental = incremental)
    expect_equal(plan$status, c("empty", "empty", "shrunk", "empty", "empty"))
    expect_false(any(plan$fetch))
  }
  # overwrite refetches a shrunk row only when the server has something
  plan <- plan_fetch(server = c(0, 5), local = c(10, 10), overwrite = TRUE)
  expect_equal(plan$status, c("shrunk", NA))
  expect_equal(plan$fetch, c(FALSE, TRUE))
  # sizes of 0 and a 0-byte file with incremental = TRUE are not "unchanged"
  expect_equal(plan_fetch(server = 0, local = 0)$status, "empty")

  # end to end: an imported archive leaves a 0-byte data.txt for 7002, whose
  # server size is 0; a full re-download must not request it and must not
  # report it missing (it aborted the export before, 2026-09-14)
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  suppressMessages(jatos_download_results(meta, root))
  empty <- local_data_path(batch_dir(root, meta$batch_id[2]), meta$study_result_id[2], meta$component_result_id[2])
  dir.create(dirname(empty), recursive = TRUE)
  writeBin(raw(), empty)
  n_before <- length(rec$requests)

  out <- suppressMessages(jatos_download_results(meta, root, incremental = FALSE))
  expect_equal(out$status, c("fetched", "empty", "fetched", "empty", "fetched", "fetched"))
  expect_equal(out$file_size[2], 0)
  ids <- unlist(lapply(data_requests(rec)[-(1:2)], function(r) unlist(request_json_body(r)$componentResultIds)))
  expect_false(7002L %in% ids)
  again <- expect_silent(jatos_download_results(meta, root))
  expect_equal(again$status[2], "empty")
  expect_length(rec$requests, n_before + 4)

  # a larger local file next to a server size of 0 stays even with overwrite
  writeBin(charToRaw("kept"), empty)
  out <- expect_silent(jatos_download_results(meta[2, ], root, overwrite = TRUE))
  expect_equal(out$status, "shrunk")
  expect_equal(readLines(empty, warn = FALSE), "kept")
  expect_length(rec$requests, n_before + 4)
  # the cache summary applies the same rule
  status <- jatos_cache_status(root)
  expect_equal(status$n_pending, c(0L, 0L))
  expect_equal(status$n_shrunk, c(1L, 0L))
})

test_that("overwrite = TRUE refetches a shrunk row", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  suppressMessages(jatos_download_results(meta, root))
  # make the local copy larger than the server says
  file <- file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")
  writeBin(charToRaw(strrep("y", 3000)), file)
  n_before <- length(rec$requests)

  out <- suppressMessages(jatos_download_results(meta, root, overwrite = TRUE))
  expect_equal(out$status[1], "fetched")
  expect_equal(file.size(file), 2048)
  data_reqs <- data_requests(rec)[-(1:2)]
  expect_length(data_reqs, 1)
  expect_equal(unlist(request_json_body(data_reqs[[1]])$componentResultIds), 7001L)
})

test_that("ids are split into chunks of chunk_size within a batch", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  make_meta <- function(n) {
    meta <- fixture_metadata()[rep(1, n), ]
    meta$study_result_id <- 100000L + seq_len(n)
    meta$component_result_id <- 200000L + seq_len(n)
    meta
  }
  suppressWarnings(suppressMessages(jatos_download_results(make_meta(50), root)))
  expect_length(data_requests(rec), 1)
  expect_length(request_json_body(data_requests(rec)[[1]])$componentResultIds, 50)

  rec2 <- local_download_mock()
  expect_warning(
    out <- suppressMessages(jatos_download_results(make_meta(51), root)),
    "not in the server's answer"
  )
  reqs <- data_requests(rec2)
  expect_length(reqs, 2)
  expect_length(request_json_body(reqs[[1]])$componentResultIds, 50)
  expect_length(request_json_body(reqs[[2]])$componentResultIds, 1)
  expect_true(all(out$status == "missing"))
  expect_true(all(is.na(out$file)))

  rec3 <- local_download_mock()
  suppressWarnings(suppressMessages(jatos_download_results(make_meta(5), root, chunk_size = 2)))
  expect_length(data_requests(rec3), 3)
})

test_that("a staging directory left by a killed run is swept before the next request", {
  local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  stale <- file.path(batch_dir(root, 34), ".staging-old")
  dir.create(stale, recursive = TRUE)
  writeLines("half a file", file.path(stale, "data.txt"))

  suppressMessages(out <- jatos_download_results(meta, root))
  expect_false(dir.exists(stale))
  expect_false(any(grepl("staging", list.files(root, recursive = TRUE, all.files = TRUE))))
  expect_equal(out$status[1], "fetched")
  expect_equal(jatos_cache_status(root)$n_orphans, c(0L, 0L))
})

test_that("only requested component results are taken from the zip", {
  local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  # the mock answers with the whole fixture zip whatever is asked
  out <- suppressMessages(jatos_download_results(meta[meta$component_result_id == 7005L, ], root))
  expect_equal(out$status, "fetched")
  files <- list.files(root, pattern = "data.txt", recursive = TRUE)
  expect_length(files, 1)
  expect_match(files, "comp-result_7005")
})

test_that("incremental = FALSE fetches every nonzero row but still guards shrunk ones", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  suppressMessages(jatos_download_results(meta, root))
  shrunk <- meta
  shrunk$data_size[shrunk$component_result_id == 7001L] <- 100
  n_before <- length(rec$requests)

  out <- suppressMessages(jatos_download_results(shrunk, root, incremental = FALSE))
  expect_equal(out$status, c("shrunk", "empty", "fetched", "empty", "fetched", "fetched"))
  ids <- unlist(lapply(data_requests(rec)[-(1:2)], function(r) unlist(request_json_body(r)$componentResultIds)))
  expect_equal(sort(ids), c(7003L, 7005L, 7006L))
  expect_length(rec$requests, n_before + 4)
})

test_that("jatos_download_results checks its arguments and never leaks the token", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  expect_error(jatos_download_results(meta[, -match("data_size", names(meta))], root), "data_size", class = "jatosr_bad_metadata")
  expect_error(jatos_download_results(meta, root, chunk_size = 0), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_download_results(meta, root, overwrite = "yes"), "TRUE", class = "jatosr_bad_argument")
  expect_error(jatos_download_results(meta, root, chunk_size = 5, incremental = NA), "TRUE", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)

  local_jatos_mock(
    "POST .*/results/data$" = mock_json("error-401.json", status = 401)
  )
  w <- capture_warnings(suppressMessages(out <- jatos_download_results(meta, root)))
  expect_no_token(w)
  expect_equal(out$status, c("failed", "empty", "failed", "empty", "failed", "failed"))
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE), 0)
  msgs <- capture_messages(local({
    local_download_mock()
    jatos_download_results(meta, file.path(root, "fresh"))
  }))
  expect_no_token(msgs)
  expect_match(paste(msgs, collapse = "\n"), "Batch 34")
})

test_that("dry_run = TRUE plans without a request, a connection or a file on disk", {
  local_no_credentials()
  rec <- local_jatos_mock()
  root <- file.path(withr::local_tempdir(), "cache")
  meta <- fixture_metadata()

  msgs <- capture_messages(out <- jatos_download_results(meta, root, dry_run = TRUE))
  expect_length(rec$requests, 0)
  expect_false(dir.exists(root))
  expect_equal(out$status, c("pending", "empty", "pending", "empty", "pending", "pending"))
  expect_true(all(is.na(out$file)))
  expect_equal(names(out), c(metadata_columns(), "file", "file_size", "status"))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Batch 34: 2 component results \\(3.6 kB\\) to fetch in 1 request")
  expect_match(text, "Batch 36: 2 component results \\(1.0 kB\\) to fetch in 1 request")

  # on a current cache the dry run says so
  local_download_mock()
  suppressMessages(jatos_download_results(meta, root))
  msgs <- capture_messages(out <- jatos_download_results(meta, root, dry_run = TRUE))
  expect_match(paste(msgs, collapse = "\n"), "Nothing to fetch")
  expect_equal(out$status, c("unchanged", "empty", "unchanged", "empty", "unchanged", "unchanged"))
  expect_error(jatos_download_results(meta, root, dry_run = NA), "TRUE", class = "jatosr_bad_argument")
})

test_that("a 200 that is not a zip marks the chunk failed instead of missing", {
  local_download_mock(
    "POST .*/results/data$" = mock_json_body(list(apiVersion = "1.1.0", data = list(ok = TRUE)))
  )
  root <- withr::local_tempdir()
  meta <- fixture_metadata()

  w <- capture_warnings(msgs <- capture_messages(out <- jatos_download_results(meta, root)))
  expect_equal(out$status, c("failed", "empty", "failed", "empty", "failed", "failed"))
  expect_length(w, 1)
  expect_match(w, "4 component results could not be fetched")
  expect_match(w, "2 failed requests")
  expect_match(w, "not answer `POST /results/data` with a zip file", fixed = TRUE)
  expect_match(w, "application/json")
  expect_match(w, '"ok"', fixed = TRUE)
  expect_no_token(w)
  expect_match(paste(msgs, collapse = "\n"), "fetched 0 of 2 component results in 1 request \\(1 request failed\\)")
  # no metadata.json and no leftovers for a batch that received nothing
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE), 0)
})

test_that("a zip that cannot be unpacked marks the chunk failed, not its rows missing", {
  # starts with PK, so it passes the zip check, and is cut short after that
  truncated <- withr::local_tempfile(fileext = ".zip")
  writeBin(c(charToRaw("PK\003\004"), as.raw(rep(0, 40))), truncated)
  local_download_mock("POST .*/results/data$" = mock_zip_file(truncated))
  root <- withr::local_tempdir()
  meta <- fixture_metadata()

  w <- capture_warnings(msgs <- capture_messages(out <- jatos_download_results(meta, root)))
  expect_equal(out$status, c("failed", "empty", "failed", "empty", "failed", "failed"))
  expect_length(w, 1)
  expect_match(w, "4 component results could not be fetched \\(2 failed requests\\)")
  expect_match(w, "could not be unpacked")
  expect_match(w, "error 1 in extracting", fixed = TRUE)
  expect_match(w, "Run the call again")
  expect_false(any(grepl("not in the server's answer", w)))
  expect_no_token(c(w, msgs))
  # nothing written, no staging directory left behind
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0)

  # the condition itself, for callers that catch it
  batch <- batch_dir(root, 34)
  err <- expect_error(fetch_chunk(meta[1, ], batch, jatos_connection()), class = "jatosr_zip_unreadable")
  expect_match(conditionMessage(err), "POST /results/data", fixed = TRUE)
  expect_match(conditionMessage(err), "44 B")
  expect_length(list.files(batch, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0)

  # an archive without entries is a valid answer: the rows are missing, no failure
  empty_zip <- withr::local_tempfile(fileext = ".zip")
  stored_zip(empty_zip, list())
  local_download_mock("POST .*/results/data$" = mock_zip_file(empty_zip))
  w <- capture_warnings(suppressMessages(out <- jatos_download_results(meta[1, ], root)))
  expect_equal(out$status, "missing")
  expect_length(w, 1)
  expect_match(w, "not in the server's answer")
  # so is one that unpacks cleanly but holds directories only: a retry
  # would get the same archive, so the rows are missing, not failed
  dirs_only <- withr::local_tempfile(fileext = ".zip")
  stored_zip(dirs_only, list("study_result_9001/" = raw(), "study_result_9001/comp-result_7001/" = raw()))
  local_download_mock("POST .*/results/data$" = mock_zip_file(dirs_only))
  w <- capture_warnings(suppressMessages(out <- jatos_download_results(meta[1, ], root)))
  expect_equal(out$status, "missing")
  expect_match(w, "not in the server's answer")
  # the request succeeded, so the batch metadata was refreshed; no data
  # file, no directory from the archive, no staging leftover
  expect_equal(
    list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE),
    file.path("batch_34", "metadata.json")
  )
})

test_that("an entry with a .. component never leaves the batch directory", {
  # R's own unzip skips such an entry only from R 4.5.1 on; before, it writes
  # the entry outside exdir (seen on the R 4.1 CI job). So the package reads
  # the names first and refuses the archive without extracting anything, and
  # a request that answers with one has failed
  zip <- withr::local_tempfile(fileext = ".zip")
  stored_zip(zip, list(
    "../escape.txt" = charToRaw("evil"),
    "study_result_9001/comp-result_7001/data.txt" = charToRaw('[{"a":1}]')
  ))

  local_download_mock("POST .*/results/data$" = mock_zip_file(zip))
  parent <- withr::local_tempdir()
  cache <- file.path(parent, "cache")
  meta <- fixture_metadata()[1, ]
  w <- capture_warnings(suppressMessages(out <- jatos_download_results(meta, cache)))
  expect_equal(out$status, "failed")
  expect_match(w, "could not be unpacked", all = FALSE)
  expect_match(w, "would leave the target directory", all = FALSE)
  expect_match(w, "../escape.txt", fixed = TRUE, all = FALSE)
  expect_length(list.files(parent, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0)
})

test_that("an archive with escaping entries is refused before R's unzip extracts anything", {
  # the refusal must not depend on the R version's unzip: extraction is
  # recorded, and must never be reached
  zip <- withr::local_tempfile(fileext = ".zip")
  stored_zip(zip, list(
    "metadata.json" = charToRaw("{}"),
    "study_result_9001/../../escape.txt" = charToRaw("evil"),
    "/abs.txt" = charToRaw("evil")
  ))
  real_unzip <- utils::unzip
  extracted <- FALSE
  local_mocked_bindings(
    unzip = function(zipfile, files = NULL, list = FALSE, ...) {
      if (!list) extracted <<- TRUE
      real_unzip(zipfile, files = files, list = list, ...)
    },
    .package = "utils"
  )
  parent <- withr::local_tempdir()

  err <- expect_error(
    jatos_import_results(zip, file.path(parent, "cache")),
    class = "jatosr_zip_unreadable"
  )
  expect_false(extracted)
  expect_match(conditionMessage(err), "2 entries would leave the target directory")
  expect_length(list.files(parent, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0)
})

test_that("zip_escaping_entries finds parent components and absolute names only", {
  zip <- withr::local_tempfile(fileext = ".zip")
  names <- c(
    "../a", "x/../../b", "x\\..\\c", "/d", "\\e", "C:/f", "..",
    "study_result_1/comp-result_2/data.txt", "x/..data.txt", "x/b..c/d.txt", "...", "x/files/..hidden"
  )
  stored_zip(zip, stats::setNames(rep(list(charToRaw("1")), length(names)), names))
  expect_equal(zip_escaping_entries(zip), names[1:7])
  expect_equal(zip_escaping_entries(fixture_path("results.zip")), character())
})

test_that("a failed chunk does not stop the run and the batch metadata follows its data", {
  calls <- 0L
  rec <- local_download_mock(
    "POST .*/results/data$" = function(req) {
      calls <<- calls + 1L
      if (calls == 1L) {
        mock_json_body(list(apiVersion = "1.1.0", error = list(message = "boom {batchIds}")), status = 500)
      } else {
        mock_zip("results.zip")
      }
    }
  )
  root <- withr::local_tempdir()
  meta <- fixture_metadata()

  w <- capture_warnings(suppressMessages(out <- jatos_download_results(meta, root, chunk_size = 1)))
  expect_equal(out$status, c("failed", "empty", "fetched", "empty", "fetched", "fetched"))
  expect_true(is.na(out$file[1]))
  expect_equal(out$file_size[3], 1536)
  expect_length(w, 1)
  expect_match(w, "1 component result could not be fetched \\(1 failed request\\)")
  expect_match(w, "boom {batchIds}", fixed = TRUE)
  expect_match(w, "Run the call again")
  expect_no_token(w)

  # requests per batch: data chunks first, then the metadata refresh
  paths <- basename(vapply(rec$requests, function(r) httr2::url_parse(r$url)$path, character(1)))
  expect_equal(paths, c("data", "data", "metadata", "data", "data", "metadata"))
  expect_true(file.exists(file.path(root, "batch_34", "metadata.json")))

  # the next run retries only the failed row
  n_before <- length(rec$requests)
  again <- suppressMessages(jatos_download_results(meta, root, chunk_size = 1))
  expect_equal(again$status, c("fetched", "empty", "unchanged", "empty", "unchanged", "unchanged"))
  expect_length(rec$requests, n_before + 2)
})

test_that("a 401 stops further requests and marks every remaining row failed", {
  rec <- local_download_mock(
    "POST .*/results/data$" = mock_json("error-401.json", status = 401)
  )
  root <- withr::local_tempdir()
  meta <- fixture_metadata()

  w <- capture_warnings(msgs <- capture_messages(out <- jatos_download_results(meta, root, chunk_size = 1)))
  expect_equal(out$status, c("failed", "empty", "failed", "empty", "failed", "failed"))
  expect_length(rec$requests, 1)
  expect_match(w, "authentication error")
  expect_match(w, "Invalid or expired API token")
  expect_no_token(c(w, msgs))
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE), 0)
})

test_that("a failed metadata refresh is a warning and leaves no temporary file", {
  local_download_mock(
    "POST .*/results/metadata$" = mock_json_body(
      list(apiVersion = "1.1.0", error = list(message = "down {x}")),
      status = 500
    )
  )
  root <- withr::local_tempdir()
  w <- capture_warnings(suppressMessages(out <- jatos_download_results(fixture_metadata(), root)))
  expect_equal(out$status, c("fetched", "empty", "fetched", "empty", "fetched", "fetched"))
  expect_length(w, 2)
  expect_match(w[1], "metadata.json.*batch 34 could not be refreshed")
  expect_match(w[1], "down {x}", fixed = TRUE)
  expect_false(any(grepl("metadata", list.files(root, recursive = TRUE, all.files = TRUE))))
  expect_true(file.exists(file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")))
})

test_that("a directory in another layout is refused before any request", {
  rec <- local_download_mock()
  meta <- fixture_metadata()

  # a metadata.json at the top level (one batch stored without a folder)
  top <- local_cache()
  file.rename(file.path(top, "batch_34", "metadata.json"), file.path(top, "metadata.json"))
  err <- expect_error(jatos_download_results(meta, top), class = "jatosr_cache_layout")
  expect_match(conditionMessage(err), "not a cache written by jatosr")
  expect_match(conditionMessage(err), "metadata.json.*top level")
  expect_match(conditionMessage(err), "jatos_import_results")
  expect_error(jatos_download_files(meta, top), "top level", class = "jatosr_cache_layout")
  expect_error(jatos_read_metadata(top), "top level", class = "jatosr_cache_layout")
  expect_error(jatos_cache_status(top), "top level", class = "jatosr_cache_layout")

  # JATOS_DATA_<id> folders
  legacy <- local_cache()
  file.rename(file.path(legacy, "batch_36"), file.path(legacy, "JATOS_DATA_36"))
  err <- expect_error(jatos_download_results(meta, legacy), class = "jatosr_cache_layout")
  expect_match(conditionMessage(err), "1 'JATOS_DATA_<id>' folder", fixed = TRUE)
  expect_match(conditionMessage(err), "JATOS_DATA_36")
  expect_match(conditionMessage(err), "Nothing in this directory has been read or changed", fixed = TRUE)
  expect_error(jatos_read_metadata(legacy), "JATOS_DATA_36", class = "jatosr_cache_layout")
  expect_error(jatos_download_results(meta, legacy, dry_run = TRUE), "JATOS_DATA_36", class = "jatosr_cache_layout")
  expect_length(rec$requests, 0)
  expect_no_token(conditionMessage(err))

  # a batch_<id> directory itself is read; a directory that does not exist yet is fine
  expect_equal(nrow(jatos_read_metadata(file.path(legacy, "batch_34"))), 4)
  expect_equal(nrow(jatos_download_results(meta, file.path(legacy, "new"), dry_run = TRUE)), 6)
})

test_that("an NA id is refused at entry rather than planned and never requested", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  for (col in c("batch_id", "study_result_id", "component_result_id")) {
    bad <- meta
    bad[[col]][c(1, 3)] <- NA
    err <- expect_error(jatos_download_results(bad, root), class = "jatosr_bad_metadata")
    expect_match(conditionMessage(err), col, fixed = TRUE)
    expect_match(conditionMessage(err), "rows 1 and 3")
    expect_error(jatos_download_files(bad, root), col, class = "jatosr_bad_metadata")
    bad$file <- NA_character_
    expect_error(jatos_extract_fields(bad, "pid"), col, class = "jatosr_bad_metadata")
    expect_error(jatos_study_results(bad), col, class = "jatosr_bad_metadata")
  }
  expect_length(rec$requests, 0)
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE), 0)
})

test_that("an upload named data.txt under files/ is not taken for result data", {
  local_download_mock("POST .*/results/data$" = mock_zip("results-decoy.zip"))
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  meta <- meta[meta$component_result_id == 7001L, ]

  expect_warning(
    out <- suppressMessages(jatos_download_results(meta, root)),
    "1 requested component result was not in the server's answer"
  )
  expect_equal(out$status, "missing")
  expect_true(is.na(out$file))
  expect_false(file.exists(file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")))
  expect_false(any(grepl("files", list.files(root, recursive = TRUE))))
  # a data.txt under files/ on disk is neither a result file nor an orphan
  dir.create(file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "files"), recursive = TRUE)
  writeLines("upload", file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "files", "data.txt"))
  expect_equal(jatos_cache_status(root)$n_orphans, 0L)
  expect_true(is.na(jatos_read_metadata(root)$file[1]))
})

test_that("move_file falls back to a copy when the rename fails, and aborts when both fail", {
  dir <- withr::local_tempdir()
  from <- file.path(dir, "from.txt")
  to <- file.path(dir, "to.txt")
  writeLines("payload", from)

  # a rename that fails (another volume, some network shares): copy and delete
  local({
    local_mocked_bindings(rename_file = function(from, to) FALSE)
    expect_equal(move_file(from, to), to)
    expect_equal(readLines(to), "payload")
    expect_false(file.exists(from))
  })
  # a target whose directory does not exist: neither works, and the source stays
  missing_dir <- file.path(dir, "no", "such", "to.txt")
  writeLines("payload", from)
  expect_error(suppressWarnings(move_file(from, missing_dir)), "Could not write")
  expect_true(file.exists(from))
  expect_false(file.exists(missing_dir))
})

test_that("write_atomically replaces an existing target and leaves no temporary file", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "target.txt")
  writeLines("old", path)

  out <- write_atomically(path, function(tmp) {
    writeLines("new", tmp)
    "value"
  })
  expect_equal(out, "value")
  expect_equal(readLines(path), "new")
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), "target.txt")

  # a writer that fails leaves the old file and no temporary
  expect_error(write_atomically(path, function(tmp) {
    writeLines("half", tmp)
    stop("boom")
  }), "boom")
  expect_equal(readLines(path), "new")
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), "target.txt")
})

test_that("an empty metadata tibble downloads nothing and returns the columns", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  out <- jatos_download_results(fixture_metadata()[0, ], root)
  expect_equal(nrow(out), 0)
  expect_true(all(c("file", "file_size", "status") %in% names(out)))
  expect_length(rec$requests, 0)
})
