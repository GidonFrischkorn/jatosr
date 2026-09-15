# The download mock (with the /results/files route) lives in helper-download.R.

files_cols <- c("study_result_id", "component_result_id", "component_id", "batch_id", "filename", "size")

test_that("jatos_result_files gives one row per attached file", {
  meta <- fixture_metadata()
  files <- jatos_result_files(meta)
  expect_s3_class(files, "tbl_df")
  expect_equal(names(files), files_cols)
  expect_equal(nrow(files), 1)
  expect_equal(files$component_result_id, 7003L)
  expect_equal(files$study_result_id, 9002L)
  expect_equal(files$batch_id, 34L)
  expect_equal(files$component_id, 121L)
  expect_equal(files$filename, "drawing.png")
  expect_equal(files$size, 4096)
  expect_type(files$size, "double")

  # several files on one result, in the order the server lists them
  two <- meta
  two$files[[6]] <- list(list(filename = "audio.webm", size = 500), list(filename = "notes.txt", size = 0))
  files <- jatos_result_files(two)
  expect_equal(files$component_result_id, c(7003L, 7006L, 7006L))
  expect_equal(files$filename, c("drawing.png", "audio.webm", "notes.txt"))
  expect_equal(files$size, c(4096, 500, 0))
})

test_that("jatos_result_files keeps the columns without files and checks its input", {
  meta <- fixture_metadata()
  none <- jatos_result_files(meta[meta$n_files == 0, ])
  expect_equal(nrow(none), 0)
  expect_equal(names(none), files_cols)
  expect_type(none$filename, "character")
  expect_equal(names(jatos_result_files(meta[0, ])), files_cols)
  expect_error(jatos_result_files(meta[, -match("files", names(meta))]), "files", class = "jatosr_bad_metadata")
  expect_error(jatos_result_files(list()), "data frame", class = "jatosr_bad_metadata")
})

test_that("jatos_download_files stores the planned files next to the data and reports status", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()

  msgs <- capture_messages(out <- jatos_download_files(meta, root))
  expect_no_token(msgs)
  expect_match(paste(msgs, collapse = "\n"), "Batch 34: fetched 1 of 1 file in 1 request")
  expect_equal(names(out), c(files_cols, "file", "file_size", "status"))
  expect_equal(out$status, "fetched")
  expected <- file.path(root, "batch_34", "study_result_9002", "comp-result_7003", "files", "drawing.png")
  expect_equal(normalizePath(out$file), normalizePath(expected))
  expect_equal(out$file_size, 4096)
  expect_equal(file.size(expected), 4096)
  expect_equal(readBin(expected, "raw", 4), as.raw(c(0x89, 0x50, 0x4E, 0x47)))

  # the file of 7006 in the zip was not asked for and is not written
  expect_length(list.files(root, recursive = TRUE), 2) # drawing.png and metadata.json
  expect_false(any(grepl("audio", list.files(root, recursive = TRUE))))
  expect_false(any(grepl("staging", list.files(root, recursive = TRUE, all.files = TRUE))))

  # one files request with the component result id, then the metadata refresh
  reqs <- file_requests(rec)
  expect_length(reqs, 1)
  expect_equal(mock_method(reqs[[1]]), "POST")
  expect_equal(reqs[[1]]$headers$Accept, "application/zip")
  expect_equal(names(request_json_body(reqs[[1]])), "componentResultIds")
  expect_equal(unlist(request_json_body(reqs[[1]])$componentResultIds), 7003L)
  expect_true(file.exists(file.path(root, "batch_34", "metadata.json")))
  expect_length(metadata_requests(rec), 1)

  # a second call issues no request
  n_before <- length(rec$requests)
  again <- expect_silent(jatos_download_files(meta, root))
  expect_equal(again$status, "unchanged")
  expect_length(rec$requests, n_before)
})

test_that("jatos_download_files applies the size rule per file", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  suppressMessages(jatos_download_files(meta, root))
  n_before <- length(rec$requests)
  path <- file.path(root, "batch_34", "study_result_9002", "comp-result_7003", "files", "drawing.png")

  # server smaller: the local file stays
  shrunk <- meta
  shrunk$files[[3]] <- list(list(filename = "drawing.png", size = 100))
  out <- expect_silent(jatos_download_files(shrunk, root))
  expect_equal(out$status, "shrunk")
  expect_equal(file.size(path), 4096)
  expect_length(rec$requests, n_before)

  # overwrite refetches it
  out <- suppressMessages(jatos_download_files(shrunk, root, overwrite = TRUE))
  expect_equal(out$status, "fetched")
  expect_length(file_requests(rec), 2)

  # server larger: fetched again; an empty file is never requested
  grown <- meta
  grown$files[[3]] <- list(list(filename = "drawing.png", size = 5000), list(filename = "empty.txt", size = 0))
  out <- suppressMessages(jatos_download_files(grown, root))
  expect_equal(out$status, c("fetched", "empty"))
  expect_equal(out$file_size, c(4096, NA))
  expect_length(file_requests(rec), 3)

  # incremental = FALSE fetches everything with a size above 0
  out <- suppressMessages(jatos_download_files(meta, root, incremental = FALSE))
  expect_equal(out$status, "fetched")
  expect_length(file_requests(rec), 4)
})

test_that("a file without a size in the metadata is not fetched, and a warning names it", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  meta$files[[3]] <- list(list(filename = "drawing.png", size = NULL), list(filename = "notes.txt", size = 12))
  expect_true(is.na(jatos_result_files(meta)$size[1]))

  w <- capture_warnings(msgs <- capture_messages(out <- jatos_download_files(meta, root, dry_run = TRUE)))
  expect_length(w, 1)
  expect_match(w, "1 file has no size in the metadata and is not fetched")
  expect_match(w, "File: 7003/drawing.png", fixed = TRUE)
  expect_equal(out$status, c("empty", "pending"))
  expect_length(rec$requests, 0)
  # without the size the file is silently treated as empty before
  meta$files[[3]] <- list(list(filename = "drawing.png", size = 4096))
  expect_no_warning(suppressMessages(jatos_download_files(meta, root, dry_run = TRUE)))
})

test_that("an uploaded file with a non-ASCII name is stored under that name", {
  name <- "Zeichnung ü.png"
  zip <- withr::local_tempfile(fileext = ".zip")
  stored_zip(zip, rlang::set_names(
    list(charToRaw("PNG bytes")),
    paste0("study_result_9002/comp-result_7003/files/", name)
  ))
  local_download_mock("POST .*/results/files$" = mock_zip_file(zip))
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  meta$files[[3]] <- list(list(filename = name, size = 9))

  out <- suppressMessages(jatos_download_files(meta, root))
  expect_equal(out$status, "fetched")
  expect_equal(out$file_size, 9)
  expected <- local_file_path(batch_dir(root, 34), 9002, 7003, name)
  expect_true(file.exists(expected))
  expect_equal(enc2utf8(basename(out$file)), enc2utf8(name))
  expect_equal(rawToChar(readBin(expected, "raw", 9)), "PNG bytes")
  # and it is unchanged on the next run
  again <- expect_silent(jatos_download_files(meta, root))
  expect_equal(again$status, "unchanged")
})

test_that("the files of one component result travel in one request and absent ones are missing", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  meta$files[[3]] <- list(list(filename = "drawing.png", size = 4096), list(filename = "lost.png", size = 10))
  meta$files[[6]] <- list(list(filename = "audio.webm", size = 500))

  w <- capture_warnings(msgs <- capture_messages(
    out <- jatos_download_files(meta, root, chunk_size = 1)
  ))
  expect_equal(out$status, c("fetched", "missing", "fetched"))
  expect_equal(out$filename, c("drawing.png", "lost.png", "audio.webm"))
  expect_true(is.na(out$file[2]))
  expect_equal(out$file_size[3], 500)
  expect_length(w, 1)
  expect_match(w, "1 requested file was not in the server's answer")
  expect_match(w, "File: 7003/lost.png", fixed = TRUE)
  expect_no_token(c(w, msgs))
  # two files of 7003 in one request, 7006 in another; one metadata refresh per batch
  reqs <- file_requests(rec)
  expect_length(reqs, 2)
  expect_equal(unlist(request_json_body(reqs[[1]])$componentResultIds), 7003L)
  expect_equal(unlist(request_json_body(reqs[[2]])$componentResultIds), 7006L)
  expect_length(metadata_requests(rec), 2)
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Batch 34: fetched 1 of 2 files in 1 request")
  expect_match(text, "Batch 36: fetched 1 of 1 file in 1 request")
})

test_that("jatos_download_files with dry_run plans without a request or a directory", {
  local_no_credentials()
  rec <- local_jatos_mock()
  root <- file.path(withr::local_tempdir(), "cache")
  meta <- fixture_metadata()

  msgs <- capture_messages(out <- jatos_download_files(meta, root, dry_run = TRUE))
  expect_length(rec$requests, 0)
  expect_false(dir.exists(root))
  expect_equal(out$status, "pending")
  expect_true(is.na(out$file))
  expect_match(paste(msgs, collapse = "\n"), "Batch 34: 1 file \\(4.1 kB\\) to fetch in 1 request")

  local_download_mock()
  suppressMessages(jatos_download_files(meta, root))
  msgs <- capture_messages(out <- jatos_download_files(meta, root, dry_run = TRUE))
  expect_match(paste(msgs, collapse = "\n"), "Nothing to fetch")
  expect_equal(out$status, "unchanged")
})

test_that("jatos_download_files marks a failed request and never leaks the token", {
  local_fake_credentials()
  local_jatos_mock(
    "POST .*/results/files$" = mock_json_body(list(apiVersion = "1.1.0", error = list(message = "boom {x}")), status = 500),
    "POST .*/results/metadata$" = mock_metadata_by_batch
  )
  root <- withr::local_tempdir()
  w <- capture_warnings(suppressMessages(out <- jatos_download_files(fixture_metadata(), root)))
  expect_equal(out$status, "failed")
  expect_length(w, 1)
  expect_match(w, "1 file could not be fetched \\(1 failed request\\)")
  expect_match(w, "boom {x}", fixed = TRUE)
  expect_no_token(w)
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE), 0)

  # a 200 that is not a zip is a failed chunk as well
  local_jatos_mock(
    "POST .*/results/files$" = mock_json_body(list(apiVersion = "1.1.0", data = list())),
    "POST .*/results/metadata$" = mock_metadata_by_batch
  )
  w <- capture_warnings(suppressMessages(out <- jatos_download_files(fixture_metadata(), root)))
  expect_equal(out$status, "failed")
  expect_match(w, "not answer `POST /results/files` with a zip file", fixed = TRUE)
})

test_that("jatos_download_files checks its arguments and does nothing without files", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  meta <- fixture_metadata()
  expect_error(jatos_download_files(meta[, -match("files", names(meta))], root), "files", class = "jatosr_bad_metadata")
  expect_error(jatos_download_files(meta, root, chunk_size = 0), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_download_files(meta, root, overwrite = "yes"), "TRUE", class = "jatosr_bad_argument")
  expect_error(jatos_download_files(meta, root, dry_run = NA), "TRUE", class = "jatosr_bad_argument")
  expect_error(jatos_download_files(meta, ""), "path", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)

  out <- expect_silent(jatos_download_files(meta[meta$n_files == 0, ], root))
  expect_equal(nrow(out), 0)
  expect_equal(names(out), c(files_cols, "file", "file_size", "status"))
  expect_length(rec$requests, 0)
})
