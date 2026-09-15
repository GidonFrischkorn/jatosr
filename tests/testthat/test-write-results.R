sample_trials <- function() {
  tibble::tibble(
    study_result_id = c(9001L, 9001L, 9004L),
    component_result_id = c(7001L, 7001L, 7006L),
    component_id = c(131L, 131L, 132L),
    study_start_time = as.POSIXct(
      c("2025-08-24 01:46:40", "2025-08-24 01:46:40", NA),
      tz = "UTC"
    ),
    trial_index = c(0L, 1L, 0L),
    rt = c(512.5, -1, 8800),
    city = c("Zürich", "Zürich", NA),
    correct = c(TRUE, FALSE, NA),
    response = list(NULL, list(age = "31", hand = "r"), c("a", "b"))
  )
}

test_that("jatos_write_results round-trips rds and RData and returns the path", {
  dir <- withr::local_tempdir()
  x <- sample_trials()

  rds <- file.path(dir, "trials.rds")
  out <- expect_invisible(jatos_write_results(x, rds))
  expect_equal(out, rds)
  expect_identical(readRDS(rds), x)
  # no temporary file left next to it
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), "trials.rds")

  rdata <- file.path(dir, "trials.RData")
  expect_equal(jatos_write_results(x, rdata), rdata)
  env <- new.env()
  expect_equal(load(rdata, envir = env), "trials")
  expect_identical(env$trials, x)

  rda <- file.path(dir, "d.rda")
  jatos_write_results(x, rda, object = "d")
  env2 <- new.env()
  expect_equal(load(rda, envir = env2), "d")
  expect_identical(env2$d, x)
})

test_that("jatos_write_results writes UTF-8 csv with ISO times and JSON for list columns", {
  dir <- withr::local_tempdir()
  x <- sample_trials()
  csv <- file.path(dir, "trials.csv")

  msgs <- capture_messages(jatos_write_results(x, csv))
  expect_match(paste(msgs, collapse = "\n"), "response")
  expect_length(msgs, 1)

  lines <- readLines(csv, encoding = "UTF-8")
  expect_equal(lines[1], '"study_result_id","component_result_id","component_id","study_start_time","trial_index","rt","city","correct","response"')
  expect_true(any(grepl("Zürich", lines, fixed = TRUE)))
  expect_false(any(grepl("NA", lines, fixed = TRUE)))

  back <- utils::read.csv(csv, encoding = "UTF-8", na.strings = "")
  expect_equal(back$study_result_id, x$study_result_id)
  expect_equal(back$trial_index, x$trial_index)
  expect_equal(back$rt, x$rt)
  expect_equal(back$city, x$city)
  expect_equal(back$correct, x$correct)
  expect_equal(back$study_start_time, c("2025-08-24T01:46:40Z", "2025-08-24T01:46:40Z", NA))
  expect_true(is.na(back$response[1]))
  expect_true(jsonlite::validate(back$response[2]))
  expect_equal(jsonlite::fromJSON(back$response[2]), list(age = "31", hand = "r"))
  expect_equal(jsonlite::fromJSON(back$response[3]), c("a", "b"))

  # a nested data-frame column (flatten = FALSE reader output) is serialised row-wise
  y <- tibble::tibble(a = 1:2)
  y$form <- data.frame(p = c("u", NA), q = c(1L, NA))
  y$items <- list(list(), NULL)
  csv2 <- file.path(dir, "nested.csv")
  msgs <- capture_messages(jatos_write_results(y, csv2))
  expect_match(msgs, "form")
  expect_match(msgs, "items")
  back2 <- utils::read.csv(csv2, encoding = "UTF-8", na.strings = "")
  expect_equal(jsonlite::fromJSON(back2$form[1]), list(p = "u", q = 1L))
  expect_true(is.na(back2$form[2]))
  expect_equal(back2$items[1], "[]")
  expect_true(is.na(back2$items[2]))

  # no list column, no message
  expect_silent(jatos_write_results(x[, c("trial_index", "rt")], file.path(dir, "plain.csv")))
})

test_that("rows_to_json serialises a nested data frame row by row, as the per-row form did", {
  per_row <- function(df) {
    purrr::map_chr(seq_len(nrow(df)), function(i) {
      row <- as.list(df[i, , drop = FALSE])
      if (all(vapply(row, is_missing_cell, logical(1)))) NA_character_ else cell_to_json(row)
    })
  }
  df <- data.frame(
    p = c("u", NA, "Zürich", "a,b\"c"),
    q = c(1L, NA, 3L, NA),
    r = c(1.5, NA, NA, 2),
    ok = c(TRUE, NA, FALSE, NA),
    stringsAsFactors = FALSE
  )
  df$inner <- data.frame(k = c("x", NA, NA, "y"), n = c(1L, NA, NA, 2L), stringsAsFactors = FALSE)
  out <- rows_to_json(df)
  expect_true(is.na(out[2]))
  expect_equal(jsonlite::fromJSON(out[1]), list(p = "u", q = 1L, r = 1.5, ok = TRUE, inner = list(k = "x", n = 1L)))
  expect_equal(jsonlite::fromJSON(out[4])$p, "a,b\"c")
  expect_equal(jsonlite::fromJSON(out[3])$p, "Zürich")
  # the scalar fields agree with the per-row form; a nested object inside is
  # written as an object with null for its missing keys (the per-row form
  # wrapped it in a one-element array)
  ref <- per_row(df)
  for (i in c(1, 3, 4)) {
    a <- jsonlite::fromJSON(out[i])
    b <- jsonlite::fromJSON(ref[i])
    expect_equal(a[setdiff(names(a), "inner")], b[setdiff(names(b), "inner")])
  }
  expect_equal(jsonlite::fromJSON(out[3])$inner, list(k = NULL, n = NULL))
  expect_match(out[3], '"inner":{"k":null,"n":null}', fixed = TRUE)
  expect_equal(rows_to_json(df[0, ]), character())
  expect_equal(rows_to_json(data.frame(a = c(NA, NA))), c(NA_character_, NA_character_))
  # an empty nested object in every row
  e <- data.frame(a = 1:2)
  e$r <- data.frame(row.names = 1:2)
  expect_equal(missing_cells(e$r), c(TRUE, TRUE))
  expect_equal(rows_to_json(e), c('{"a":1,"r":{}}', '{"a":2,"r":{}}'))
})

test_that("jatos_write_results writes tsv and gzip-compressed csv, and parquet through arrow", {
  dir <- withr::local_tempdir()
  x <- sample_trials()

  tsv <- file.path(dir, "trials.tsv")
  suppressMessages(jatos_write_results(x, tsv))
  lines <- readLines(tsv, encoding = "UTF-8")
  expect_equal(lines[1], paste0('"', paste(names(x), collapse = '"\t"'), '"'))
  back <- utils::read.delim(tsv, encoding = "UTF-8", na.strings = "")
  expect_equal(back$rt, x$rt)
  expect_equal(back$city, x$city)
  expect_equal(jsonlite::fromJSON(back$response[2]), list(age = "31", hand = "r"))

  gz <- file.path(dir, "trials.csv.gz")
  suppressMessages(jatos_write_results(x, gz))
  expect_equal(readBin(gz, "raw", 2), as.raw(c(0x1f, 0x8b)))
  con <- gzfile(gz, encoding = "UTF-8")
  back <- utils::read.csv(con, na.strings = "")
  expect_equal(back$rt, x$rt)
  expect_equal(back$city, x$city)
  expect_equal(back$study_start_time[1], "2025-08-24T01:46:40Z")
  expect_identical(readLines(gzfile(file.path(dir, "trials.csv.gz"), encoding = "UTF-8")), {
    csv <- file.path(dir, "same.csv")
    suppressMessages(jatos_write_results(x, csv))
    readLines(csv, encoding = "UTF-8")
  })
  expect_equal(resolve_format("a.csv.gz", NULL), "csv.gz")
  expect_equal(resolve_format("A.CSV.GZ", NULL), "csv.gz")
  expect_equal(resolve_format("a.tsv", NULL), "tsv")
  expect_equal(resolve_format("a.gz", "csv.gz"), "csv.gz")
  expect_error(resolve_format("a.csv.gz", "csv"), "csv.gz", class = "jatosr_bad_argument")
  expect_equal(file_extension("a.csv.gz"), "csv.gz")
  expect_equal(file_extension("b.Csv.GZ"), "Csv.GZ")
  expect_equal(file_extension(".csv.gz"), "gz")
  expect_equal(file_extension("data.v2/trials"), "")
  expect_equal(file_extension("data.v2/trials.RDS"), "RDS")
  expect_equal(suffix_file_name("data.v2/trials.RDS", "_metadata"), "data.v2/trials_metadata.RDS")
  expect_equal(metadata_file_name("s.csv.gz"), "s_metadata.csv.gz")
  expect_equal(component_file_names("s.csv.gz", 3), "s_component_3.csv.gz")
})

test_that("jatos_write_results writes parquet through arrow", {
  # a skip, not a branch: where arrow is absent the report says so
  skip_if_not_installed("arrow")
  dir <- withr::local_tempdir()
  x <- sample_trials()
  parquet <- file.path(dir, "trials.parquet")

  # `response` mixes an object and a vector, which arrow cannot give one
  # type; it goes out as JSON strings, the atomic columns stay typed
  expect_message(jatos_write_results(x, parquet), "response")
  back <- arrow::read_parquet(parquet)
  expect_equal(names(back), names(x))
  expect_equal(back$rt, x$rt)
  expect_equal(back$city, x$city)
  expect_equal(back$correct, x$correct)
  expect_equal(nrow(back), 3)
  expect_type(back$response, "character")
  expect_true(is.na(back$response[1]))
  expect_equal(jsonlite::fromJSON(back$response[2]), list(age = "31", hand = "r"))
  expect_equal(jsonlite::fromJSON(back$response[3]), c("a", "b"))

  # a list column of one shape is arrow's to type and comes back a list
  typed <- x
  typed$response <- list(c("a", "b"), "c", character())
  parquet2 <- file.path(dir, "typed.parquet")
  expect_no_message(jatos_write_results(typed, parquet2))
  back2 <- arrow::read_parquet(parquet2)
  expect_equal(lapply(back2$response, as.character), typed$response)
})

test_that("a parquet target without arrow is refused before anything is written", {
  dir <- withr::local_tempdir()
  x <- sample_trials()
  parquet <- file.path(dir, "trials.parquet")

  # the guard is consulted before any write, whatever the machine has
  local({
    local_mocked_bindings(
      check_installed = function(pkg, ...) rlang::abort(paste("The package", pkg, "is required")),
      .package = "rlang"
    )
    expect_error(jatos_write_results(x, parquet), "arrow")
    expect_error(jatos_write_results(x, file.path(dir, "bare"), format = "parquet"), "arrow")
    expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), character())
  })
  # and rlang's own answer on a machine without arrow
  skip_if(rlang::is_installed("arrow"), "arrow is installed; the parquet write path is tested instead")
  expect_error(jatos_write_results(x, parquet), "arrow")
  expect_false(file.exists(parquet))
})

test_that("prepare_parquet_columns serialises only the list columns arrow cannot type", {
  x <- sample_trials()
  # no list column, nothing to probe: arrow is not consulted
  atomic <- x[setdiff(names(x), "response")]
  expect_no_message(out <- prepare_parquet_columns(atomic))
  expect_identical(out, atomic)

  # the probe's answer decides; the JSON is the csv writer's
  testthat::local_mocked_bindings(arrow_can_type = function(value) FALSE)
  expect_message(out <- prepare_parquet_columns(x), "response.*arrow cannot give it one type")
  expect_equal(out$response, c(NA, '{"age":"31","hand":"r"}', '["a","b"]'))
  expect_identical(out[names(atomic)], atomic)

  nested <- x
  nested$extra <- data.frame(k = c(1, NA, 3))
  expect_message(out <- prepare_parquet_columns(nested), "response.*extra.*arrow cannot give them one type")
  expect_equal(out$extra, c('{"k":1}', NA, '{"k":3}'))

  testthat::local_mocked_bindings(arrow_can_type = function(value) TRUE)
  expect_no_message(out <- prepare_parquet_columns(x))
  expect_identical(out, x)
})

test_that("jatos_write_results refuses to overwrite unless asked", {
  dir <- withr::local_tempdir()
  x <- sample_trials()
  rds <- file.path(dir, "trials.rds")
  jatos_write_results(x, rds)
  before <- readBin(rds, "raw", file.size(rds))

  expect_error(jatos_write_results(x[1, ], rds), class = "jatosr_file_exists")
  expect_identical(readBin(rds, "raw", file.size(rds)), before)
  expect_error(jatos_write_results(x[1, ], rds, overwrite = "yes"), "TRUE", class = "jatosr_bad_argument")

  jatos_write_results(x[1, ], rds, overwrite = TRUE)
  expect_equal(nrow(readRDS(rds)), 1)
})

test_that("jatos_write_results infers the format from the extension and refuses a mismatch", {
  dir <- withr::local_tempdir()
  x <- sample_trials()

  # a distinct stem: the file system may be case-insensitive
  upper <- file.path(dir, "upper.RDS")
  jatos_write_results(x, upper)
  expect_identical(readRDS(upper), x)
  expect_equal(resolve_format("a.RData", NULL), "rdata")
  expect_equal(resolve_format("a.rda", NULL), "rdata")
  expect_equal(resolve_format("a.csv", NULL), "csv")
  expect_equal(resolve_format("a.csv", "csv"), "csv")
  expect_equal(resolve_format("a.txt", "csv"), "csv")

  expect_error(jatos_write_results(x, file.path(dir, "trials.rds"), format = "csv"), "rds", class = "jatosr_bad_argument")
  expect_false(file.exists(file.path(dir, "trials.rds")))
  expect_error(jatos_write_results(x, file.path(dir, "trials")), "format", class = "jatosr_bad_argument")
  expect_error(jatos_write_results(x, file.path(dir, "trials.txt")), "format", class = "jatosr_bad_argument")
  expect_error(jatos_write_results(x, file.path(dir, "trials.rds"), format = "feather"), "feather")

  bare <- file.path(dir, "trials")
  expect_equal(jatos_write_results(x, bare, format = "rds"), bare)
  expect_identical(readRDS(bare), x)
})

test_that("jatos_write_results can write one file per component", {
  dir <- withr::local_tempdir()
  x <- sample_trials()
  target <- file.path(dir, "trials.rds")

  out <- jatos_write_results(x, target, split = "component")
  expect_equal(out, file.path(dir, c("trials_component_131.rds", "trials_component_132.rds")))
  expect_false(file.exists(target))
  expect_identical(readRDS(out[1]), x[x$component_id == 131L, ])
  expect_identical(readRDS(out[2]), x[x$component_id == 132L, ])

  # the guard covers every file before any is written
  unlink(out[1])
  expect_error(jatos_write_results(x, target, split = "component"), "trials_component_132.rds", class = "jatosr_file_exists")
  expect_false(file.exists(out[1]))
  expect_equal(component_file_names("a/b/data", c(1, 2)), c("a/b/data_component_1", "a/b/data_component_2"))
  expect_equal(component_file_names("a/b/data.rds", integer()), character())

  expect_error(jatos_write_results(x[, "rt"], target, split = "component"), "component_id", class = "jatosr_bad_argument")
  expect_error(jatos_write_results(x, target, split = "batch"), "split")

  # RData parts carry the component in the object name, like the file name
  rdata <- file.path(dir, "parts.RData")
  parts <- jatos_write_results(x, rdata, split = "component")
  env <- new.env()
  expect_equal(load(parts[1], envir = env), "trials_component_131")
  expect_equal(load(parts[2], envir = env), "trials_component_132")
  expect_identical(env$trials_component_132, x[x$component_id == 132L, ])
  named <- jatos_write_results(x, file.path(dir, "d.rda"), split = "component", object = "d")
  expect_equal(load(named[1], envir = env), "d_component_131")
})

test_that("the RData object name must be syntactic", {
  dir <- withr::local_tempdir()
  x <- sample_trials()
  for (bad in c("my data", "1st", "_x", "a-b")) {
    err <- expect_error(jatos_write_results(x, file.path(dir, "a.RData"), object = bad), class = "jatosr_bad_argument")
    expect_match(conditionMessage(err), "syntactic name")
    expect_match(conditionMessage(err), make.names(bad), fixed = TRUE)
  }
  expect_equal(list.files(dir), character())
  expect_equal(check_object_name("trials.v2"), "trials.v2")
})

test_that("jatos_write_results checks its input", {
  dir <- withr::local_tempdir()
  x <- sample_trials()
  expect_error(jatos_write_results(list(a = 1), file.path(dir, "a.rds")), "data frame", class = "jatosr_bad_argument")
  expect_error(jatos_write_results(x, file.path(dir, "a.rds"), "rds"), "must be empty|\\.\\.\\.")
  expect_error(jatos_write_results(x, file.path(dir, "a.RData"), object = ""), "object", class = "jatosr_bad_argument")
  expect_error(jatos_write_results(x, file.path(dir, "missing", "a.rds")), "does not exist", class = "jatosr_bad_argument")
  expect_error(jatos_write_results(x, ""), "file", class = "jatosr_bad_argument")
  # NA is not the archive path's "no format to resolve"; it is a bad argument
  expect_error(jatos_write_results(x, file.path(dir, "a.rds"), format = NA), "string or character vector")
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), character())
})
