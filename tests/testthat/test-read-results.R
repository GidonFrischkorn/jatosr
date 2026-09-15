write_text <- function(text, .env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".txt", .local_envir = .env)
  writeBin(charToRaw(enc2utf8(text)), path)
  path
}

test_that("jatos_read_json reads a single array into one row per trial", {
  path <- write_text('[{"trial_index":0,"rt":300,"city":"Zürich"},{"trial_index":1,"rt":null,"city":"Bern"}]')
  trials <- jatos_read_json(path)
  expect_s3_class(trials, "tbl_df")
  expect_equal(nrow(trials), 2)
  expect_equal(trials$trial_index, c(0L, 1L))
  expect_equal(trials$rt, c(300L, NA))
  expect_equal(trials$city, c("Zürich", "Bern"))
})

test_that("jatos_read_json joins the top-level values that appendResultData leaves behind", {
  trials <- jatos_read_json(fixture_path("data-concatenated.txt"))
  expect_equal(nrow(trials), 2)
  expect_equal(trials$trial_index, c(0L, 1L))
  expect_equal(trials$rt, c(300L, 420L))

  # arrays after arrays, empty arrays at a seam, whitespace between values
  expect_equal(join_json_values('[{"a":1}] [{"a":2}]'), '[{"a":1},{"a":2}]')
  expect_equal(join_json_values('[][{"a":2}]'), '[{"a":2}]')
  expect_equal(join_json_values('[{"a":1}][]\n'), '[{"a":1}]')
  expect_equal(join_json_values('[{"a":1}]'), '[{"a":1}]')
  # one object per call, and objects mixed with arrays
  expect_equal(join_json_values('{"a":1}{"a":2}'), '[{"a":1},{"a":2}]')
  expect_equal(join_json_values('{"a":1}\n[{"a":2},{"a":3}]'), '[{"a":1},{"a":2},{"a":3}]')
  expect_equal(nrow(jatos_read_json(write_text('{"a":1}{"a":2}'))), 2)
  # seam text and brackets inside string values, escaped quotes included
  expect_equal(join_json_values('[{"a":"x][y"}]'), '[{"a":"x][y"}]')
  expect_equal(jatos_read_json(write_text('[{"a":"}][{"}]'))$a, "}][{")
  expect_equal(jatos_read_json(write_text('[{"a":"q\\"}][{\\"z"}]'))$a, 'q"}][{"z')
  expect_equal(jatos_read_json(write_text('[{"a":"back\\\\"}][{"a":"x"}]'))$a, c("back\\", "x"))
  # non-ASCII text does not shift the byte positions
  expect_equal(jatos_read_json(write_text('[{"a":"Zürich"}][{"a":"Genève"}]'))$a, c("Zürich", "Genève"))
  # a truncated file, a scalar, or text between values is left to jsonlite
  expect_null(join_json_values('[{"a":1},{"a":'))
  expect_null(join_json_values('"abc"'))
  expect_null(join_json_values('[{"a":1}] x [{"a":2}]'))
  expect_null(join_json_values(']['))
  expect_error(jatos_read_json(write_text('[{"a":1}] x [{"a":2}]')), "not valid JSON")
  expect_error(jatos_read_json(write_text('{"a":1}{"a":')), "not valid JSON")
  # the extractor's cross-check parses with the same rule
  expect_length(parse_for_check('{"a":1}{"a":2}'), 2)
  expect_null(parse_for_check('{"a":1}{"a":'))
})

test_that("one clean array goes to jsonlite without the splitter, everything else through it", {
  clean <- ' \n[{"a":1,"b":"x"},{"a":2,"b":"y"}]\n'
  expected <- jsonlite::fromJSON(clean)
  # the fast path: the splitter is never entered for a single array
  local({
    local_mocked_bindings(join_json_values = function(text) stop("splitter entered"))
    expect_identical(parse_result_json(clean), expected)
    expect_identical(parse_result_json("[]"), list())
    expect_identical(parse_result_json("[1,2,3]"), 1:3)
    expect_error(parse_result_json('{"a":1}{"a":2}'), "splitter entered")
  })
  # a text jsonlite refuses falls back to the splitter and gives the same tibble
  expect_identical(parse_result_json('[{"a":1,"b":"x"}] [{"a":2,"b":"y"}]'), expected)
  expect_identical(parse_result_json('[{"a":1,"b":"x"}][]'), jsonlite::fromJSON('[{"a":1,"b":"x"}]'))
  # the arguments reach jsonlite on both paths
  flat <- parse_result_json('[{"r":{"k":1}}]', flatten = TRUE)
  expect_equal(names(flat), "r.k")
  expect_equal(names(parse_result_json('[{"r":{"k":1}}] [{"r":{"k":2}}]', flatten = TRUE)), "r.k")
  expect_type(parse_result_json('[{"a":1}]', simplify = FALSE), "list")
  # a text that starts with [ and that neither can read errors with jsonlite's message
  err <- expect_error(parse_result_json('[{"a":1},{"a":'), class = "error")
  expect_false(grepl("splitter", conditionMessage(err)))
  expect_error(jatos_read_json(write_text('[{"a":1},{"a":')), "not valid JSON")
})

test_that("jatos_read_json handles empty files and rejects broken ones", {
  empty <- write_text("")
  expect_equal(nrow(jatos_read_json(empty)), 0)
  expect_equal(ncol(jatos_read_json(empty)), 0)
  blank <- write_text("  \n")
  expect_equal(nrow(jatos_read_json(blank)), 0)
  expect_equal(nrow(jatos_read_json(write_text("[]"))), 0)

  broken <- write_text('[{"a":1},{"a":')
  expect_error(jatos_read_json(broken), "not valid JSON")
  expect_error(jatos_read_json(write_text("[1,2,3]")), "not an array of objects")
  expect_error(jatos_read_json("/no/such/file.txt"), "does not exist", class = "jatosr_bad_argument")

  one <- jatos_read_json(write_text('{"a":1,"b":"x"}'))
  expect_equal(nrow(one), 1)
  expect_equal(one$b, "x")
})

test_that("a NUL byte in a result file is an error naming the file, not a truncated read", {
  path <- withr::local_tempfile(fileext = ".txt")
  writeBin(c(charToRaw('[{"a":1},'), as.raw(0), charToRaw('{"a":2}]')), path)
  # readChar() stopped at the NUL with a warning and returned the head
  # before; now the whole file is refused
  err <- expect_error(read_text_file(path), class = "rlang_error")
  expect_match(conditionMessage(err), "NUL byte at position 10 of 18")
  expect_match(conditionMessage(err), basename(path), fixed = TRUE)
  expect_error(jatos_read_json(path), "NUL byte")
  expect_no_warning(tryCatch(jatos_read_json(path), error = function(e) NULL))

  # the reader skips such a file on request, and the extractor names it
  meta <- meta_with_files(list("7001" = '[{"a":1}]', "7003" = "placeholder"))
  writeBin(c(charToRaw('[{"a":'), as.raw(0), charToRaw("2}]")), meta$file[3])
  w <- capture_warnings(suppressMessages(trials <- jatos_read_results(meta, on_error = "skip")))
  expect_equal(trials$a, 1L)
  expect_match(w, "NUL byte")
  expect_error(suppressMessages(jatos_extract_fields(meta, "a")), "NUL byte")
  # a file that is all NUL, and the empty file, for the boundaries
  writeBin(as.raw(0), path)
  expect_error(read_text_file(path), "position 1 of 1")
  writeBin(raw(), path)
  expect_equal(read_text_file(path), "")
  # bytes are read as bytes: non-ASCII text keeps its length
  writeBin(charToRaw('[{"a":"Zürich"}]'), path)
  expect_equal(read_text_file(path), '[{"a":"Zürich"}]')
  expect_equal(Encoding(read_text_file(path)), "UTF-8")
})

test_that("an empty key becomes a named column instead of an error", {
  path <- write_text('[{"t":0,"":"x","k":1},{"t":1,"":"z","k":2}]')
  trials <- jatos_read_json(path)
  expect_equal(names(trials), c("t", "unnamed_2", "k"))
  expect_equal(trials$unnamed_2, c("x", "z"))
  expect_equal(repair_json_names(c("a", "", "a", "")), c("a", "unnamed_2", "a_1", "unnamed_4"))
  bound <- jatos_read_results(c(path, path))
  expect_equal(nrow(bound), 4)
  expect_equal(names(bound), c("file", "t", "unnamed_2", "k"))
})

test_that("jatos_read_json can flatten nested objects", {
  path <- write_text('[{"trial_index":0,"response":{"age":"31","hand":"r"}}]')
  nested <- jatos_read_json(path)
  expect_s3_class(nested$response, "data.frame")
  flat <- jatos_read_json(path, flatten = TRUE)
  expect_equal(flat$response.age, "31")
})

test_that("jatos_read_results binds heterogeneous files and attaches id columns", {
  meta <- meta_with_files(list(
    "7001" = '[{"trial_index":0,"rt":300},{"trial_index":1,"rt":420}]',
    "7006" = '[{"trial_index":0,"response":"yes"}]',
    "7005" = ""
  ))

  msgs <- capture_messages(trials <- jatos_read_results(meta))
  expect_match(paste(msgs, collapse = "\n"), "3 rows have no local file\\.")
  one_missing <- meta[!is.na(meta$file) | seq_len(nrow(meta)) == which(is.na(meta$file))[[1]], ]
  msgs <- capture_messages(jatos_read_results(one_missing))
  expect_match(paste(msgs, collapse = "\n"), "1 row has no local file\\.")
  expect_equal(names(trials)[1:2], c("study_result_id", "component_result_id"))
  expect_equal(nrow(trials), 3)
  expect_equal(trials$study_result_id, c(9001L, 9001L, 9004L))
  expect_equal(trials$component_result_id, c(7001L, 7001L, 7006L))
  expect_equal(trials$rt, c(300L, 420L, NA))
  expect_equal(trials$response, c(NA, NA, "yes"))

  with_batch <- jatos_read_results(meta[c(1, 6), ], id_cols = c("batch_id", "component_result_id"))
  expect_equal(names(with_batch)[1:2], c("batch_id", "component_result_id"))
  expect_equal(with_batch$batch_id, c(34L, 34L, 36L))

  from_paths <- jatos_read_results(meta$file[c(1, 6)])
  expect_equal(names(from_paths)[1], "file")
  expect_equal(nrow(from_paths), 3)
})

test_that("jatos_read_results joins metadata columns to every trial row", {
  meta <- meta_with_files(list(
    "7001" = '[{"trial_index":0,"rt":300},{"trial_index":1,"rt":420}]',
    "7006" = '[{"trial_index":0,"response":"yes"}]'
  ))

  trials <- suppressMessages(jatos_read_results(meta))
  expect_equal(
    names(trials),
    c(
      "study_result_id", "component_result_id", "batch_id", "component_id",
      "worker_id", "worker_type", "study_state", "study_start_time", "trial_index", "rt", "response"
    )
  )
  expect_equal(trials$batch_id, c(34L, 34L, 36L))
  expect_equal(trials$component_id, meta$component_id[c(1, 1, 6)])
  expect_equal(trials$worker_id, meta$worker_id[c(1, 1, 6)])
  expect_equal(trials$worker_type, c("GeneralMultiple", "GeneralMultiple", "PersonalSingle"))
  expect_equal(trials$study_state, meta$study_state[c(1, 1, 6)])
  expect_s3_class(trials$study_start_time, "POSIXct")
  expect_equal(trials$study_start_time, meta$study_start_time[c(1, 1, 6)])
  expect_equal(trials$rt, c(300L, 420L, NA))
  expect_equal(eval(formals(jatos_read_results)$metadata_cols), default_metadata_cols())

  # an extracted field is joined when named; its status column is not
  meta$pid <- c("P1", NA, "P2", NA, "P4", "P4")
  meta$pid_status <- c("unique", NA, "unique", NA, "unique", "unique")
  with_pid <- suppressMessages(jatos_read_results(meta, metadata_cols = c("batch_id", "pid")))
  expect_equal(names(with_pid)[1:4], c("study_result_id", "component_result_id", "batch_id", "pid"))
  expect_equal(with_pid$pid, c("P1", "P1", "P4"))
  expect_false("pid_status" %in% names(with_pid))

  # NULL keeps only the id columns; a column named twice is joined once
  plain <- suppressMessages(jatos_read_results(meta, metadata_cols = NULL))
  expect_equal(names(plain), c("study_result_id", "component_result_id", "trial_index", "rt", "response"))
  twice <- suppressMessages(jatos_read_results(meta, metadata_cols = c("component_result_id", "batch_id")))
  expect_equal(names(twice)[1:3], c("study_result_id", "component_result_id", "batch_id"))
  expect_equal(sum(names(twice) == "component_result_id"), 1)

  # a character x ignores metadata_cols
  from_paths <- jatos_read_results(meta$file[c(1, 6)])
  expect_equal(names(from_paths)[1], "file")
  expect_false("batch_id" %in% names(from_paths))

  # nothing readable gives zero rows, still with the joined columns absent
  none <- suppressMessages(jatos_read_results(meta[c(2, 4), ]))
  expect_equal(nrow(none), 0)
})

test_that("jatos_read_results refuses a trial column that a metadata column would shadow", {
  meta <- meta_with_files(list(
    "7001" = '[{"trial_index":0,"worker_id":"w9","batch_id":1}]',
    "7003" = '[{"trial_index":0}]'
  ))

  err <- expect_error(suppressMessages(jatos_read_results(meta)), class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "batch_id")
  expect_match(conditionMessage(err), "worker_id")
  expect_match(conditionMessage(err), "comp-result_7001")

  # dropping the clashing names from the join keeps the trial values
  ok <- suppressMessages(jatos_read_results(meta, metadata_cols = c("component_id", "study_state")))
  expect_equal(ok$worker_id, c("w9", NA))
  expect_equal(ok$batch_id, c(1L, NA))

  # id_cols are covered by the same check
  writeLines('[{"trial_index":0,"study_result_id":5}]', meta$file[1])
  expect_error(suppressMessages(jatos_read_results(meta, metadata_cols = NULL)), "study_result_id", class = "jatosr_bad_argument")

  expect_error(jatos_read_results(meta, metadata_cols = "nope"), "nope", class = "jatosr_bad_metadata")
  expect_error(jatos_read_results(meta, metadata_cols = 1), "metadata_cols", class = "jatosr_bad_argument")
  expect_error(jatos_read_results(meta, id_cols = NA_character_), "id_cols", class = "jatosr_bad_argument")
})

test_that("jatos_read_results needs only file and the joined columns of a metadata tibble", {
  meta <- meta_with_files(list("7001" = '[{"trial_index":0}]', "7006" = '[{"trial_index":0}]'))
  slim <- meta[, c("file", "study_result_id", "component_result_id")]

  trials <- suppressMessages(jatos_read_results(slim, metadata_cols = NULL))
  expect_equal(names(trials), c("study_result_id", "component_result_id", "trial_index"))
  expect_equal(nrow(trials), 2)
  err <- expect_error(suppressMessages(jatos_read_results(slim)), "batch_id", class = "jatosr_bad_metadata")
  expect_false(grepl("data_size", conditionMessage(err)))
  expect_error(suppressMessages(jatos_read_results(slim, metadata_cols = NULL, split = "component")), "component_id", class = "jatosr_bad_metadata")
})

test_that("a reader of your own replaces jatos_read_json and is checked", {
  meta <- meta_with_files(list("7001" = "trial,rt\n0,300\n1,420\n", "7006" = "trial,rt\n0,8800\n"))

  trials <- suppressMessages(
    jatos_read_results(meta, reader = function(file) utils::read.csv(file), metadata_cols = "batch_id")
  )
  expect_equal(names(trials), c("study_result_id", "component_result_id", "batch_id", "trial", "rt"))
  expect_equal(trials$rt, c(300L, 420L, 8800L))
  expect_s3_class(trials, "tbl_df")

  # the default reader refuses the csv; a reader must be a function and return a data frame
  expect_error(suppressMessages(jatos_read_results(meta)), "not valid JSON")
  expect_error(jatos_read_results(meta, reader = "read.csv"), "reader", class = "jatosr_bad_argument")
  expect_error(
    suppressMessages(jatos_read_results(meta, reader = function(file) readLines(file))),
    "data frame",
    class = "jatosr_bad_argument"
  )
  expect_error(jatos_read_results(meta, on_error = "ignore"), "on_error")
})

test_that("on_error = 'skip' leaves unreadable files out with one warning", {
  meta <- meta_with_files(list(
    "7001" = '[{"trial_index":0,"rt":300}]',
    "7003" = '[{"trial_index":0},{"trial_index":',
    "7005" = '[1,2,3]',
    "7006" = '[{"trial_index":0,"rt":8800}]'
  ))

  expect_error(suppressMessages(jatos_read_results(meta)), "not valid JSON")
  w <- capture_warnings(suppressMessages(trials <- jatos_read_results(meta, on_error = "skip")))
  expect_length(w, 1)
  expect_match(w, "2 files could not be read and were skipped")
  expect_match(w, "not valid JSON")
  expect_match(w, "comp-result_7003")
  expect_match(w, "comp-result_7005")
  expect_equal(trials$component_result_id, c(7001L, 7006L))
  expect_equal(trials$rt, c(300L, 8800L))
  # classed, with the files, for a caller that counts them
  cnd <- expect_warning(suppressMessages(jatos_read_results(meta, on_error = "skip")), class = "jatosr_files_skipped")
  bad <- meta$component_result_id %in% c(7003L, 7005L)
  expect_equal(cnd$files, meta$file[bad])

  # a clash is a configuration error and still aborts
  writeLines('[{"trial_index":0,"batch_id":1}]', meta$file[1])
  expect_error(suppressMessages(jatos_read_results(meta, on_error = "skip")), "batch_id", class = "jatosr_bad_argument")
})

test_that("split = 'component' returns one tibble per component id", {
  meta <- meta_with_files(list(
    "7001" = '[{"trial_index":0,"rt":300}]',
    "7003" = '[{"trial_index":0,"rt":"slow"}]',
    "7005" = '[{"trial_index":0,"rt":2100}]',
    "7006" = '[{"trial_index":0,"response":"yes"}]'
  ))

  # 7001 and 7003 share component 121 and disagree on rt: the split cannot help there
  expect_error(suppressMessages(jatos_read_results(meta, split = "component")), "disagree on a column")
  writeLines('[{"trial_index":0,"rt":950}]', meta$file[3])
  writeLines('[{"trial_index":0,"rt":"slow"}]', meta$file[5])
  # now 7005 (component 131) disagrees with the others: the split keeps them apart
  expect_error(suppressMessages(jatos_read_results(meta)), "disagree on a column")
  parts <- suppressMessages(jatos_read_results(meta, split = "component"))
  expect_type(parts, "list")
  expect_equal(names(parts), c("121", "131", "132"))
  expect_equal(parts[["121"]]$rt, c(300L, 950L))
  expect_equal(parts[["131"]]$rt, "slow")
  expect_equal(parts[["132"]]$response, "yes")
  expect_equal(names(parts[["132"]])[1:3], c("study_result_id", "component_result_id", "batch_id"))

  expect_error(jatos_read_results(meta$file[1], split = "component"), "component_id", class = "jatosr_bad_argument")
  expect_error(jatos_read_results(meta, split = "batch"), "split")

  # a file the reader cannot parse leaves its component's tibble short, the
  # others whole, with the one warning; a component whose only file is
  # skipped still has its tibble, with zero rows
  writeLines('[{"trial_index":0},{"trial_index":', meta$file[3])
  writeLines("not json", meta$file[5])
  w <- capture_warnings(suppressMessages(parts <- jatos_read_results(meta, split = "component", on_error = "skip")))
  expect_length(w, 1)
  expect_match(w, "2 files could not be read")
  expect_equal(names(parts), c("121", "131", "132"))
  expect_equal(parts[["121"]]$component_result_id, 7001L)
  expect_equal(nrow(parts[["131"]]), 0)
  expect_equal(names(parts[["131"]])[1:2], c("study_result_id", "component_result_id"))
  expect_equal(parts[["132"]]$response, "yes")
})

test_that("a nested object column is a list column whatever shape the files give it", {
  # every trial of the first file carries a response object with the same
  # keys (jsonlite: a data-frame column); the second mixes objects, null
  # and a scalar (a list column); the third has no response at all
  a <- write_text('[{"t":0,"response":{"age":"31","hand":"r"}},{"t":1,"response":{"age":"40","hand":"l"}}]')
  b <- write_text('[{"t":0,"response":{"age":"29"}},{"t":1,"response":null},{"t":2,"response":5}]')
  c <- write_text('[{"t":0}]')
  expect_s3_class(jatos_read_json(a)$response, "data.frame")
  expect_type(jatos_read_json(b)$response, "list")

  msgs <- capture_messages(trials <- jatos_read_results(c(a, b, c)))
  expect_match(paste(msgs, collapse = "\n"), "Stored the nested object column response as list column")
  expect_type(trials$response, "list")
  expect_equal(nrow(trials), 6)
  expect_equal(trials$response[[1]], list(age = "31", hand = "r"))
  expect_equal(trials$response[[2]], list(age = "40", hand = "l"))
  expect_equal(trials$response[[3]], list(age = "29"))
  expect_null(trials$response[[4]])
  expect_equal(trials$response[[5]], 5L)
  expect_null(trials$response[[6]])
  expect_equal(names(trials), c("file", "t", "response"))

  # a key some trials lack is absent from their lists, not NA
  d <- write_text('[{"t":0,"response":{"age":"31","hand":"r"}},{"t":1,"response":{"age":"40"}}]')
  out <- suppressMessages(jatos_read_results(c(d, c)))
  expect_equal(out$response[[2]], list(age = "40"))
  # nested inside nested
  e <- write_text('[{"t":0,"r":{"inner":{"k":1}}},{"t":1,"r":{"inner":{"k":2}}}]')
  out <- suppressMessages(jatos_read_results(c(e, c)))
  expect_equal(out$r[[2]], list(inner = list(k = 2L)))
  # an object without keys in every trial (a zero-column data frame), and
  # an object without keys in some trials
  g <- write_text('[{"t":0,"r":{}},{"t":1,"r":{}}]')
  expect_s3_class(jatos_read_json(g)$r, "data.frame")
  out <- suppressMessages(jatos_read_results(c(g, c)))
  expect_equal(out$r, list(NULL, NULL, NULL))
  h <- write_text('[{"t":0,"r":{"k":1}},{"t":1,"r":{}}]')
  out <- suppressMessages(jatos_read_results(c(h, c)))
  expect_equal(out$r, list(list(k = 1L), NULL, NULL))
  # one message for several columns, none without a nested column
  f <- write_text('[{"t":0,"r":{"k":1},"s":{"k":2}}]')
  msgs <- capture_messages(jatos_read_results(c(f, f)))
  expect_length(msgs, 1)
  expect_match(msgs, "columns r and s")
  expect_no_message(jatos_read_results(c(c, c)))
  # flatten = TRUE has no nested column to store, so nothing is said
  flat <- jatos_read_results(c(a, c), flatten = TRUE)
  expect_equal(flat$response.age, c("31", "40", NA))
})

test_that("coerce = 'character' converts columns the files disagree on", {
  a <- write_text('[{"rt":300,"ok":true,"note":null}]')
  b <- write_text('[{"rt":"slow","ok":1,"note":"n"}]')
  expect_error(jatos_read_results(c(a, b)), "disagree on a column")
  msgs <- capture_messages(out <- jatos_read_results(c(a, b), coerce = "character"))
  expect_match(msgs, "Coerced the column rt to character")
  expect_equal(out$rt, c("300", "slow"))
  # logical and numeric share a family, an all-NA column belongs to none
  expect_equal(out$ok, c(1, 1))
  expect_equal(out$note, c(NA, "n"))
  expect_equal(conflicting_columns(list(jatos_read_json(a), jatos_read_json(b))), "rt")
  # a list column against an atomic one cannot be coerced and stays an error,
  # and the column is not named as coercible
  l <- write_text('[{"rt":[1,2]}]')
  err <- expect_error(jatos_read_results(c(a, l), coerce = "character"), "disagree on a column")
  expect_match(conditionMessage(err), "rt")
  expect_equal(conflicting_columns(list(jatos_read_json(a), jatos_read_json(l))), character())
  # nor can two list columns of different shapes be coerced, they bind as lists
  l2 <- write_text('[{"rt":{"k":1}}]')
  expect_type(jatos_read_results(c(l, l2), coerce = "character")$rt, "list")
  expect_error(jatos_read_results(c(a, b), coerce = "numeric"), "coerce")
  # with the split, coercion works within each component
  meta <- meta_with_files(list("7001" = '[{"rt":300}]', "7003" = '[{"rt":"slow"}]', "7005" = '[{"rt":1}]'))
  parts <- suppressMessages(jatos_read_results(meta, split = "component", coerce = "character"))
  expect_equal(parts[["121"]]$rt, c("300", "slow"))
  expect_equal(parts[["131"]]$rt, 1L)
})

test_that("the id columns are prepended once after the bind", {
  meta <- meta_with_files(list("7001" = '[{"t":0},{"t":1},{"t":2}]', "7003" = "[]", "7006" = '[{"t":0}]'))
  trials <- suppressMessages(jatos_read_results(meta, metadata_cols = "batch_id"))
  expect_equal(trials$study_result_id, c(9001L, 9001L, 9001L, 9004L))
  expect_equal(trials$component_result_id, c(7001L, 7001L, 7001L, 7006L))
  expect_equal(trials$batch_id, c(34L, 34L, 34L, 36L))
  expect_equal(trials$t, c(0L, 1L, 2L, 0L))
  # zero readable rows still gives the id columns
  none <- suppressMessages(jatos_read_results(meta[3, ], metadata_cols = "batch_id"))
  expect_equal(names(none), c("study_result_id", "component_result_id", "batch_id"))
  expect_equal(nrow(none), 0)
})

test_that("jatos_read_results explains incompatible column types and checks input", {
  a <- write_text('[{"rt":300}]')
  b <- write_text('[{"rt":"slow"}]')
  err <- expect_error(jatos_read_results(c(a, b)), "disagree on a column")
  expect_match(conditionMessage(err), 'coerce = "character"', fixed = TRUE)
  expect_error(jatos_read_results(c(a, b), TRUE), "must be empty|\\.\\.\\.")
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  expect_error(jatos_read_results(meta), "file", class = "jatosr_bad_metadata")
  meta$file <- NA_character_
  expect_error(jatos_read_results(meta, id_cols = "nope"), "nope", class = "jatosr_bad_metadata")
  all_missing <- suppressMessages(jatos_read_results(meta))
  expect_equal(nrow(all_missing), 0)
})
