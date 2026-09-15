local_study_archive_mock <- function(.env = parent.frame()) {
  local_fake_credentials(.env = .env)
  local_jatos_mock(
    "GET .*/studies/[0-9A-Za-z-]+$" = mock_zip("study.jzip"),
    .env = .env
  )
}

test_that("jatos_export_study writes the archive and returns the path", {
  rec <- local_study_archive_mock()
  root <- withr::local_tempdir()
  file <- file.path(root, "study12.jzip")

  msgs <- capture_messages(out <- expect_invisible(jatos_export_study(12, file)))
  expect_equal(out, file)
  expect_no_token(msgs)
  expect_match(paste(msgs, collapse = "\n"), "archive of study 12")
  expect_match(paste(msgs, collapse = "\n"), "study12.jzip")
  expect_true(file.exists(file))
  expect_equal(readBin(file, "raw", 2), charToRaw("PK"))
  listed <- utils::unzip(file, list = TRUE)
  expect_setequal(listed$Name, c("A03_ColorBinding.jas", "A03_ColorBinding/index.html"))
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), "study12.jzip")

  req <- last_request(rec)
  expect_equal(mock_method(req), "GET")
  expect_match(httr2::url_parse(req$url)$path, "/jatos/api/v1/studies/12$")
  expect_equal(req$headers$Accept, "application/zip")
  expect_length(rec$requests, 1)

  # a uuid goes into the path as it is
  uuid <- "1c2d3e4f-0000-4000-8000-000000000012"
  suppressMessages(jatos_export_study(uuid, file.path(root, "by-uuid.jzip")))
  expect_match(httr2::url_parse(last_request(rec)$url)$path, paste0("/studies/", uuid, "$"))
})

test_that("jatos_export_study guards the target before the request", {
  rec <- local_study_archive_mock()
  root <- withr::local_tempdir()
  file <- file.path(root, "study12.jzip")
  writeLines("keep", file)

  expect_error(jatos_export_study(12, file), class = "jatosr_file_exists")
  expect_equal(readLines(file), "keep")
  expect_error(jatos_export_study(12, file.path(root, "no", "x.jzip")), "does not exist", class = "jatosr_bad_argument")
  expect_error(jatos_export_study(12, ""), "file", class = "jatosr_bad_argument")
  expect_error(jatos_export_study(12, file, overwrite = "yes"), "TRUE", class = "jatosr_bad_argument")
  expect_error(jatos_export_study("12/../admin", file), "uuid", class = "jatosr_bad_argument")
  expect_error(jatos_export_study(0, file), "uuid", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)

  suppressMessages(jatos_export_study(12, file, overwrite = TRUE))
  expect_equal(readBin(file, "raw", 2), charToRaw("PK"))
})

test_that("jatos_export_study refuses an answer that is not a zip and leaves nothing behind", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/studies/12$" = mock_json_body(list(apiVersion = "1.1.0", data = list(id = 12))),
    "GET .*/studies/99$" = mock_json("error-401.json", status = 401)
  )
  root <- withr::local_tempdir()
  err <- expect_error(jatos_export_study(12, file.path(root, "a.jzip")), "not answer `GET /studies/12` with a zip file", class = "jatosr_zip_unreadable")
  expect_match(conditionMessage(err), "application/json")
  expect_no_token(conditionMessage(err))
  expect_length(list.files(root, all.files = TRUE, no.. = TRUE), 0)

  err <- expect_error(jatos_export_study(99, file.path(root, "b.jzip")), "401")
  expect_no_token(conditionMessage(err))
  expect_length(list.files(root, all.files = TRUE, no.. = TRUE), 0)
})

test_that("jatos_export_study without `file` takes the server's name in the working directory", {
  uuid <- "1c2d3e4f-0000-4000-8000-000000000012"
  named <- mock_zip("study.jzip", filename = paste0("jatos_study_", uuid, ".jzip"))
  unnamed <- mock_zip("study.jzip")
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/studies/[0-9A-Za-z-]+$" = named)
  root <- withr::local_tempdir()
  withr::local_dir(root)

  msgs <- capture_messages(out <- expect_invisible(jatos_export_study(12)))
  expect_equal(out, paste0("jatos_study_", uuid, ".jzip"))
  expect_equal(readBin(out, "raw", 2), charToRaw("PK"))
  expect_match(paste(msgs, collapse = "\n"), "jatos_study_", fixed = TRUE)
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), out)
  expect_length(rec$requests, 1)

  expect_error(jatos_export_study(12), class = "jatosr_file_exists")
  expect_equal(list.files(root, all.files = TRUE, no.. = TRUE), out)
  suppressMessages(jatos_export_study(12, overwrite = TRUE))

  # no Content-Disposition: the fallback name, here the one the server sent before
  local_jatos_mock("GET .*/studies/[0-9A-Za-z-]+$" = unnamed)
  out <- suppressMessages(jatos_export_study(uuid, overwrite = TRUE))
  expect_equal(out, paste0("jatos_study_", uuid, ".jzip"))
  out <- suppressMessages(jatos_export_study(13))
  expect_equal(out, "jatos_study_13.jzip")
  expect_true(file.exists(file.path(root, "jatos_study_13.jzip")))
})

test_that("content_disposition_filename reads quoted, bare and RFC 5987 names and keeps the base name only", {
  expect_equal(content_disposition_filename('attachment; filename="jatos_study_abc.jzip"'), "jatos_study_abc.jzip")
  expect_equal(content_disposition_filename("attachment; filename=results.zip"), "results.zip")
  expect_equal(content_disposition_filename("attachment; filename=results.zip; size=12"), "results.zip")
  expect_equal(content_disposition_filename("attachment; filename*=UTF-8''st%C3%BCdy.jzip"), "st\u00fcdy.jzip")
  expect_equal(content_disposition_filename('attachment; filename="../../evil.zip"'), "evil.zip")
  expect_equal(content_disposition_filename('attachment; filename="C:\\x\\y.zip"'), "y.zip")
  expect_null(content_disposition_filename(NULL))
  expect_null(content_disposition_filename("attachment"))
  expect_null(content_disposition_filename('attachment; filename=""'))
  expect_null(content_disposition_filename('attachment; filename=".."'))
  expect_null(content_disposition_filename('attachment; filename="/"'))
})

test_that("study_archive_names follows the trials file", {
  expect_equal(study_archive_names("data/s12.rds", 12), "data/s12_study.jzip")
  expect_equal(study_archive_names("data/s12.rds", c(12, 13)), c("data/s12_study_12.jzip", "data/s12_study_13.jzip"))
  expect_equal(study_archive_names("data/s12.rds", 13, named = FALSE), "data/s12_study_13.jzip")
  expect_equal(study_archive_names("data/s12", 12), "data/s12_study.jzip")
})

test_that("jatos_export_results with archive_study writes the archive next to the dataset", {
  rec <- local_download_mock("GET .*/studies/[0-9A-Za-z-]+$" = mock_zip("study.jzip"))
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "study12.rds")

  msgs <- capture_messages(
    jatos_export_results(study_id = 12, cache = cache, file = file, archive_study = TRUE)
  )
  archive <- file.path(root, "study12_study.jzip")
  expect_true(file.exists(archive))
  expect_equal(readBin(archive, "raw", 2), charToRaw("PK"))
  expect_match(paste(msgs, collapse = "\n"), "study12_study.jzip")
  prov <- jsonlite::read_json(file.path(root, "study12_export.json"))
  expect_equal(prov$files$study_archive, archive)
  paths <- basename(request_paths(rec))
  expect_equal(paths, c("metadata", "data", "metadata", "data", "metadata", "12"))

  # an archive in the way is refused before the first request
  n_before <- length(rec$requests)
  expect_error(
    jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "study12.csv"), archive_study = TRUE),
    "study12_study.jzip",
    class = "jatosr_file_exists"
  )
  expect_length(rec$requests, n_before)
  expect_false(file.exists(file.path(root, "study12.csv")))

  # with batch_id only, the study ids come from the metadata: one archive per study
  msgs <- capture_messages(
    jatos_export_results(batch_id = c(34, 36), cache = cache, file = file.path(root, "both.rds"), archive_study = TRUE)
  )
  expect_true(file.exists(file.path(root, "both_study_12.jzip")))
  expect_true(file.exists(file.path(root, "both_study_13.jzip")))
  prov <- jsonlite::read_json(file.path(root, "both_export.json"))
  expect_equal(unlist(prov$files$study_archive), file.path(root, c("both_study_12.jzip", "both_study_13.jzip")))
  ids <- sub("^.*/studies/", "", request_paths(rec)[grepl("/studies/", request_paths(rec))])
  expect_equal(ids, c("12", "12", "13"))

  # off by default, and checked as a flag
  suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "plain.rds")))
  expect_false(file.exists(file.path(root, "plain_study.jzip")))
  expect_null(jsonlite::read_json(file.path(root, "plain_export.json"))$files$study_archive)
  expect_error(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "q.rds"), archive_study = NA), "TRUE", class = "jatosr_bad_argument")
})
