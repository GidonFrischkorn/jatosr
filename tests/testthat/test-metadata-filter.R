test_that("jatos_filter_metadata drops study results by state, worker type and start", {
  meta <- fixture_metadata()

  msgs <- capture_messages(finished <- jatos_filter_metadata(meta, states = "FINISHED"))
  expect_equal(finished$study_result_id, c(9001L, 9002L, 9002L, 9004L, 9004L))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Excluded 1 of 4 study results; 3 remain")
  expect_match(text, "1 by study state")
  expect_match(text, "FINISHED")

  personal <- suppressMessages(jatos_filter_metadata(meta, worker_types = "PersonalSingle"))
  expect_equal(unique(personal$study_result_id), 9004L)
  several <- suppressMessages(jatos_filter_metadata(meta, worker_types = c("PersonalSingle", "GeneralMultiple")))
  expect_equal(nrow(several), 6)

  # 9001 started at 01:46:40 UTC on 2025-08-24, the others after 02:00
  late <- suppressMessages(jatos_filter_metadata(meta, since = "2025-08-24 02:00:00"))
  expect_equal(unique(late$study_result_id), c(9002L, 9003L, 9004L))
  expect_equal(nrow(suppressMessages(jatos_filter_metadata(meta, since = as.Date("2025-08-25")))), 0)
  expect_equal(nrow(suppressMessages(jatos_filter_metadata(meta, since = "2025-08-24"))), 6)
  stamp <- as.POSIXct("2025-08-24 02:00:00", tz = "UTC")
  expect_identical(suppressMessages(jatos_filter_metadata(meta, since = stamp)), late)

  # filters apply in order and each reports what it removed on top of the previous
  msgs <- capture_messages(both <- jatos_filter_metadata(meta, states = "FINISHED", since = stamp))
  expect_equal(unique(both$study_result_id), c(9002L, 9004L))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Excluded 2 of 4 study results; 2 remain")
  expect_match(text, "1 by study state")
  expect_match(text, "1 that started before 2025-08-24 02:00:00 UTC")

  # each filter reports its own count, rendered when it is computed: alone,
  # the state filter drops 1 and the worker filter 3; together 1 and 2
  msgs <- capture_messages(jatos_filter_metadata(meta, worker_types = "PersonalSingle"))
  expect_match(paste(msgs, collapse = "\n"), "3 by worker type")
  msgs <- capture_messages(
    both <- jatos_filter_metadata(meta, states = "FINISHED", worker_types = "PersonalSingle")
  )
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Excluded 3 of 4 study results; 1 remains")
  expect_match(text, "1 by study state")
  expect_match(text, "2 by worker type")
  expect_equal(unique(both$study_result_id), 9004L)
  # a brace in a kept value is text, not a template
  msgs <- capture_messages(jatos_filter_metadata(meta, states = "{FINISHED}"))
  expect_match(paste(msgs, collapse = "\n"), 'kept "{FINISHED}"', fixed = TRUE)

  # a run without a start time is dropped when since is given
  no_start <- meta
  no_start$study_start_time[5:6] <- NA
  expect_false(9004L %in% suppressMessages(jatos_filter_metadata(no_start, since = "2025-08-24"))$study_result_id)

  # no filter: nothing happens, no message
  expect_silent(expect_identical(jatos_filter_metadata(meta), meta))
  expect_equal(nrow(suppressMessages(jatos_filter_metadata(meta[0, ], states = "FINISHED"))), 0)
})

test_that("jatos_filter_metadata cuts with until, excludes ids, and reads dates in tz", {
  meta <- fixture_metadata()
  # 9001 started 01:46:40, 9002 02:03:20, 9003 02:36:40, 9004 02:53:20 UTC
  msgs <- capture_messages(early <- jatos_filter_metadata(meta, until = "2025-08-24 02:30:00"))
  expect_equal(unique(early$study_result_id), c(9001L, 9002L))
  expect_match(paste(msgs, collapse = "\n"), "2 that started at or after 2025-08-24 02:30:00 UTC")
  # half-open: since is inclusive, until exclusive
  stamp <- as.POSIXct("2025-08-24 02:03:20", tz = "UTC")
  one <- suppressMessages(jatos_filter_metadata(meta, since = stamp, until = as.POSIXct("2025-08-24 02:36:40", tz = "UTC")))
  expect_equal(unique(one$study_result_id), 9002L)
  no_start <- meta
  no_start$study_start_time[1] <- NA
  expect_false(9001L %in% suppressMessages(jatos_filter_metadata(no_start, until = "2025-08-25"))$study_result_id)

  msgs <- capture_messages(out <- jatos_filter_metadata(meta, exclude_study_result_id = c(9002, 9999)))
  expect_equal(unique(out$study_result_id), c(9001L, 9003L, 9004L))
  expect_match(paste(msgs, collapse = "\n"), "1 by study result id \\(2 excluded\\)")
  msgs <- capture_messages(out <- jatos_filter_metadata(meta, exclude_worker_id = 504))
  expect_equal(unique(out$study_result_id), c(9001L, 9002L, 9003L))
  expect_match(paste(msgs, collapse = "\n"), "1 by worker id \\(1 excluded\\)")
  # every filter reports its own count, in order
  msgs <- capture_messages(out <- jatos_filter_metadata(
    meta, states = "FINISHED", until = "2025-08-24 02:30:00", exclude_worker_id = 501
  ))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Excluded 3 of 4 study results; 1 remains")
  expect_match(text, "1 by study state")
  expect_match(text, "1 that started at or after")
  expect_match(text, "1 by worker id")
  expect_equal(unique(out$study_result_id), 9002L)

  # tz reads the strings and labels the message; a POSIXct is taken as is
  msgs <- capture_messages(local <- jatos_filter_metadata(meta, since = "2025-08-24 04:03:20", tz = "Europe/Zurich"))
  expect_equal(unique(local$study_result_id), c(9002L, 9003L, 9004L))
  expect_match(paste(msgs, collapse = "\n"), "before 2025-08-24 04:03:20 Europe/Zurich")
  expect_identical(
    suppressMessages(jatos_filter_metadata(meta, since = stamp, tz = "Europe/Zurich")),
    suppressMessages(jatos_filter_metadata(meta, since = stamp))
  )
  expect_equal(
    nrow(suppressMessages(jatos_filter_metadata(meta, since = as.Date("2025-08-24"), tz = "Pacific/Kiritimati"))),
    6
  )
  # midnight on Kiritimati (UTC+14) is 10:00 UTC the day before: every run is after it
  expect_equal(
    nrow(suppressMessages(jatos_filter_metadata(meta, until = as.Date("2025-08-24"), tz = "Pacific/Kiritimati"))),
    0
  )
  expect_equal(attr(check_since("2025-08-24", tz = "Europe/Zurich"), "tzone"), "UTC")
  expect_equal(as.numeric(check_since("2025-08-24 02:00", tz = "Europe/Zurich")), as.numeric(as.POSIXct("2025-08-24 00:00", tz = "UTC")))
})

test_that("jatos_filter_metadata checks its arguments", {
  meta <- fixture_metadata()
  expect_error(jatos_filter_metadata(meta, states = 1), "study states", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, worker_types = ""), "worker types", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, since = "yesterday"), "since", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, since = c("2025-01-01", "2025-01-02")), "since", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, since = NA), "since", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, until = "soon"), "until", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, exclude_study_result_id = "a"), "exclude_study_result_id", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, exclude_worker_id = 0), "exclude_worker_id", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, tz = "Mars/Olympus"), "time zone", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta, tz = ""), "tz", class = "jatosr_bad_argument")
  expect_error(jatos_filter_metadata(meta[, "study_state"]), "study_result_id", class = "jatosr_bad_metadata")
  expect_error(jatos_filter_metadata(list()), "data frame", class = "jatosr_bad_metadata")
})

test_that("jatos_url_query widens the query parameters into prefixed snake-case columns", {
  meta <- fixture_metadata()
  out <- jatos_url_query(meta)
  expect_equal(names(out), c(names(meta), "query_prolific_pid", "query_session_id"))
  expect_equal(out$query_prolific_pid, c(NA, NA, NA, NA, "p-0004", "p-0004"))
  expect_equal(out$query_session_id[5], "s-0004")
  expect_identical(out$url_query, meta$url_query)

  # STUDY_ID stays apart from study_id; a camelCase key is snake-cased
  meta$url_query[[1]] <- list(STUDY_ID = "st-1", camelCase = "x")
  out2 <- jatos_url_query(meta)
  expect_equal(
    setdiff(names(out2), names(meta)),
    c("query_study_id", "query_camel_case", "query_prolific_pid", "query_session_id")
  )
  expect_equal(out2$query_study_id, c("st-1", NA, NA, NA, NA, NA))
  expect_equal(out2$study_id[1], 12L)
  expect_error(jatos_url_query(meta, prefix = ""), "study_id", class = "jatosr_bad_argument")
  expect_true("url_prolific_pid" %in% names(jatos_url_query(meta, prefix = "url_")))

  # repeated values are joined; no parameter anywhere leaves the tibble as is
  meta$url_query[[2]] <- list(PROLIFIC_PID = c("a", "b"))
  expect_equal(jatos_url_query(meta)$query_prolific_pid[2], "a,b")
  none <- fixture_metadata()
  none$url_query <- rep(list(list()), nrow(none))
  expect_identical(jatos_url_query(none), none)

  expect_error(jatos_url_query(meta, prefix = 1), "prefix", class = "jatosr_bad_argument")
  expect_error(jatos_url_query(meta[, "study_id"]), "url_query", class = "jatosr_bad_metadata")
})

test_that("query keys that share a column name are told apart with a warning naming them", {
  meta <- fixture_metadata()
  meta$url_query[[1]] <- list(prolific_pid = "lower", `Prolific-Pid` = "dashed")
  w <- capture_warnings(out <- jatos_url_query(meta))
  expect_length(w, 1)
  expect_match(w, "1 column name is shared")
  expect_match(w, '"PROLIFIC_PID"', fixed = TRUE)
  expect_match(w, '"prolific_pid"', fixed = TRUE)
  expect_match(w, "query_prolific_pid_1")
  cols <- setdiff(names(out), names(meta))
  expect_true(all(c("query_prolific_pid", "query_prolific_pid_1") %in% cols))
  # the values follow the keys, in order of first appearance across rows:
  # the lower-case key of row 1 comes before the Prolific one of row 5
  expect_equal(out$query_prolific_pid[1], "lower")
  expect_true(is.na(out$query_prolific_pid[5]))
  expect_equal(out$query_prolific_pid_1[5], "p-0004")
  # a dash is kept by the snake case, so that key does not collide
  expect_equal(out$`query_prolific-pid`[1], "dashed")
  expect_no_warning(jatos_url_query(fixture_metadata()))
})
