test_that("jatos_study_results collapses to one row per study result", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  sr <- jatos_study_results(meta)

  expect_s3_class(sr, "tbl_df")
  expect_equal(nrow(sr), 4)
  expect_equal(sr$study_result_id, c(9001L, 9002L, 9003L, 9004L))
  expect_equal(sr$study_id, c(12L, 12L, 12L, 13L))
  expect_equal(sr$study_title[4], "A01_Registration")
  expect_equal(sr$worker_id, c(501L, 502L, 503L, 504L))
  expect_equal(sr$batch_id, c(34L, 34L, 34L, 36L))
  expect_equal(sr$study_state, c("FINISHED", "FINISHED", "STARTED", "FINISHED"))
  expect_equal(as.numeric(sr$study_duration), c(15, 20, NA, 10))
  expect_equal(sr$comment[2], "browser crashed once")
  expect_equal(sr$url_query[[4]]$PROLIFIC_PID, "p-0004")

  # a reload is two component results of one component; a two-component
  # study is two component results of two components
  expect_equal(sr$n_component_results, c(1L, 2L, 1L, 2L))
  expect_equal(sr$n_components, c(1L, 1L, 1L, 2L))
  expect_equal(sr$n_finished, c(1L, 1L, 0L, 2L))
  expect_equal(sr$data_size, c(2048, 1536, 0, 1000))
  expect_equal(sr$n_files, c(0L, 1L, 0L, 0L))
  expect_equal(as.numeric(sr$first_component_start), c(1756000000, 1756001000, 1756003000, 1756004000))
  expect_equal(as.numeric(sr$last_component_end), c(1756000900, 1756002200, NA, 1756004600))
  expect_false("component_result_id" %in% names(sr))
  expect_false("component_state" %in% names(sr))
})

test_that("jatos_study_results carries extracted fields and flags disagreement", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  meta$participant_id <- c("P1", NA, "P2", NA, "P4", "P4")
  meta$age <- c(31L, NA, 31L, NA, 40L, 41L)

  expect_warning(sr <- jatos_study_results(meta), "age")
  expect_equal(sr$participant_id, c("P1", "P2", NA, "P4"))
  expect_equal(sr$age, c(31L, 31L, NA, NA))
  expect_type(sr$conflicts, "list")
  expect_equal(sr$conflicts[[4]], "age")
  expect_equal(lengths(sr$conflicts), c(0L, 0L, 0L, 1L))

  # NA next to a value is filling, not a conflict
  meta$age <- c(31L, NA, 31L, NA, 40L, NA)
  expect_no_warning(sr2 <- jatos_study_results(meta))
  expect_equal(sr2$age, c(31L, 31L, NA, 40L))

  # several conflicting study results are all named in one warning
  meta$age <- c(31L, 30L, 31L, NA, 40L, 41L)
  expect_warning(sr3 <- jatos_study_results(meta), "9002 and 9004")
  expect_equal(lengths(sr3$conflicts), c(0L, 1L, 0L, 1L))
})

test_that("jatos_study_results counts runs per participant key", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  # no key: no column, no message
  expect_false("n_runs" %in% names(jatos_study_results(meta)))
  expect_no_message(jatos_study_results(meta))

  # query_prolific_pid is the default key when present: 9004 only carries one
  q <- jatos_url_query(meta)
  sr <- expect_no_message(jatos_study_results(q))
  expect_equal(sr$n_runs, c(NA, NA, NA, 1L))
  expect_equal(names(sr)[match("last_component_end", names(sr)) + 1], "n_runs")
  q$query_prolific_pid[1:4] <- "p-0004"
  msgs <- capture_messages(sr <- jatos_study_results(q))
  expect_equal(sr$n_runs, c(4L, 4L, 4L, 4L))
  expect_match(msgs, "1 value of query_prolific_pid has more than one study result")

  # an explicit key: worker id, or an extracted field
  sr <- jatos_study_results(meta, participant = "worker_id")
  expect_equal(sr$n_runs, c(1L, 1L, 1L, 1L))
  dup <- meta
  dup$worker_id[dup$study_result_id == 9002L] <- 501L
  sr <- suppressMessages(jatos_study_results(dup, participant = "worker_id"))
  expect_equal(sr$n_runs, c(2L, 2L, 1L, 1L))
  dup$pid <- c("A", NA, "A", NA, "B", "B")
  sr <- suppressMessages(jatos_study_results(dup, participant = "pid"))
  expect_equal(sr$n_runs, c(2L, 2L, NA, 1L))
  # the explicit key wins over query_prolific_pid; zero rows keep the column
  expect_equal(suppressMessages(jatos_study_results(jatos_url_query(dup), participant = "pid"))$n_runs, c(2L, 2L, NA, 1L))
  expect_equal(names(jatos_study_results(q[0, ]))[match("last_component_end", names(sr)) + 1], "n_runs")
  # a per-component column cannot identify a participant
  dup$file <- NA_character_
  expect_error(jatos_study_results(dup, participant = "file"), "per component result", class = "jatosr_bad_argument")
  expect_error(jatos_study_results(dup, participant = "nope"), "nope", class = "jatosr_bad_metadata")
  expect_error(jatos_study_results(dup, participant = "url_query"), "list column", class = "jatosr_bad_argument")
  expect_error(jatos_study_results(dup, participant = 1), "participant", class = "jatosr_bad_argument")
})

test_that("jatos_study_results ignores local file columns and checks its input", {
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  meta$file <- NA_character_
  meta$file_size <- NA_real_
  sr <- jatos_study_results(meta)
  expect_false(any(c("file", "file_size") %in% names(sr)))
  expect_false("conflicts" %in% names(sr))

  expect_error(jatos_study_results(meta[, c("study_result_id", "batch_id")]), "component_result_id", class = "jatosr_bad_metadata")
  expect_equal(nrow(jatos_study_results(meta[0, ])), 0)
})
