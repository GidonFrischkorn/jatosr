test_that("jatos_study_log parses newline-delimited JSON into rows", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/studies/12/log$" = mock_ndjson("study-log.ndjson"))
  log <- jatos_study_log(12, limit = 3)

  expect_s3_class(log, "tbl_df")
  expect_equal(nrow(log), 3)
  expect_equal(log$msg, c("Study created", "Component created", "Result data exported"))
  expect_s3_class(log$timestamp, "POSIXct")
  expect_equal(as.numeric(log$timestamp[1]), 1756001000)
  expect_equal(log$study_result_ids[[3]], list(9001L, 9002L))
  expect_true(is.na(log$component_uuid[1]))
  expect_equal(unique(log$study_id), 12L)

  q <- request_query(last_request(rec))
  expect_equal(q$download, "false")
  expect_equal(q$entryLimit, "3")
})

test_that("jatos_study_log validates limit and handles an empty log", {
  local_fake_credentials()
  expect_error(jatos_study_log(12, limit = 0), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_study_log(12, limit = "many"), "positive integer", class = "jatosr_bad_argument")
  local_jatos_mock("GET .*/studies/12/log$" = mock_ndjson(text = "\n"))
  log <- jatos_study_log(12)
  expect_equal(nrow(log), 0)
  expect_named(log, "study_id")
})
