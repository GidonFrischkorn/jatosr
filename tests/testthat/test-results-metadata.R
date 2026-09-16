test_that("jatos_flatten_metadata gives one row per component result with level-named columns", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))

  expect_s3_class(meta, "tbl_df")
  expect_equal(nrow(meta), 6)
  expect_equal(meta$component_result_id, c(7001L, 7002L, 7003L, 7004L, 7005L, 7006L))
  expect_equal(meta$study_result_id, c(9001L, 9002L, 9002L, 9003L, 9004L, 9004L))
  expect_equal(meta$study_id, c(12L, 12L, 12L, 12L, 13L, 13L))
  expect_equal(meta$study_title[c(1, 5)], c("A03_ColorBinding", "A01_Registration"))
  expect_equal(meta$component_id, c(121L, 121L, 121L, 121L, 131L, 132L))
  expect_equal(meta$batch_id, c(34L, 34L, 34L, 34L, 36L, 36L))
  expect_equal(meta$batch_title[1], "Default")
  expect_equal(meta$worker_id, c(501L, 502L, 502L, 503L, 504L, 504L))
  expect_equal(meta$worker_type[5], "PersonalSingle")
  expect_equal(meta$study_code[1], "code9001")
  expect_true(all(is.na(meta$group_id)))

  # study and component states are separate columns
  expect_equal(meta$study_state, c("FINISHED", "FINISHED", "FINISHED", "STARTED", "FINISHED", "FINISHED"))
  expect_equal(meta$component_state, c("FINISHED", "RELOADED", "FINISHED", "STARTED", "FINISHED", "FINISHED"))

  # sizes are bytes as doubles; the reload row is empty
  expect_type(meta$data_size, "double")
  expect_equal(meta$data_size, c(2048, 0, 1536, 0, 300, 700))
  expect_equal(meta$data_file, c(NA, NA, "data.txt", NA, NA, NA))
  expect_equal(meta$n_files, c(0L, 0L, 1L, 0L, 0L, 0L))
  expect_equal(meta$files[[3]][[1]]$filename, "drawing.png")
  expect_equal(meta$path[1], "/study_result_9001/comp-result_7001")
})

test_that("jatos_flatten_metadata converts times to POSIXct UTC and computes durations", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))

  expect_s3_class(meta$study_start_time, "POSIXct")
  expect_equal(attr(meta$study_start_time, "tzone"), "UTC")
  expect_equal(as.numeric(meta$study_start_time[1]), 1756000000)
  expect_equal(as.numeric(meta$study_end_time[1]), 1756000900)
  expect_true(is.na(meta$study_end_time[4]))
  expect_equal(as.numeric(meta$last_seen[4]), 1756003300)

  expect_s3_class(meta$study_duration, "difftime")
  expect_equal(units(meta$study_duration), "mins")
  expect_equal(as.numeric(meta$study_duration), c(15, 20, 20, NA, 10, 10))

  expect_true(is.na(meta$component_end_time[2]))
  expect_equal(as.numeric(meta$component_duration), c(15, NA, 18 + 20 / 60, NA, 10 / 3, 20 / 3))
})

test_that("jatos_flatten_metadata keeps optional study-result fields", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  expect_equal(meta$comment, c(NA, "browser crashed once", "browser crashed once", NA, NA, NA))
  # message, confirmationCode and isQuotaReached of ResultsMetadataStudyResultList
  expect_equal(meta$study_message, c(NA, NA, NA, "Browser closed", NA, NA))
  expect_equal(meta$confirmation_code, c(NA, NA, NA, NA, "MTURK-9004", "MTURK-9004"))
  expect_equal(meta$quota_reached, rep(FALSE, 6))
  expect_type(meta$quota_reached, "logical")
  expect_equal(
    which(names(meta) == "comment") + 1:3,
    match(c("study_message", "confirmation_code", "quota_reached"), names(meta))
  )
  expect_true(all(c("study_message", "confirmation_code", "quota_reached") %in% metadata_study_columns()))
  expect_type(meta$url_query, "list")
  expect_equal(meta$url_query[[5]], list(PROLIFIC_PID = "p-0004", SESSION_ID = "s-0004"))
  expect_equal(meta$url_query[[1]], list())
})

test_that("jatos_flatten_metadata accepts a parsed envelope, its data list, and a path", {
  from_path <- jatos_flatten_metadata(fixture_path("metadata.json"))
  parsed <- read_fixture_json("metadata.json")
  expect_equal(jatos_flatten_metadata(parsed), from_path)
  expect_equal(jatos_flatten_metadata(parsed$data), from_path)
  expect_error(jatos_flatten_metadata(42), "parsed", class = "jatosr_bad_metadata")
  expect_error(jatos_flatten_metadata("/no/such/file.json"), "does not exist", class = "jatosr_bad_argument")
})

test_that("jatos_flatten_metadata refuses a metadata tibble and says what produces one", {
  from_path <- jatos_flatten_metadata(fixture_path("metadata.json"))

  err <- expect_error(jatos_flatten_metadata(from_path), "already", class = "jatosr_bad_metadata")
  expect_match(conditionMessage(err), "jatos_results_metadata")
  expect_match(conditionMessage(err), "jatos_read_metadata")

  # A plain data frame, and one carrying none of the metadata columns: a data
  # frame is a list, so every one of them used to reach metadata_rows().
  expect_error(jatos_flatten_metadata(as.data.frame(from_path)), "already", class = "jatosr_bad_metadata")
  expect_error(jatos_flatten_metadata(data.frame(a = 1)), "already", class = "jatosr_bad_metadata")
  # A frame of nothing but list columns returned zero rows in silence.
  list_cols <- data.frame(i = 1)
  list_cols$files <- list(list())
  expect_error(jatos_flatten_metadata(list_cols["files"]), "already", class = "jatosr_bad_metadata")

  # Control: the documented inputs still flatten to the same six rows.
  parsed <- read_fixture_json("metadata.json")
  expect_equal(jatos_flatten_metadata(parsed), from_path)
  expect_equal(jatos_flatten_metadata(parsed$data), from_path)
  expect_equal(nrow(from_path), 6L)
})

test_that("check_metadata names jatos_flatten_metadata when given a parsed answer", {
  err <- expect_error(
    check_metadata(read_fixture_json("metadata.json")),
    "data frame",
    class = "jatosr_bad_metadata"
  )
  expect_match(conditionMessage(err), "jatos_flatten_metadata")
})

test_that("jatos_flatten_metadata with no results returns zero rows with every column", {
  empty <- jatos_flatten_metadata(list(apiVersion = "1.1.0", data = list()))
  expect_equal(nrow(empty), 0)
  expect_equal(names(empty), metadata_columns())
  expect_s3_class(empty$study_start_time, "POSIXct")

  no_results <- jatos_flatten_metadata(list(data = list(list(
    studyId = 14, studyUuid = "u", studyTitle = "A00_Empty", studyResults = list()
  ))))
  expect_equal(nrow(no_results), 0)
  expect_equal(names(no_results), metadata_columns())
})

test_that("jatos_results_metadata posts a JSON body with id arrays and download=false", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/results/metadata$" = mock_json("metadata.json"))

  meta <- suppressMessages(jatos_results_metadata(study_id = c(12, 13)))
  expect_equal(nrow(meta), 6)
  expect_equal(names(meta), metadata_columns())

  req <- last_request(rec)
  expect_equal(mock_method(req), "POST")
  expect_equal(request_query(req)$download, "false")
  body <- request_json_body(req)
  expect_equal(names(body), "studyIds")
  expect_equal(unlist(body$studyIds), c(12L, 13L))
})

test_that("jatos_results_metadata sends every filter under its API name", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/results/metadata$" = mock_json("metadata.json"))
  suppressMessages(jatos_results_metadata(
    study_id = 12, batch_id = c(34, 36), component_id = 121,
    study_result_id = 9001:9004, component_result_id = 7001, group_id = 5
  ))
  body <- request_json_body(last_request(rec))
  expect_equal(
    names(body),
    c("studyIds", "batchIds", "componentIds", "studyResultIds", "componentResultIds", "groupIds")
  )
  expect_equal(unlist(body$studyResultIds), 9001:9004)
  expect_equal(unlist(body$batchIds), c(34L, 36L))
})

test_that("jatos_results_metadata keeps long id vectors in the body, not the URL", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/results/metadata$" = mock_json("metadata.json"))
  ids <- 1:250
  suppressMessages(jatos_results_metadata(component_result_id = ids))
  req <- last_request(rec)
  expect_equal(unlist(request_json_body(req)$componentResultIds), ids)
  expect_false(grepl("componentResultId", req$url))
  expect_lt(nchar(req$url), 200)
})

test_that("jatos_results_metadata requires at least one filter and validates ids", {
  local_fake_credentials()
  rec <- local_jatos_mock()
  expect_error(jatos_results_metadata(), "at least one", class = "jatosr_bad_argument")
  expect_error(jatos_results_metadata(study_id = -1), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_results_metadata(batch_id = c(1, NA)), "positive integer", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)
})

study_uuids <- c("1c2d3e4f-0000-4000-8000-000000000012", "1c2d3e4f-0000-4000-8000-000000000013")

test_that("jatos_results_metadata routes uuid strings to the *Uuids body fields", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/results/metadata$" = mock_json("metadata.json"))

  meta <- suppressMessages(jatos_results_metadata(study_id = study_uuids))
  expect_equal(nrow(meta), 6)
  body <- request_json_body(last_request(rec))
  expect_equal(names(body), "studyUuids")
  expect_equal(unlist(body$studyUuids), study_uuids)

  suppressMessages(jatos_results_metadata(
    study_id = 12, component_id = "AABBCCDD-0000-4000-8000-000000000121", batch_id = 34
  ))
  body <- request_json_body(last_request(rec))
  expect_equal(names(body), c("studyIds", "batchIds", "componentUuids"))
  expect_equal(unlist(body$studyIds), 12L)
  expect_equal(unlist(body$componentUuids), "AABBCCDD-0000-4000-8000-000000000121")

  # a single uuid is still a JSON array
  suppressMessages(jatos_results_metadata(study_id = study_uuids[1]))
  expect_equal(request_json_body(last_request(rec))$studyUuids, list(study_uuids[1]))
})

test_that("jatos_results_metadata refuses a mix of ids and uuids, and uuids where the server takes none", {
  local_fake_credentials()
  rec <- local_jatos_mock()
  err <- expect_error(jatos_results_metadata(study_id = c("12", study_uuids[1])), "mixes ids and uuids", class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "study_id")
  expect_error(jatos_results_metadata(study_id = 12, component_id = c(121, "x")), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_results_metadata(batch_id = study_uuids[1]), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_results_metadata(study_result_id = study_uuids[1]), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_results_metadata(study_id = "12/../admin"), "positive integer", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)
})

test_that("jatos_results_metadata reports host, both counts and unfinished component results", {
  local_fake_credentials()
  local_jatos_mock("POST .*/results/metadata$" = mock_json("metadata.json"))
  msgs <- capture_messages(jatos_results_metadata(study_id = 12))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, fake_host, fixed = TRUE)
  expect_match(text, "4 study results")
  expect_match(text, "6 component results")
  expect_match(text, "2 not FINISHED")
  expect_no_token(text)

  withr::local_options(rlib_message_verbosity = "quiet")
  expect_silent(jatos_results_metadata(study_id = 12))
})

test_that("jatos_results_metadata with an empty answer returns zero rows and says so", {
  local_fake_credentials()
  local_jatos_mock(
    "POST .*/results/metadata$" = mock_json_body(list(apiVersion = "1.1.0", data = list()))
  )
  msgs <- capture_messages(meta <- jatos_results_metadata(batch_id = 99))
  expect_equal(nrow(meta), 0)
  expect_match(paste(msgs, collapse = "\n"), "0 study results")
})

test_that("check_metadata accepts the contract and names missing columns", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  expect_invisible(check_metadata(meta))
  expect_error(check_metadata(meta[, -match("data_size", names(meta))]), "data_size", class = "jatosr_bad_metadata")
  expect_error(check_metadata(list(a = 1)), "data frame", class = "jatosr_bad_metadata")
  expect_error(check_metadata(meta, needs = "file"), "file", class = "jatosr_bad_metadata")
  broken <- meta
  broken$component_state <- NULL
  err <- expect_error(check_metadata(broken), "component_state", class = "jatosr_bad_metadata")
  expect_match(conditionMessage(err), "jatos_results_metadata")
})
