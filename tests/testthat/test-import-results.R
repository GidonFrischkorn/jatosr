# results-export.zip is the POST /results layout: metadata.json at the root,
# four data.txt and one uploaded file (see data-raw/make-fixtures.R).

test_that("jatos_import_results unpacks a results zip into the batch layout", {
  root <- file.path(withr::local_tempdir(), "cache")
  msgs <- capture_messages(out <- expect_invisible(jatos_import_results(fixture_path("results-export.zip"), root)))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Imported batches 34 and 36")
  expect_match(text, "6 component results listed, 4 data files and 1 uploaded file written")

  expect_equal(sort(list.files(root)), c("batch_34", "batch_36"))
  expect_true(file.exists(file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")))
  expect_true(file.exists(file.path(root, "batch_34", "study_result_9002", "comp-result_7003", "files", "drawing.png")))
  expect_true(file.exists(file.path(root, "batch_36", "study_result_9004", "comp-result_7006", "data.txt")))
  expect_false(file.exists(file.path(root, "metadata.json")))
  expect_equal(file.size(file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")), 2048)

  # each batch's metadata.json holds that batch only, with the fields intact
  one <- jatos_flatten_metadata(file.path(root, "batch_34", "metadata.json"))
  expect_equal(unique(one$batch_id), 34L)
  expect_equal(one$component_result_id, c(7001L, 7002L, 7003L, 7004L))
  expect_equal(one$comment[2], "browser crashed once")
  expect_true(is.na(one$group_id[1]))
  two <- jatos_flatten_metadata(file.path(root, "batch_36", "metadata.json"))
  expect_equal(two$study_id, c(13L, 13L))
  expect_equal(two$url_query[[1]]$PROLIFIC_PID, "p-0004")
  whole <- fixture_metadata()
  replay <- jatos_read_metadata(root)
  expect_equal(replay[, names(whole)], whole[order(whole$batch_id, whole$component_result_id), ], ignore_attr = TRUE)
  expect_equal(sum(!is.na(replay$file)), 4)
  expect_equal(replay$file_size[replay$component_result_id == 7003L], 1536)
  expect_equal(out, replay)

  # the cache is consistent: no orphans, nothing to fetch, the files read
  status <- jatos_cache_status(root)
  expect_equal(status$n_orphans, c(0L, 0L))
  expect_equal(status$n_pending, c(0L, 0L))
  local_no_credentials()
  plan <- suppressMessages(jatos_download_results(whole, root, dry_run = TRUE))
  expect_equal(plan$status, c("unchanged", "empty", "unchanged", "empty", "unchanged", "unchanged"))
  files <- jatos_download_files(whole, root, dry_run = TRUE)
  expect_equal(files$status, "unchanged")
  trials <- suppressMessages(jatos_read_results(replay))
  expect_equal(nrow(trials), 6)
})

test_that("a zip that wraps everything in one folder imports to the same layout", {
  # A results zip re-packed from a folder has one extra level. Entries are
  # located by their suffix and placed by the ids read from it, so the
  # cache is the same, file for file.
  fixture <- fixture_path("results-export.zip")
  unpacked <- withr::local_tempdir()
  utils::unzip(fixture, exdir = unpacked)
  names <- list.files(unpacked, recursive = TRUE)
  entries <- rlang::set_names(
    lapply(file.path(unpacked, names), function(f) readBin(f, "raw", file.size(f))),
    paste0("export/", names)
  )
  wrapped_zip <- withr::local_tempfile(fileext = ".zip")
  stored_zip(wrapped_zip, entries)

  plain <- file.path(withr::local_tempdir(), "plain")
  wrapped <- file.path(withr::local_tempdir(), "wrapped")
  suppressMessages(jatos_import_results(fixture, plain))
  suppressMessages(jatos_import_results(wrapped_zip, wrapped))
  files <- list.files(plain, recursive = TRUE)
  expect_length(files, 7)
  expect_setequal(list.files(wrapped, recursive = TRUE), files)
  expect_equal(
    unname(tools::md5sum(file.path(wrapped, files))),
    unname(tools::md5sum(file.path(plain, files)))
  )
})

test_that("jatos_import_results refuses an existing batch unless overwrite, and other layouts", {
  root <- withr::local_tempdir()
  suppressMessages(jatos_import_results(fixture_path("results-export.zip"), root))
  data_file <- file.path(root, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")
  writeLines("edited", data_file)
  extra <- file.path(root, "batch_34", "study_result_9999", "comp-result_8888", "data.txt")
  dir.create(dirname(extra), recursive = TRUE)
  writeLines("[]", extra)

  err <- expect_error(jatos_import_results(fixture_path("results-export.zip"), root), class = "jatosr_file_exists")
  expect_match(conditionMessage(err), "batch_34")
  expect_match(conditionMessage(err), "batch_36")
  expect_match(conditionMessage(err), "already exist")
  expect_equal(readLines(data_file), "edited")

  suppressMessages(jatos_import_results(fixture_path("results-export.zip"), root, overwrite = TRUE))
  expect_equal(file.size(data_file), 2048)
  expect_true(file.exists(extra))

  # not a zip, a zip cut short, no metadata.json inside, a legacy cache, bad arguments
  expect_error(jatos_import_results(fixture_path("metadata.json"), root), "not a zip file", class = "jatosr_zip_unreadable")
  truncated <- withr::local_tempfile(fileext = ".zip")
  writeBin(readBin(fixture_path("results-export.zip"), "raw", 300), truncated)
  err <- expect_error(jatos_import_results(truncated, file.path(root, "cut")), class = "jatosr_zip_unreadable")
  expect_match(conditionMessage(err), "could not be unpacked")
  expect_match(conditionMessage(err), "Export the results")
  expect_false(dir.exists(file.path(root, "cut")))
  expect_error(jatos_import_results(fixture_path("results.zip"), root), "no 'metadata.json'", class = "jatosr_bad_metadata")
  expect_error(jatos_import_results(file.path(root, "nope.zip"), root), "does not exist", class = "jatosr_bad_argument")
  legacy <- local_cache()
  file.rename(file.path(legacy, "batch_36"), file.path(legacy, "JATOS_DATA_36"))
  expect_error(jatos_import_results(fixture_path("results-export.zip"), legacy), "JATOS_DATA_36", class = "jatosr_cache_layout")
  expect_error(jatos_import_results(fixture_path("results-export.zip"), ""), "path", class = "jatosr_bad_argument")
  expect_error(jatos_import_results(fixture_path("results-export.zip"), root, overwrite = "yes"), "TRUE", class = "jatosr_bad_argument")
})

test_that("jatos_import_results leaves entries out that the metadata does not list", {
  # a zip whose metadata.json lists batch 36 only: the batch 34 entries are skipped
  parsed <- read_fixture_json("metadata.json")
  parsed$data <- Filter(function(study) study$studyId == 13, parsed$data)
  build <- withr::local_tempdir()
  utils::unzip(fixture_path("results-export.zip"), exdir = build)
  jsonlite::write_json(parsed, file.path(build, "metadata.json"), auto_unbox = TRUE, null = "null", digits = NA)
  zip <- file.path(withr::local_tempdir(), "partial.zip")
  withr::with_dir(build, utils::zip(zip, files = list.files(recursive = TRUE), flags = "-q"))

  root <- withr::local_tempdir()
  msgs <- capture_messages(jatos_import_results(zip, root))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Imported batch 36")
  expect_match(text, "2 component results listed, 2 data files and 0 uploaded files")
  expect_match(text, "3 entries of the zip belong to no study result")
  expect_equal(list.files(root), "batch_36")
  expect_equal(nrow(jatos_read_metadata(root)), 2)
})

test_that("a metadata.json without batch ids is refused with the reason", {
  parsed <- read_fixture_json("metadata.json")
  parsed$data[[2]]$studyResults[[1]]$batchId <- NULL
  json <- jsonlite::toJSON(parsed, auto_unbox = TRUE, null = "null", digits = NA)
  zip <- withr::local_tempfile(fileext = ".zip")
  stored_zip(zip, list(
    "metadata.json" = charToRaw(as.character(json)),
    "study_result_9004/comp-result_7005/data.txt" = charToRaw("[]")
  ))
  root <- file.path(withr::local_tempdir(), "cache")

  # it said "`batch_id` must be one or more positive integer ids" before
  err <- expect_error(jatos_import_results(zip, root), class = "jatosr_bad_metadata")
  expect_match(conditionMessage(err), "2 component results without a batch id")
  expect_match(conditionMessage(err), "laid out by batch")
  expect_false(dir.exists(root))
})

test_that("write_metadata_subset keeps the envelope and drops studies without the batch", {
  parsed <- read_fixture_json("metadata.json")
  file <- withr::local_tempfile(fileext = ".json")
  write_metadata_subset(parsed, 36, file)
  back <- jsonlite::read_json(file, simplifyVector = FALSE)
  expect_equal(back$apiVersion, "1.1.0")
  expect_length(back$data, 1)
  expect_equal(back$data[[1]]$studyId, 13L)
  expect_equal(back$data[[1]]$studyResults[[1]]$componentResults[[1]]$data$size, 300L)
  expect_null(back$data[[1]]$studyResults[[1]]$groupId)
  expect_equal(back$data[[1]]$studyResults[[1]]$startDate, 1756004000000)
})
