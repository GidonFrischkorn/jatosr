test_that("jatos_write_raw copies each data file byte for byte under its study result id", {
  meta <- meta_with_files(list(
    "7001" = '[{"a":"Zürich"}]',
    "7003" = '[{"a":2}]',
    "7005" = '[{"a":3}]',
    "7006" = '[{"a":4}]'
  ))
  dir <- file.path(withr::local_tempdir(), "raw")

  msgs <- capture_messages(out <- expect_invisible(jatos_write_raw(meta, dir)))
  expect_match(paste(msgs, collapse = "\n"), "2 rows have no local file\\.")
  expect_match(paste(msgs, collapse = "\n"), "Wrote 4 files")
  # 9004 has two files, one per component: suffixed by component result id
  expect_equal(
    sort(list.files(dir)),
    c("9001.json", "9002.json", "9004_7005.json", "9004_7006.json")
  )
  expect_equal(names(out), c("study_result_id", "component_result_id", "file", "path"))
  expect_equal(out$component_result_id, c(7001L, 7003L, 7005L, 7006L))
  expect_equal(basename(out$path), c("9001.json", "9002.json", "9004_7005.json", "9004_7006.json"))
  expect_identical(
    readBin(out$path[1], "raw", file.size(out$path[1])),
    readBin(meta$file[1], "raw", file.size(meta$file[1]))
  )
  expect_equal(readLines(out$path[1], encoding = "UTF-8", warn = FALSE), '[{"a":"Zürich"}]')

  # an existing file is refused unless overwrite; nothing is written before the check
  writeLines("x", file.path(dir, "9002.json"))
  unlink(file.path(dir, "9001.json"))
  expect_error(jatos_write_raw(meta, dir), "9002.json", class = "jatosr_file_exists")
  expect_false(file.exists(file.path(dir, "9001.json")))
  suppressMessages(jatos_write_raw(meta, dir, overwrite = TRUE))
  expect_equal(readLines(file.path(dir, "9002.json"), warn = FALSE), '[{"a":2}]')
})

test_that("jatos_write_raw names by another column, including an extracted field", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":"P1"}]',
    "7003" = '[{"pid":"P2"}]',
    "7006" = '[{"pid":"P4"}]'
  ))
  dir <- withr::local_tempdir()
  out <- suppressMessages(jatos_write_raw(meta, file.path(dir, "by_worker"), name_by = "worker_id"))
  expect_equal(basename(out$path), c("501.json", "502.json", "504.json"))

  extracted <- suppressMessages(jatos_extract_fields(meta, "pid", warn = FALSE))
  out <- suppressMessages(jatos_write_raw(extracted, file.path(dir, "by_pid"), name_by = "pid"))
  expect_equal(basename(out$path), c("P1.json", "P2.json", "P4.json"))

  # a name shared by two study results is refused with the ids
  extracted$pid[c(1, 3)] <- "SAME"
  err <- expect_error(jatos_write_raw(extracted, file.path(dir, "dup"), name_by = "pid"), class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "SAME")
  expect_match(conditionMessage(err), "9001 and 9002")
  expect_false(dir.exists(file.path(dir, "dup")))
  # NA names are refused with the rows named
  extracted$pid[1] <- NA
  err <- expect_error(jatos_write_raw(extracted, file.path(dir, "na"), name_by = "pid"), class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "7001")
  expect_match(conditionMessage(err), "NA")
  # two NA rows: the message pluralises after the id list (it errored inside
  # cli before, since `{ids}` reset the quantity)
  extracted$pid[3] <- NA
  err <- expect_error(jatos_write_raw(extracted, file.path(dir, "na"), name_by = "pid"), class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "7001 and 7003")
  expect_match(conditionMessage(err), "those rows")
})

test_that("a name that could leave the directory is refused before anything is written", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":"P1"}]',
    "7003" = '[{"pid":"P2"}]',
    "7006" = '[{"pid":"P4"}]'
  ))
  root <- withr::local_tempdir()
  dir <- file.path(root, "inner", "raw")
  dir.create(dir, recursive = TRUE)
  extracted <- suppressMessages(jatos_extract_fields(meta, "pid", warn = FALSE))

  # the participant-controlled value of the review: two directories up
  extracted$pid[1] <- "../../escaped"
  err <- expect_error(jatos_write_raw(extracted, dir, name_by = "pid"), class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "outside")
  expect_match(conditionMessage(err), "7001")
  expect_false(file.exists(file.path(root, "escaped.json")))
  expect_length(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0)

  # every unsafe shape, each naming its row; nothing of the safe rows is written either
  for (bad in c("a/b", "a\\b", ".", "..", "/abs")) {
    extracted$pid[c(1, 6)] <- c(bad, "P4")
    extracted$pid[3] <- bad
    err <- expect_error(jatos_write_raw(extracted, dir, name_by = "pid"), class = "jatosr_bad_argument")
    expect_match(conditionMessage(err), "7001 and 7003")
    expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 0)
  }
  # the same check on the id and worker columns costs nothing and changes nothing
  out <- suppressMessages(jatos_write_raw(meta, file.path(root, "ok"), name_by = "worker_id"))
  expect_equal(basename(out$path), c("501.json", "502.json", "504.json"))
})

test_that("jatos_write_raw writes each copy through a temporary name", {
  meta <- meta_with_files(list("7001" = '[{"a":1}]', "7003" = '[{"a":2}]'))
  dir <- file.path(withr::local_tempdir(), "raw")

  # the rename into place fails: nothing sits under the real name, and no
  # temporary file is left in the directory (the copy went straight to the
  # real name before)
  local({
    local_mocked_bindings(move_file = function(from, to) cli::cli_abort("disk full"))
    expect_error(suppressMessages(jatos_write_raw(meta, dir)), "disk full")
    expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 0)
  })
  # a source that cannot be read is an error naming the target, with the same guarantees
  gone <- meta
  unlink(gone$file[3])
  err <- expect_error(suppressMessages(jatos_write_raw(gone, dir)), class = "rlang_error")
  expect_match(conditionMessage(err), "9002.json")
  expect_equal(list.files(dir, all.files = TRUE, no.. = TRUE), "9001.json")
})

test_that("jatos_write_raw checks its input", {
  meta <- meta_with_files(list("7001" = "[]"))
  dir <- withr::local_tempdir()
  expect_error(jatos_write_raw(meta, dir, name_by = "nope"), "nope", class = "jatosr_bad_metadata")
  expect_error(jatos_write_raw(meta, dir, name_by = "url_query"), "list column", class = "jatosr_bad_argument")
  expect_error(jatos_write_raw(meta[, c("study_result_id", "file")], dir), "component_result_id", class = "jatosr_bad_metadata")
  expect_error(jatos_write_raw(fixture_metadata(), dir), "file", class = "jatosr_bad_metadata")
  expect_error(jatos_write_raw(meta, ""), "path", class = "jatosr_bad_argument")
  expect_error(jatos_write_raw(meta, dir, overwrite = 1), "TRUE", class = "jatosr_bad_argument")
  expect_equal(list.files(dir), character())
  none <- suppressMessages(jatos_write_raw(meta[meta$component_result_id != 7001L, ], dir))
  expect_equal(nrow(none), 0)
})
