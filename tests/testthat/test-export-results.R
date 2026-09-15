query_cols <- c("query_prolific_pid", "query_session_id")

test_that("jatos_export_results runs the pipeline once and writes what the steps produce", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "study12.rds")

  msgs <- capture_messages(
    out <- expect_invisible(jatos_export_results(study_id = 12, cache = cache, file = file))
  )
  expect_no_token(msgs)
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Wrote 6 trials from 4 component results")
  expect_match(text, "study12.rds")
  expect_match(text, "study12_metadata.rds")
  expect_match(text, "study12_export.json")
  expect_equal(
    sort(list.files(root)),
    c("cache", "study12.rds", "study12_export.json", "study12_metadata.rds")
  )

  # metadata for the study, then per batch one data chunk and one metadata refresh
  paths <- request_paths(rec)
  expect_equal(basename(paths), c("metadata", "data", "metadata", "data", "metadata"))
  expect_equal(unlist(request_json_body(rec$requests[[1]])$studyIds), 12L)
  expect_null(request_json_body(rec$requests[[1]])$batchIds)
  expect_equal(request_query(rec$requests[[1]])$download, "false")

  # the file holds the tibble the individual steps produce on the same cache
  meta <- suppressMessages(jatos_results_metadata(study_id = 12))
  meta <- suppressMessages(jatos_download_results(meta, cache))
  expect_true(all(meta$status %in% c("unchanged", "empty")))
  meta <- jatos_url_query(meta)
  trials <- suppressMessages(jatos_read_results(meta, metadata_cols = c(default_metadata_cols(), query_cols)))
  expect_identical(out, trials)
  expect_identical(readRDS(file), trials)
  expect_equal(nrow(trials), 6)
  expect_equal(
    names(trials)[1:10],
    c("study_result_id", "component_result_id", default_metadata_cols(), query_cols)
  )
  expect_equal(trials$query_prolific_pid, c(NA, NA, NA, NA, "p-0004", "p-0004"))
  expect_true("participant_id" %in% names(trials))

  # the metadata file: one row per study result with the query columns
  metadata <- readRDS(file.path(root, "study12_metadata.rds"))
  expect_equal(metadata$study_result_id, c(9001L, 9002L, 9003L, 9004L))
  expect_equal(metadata$query_prolific_pid, c(NA, NA, NA, "p-0004"))
  expect_true(all(c("n_component_results", "study_state", "worker_type", "study_duration") %in% names(metadata)))
  expect_false(any(c("file", "status") %in% names(metadata)))

  # the provenance file
  prov <- jsonlite::read_json(file.path(root, "study12_export.json"))
  expect_equal(prov$package, "jatosr")
  expect_equal(prov$version, as.character(utils::packageVersion("jatosr")))
  expect_match(prov$exported_at, "^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")
  expect_equal(prov$host, fake_host)
  expect_equal(prov$profile, "default")
  expect_equal(prov$study_id, 12L)
  expect_null(prov$batch_id)
  expect_length(prov$filters, 0)
  expect_null(prov$fields)
  expect_equal(prov$cache, normalizePath(cache))
  expect_equal(prov$counts$on_server, list(study_results = 4L, component_results = 6L))
  expect_equal(prov$counts$exported, list(study_results = 4L, component_results = 6L, files_read = 4L, trials = 6L))
  expect_equal(prov$files, list(trials = file, metadata = file.path(root, "study12_metadata.rds")))
  expect_no_token(readLines(file.path(root, "study12_export.json")))
})

test_that("jatos_export_results applies the filters before the download and records them", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "late.rds")

  msgs <- capture_messages(
    out <- jatos_export_results(
      study_id = 12, cache = cache, file = file,
      states = "FINISHED", since = "2025-08-24 02:00:00"
    )
  )
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Excluded 2 of 4 study results")
  expect_match(text, "Wrote 4 trials from 3 component results")
  # 9001 was excluded before the download: its data was never requested
  ids <- unlist(lapply(data_requests(rec), function(r) unlist(request_json_body(r)$componentResultIds)))
  expect_equal(sort(ids), c(7003L, 7005L, 7006L))
  expect_false(file.exists(file.path(cache, "batch_34", "study_result_9001", "comp-result_7001", "data.txt")))
  expect_equal(unique(out$study_result_id), c(9002L, 9004L))

  metadata <- readRDS(file.path(root, "late_metadata.rds"))
  expect_equal(metadata$study_result_id, c(9002L, 9004L))
  prov <- jsonlite::read_json(file.path(root, "late_export.json"))
  expect_equal(prov$filters, list(states = "FINISHED", since = "2025-08-24T02:00:00Z", tz = "UTC"))
  expect_equal(prov$counts$on_server$study_results, 4L)
  expect_equal(prov$counts$exported$study_results, 2L)
  expect_equal(prov$counts$exported$trials, 4L)

  # worker_types is recorded as a vector
  suppressMessages(jatos_export_results(
    study_id = 12, cache = cache, file = file.path(root, "wt.rds"),
    worker_types = c("PersonalSingle", "GeneralMultiple"), provenance = TRUE
  ))
  prov <- jsonlite::read_json(file.path(root, "wt_export.json"))
  expect_equal(unlist(prov$filters$worker_types), c("PersonalSingle", "GeneralMultiple"))

  # until, the exclusions and tz pass through and are recorded
  msgs <- capture_messages(cut <- jatos_export_results(
    study_id = 12, cache = cache, file = file.path(root, "cut.rds"),
    until = "2025-08-24 04:30:00", tz = "Europe/Zurich",
    exclude_study_result_id = 9001, exclude_worker_id = 999
  ))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "2 that started at or after 2025-08-24 04:30:00 Europe/Zurich")
  expect_match(text, "1 by study result id")
  expect_match(text, "0 by worker id")
  expect_equal(unique(cut$study_result_id), 9002L)
  prov <- jsonlite::read_json(file.path(root, "cut_export.json"))
  expect_equal(prov$filters$until, "2025-08-24T02:30:00Z")
  expect_equal(prov$filters$tz, "Europe/Zurich")
  expect_equal(prov$filters$exclude_study_result_id, 9001L)
  expect_equal(prov$filters$exclude_worker_id, 999L)
  expect_null(prov$filters$since)
  expect_error(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "e.rds"), tz = "Nowhere"), "time zone", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "e.rds"), until = "later"), "until", class = "jatosr_bad_argument")
  expect_false(file.exists(file.path(root, "e.rds")))
})

test_that("jatos_export_results joins extracted fields and honours format, sidecars and overwrite", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "study12.csv")

  # `age` sits inside a survey response: absent in three files is a message,
  # the nested cross-check agrees, so nothing warns
  msgs <- capture_messages(expect_no_warning(
    out <- jatos_export_results(study_id = 12, cache = cache, file = file, fields = "age")
  ))
  expect_match(paste(msgs, collapse = "\n"), "3 files without age")
  expect_equal(names(out)[11], "age")
  expect_equal(out$age[out$component_result_id == 7006L], "31")
  expect_true(all(is.na(out$age[out$component_result_id != 7006L])))
  expect_false("age_status" %in% names(out))
  back <- utils::read.csv(file, encoding = "UTF-8", na.strings = "")
  # read.csv types the quoted "31" as integer; the value is what matters here
  expect_equal(as.character(back$age), out$age)
  expect_equal(back$city[1], "Zürich")
  expect_equal(back$query_prolific_pid, out$query_prolific_pid)
  meta_back <- utils::read.csv(file.path(root, "study12_metadata.csv"), encoding = "UTF-8", na.strings = "")
  expect_equal(meta_back$study_result_id, c(9001L, 9002L, 9003L, 9004L))
  expect_equal(as.character(meta_back$age), c(NA, NA, NA, "31"))
  prov <- jsonlite::read_json(file.path(root, "study12_export.json"))
  expect_equal(prov$fields, "age")

  # a field that is already a trial column is a clash, not a silent rename
  expect_error(
    suppressMessages(
      jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "x.rds"), fields = "participant_id")
    ),
    "participant_id",
    class = "jatosr_bad_argument"
  )
  expect_false(file.exists(file.path(root, "x.rds")))

  # second run: the file exists, nothing is downloaded, the guard fires
  n_before <- length(rec$requests)
  err <- expect_error(
    suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file)),
    "already exist",
    class = "jatosr_file_exists"
  )
  # every path the call would write is named at once
  expect_match(conditionMessage(err), "study12.csv")
  expect_match(conditionMessage(err), "study12_metadata.csv")
  expect_match(conditionMessage(err), "study12_export.json")
  expect_length(rec$requests, n_before)
  # a sidecar in the way is refused before any request as well
  fresh <- file.path(root, "fresh.rds")
  writeLines("", file.path(root, "fresh_metadata.rds"))
  expect_error(suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = fresh)), "fresh_metadata.rds", class = "jatosr_file_exists")
  unlink(file.path(root, "fresh_metadata.rds"))
  writeLines("", file.path(root, "fresh_export.json"))
  expect_error(suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = fresh)), "fresh_export.json", class = "jatosr_file_exists")
  expect_length(rec$requests, n_before)

  # with overwrite only the metadata request is made; the cache is current
  suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file, overwrite = TRUE))
  expect_length(rec$requests, n_before + 1)
  expect_equal(basename(request_paths(rec)[n_before + 1]), "metadata")

  # explicit format on a bare file name, no sidecars, a named metadata file
  bare <- file.path(root, "study12")
  suppressMessages(jatos_export_results(
    batch_id = 36, cache = cache, file = bare, format = "rds",
    metadata_file = FALSE, provenance = FALSE
  ))
  expect_equal(unique(readRDS(bare)$batch_id), 36L)
  expect_false(file.exists(file.path(root, "study12_metadata")))
  named <- file.path(root, "runs.rds")
  suppressMessages(jatos_export_results(
    batch_id = 36, cache = cache, file = file.path(root, "b36.rds"),
    metadata_file = named, provenance = FALSE
  ))
  expect_equal(readRDS(named)$study_result_id, 9004L)
  expect_false(file.exists(file.path(root, "b36_export.json")))
})

test_that("jatos_export_results with split = 'component' writes one trials file per component", {
  local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "s13.rds")

  # the mock filters by batch only, so batch 36 stands for study 13
  msgs <- capture_messages(
    out <- jatos_export_results(batch_id = 36, cache = cache, file = file, split = "component")
  )
  expect_type(out, "list")
  expect_equal(names(out), c("131", "132"))
  files <- file.path(root, c("s13_component_131.rds", "s13_component_132.rds"))
  expect_true(all(file.exists(files)))
  expect_false(file.exists(file))
  expect_identical(readRDS(files[2]), out[["132"]])
  expect_equal(readRDS(file.path(root, "s13_metadata.rds"))$study_result_id, 9004L)
  prov <- jsonlite::read_json(file.path(root, "s13_export.json"))
  expect_equal(unlist(prov$files$trials), files)
  expect_equal(prov$counts$exported$trials, 2L)
  expect_match(paste(msgs, collapse = "\n"), "Wrote 2 trials from 2 component results")
})

test_that("jatos_export_results takes a study uuid and records it", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  uuid <- "1c2d3e4f-0000-4000-8000-000000000012"
  suppressMessages(jatos_export_results(study_id = uuid, cache = file.path(root, "cache"), file = file.path(root, "u.rds")))
  body <- request_json_body(rec$requests[[1]])
  expect_equal(names(body), "studyUuids")
  expect_equal(unlist(body$studyUuids), uuid)
  prov <- jsonlite::read_json(file.path(root, "u_export.json"))
  expect_equal(prov$study_id, uuid)
  expect_error(
    jatos_export_results(study_id = c(12, uuid), cache = file.path(root, "cache"), file = file.path(root, "v.rds")),
    "mixes ids and uuids",
    class = "jatosr_bad_argument"
  )
  expect_false(file.exists(file.path(root, "v.rds")))
})

test_that("jatos_export_results stops before writing when a download failed", {
  local_download_mock(
    "POST .*/results/data$" = mock_json_body(list(apiVersion = "1.1.0", data = list()))
  )
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  err <- expect_error(
    suppressWarnings(suppressMessages(
      jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "a.rds"))
    )),
    "4 component results could not be downloaded \\(4 failed, 0 missing",
    class = "jatosr_incomplete_download"
  )
  expect_no_token(conditionMessage(err))
  expect_equal(list.files(root), "cache")
})

test_that("jatos_export_results stops before writing when a result was missing from the answer", {
  # the metadata lists a component result 7009 (500 bytes) that the zip lacks
  parsed <- read_fixture_json("metadata.json")
  extra <- parsed$data[[1]]$studyResults[[1]]$componentResults[[1]]
  extra$id <- 7009L
  extra$data$size <- 500
  parsed$data[[1]]$studyResults[[1]]$componentResults <- c(
    parsed$data[[1]]$studyResults[[1]]$componentResults, list(extra)
  )
  local_download_mock(
    "POST .*/results/metadata$" = function(req) mock_metadata_by_batch(req, parsed = parsed)
  )
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  err <- expect_error(
    suppressWarnings(suppressMessages(
      jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "a.rds"))
    )),
    "1 component result could not be downloaded \\(0 failed, 1 missing",
    class = "jatosr_incomplete_download"
  )
  expect_match(conditionMessage(err), "Nothing was written")
  expect_equal(list.files(root), "cache")
  # the four files that did arrive are in the cache for the next run
  expect_length(list.files(cache, pattern = "data.txt", recursive = TRUE), 4)
})

test_that("a stale part file is caught after the metadata answer, before the download", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "s13.rds")
  writeLines("stale", file.path(root, "s13_component_131.rds"))

  err <- expect_error(
    suppressMessages(jatos_export_results(batch_id = 36, cache = cache, file = file, split = "component")),
    "s13_component_131.rds",
    class = "jatosr_file_exists"
  )
  expect_match(conditionMessage(err), "already exists")
  # one request (the metadata), no data fetched, nothing else written
  expect_equal(basename(request_paths(rec)), "metadata")
  expect_false(dir.exists(cache))
  expect_equal(sort(list.files(root)), "s13_component_131.rds")
  expect_equal(readLines(file.path(root, "s13_component_131.rds")), "stale")

  # with overwrite the parts are written in a plain loop
  suppressMessages(jatos_export_results(batch_id = 36, cache = cache, file = file, split = "component", overwrite = TRUE))
  expect_equal(nrow(readRDS(file.path(root, "s13_component_131.rds"))), 1)
})

test_that("the metadata sidecar may have a format of its own", {
  local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  file <- file.path(root, "s.rds")
  sidecar <- file.path(root, "s_meta.csv")

  suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file, metadata_file = sidecar))
  expect_true(file.exists(file))
  expect_true(file.exists(sidecar))
  back <- utils::read.csv(sidecar, encoding = "UTF-8", na.strings = "")
  expect_equal(back$study_result_id, c(9001L, 9002L, 9003L, 9004L))
  expect_equal(jsonlite::read_json(file.path(root, "s_export.json"))$files$metadata, sidecar)

  # a sidecar path without an extension cannot be written, and says so before any request
  rec <- local_download_mock()
  expect_error(
    jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "t.rds"), metadata_file = file.path(root, "t_meta")),
    "t_meta",
    class = "jatosr_bad_argument"
  )
  expect_length(rec$requests, 0)
  # the default sidecar follows an explicit format on a bare trials name
  suppressMessages(jatos_export_results(batch_id = 36, cache = cache, file = file.path(root, "bare"), format = "csv"))
  expect_true(file.exists(file.path(root, "bare_metadata")))
  expect_equal(utils::read.csv(file.path(root, "bare_metadata"))$study_result_id, 9004L)
})

test_that("jatos_export_results(download = FALSE) builds the dataset from the cache without a request", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  online <- suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "on.rds"), states = "FINISHED"))
  n_before <- length(rec$requests)

  # no credentials, no routes: the offline export must not need either. The
  # mock answered study 12 with both studies' batches, so the offline call
  # names both studies to select the same rows.
  local_no_credentials()
  rec2 <- local_jatos_mock()
  msgs <- capture_messages(
    offline <- jatos_export_results(study_id = c(12, 13), cache = cache, file = file.path(root, "off.rds"), states = "FINISHED", download = FALSE)
  )
  expect_length(rec2$requests, 0)
  expect_length(rec$requests, n_before)
  expect_identical(offline, online)
  expect_identical(readRDS(file.path(root, "off.rds")), readRDS(file.path(root, "on.rds")))
  expect_identical(readRDS(file.path(root, "off_metadata.rds")), readRDS(file.path(root, "on_metadata.rds")))
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "in the cached metadata; no request made")
  expect_match(text, "Excluded 1 of 4 study results")
  expect_match(text, "Reading 4 files")
  expect_match(text, "Writing 6 trials to")
  expect_no_token(text)

  prov <- jsonlite::read_json(file.path(root, "off_export.json"))
  expect_true(prov$offline)
  expect_null(prov$host)
  expect_null(prov$profile)
  expect_equal(unlist(prov$study_id), c(12L, 13L))
  expect_equal(prov$filters$states, "FINISHED")
  expect_null(prov$counts$on_server)
  expect_equal(prov$counts$in_cache$study_results, 4L)
  expect_equal(prov$counts$in_cache$component_results, 6L)
  files <- prov$counts$in_cache$metadata_files
  expect_length(files, 2)
  expect_equal(basename(dirname(files[[1]]$file)), "batch_34")
  expect_match(files[[1]]$modified, "^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")
  expect_equal(prov$counts$exported$trials, 6L)
  online_prov <- jsonlite::read_json(file.path(root, "on_export.json"))
  expect_null(online_prov$offline)
  expect_equal(online_prov$host, fake_host)

  # ids select exactly, and the union, as the server does; both NULL is the whole cache
  one <- suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "s12.rds"), download = FALSE))
  expect_equal(unique(one$study_result_id), c(9001L, 9002L))
  expect_equal(jsonlite::read_json(file.path(root, "s12_export.json"))$counts$in_cache$study_results, 3L)
  by_batch <- suppressMessages(jatos_export_results(batch_id = 36, cache = cache, file = file.path(root, "b36.rds"), download = FALSE))
  expect_equal(unique(by_batch$batch_id), 36L)
  uuid <- "1c2d3e4f-0000-4000-8000-000000000012"
  by_uuid <- suppressMessages(jatos_export_results(study_id = uuid, cache = cache, file = file.path(root, "uu.rds"), download = FALSE))
  expect_equal(unique(by_uuid$batch_id), 34L)
  both <- suppressMessages(jatos_export_results(study_id = 13, batch_id = 34, cache = cache, file = file.path(root, "both.rds"), download = FALSE))
  expect_equal(nrow(both), 6)
  whole <- suppressMessages(jatos_export_results(cache = cache, file = file.path(root, "all.rds"), download = FALSE))
  expect_equal(nrow(whole), 6)
  expect_null(jsonlite::read_json(file.path(root, "all_export.json"))$study_id)
  expect_equal(nrow(suppressMessages(jatos_export_results(study_id = 99, cache = cache, file = file.path(root, "none.rds"), download = FALSE))), 0)

  # the archive needs the server; a missing cache is an error before anything is written
  expect_error(
    jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "z.rds"), download = FALSE, archive_study = TRUE),
    "archive_study",
    class = "jatosr_bad_argument"
  )
  expect_error(jatos_export_results(study_id = 12, cache = file.path(root, "nope"), file = file.path(root, "z.rds"), download = FALSE), "does not exist", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "z.rds"), download = NA), "TRUE", class = "jatosr_bad_argument")
  expect_false(file.exists(file.path(root, "z.rds")))
  expect_length(rec2$requests, 0)
})

test_that("jatos_export_results passes reader and metadata_cols through", {
  local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")

  tagged <- function(file) {
    trials <- jatos_read_json(file)
    trials$from_reader <- TRUE
    trials
  }
  out <- suppressMessages(jatos_export_results(
    study_id = 12, cache = cache, file = file.path(root, "r.rds"),
    reader = tagged, metadata_cols = c("batch_id", "worker_type")
  ))
  expect_true(all(out$from_reader))
  expect_equal(names(out)[1:6], c("study_result_id", "component_result_id", "batch_id", "worker_type", query_cols))
  expect_false("component_id" %in% names(out))
  # NULL joins the ids, the query columns and the fields only
  bare <- suppressMessages(jatos_export_results(
    study_id = 12, cache = cache, file = file.path(root, "n.rds"), metadata_cols = NULL, fields = "age"
  ))
  expect_equal(names(bare)[1:5], c("study_result_id", "component_result_id", query_cols, "age"))
  expect_error(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "e.rds"), reader = "read.csv"), "reader", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "e.rds"), metadata_cols = 1), "metadata_cols", class = "jatosr_bad_argument")
  expect_false(file.exists(file.path(root, "e.rds")))
})

test_that("jatos_export_results passes coerce and on_error through and counts the files it read", {
  local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  suppressMessages(jatos_export_results(study_id = 12, cache = cache, file = file.path(root, "on.rds")))
  files <- jatos_read_metadata(cache)$file
  files <- files[!is.na(files)]
  expect_length(files, 4)
  offline <- function(name, ...) {
    jatos_export_results(cache = cache, file = file.path(root, name), download = FALSE, ...)
  }

  # a column that is a string in one file and a number in the others
  writeLines('[{"trial_index":0,"rt":"slow"}]', files[[1]])
  for (f in files[-1]) writeLines('[{"trial_index":0,"rt":300}]', f)
  expect_error(suppressMessages(offline("conflict.rds")), "disagree on a column's type")
  expect_false(file.exists(file.path(root, "conflict.rds")))
  coerced <- suppressMessages(offline("coerced.rds", coerce = "character"))
  expect_type(coerced$rt, "character")
  expect_equal(sort(coerced$rt), c("300", "300", "300", "slow"))

  # a file the reader cannot read: an abort by default, left out with skip
  writeLines("not json", files[[1]])
  expect_error(suppressMessages(offline("broken.rds")), "not valid JSON")
  expect_false(file.exists(file.path(root, "broken.rds")))
  msgs <- capture_messages(
    cnd <- expect_warning(skipped <- offline("skipped.rds", on_error = "skip"), class = "jatosr_files_skipped")
  )
  expect_equal(cnd$files, files[[1]])
  expect_equal(nrow(skipped), 3)
  text <- paste(msgs, collapse = "\n")
  expect_match(text, "Reading 4 files")
  expect_match(text, "Wrote 3 trials from 3 component results")
  prov <- jsonlite::read_json(file.path(root, "skipped_export.json"))
  expect_equal(prov$counts$exported$files_read, 3L)
  expect_equal(prov$counts$exported$trials, 3L)
  expect_named(prov$counts$exported, c("study_results", "component_results", "files_read", "trials"))
})

test_that("jatos_export_results checks its arguments before any request", {
  rec <- local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  target <- file.path(root, "a.rds")
  expect_error(jatos_export_results(cache = cache, file = target), "at least one id", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, format = "csv"), "rds", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, format = NA), "string or character vector")
  expect_error(jatos_export_results(12, cache = cache, file = file.path(root, "a")), "format", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = file.path(root, "data", "a.rds")), "does not exist", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, 34, 7, cache = cache, file = target), "must be empty|\\.\\.\\.")
  expect_error(jatos_export_results(12, cache = "", file = target), "cache", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, overwrite = 1), "TRUE", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, fields = c("a", "a")), "repeat", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, fields = ""), "fields", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, states = 1), "study states", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, worker_types = NA), "worker types", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, since = "soon"), "since", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, split = "batch"), "split")
  expect_error(jatos_export_results(12, cache = cache, file = target, metadata_file = 1), "metadata_file", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, metadata_file = file.path(root, "no", "m.rds")), "does not exist", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, provenance = "yes"), "TRUE", class = "jatosr_bad_argument")
  expect_error(jatos_export_results(12, cache = cache, file = target, coerce = "numeric"), "`coerce` must be one of")
  expect_error(jatos_export_results(12, cache = cache, file = target, on_error = "ignore"), "`on_error` must be one of")
  expect_length(rec$requests, 0)
  expect_false(dir.exists(cache))
  expect_equal(list.files(root), character())
})
