local_results_archive_mock <- function(.env = parent.frame()) {
  local_download_mock("POST .*/results$" = mock_zip("results-export.zip"), .env = .env)
}

test_that("jatos_export_archive writes the server's zip untouched", {
  rec <- local_results_archive_mock()
  root <- withr::local_tempdir()
  file <- file.path(root, "study12_results.zip")

  msgs <- capture_messages(out <- expect_invisible(jatos_export_archive(study_id = 12, file = file)))
  expect_equal(out, file)
  expect_no_token(msgs)
  expect_match(paste(msgs, collapse = "\n"), "results archive")
  expect_match(paste(msgs, collapse = "\n"), "study12_results.zip")
  expect_identical(
    readBin(file, "raw", file.size(file)),
    readBin(fixture_path("results-export.zip"), "raw", file.size(fixture_path("results-export.zip")))
  )
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), "study12_results.zip")

  req <- last_request(rec)
  expect_equal(mock_method(req), "POST")
  expect_match(httr2::url_parse(req$url)$path, "/jatos/api/v1/results$")
  expect_equal(req$headers$Accept, "application/zip")
  expect_equal(request_json_body(req), list(studyIds = list(12L)))
  expect_length(rec$requests, 1)

  # batches, both, and a uuid
  suppressMessages(jatos_export_archive(batch_id = c(34, 36), file = file.path(root, "b.zip")))
  expect_equal(request_json_body(last_request(rec)), list(batchIds = list(34L, 36L)))
  uuid <- "1c2d3e4f-0000-4000-8000-000000000012"
  suppressMessages(jatos_export_archive(study_id = uuid, batch_id = 34, file = file.path(root, "u.zip")))
  expect_equal(request_json_body(last_request(rec)), list(studyUuids = list(uuid), batchIds = list(34L)))
  # the archive imports into a cache
  imported <- suppressMessages(jatos_import_results(file, file.path(root, "cache")))
  expect_equal(nrow(imported), 6)
})

test_that("jatos_export_archive guards its arguments and target before the request", {
  rec <- local_results_archive_mock()
  root <- withr::local_tempdir()
  file <- file.path(root, "r.zip")
  writeLines("keep", file)

  expect_error(jatos_export_archive(file = file), "at least one id", class = "jatosr_bad_argument")
  expect_error(jatos_export_archive(study_id = 12, file = file), class = "jatosr_file_exists")
  expect_equal(readLines(file), "keep")
  expect_error(jatos_export_archive(study_id = 12, file = file.path(root, "no", "x.zip")), "does not exist", class = "jatosr_bad_argument")
  expect_error(jatos_export_archive(study_id = 12, file = ""), "file", class = "jatosr_bad_argument")
  expect_error(jatos_export_archive(study_id = c(12, "1c2d3e4f-0000-4000-8000-000000000012"), file = file), "mixes", class = "jatosr_bad_argument")
  expect_error(jatos_export_archive(study_id = 12, file = file, overwrite = "yes"), "TRUE", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)
  suppressMessages(jatos_export_archive(study_id = 12, file = file, overwrite = TRUE))
  expect_equal(readBin(file, "raw", 2), charToRaw("PK"))

  # an answer that is not a zip leaves nothing behind
  local_jatos_mock("POST .*/results$" = mock_json_body(list(apiVersion = "1.1.0", data = list())))
  err <- expect_error(jatos_export_archive(study_id = 12, file = file.path(root, "z.zip")), "not answer `POST /results` with a zip file", class = "jatosr_zip_unreadable")
  expect_no_token(conditionMessage(err))
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), "r.zip")
})

test_that("jatos_export_archive without `file` takes the server's name in the working directory", {
  # the mocks read their fixtures now, before the working directory changes
  named <- mock_zip("results-export.zip", filename = "jatos_results_20250824.zip")
  climbing <- mock_zip("results-export.zip", filename = "../../evil.zip")
  unnamed <- mock_zip("results-export.zip")
  rec <- local_download_mock("POST .*/results$" = named)
  root <- withr::local_tempdir()
  withr::local_dir(root)

  msgs <- capture_messages(out <- expect_invisible(jatos_export_archive(study_id = 12)))
  expect_equal(out, "jatos_results_20250824.zip")
  expect_equal(readBin(out, "raw", 2), charToRaw("PK"))
  expect_match(paste(msgs, collapse = "\n"), "jatos_results_20250824.zip")
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), "jatos_results_20250824.zip")
  expect_length(rec$requests, 1)

  # a file in the way is refused after the answer, and nothing else is left behind
  expect_error(jatos_export_archive(study_id = 12), class = "jatosr_file_exists")
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), "jatos_results_20250824.zip")
  suppressMessages(jatos_export_archive(study_id = 12, overwrite = TRUE))
  expect_equal(readBin(out, "raw", 2), charToRaw("PK"))

  # a name that climbs out of the directory is reduced to its base name
  local_jatos_mock("POST .*/results$" = climbing)
  out <- suppressMessages(jatos_export_archive(study_id = 12))
  expect_equal(out, "evil.zip")
  expect_true(file.exists(file.path(root, "evil.zip")))
  expect_false(file.exists(file.path(root, "..", "..", "evil.zip")))

  # no Content-Disposition: a fixed fallback name
  local_jatos_mock("POST .*/results$" = unnamed)
  out <- suppressMessages(jatos_export_archive(batch_id = 34))
  expect_equal(out, "jatos_results.zip")
  expect_true(file.exists(file.path(root, "jatos_results.zip")))
})

test_that("jatos_export_results(archive_results = TRUE) writes the archive with size and md5 in the record", {
  rec <- local_results_archive_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "study12.rds")

  msgs <- capture_messages(
    jatos_export_results(study_id = 12, cache = cache, file = file, archive_results = TRUE)
  )
  archive <- file.path(root, "study12_results.zip")
  expect_true(file.exists(archive))
  expect_match(paste(msgs, collapse = "\n"), "study12_results.zip")
  prov <- jsonlite::read_json(file.path(root, "study12_export.json"))
  expect_equal(prov$files$results_archive$file, archive)
  expect_equal(prov$files$results_archive$bytes, file.size(archive))
  expect_equal(prov$files$results_archive$md5, unname(tools::md5sum(archive)))
  expect_equal(nchar(prov$files$results_archive$md5), 32)
  # the archive request carries the same ids as the metadata request, after the data
  paths <- basename(request_paths(rec))
  expect_equal(paths, c("metadata", "data", "metadata", "data", "metadata", "results"))
  expect_equal(request_json_body(last_request(rec)), list(studyIds = list(12L)))

  # in the way: refused before the first request; off by default; not offline
  n_before <- length(rec$requests)
  writeLines("", file.path(root, "t_results.zip"))
  expect_error(
    jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "t.rds"), archive_results = TRUE),
    "t_results.zip",
    class = "jatosr_file_exists"
  )
  expect_length(rec$requests, n_before)
  suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "plain.rds")))
  expect_false(file.exists(file.path(root, "plain_results.zip")))
  expect_null(jsonlite::read_json(file.path(root, "plain_export.json"))$files$results_archive)
  expect_error(
    jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "o.rds"), archive_results = TRUE, download = FALSE),
    "archive_results",
    class = "jatosr_bad_argument"
  )
  expect_error(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "o.rds"), archive_results = NA), "TRUE", class = "jatosr_bad_argument")
})
