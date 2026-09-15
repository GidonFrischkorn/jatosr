# The files under inst/extdata/ that the runnable examples read (see
# data-raw/make-fixtures.R). The examples run only under R CMD check, so a
# fixture that drifts from its metadata would otherwise surface there first.

extdata <- function(...) {
  system.file("extdata", ..., package = "jatosr", mustWork = TRUE)
}

test_that("the shipped cache is complete: nothing pending, nothing orphaned", {
  status <- jatos_cache_status(extdata("JATOS_data"))
  expect_equal(nrow(status), 1)
  expect_equal(status$batch_id, 34L)
  expect_equal(status$n_results, 4L)
  expect_equal(status$n_downloaded, 2L)
  expect_equal(status$n_pending, 0L)
  expect_equal(status$n_shrunk, 0L)
  expect_equal(status$n_orphans, 0L)
  expect_equal(status$bytes, 2048 + 1536)
})

test_that("the shipped cache is batch 34 of the shipped metadata.json", {
  whole <- jatos_flatten_metadata(extdata("metadata.json"))
  cached <- jatos_read_metadata(extdata("JATOS_data"))
  expect_equal(cached[, names(whole)], whole[whole$batch_id == 34, ], ignore_attr = TRUE)
  expect_equal(cached$worker_id, c(501L, 502L, 502L, 503L))
})

test_that("the shipped results zip imports to the shipped cache", {
  root <- file.path(withr::local_tempdir(), "cache")
  imported <- suppressMessages(jatos_import_results(extdata("results.zip"), root))
  shipped <- jatos_read_metadata(extdata("JATOS_data"))
  columns <- setdiff(names(shipped), "file")
  expect_equal(imported[, columns], shipped[, columns], ignore_attr = TRUE)
  expect_equal(
    unname(tools::md5sum(imported$file[!is.na(imported$file)])),
    unname(tools::md5sum(shipped$file[!is.na(shipped$file)]))
  )
})

test_that("the shipped data.txt and the cached files are jsPsych trials", {
  trials <- jatos_read_json(extdata("data.txt"))
  expect_equal(trials$trial_index, 0:8)
  expect_equal(unique(trials$participant_id), "P501")

  meta <- jatos_extract_fields(jatos_read_metadata(extdata("JATOS_data")), c("participant_id", "age"))
  expect_equal(meta$participant_id, c("P501", NA, "P502", NA))
  expect_equal(meta$age, c("24", NA, "31", NA))
})
