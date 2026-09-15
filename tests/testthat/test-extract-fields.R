quiet_extract <- function(...) {
  suppressMessages(jatos_extract_fields(...))
}

test_that("jatos_extract_fields reads key-position values and ignores value-position decoys", {
  meta <- meta_with_files(list(
    "7001" = '[{"participant_id":"P1","rt":1},{"participant_id":"P1","rt":2}]',
    "7003" = '[{"participant_id":"P2","url":"https://x.org/run?participant_id=DECOY&letter-firstname=n","letter-firstname":"k"}]'
  ))
  out <- quiet_extract(meta, c("participant_id", "letter-firstname"), warn = FALSE)

  expect_equal(names(out), c(names(meta), "participant_id", "participant_id_status", "letter-firstname", "letter-firstname_status"))
  expect_equal(out$participant_id, c("P1", NA, "P2", NA, NA, NA))
  expect_equal(out$participant_id_status, c("unique", NA, "unique", NA, NA, NA))
  expect_equal(out$`letter-firstname`[3], "k")
  expect_equal(out$`letter-firstname_status`[1], "absent")
  expect_equal(attr(out, "jatosr_extracted"), c("participant_id", "letter-firstname"))
})

test_that("escaped JSON inside a string value is not a key", {
  meta <- meta_with_files(list(
    "7005" = '[{"participant_id":"P4","raw":"{\\"participant_id\\":\\"ESC\\"}"}]'
  ))
  out <- quiet_extract(meta, "participant_id", warn = FALSE)
  expect_equal(out$participant_id[5], "P4")
  expect_equal(out$participant_id_status[5], "unique")
})

test_that("disagreeing occurrences are a conflict with NA and a warning", {
  meta <- meta_with_files(list(
    "7001" = '[{"participant_id":"P1"},{"participant_id":"P1b"}]',
    "7003" = '[{"participant_id":"P2"}]'
  ))
  expect_warning(
    out <- quiet_extract(meta, "participant_id"),
    "1 conflict"
  )
  expect_equal(out$participant_id, c(NA, NA, "P2", NA, NA, NA))
  expect_equal(out$participant_id_status[1], "conflict")
  expect_no_warning(quiet_extract(meta, "participant_id", warn = FALSE))
})

test_that("empty strings, null, numbers, booleans and escapes are read", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":"","age":-3.5,"ok":true,"note":null,"name":"Z\\u00fcrich \\"x\\""}]',
    "7003" = '[{"pid":"","age":31,"ok":false,"note":"n"}]',
    "7005" = '[{"age":1e3}]'
  ))
  out <- quiet_extract(meta, c("pid", "age", "ok", "note", "name"), warn = FALSE)
  expect_equal(out$pid[c(1, 3)], c("", ""))
  expect_equal(out$pid_status[c(1, 3)], c("unique", "unique"))
  expect_type(out$age, "double")
  expect_equal(out$age[c(1, 3, 5)], c(-3.5, 31, 1000))
  expect_type(out$ok, "logical")
  expect_equal(out$ok[c(1, 3)], c(TRUE, FALSE))
  expect_true(is.na(out$note[1]))
  expect_equal(out$note_status[1], "unique")
  expect_equal(out$note[3], "n")
  expect_equal(out$name[1], "Zürich \"x\"")
})

test_that("a key holding a colon, a quote or non-ASCII characters is read like any other", {
  meta <- meta_with_files(list(
    "7001" = '[{"a:b":"x","plain":"y","q\\"k":"v","stadt:ü":"Zürich","n:1":5,"e:":""}]',
    "7003" = '[{"a:b":"x2","q\\"k":"v2","stadt:ü":"Bern","n:1":6,"e:":"","t:f":true}]',
    "7005" = '[{"a:b":"","plain":"z"}]'
  ))
  out <- quiet_extract(meta, c("a:b", "q\\\"k", "stadt:ü", "n:1", "e:", "t:f", "plain"), warn = FALSE)
  # every value string before (the first colon of the match was taken for
  # the key's end, so the value looked nonscalar)
  expect_equal(out$`a:b`[c(1, 3, 5)], c("x", "x2", ""))
  expect_equal(out$`a:b_status`[c(1, 3, 5)], c("unique", "unique", "unique"))
  # a quote inside a key is asked for the way the file spells it, escaped
  expect_equal(out[["q\\\"k"]][c(1, 3)], c("v", "v2"))
  expect_equal(out$`stadt:ü`[c(1, 3)], c("Zürich", "Bern"))
  expect_equal(out$`n:1`[c(1, 3)], c(5, 6))
  expect_type(out$`n:1`, "double")
  expect_equal(out$`e:`[c(1, 3)], c("", ""))
  expect_equal(out$`t:f`[3], TRUE)
  expect_equal(out$`t:f_status`[1], "absent")
  expect_equal(out$plain[c(1, 5)], c("y", "z"))
  # the pieces themselves: the opening quote is the string marker
  occ <- extract_field_occurrences('{"a:b":"", "a:b":":", "a:b":null, "a:b":[1]}', "a:b")
  expect_equal(occ$kind, c("string", "string", "null", "nonscalar"))
  expect_equal(occ$value, c("", ":", NA, NA))
})

test_that("an array or object value counts as a conflict, a missing key as absent", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":[1,2]},{"pid":"a"}]',
    "7003" = '[{"other":1}]'
  ))
  out <- quiet_extract(meta, "pid", warn = FALSE)
  expect_equal(out$pid_status[c(1, 3)], c("conflict", "absent"))
  expect_true(is.na(out$pid[1]))
})

test_that("the cross-check parses exactly the absent and conflict files, flags unparseable ones and disagreements", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":"P1"}]',
    "7003" = '[{"pid":"P2"},{"pid":',
    "7005" = '[{"wrapper":{"pid":"NESTED"}}]',
    # a unicode-escaped key: jsonlite sees `pid`, the regex does not
    "7006" = '[{"p\\u0069d":"P9"}]'
  ))
  msgs <- capture_messages(
    warnings <- capture_warnings(out <- jatos_extract_fields(meta, "pid"))
  )
  # 7001 and 7003 read unique by regex and are not parsed; 7006 (absent) is
  expect_match(paste(msgs, collapse = "\n"), "Cross-checked 1 file without a unique value")
  expect_match(paste(msgs, collapse = "\n"), "1 parsed, 0 unparseable")
  expect_equal(out$pid_status[c(1, 3, 5, 6)], c("unique", "unique", "unique", "absent"))
  expect_equal(out$pid[3], "P2")
  # a nested key is read by both and is no disagreement
  expect_equal(out$pid[5], "NESTED")
  disagree <- warnings[grepl("disagree", warnings)]
  expect_length(disagree, 1)
  expect_match(disagree, "7006")
  expect_length(warnings, 1)

  # a conflict file that the parser cannot read is unparseable
  broken <- meta_with_files(list(
    "7001" = '[{"pid":"a"},{"pid":"b"},{"pid":',
    "7003" = '[{"pid":"P2"}]'
  ))
  w <- capture_warnings(msgs <- capture_messages(out <- jatos_extract_fields(broken, "pid")))
  expect_equal(out$pid_status[c(1, 3)], c("unparseable", "unique"))
  expect_true(is.na(out$pid[1]))
  expect_match(paste(msgs, collapse = "\n"), "0 parsed, 1 unparseable")
  expect_length(w, 1)
  expect_match(w, "1 unparseable")
  # the same file stops the reader, so the two agree on what unparseable means
  expect_error(jatos_read_json(broken$file[1]), "not valid JSON")
})

test_that("a key found in no file is not cross-checked; one found somewhere has its absent files parsed", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":"P1"},{"other":1}]',
    "7003" = '[{"other":2}]',
    "7005" = '[{"other":3}]'
  ))
  # `nowhere` is absent in all three files: with the parser blocked, the
  # extraction still runs, and no cross-check message is printed for it
  local({
    local_mocked_bindings(parse_for_check = function(text) stop("parsed a file"))
    msgs <- capture_messages(out <- jatos_extract_fields(meta, "nowhere"))
    expect_equal(out$nowhere_status[c(1, 3, 5)], c("absent", "absent", "absent"))
    expect_false(any(grepl("Cross-checked", msgs)))
    expect_match(paste(msgs, collapse = "\n"), "3 files without nowhere")
    # `pid` is unique in one file, so its two absent files are parsed
    expect_error(jatos_extract_fields(meta, "pid"), "parsed a file")
    # a conflict is always parsed, whether or not the key was found elsewhere
    conflict <- meta_with_files(list("7001" = '[{"pid":"a"},{"pid":"b"}]'))
    expect_error(jatos_extract_fields(conflict, "pid"), "parsed a file")
  })
  msgs <- capture_messages(out <- jatos_extract_fields(meta, c("pid", "nowhere")))
  expect_match(paste(msgs, collapse = "\n"), "Cross-checked 2 files")
  expect_equal(out$pid[1], "P1")
  # the rule itself
  expect_equal(files_to_cross_check(list(status = c("unique", "absent", NA, "conflict"))), c(2L, 4L))
  # a conflict counts as found, so the absent files next to it are parsed
  expect_equal(files_to_cross_check(list(status = c("absent", "absent", NA, "conflict"))), c(1L, 2L, 4L))
  expect_equal(files_to_cross_check(list(status = c("absent", "absent", NA))), integer())
  expect_equal(files_to_cross_check(list(status = c(NA_character_, NA_character_))), integer())
})

test_that("find_key_values collects every occurrence in document order", {
  x <- list(
    list(pid = "a", inner = list(pid = NULL, deeper = list(list(pid = 1), list(pid = list(1, 2))))),
    list(other = "x"),
    list(pid = c("v", "w"))
  )
  expect_equal(find_key_values(x, "pid"), c("a", NA, "1", nonscalar_marker, nonscalar_marker))
  expect_equal(find_key_values(x, "other"), "x")
  expect_equal(find_key_values(x, "none"), character())
  expect_equal(find_key_values(list(), "pid"), character())
  expect_equal(find_key_values("scalar", "pid"), character())
  expect_type(find_key_values(list(list(pid = TRUE)), "pid"), "character")
})

test_that("the cross-check compares typed values, so number formats do not disagree", {
  meta <- meta_with_files(list(
    "7001" = '[{"age":30.0},{"other":1}]',
    "7003" = '[{"age":"30"}]',
    "7005" = '[{"age":1e5},{"age":1E5}]',
    "7006" = '[{"age":1.50}]'
  ))
  # mixed kinds keep the column character with the raw text; two spellings
  # of one number within a file are one value, not a conflict; nothing is
  # parsed, so no disagreement can arise from formats
  expect_no_warning(msgs <- capture_messages(out <- jatos_extract_fields(meta, "age")))
  expect_type(out$age, "character")
  expect_equal(out$age[c(1, 3, 5, 6)], c("30.0", "30", "1e5", "1.50"))
  expect_equal(out$age_status[c(1, 3, 5, 6)], c("unique", "unique", "unique", "unique"))
  expect_length(msgs, 0)
  # numbers only: typed as numeric, 30 and 30.0 agree within a file
  nums <- meta_with_files(list("7001" = '[{"age":30},{"age":30.0},{"age":3e1}]'))
  out <- quiet_extract(nums, "age")
  expect_equal(out$age[1], 30)
  expect_equal(out$age_status[1], "unique")
  # the typed comparison itself
  expect_equal(typed_text("30.0", "number"), "30")
  expect_equal(typed_text("1e5", "number"), "1e+05")
  expect_equal(typed_text("1.50", "number"), "1.5")
  expect_equal(typed_text("true", "logical"), "TRUE")
  expect_equal(typed_text("30", "string"), "30")
  expect_true(is.na(typed_text(NA, "null")))
  expect_true(same_value(as.character(30), typed_text("30.0", "number")))
  expect_true(same_value(as.character(TRUE), typed_text("true", "logical")))
})

test_that("a field that is null everywhere, or nested, agrees with the parser", {
  meta <- meta_with_files(list(
    "7001" = '[{"age":null},{"age":null}]',
    "7003" = '[{"trial":1,"response":{"age":"31"}},{"trial":2}]',
    "7005" = '[{"age":null},{"age":31}]',
    "7006" = '[{"age":[1,2]}]'
  ))
  w <- capture_warnings(msgs <- capture_messages(out <- jatos_extract_fields(meta, "age")))
  expect_false(any(grepl("disagree", w)))
  expect_length(w, 1)
  expect_match(w, "2 conflict")
  expect_equal(out$age_status[c(1, 3, 5, 6)], c("unique", "unique", "conflict", "conflict"))
  expect_true(is.na(out$age[1]))
  expect_equal(out$age[3], "31")
  expect_match(paste(msgs, collapse = "\n"), "Cross-checked 2 files")
})

test_that("absent files are a message, conflicts and unparseable files a warning", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":"P1"}]',
    "7003" = '[{"other":1}]',
    "7005" = '[{"other":2}]'
  ))
  msgs <- capture_messages(expect_no_warning(out <- jatos_extract_fields(meta, "pid")))
  expect_match(paste(msgs, collapse = "\n"), "2 files without pid")
  expect_equal(out$pid_status[c(1, 3, 5)], c("unique", "absent", "absent"))

  conflict <- meta_with_files(list("7001" = '[{"pid":"a"},{"pid":"b"}]', "7003" = '[{"other":1}]'))
  w <- capture_warnings(msgs <- capture_messages(jatos_extract_fields(conflict, "pid")))
  expect_length(w, 1)
  expect_match(w, "1 file without a unique pid: 1 conflict")
  expect_match(w, "7001")
  expect_match(paste(msgs, collapse = "\n"), "1 file without pid")
  expect_no_warning(quiet_extract(conflict, "pid", warn = FALSE))
})

test_that("a field that names a metadata column is refused before any file is read", {
  meta <- meta_with_files(list("7001" = '[{"batch_id":99,"pid":"P1"}]'))
  meta$status <- "fetched"
  for (field in c("batch_id", "worker_id", "file", "component_result_id", "status", "file_size")) {
    err <- expect_error(jatos_extract_fields(meta, c("pid", field)), class = "jatosr_bad_argument")
    expect_match(conditionMessage(err), field, fixed = TRUE)
    expect_match(conditionMessage(err), "would overwrite")
  }
  expect_equal(meta$batch_id[1], 34L)

  # a previous extraction of the same field is replaced, not refused
  once <- quiet_extract(meta, "pid")
  twice <- quiet_extract(once, "pid")
  expect_equal(names(twice), names(once))
  expect_equal(twice$pid, once$pid)
  expect_equal(attr(twice, "jatosr_extracted"), "pid")
  more <- quiet_extract(once, "batch", warn = FALSE)
  expect_equal(attr(more, "jatosr_extracted"), c("pid", "batch"))
  # but a lone value column without its status column is a clash
  lone <- once
  lone$pid_status <- NULL
  expect_error(jatos_extract_fields(lone, "pid"), "would overwrite", class = "jatosr_bad_argument")
  expect_error(jatos_extract_fields(meta, c("pid", "pid")), "repeat", class = "jatosr_bad_argument")
  # a field and its own status column cannot both be asked for
  err <- expect_error(jatos_extract_fields(meta, c("age", "age_status")), class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "age_status")
  expect_match(conditionMessage(err), "would overwrite the first")
})

test_that("a user's own <x> / <x>_status pair is neither overwritten nor dropped", {
  meta <- meta_with_files(list("7001" = '[{"payment":"2.50"}]', "7006" = '[{"payment":"1.00"}]'))
  meta$payment <- c(2.5, NA, NA, NA, 1, 1)
  meta$payment_status <- c("paid", NA, NA, NA, "open", "open")
  expect_null(attr(meta, "jatosr_extracted"))
  # the extractor refuses the field, since the pair is not its own
  expect_error(jatos_extract_fields(meta, "payment"), "payment", class = "jatosr_bad_argument")
  # the collapse carries both columns
  sr <- jatos_study_results(meta)
  expect_equal(sr$payment, c(2.5, NA, NA, 1))
  expect_equal(sr$payment_status, c("paid", NA, NA, "open"))
  # after an extraction, its own status column is left out and the user's kept
  out <- quiet_extract(meta, "pid", warn = FALSE)
  sr2 <- jatos_study_results(out)
  expect_true("payment_status" %in% names(sr2))
  expect_false("pid_status" %in% names(sr2))
  # the record survives row and column subsetting
  expect_equal(attr(out[out$batch_id == 34, ], "jatosr_extracted"), "pid")
  expect_equal(attr(out[, c("study_result_id", "pid", "pid_status")], "jatosr_extracted"), "pid")
})

test_that("jatos_extract_fields makes no random draw", {
  meta <- meta_with_files(list(
    "7001" = '[{"pid":"P1"}]',
    "7003" = '[{"other":1}]'
  ))
  withr::local_seed(1)
  expected <- stats::runif(3)
  withr::local_seed(1)
  quiet_extract(meta, "pid")
  expect_identical(stats::runif(3), expected)
  expect_false("sample_size" %in% names(formals(jatos_extract_fields)))
})

test_that("jatos_extract_fields checks its input and names a custom file column", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  expect_error(jatos_extract_fields(meta, "pid"), "file", class = "jatosr_bad_metadata")
  meta$local <- NA_character_
  out <- quiet_extract(meta, "pid", file_col = "local")
  expect_true(all(is.na(out$pid_status)))
  expect_error(jatos_extract_fields(meta, character(), file_col = "local"), "fields", class = "jatosr_bad_argument")
  expect_error(jatos_extract_fields(meta, "pid", file_col = "local", warn = "no"), "warn", class = "jatosr_bad_argument")
})

test_that("jatos_study_results reacts to an extracted field and ignores its status column", {
  meta <- meta_with_files(list(
    "7005" = '[{"pid":"P4"}]',
    "7006" = '[{"pid":"P4-other"}]',
    "7001" = '[{"pid":"P1"}]'
  ))
  out <- quiet_extract(meta, "pid", warn = FALSE)
  expect_warning(sr <- jatos_study_results(out), "pid")
  expect_equal(sr$pid, c("P1", NA, NA, NA))
  expect_equal(sr$conflicts[[4]], "pid")
  expect_false("pid_status" %in% names(sr))
  expect_false("status" %in% names(sr))
})
