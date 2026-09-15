test_that("jatos_studies returns one row per study with nested components and batches", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/studies/properties$" = mock_json("studies.json"))
  studies <- jatos_studies()

  expect_s3_class(studies, "tbl_df")
  expect_equal(nrow(studies), 2)
  expect_equal(studies$study_id, c(12L, 13L))
  expect_equal(studies$title, c("A03_ColorBinding", "A01_Registration"))
  expect_equal(studies$active, c(TRUE, FALSE))
  expect_equal(studies$locked, c(FALSE, TRUE))
  expect_true(is.na(studies$description[2]))
  expect_equal(studies$members[[1]], "researcher@example.org")
  expect_equal(studies$members[[2]], character())

  comps <- studies$components[[2]]
  expect_equal(comps$component_id, c(131L, 132L))
  expect_equal(comps$study_id, c(13L, 13L))
  expect_equal(comps$reloadable, c(TRUE, FALSE))

  batches <- studies$batches[[1]]
  expect_equal(batches$batch_id, c(34L, 35L))
  expect_equal(batches$max_total_workers, c(NA_integer_, 120L))
  expect_equal(batches$allowed_worker_types[[1]], c("PersonalSingle", "GeneralSingle"))

  q <- request_query(last_request(rec))
  expect_equal(q$withComponentProperties, "true")
  expect_equal(q$withBatchProperties, "true")
})

test_that("jatos_studies forwards the flags and validates them", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/studies/properties$" = mock_json("studies.json"))
  jatos_studies(with_components = FALSE, with_batches = FALSE)
  q <- request_query(last_request(rec))
  expect_equal(q$withComponentProperties, "false")
  expect_equal(q$withBatchProperties, "false")
  expect_error(jatos_studies(with_components = "yes"), "TRUE", class = "jatosr_bad_argument")
})

test_that("jatos_studies with no studies returns an empty tibble with all columns", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/studies/properties$" = mock_json_body(list(apiVersion = "1.1.0", data = list()))
  )
  studies <- jatos_studies()
  expect_equal(nrow(studies), 0)
  expect_true(all(c("study_id", "title", "components", "batches") %in% names(studies)))
})

test_that("jatos_study fetches one study by id or uuid", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/studies/[^/]+/properties$" = mock_json("study.json"))
  one <- jatos_study(12)
  expect_equal(nrow(one), 1)
  expect_equal(one$study_id, 12L)
  expect_equal(one$batches[[1]]$batch_id, 34L)
  expect_match(last_request(rec)$url, "/studies/12/properties")

  jatos_study("1c2d3e4f-0000-4000-8000-000000000012")
  expect_match(last_request(rec)$url, "/studies/1c2d3e4f-0000-4000-8000-000000000012/properties")
  jatos_study("1C2D3E4F-0000-4000-8000-000000000012")
  jatos_study("12")
  expect_match(last_request(rec)$url, "/studies/12/properties")

  expect_error(jatos_study(-1), "positive id", class = "jatosr_bad_argument")
  expect_error(jatos_study(c(1, 2)), "positive id", class = "jatosr_bad_argument")
  expect_error(jatos_study(""), "positive id", class = "jatosr_bad_argument")
  expect_error(jatos_study("0"), "positive id", class = "jatosr_bad_argument")
})

test_that("check_ref refuses strings that are neither an id nor a uuid before any request", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*" = mock_json("study.json"))
  bad <- c(
    "12/../../admin/token", "12?x=1", "12 ", "c000-uuid",
    "1c2d3e4f-0000-4000-8000-00000000001", "1c2d3e4f-0000-4000-8000-0000000000123",
    "1c2d3e4f_0000_4000_8000_000000000012", "1c2d3e4g-0000-4000-8000-000000000012"
  )
  for (x in bad) {
    expect_error(jatos_study(x), "uuid", class = "jatosr_bad_argument")
    expect_error(jatos_batch(x), "uuid", class = "jatosr_bad_argument")
    expect_error(jatos_components(x), "uuid", class = "jatosr_bad_argument")
  }
  expect_length(rec$requests, 0)
  expect_equal(check_ref("007"), "7")
})

test_that("jatos_components and jatos_batches attach the study id", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/studies/13/components$" = mock_json("components.json"),
    "GET .*/studies/13/batches$" = mock_json("batches.json")
  )
  comps <- jatos_components(13)
  expect_equal(comps$component_id, c(131L, 132L))
  expect_equal(comps$html_file_path, c("consent.html", "demo.html"))
  expect_equal(unique(comps$study_id), 13L)

  batches <- jatos_batches(13)
  expect_equal(batches$batch_id, c(34L, 35L))
  expect_equal(batches$title, c("Default", "Prolific wave 2"))
  expect_equal(unique(batches$study_id), 13L)
})

test_that("study id from a uuid reference is NA", {
  local_fake_credentials()
  local_jatos_mock("GET .*/studies/[^/]+/components$" = mock_json("components.json"))
  comps <- jatos_components("1c2d3e4f-0000-4000-8000-000000000013")
  expect_true(all(is.na(comps$study_id)))
})

test_that("jatos_batch and jatos_groups parse their endpoints", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/batches/35$" = mock_json("batch.json"),
    "GET .*/batches/35/groups$" = mock_json("groups.json")
  )
  b <- jatos_batch(35)
  expect_equal(nrow(b), 1)
  expect_equal(b$batch_id, 35L)
  expect_false(b$active)
  expect_true(is.na(b$study_id))

  g <- jatos_groups(35)
  expect_equal(g$group_id, c(501L, 502L))
  expect_equal(g$active_members[[1]], c(9001L, 9002L))
  expect_equal(g$history_members[[2]], c(9003L, 9004L, 9005L))
  expect_equal(g$n_results, c(2L, 3L))
  expect_true(is.na(g$end_time[1]))
  expect_equal(as.numeric(g$end_time[2]), 1756005600)
  expect_equal(unique(g$batch_id), 35L)
})
