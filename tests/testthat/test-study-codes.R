# POST /studies/{id}/studyCodes answers with a bare array of code strings
# (jatos-api.yaml, verified 2026-09-05); the mock generates `amount` of them
# so tests can assert on the body and on the row count together.
mock_study_codes <- function(req) {
  body <- request_json_body(req)
  n <- body$amount %||% 1
  codes <- sprintf("code%04d", seq_len(n))
  mock_json_body(list(apiVersion = "1.1.0", data = as.list(codes)))
}

# --- jatos_create_study_codes ----------------------------------------------------

test_that("jatos_create_study_codes posts type, batch, amount and comment as JSON", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/studies/12/studyCodes$" = mock_study_codes)

  out <- suppressMessages(jatos_create_study_codes(12, batch_id = 34, comment = "pilot 1"))

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 1)
  expect_equal(
    names(out),
    c("study_code", "study_id", "batch_id", "type", "comment", "study_link")
  )
  expect_equal(out$study_code, "code0001")
  expect_equal(out$study_id, 12L)
  expect_equal(out$batch_id, 34L)
  expect_equal(out$type, "PersonalSingle")
  expect_equal(out$comment, "pilot 1")
  expect_equal(out$study_link, paste0(fake_host, "/publix/code0001"))

  expect_length(rec$requests, 1)
  req <- last_request(rec)
  expect_equal(mock_method(req), "POST")
  expect_match(req$url, "/studies/12/studyCodes$")
  body <- request_json_body(req)
  expect_equal(body$type, "PersonalSingle")
  expect_equal(body$batchId, 34L)
  expect_equal(body$amount, 1L)
  expect_equal(body$comment, "pilot 1")
})

test_that("n = 3 yields three rows and amount = 3 in the body", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/studies/12/studyCodes$" = mock_study_codes)

  out <- suppressMessages(
    jatos_create_study_codes(12, batch_id = 34, n = 3, type = "PersonalMultiple")
  )
  expect_equal(nrow(out), 3)
  expect_equal(out$study_code, c("code0001", "code0002", "code0003"))
  expect_equal(out$type, rep("PersonalMultiple", 3))
  expect_true(all(is.na(out$comment)))
  expect_equal(out$study_link, paste0(fake_host, "/publix/code000", 1:3))
  expect_equal(request_json_body(last_request(rec))$amount, 3L)
  expect_length(rec$requests, 1)
})

test_that("the POST that creates codes carries no retry policy", {
  # Every other request only reads and carries httr2's retry policy (see
  # test-request.R). This one creates codes and workers on the server, and
  # a second POST after an ambiguous answer would create a second set that
  # the first answer never reported. A mock cannot show a retry (httr2
  # answers a mocked request before its retry loop), so the policy on the
  # request the server would see is what is asserted.
  local_fake_credentials()
  rec <- local_jatos_mock(
    "POST .*/studies/12/studyCodes$" = mock_study_codes,
    "GET .*/studyCodes/code0001$" = mock_json("study-code.json")
  )

  suppressMessages(jatos_create_study_codes(12, n = 2))
  expect_null(last_request(rec)$policies$retry_max_tries)

  jatos_study_code("code0001")
  expect_equal(last_request(rec)$policies$retry_max_tries, 3)
})

test_that("without batch_id the body names no batch and batch_id is NA", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/studies/[^/]+/studyCodes$" = mock_study_codes)

  out <- suppressMessages(jatos_create_study_codes("1c2d3e4f-0000-4000-8000-000000000012"))
  body <- request_json_body(last_request(rec))
  expect_false("batchId" %in% names(body))
  expect_false("comment" %in% names(body))
  expect_true(is.na(out$batch_id))
  expect_true(is.na(out$study_id))
  expect_match(last_request(rec)$url, "/studies/1c2d3e4f-0000-4000-8000-000000000012/studyCodes$")
})

test_that("general types return the batch's one code and refuse n > 1 or a comment before any request", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/studies/12/studyCodes$" = mock_study_codes)

  out <- suppressMessages(jatos_create_study_codes(12, batch_id = 34, type = "GeneralMultiple"))
  expect_equal(nrow(out), 1)
  expect_equal(request_json_body(last_request(rec))$type, "GeneralMultiple")
  expect_length(rec$requests, 1)

  expect_error(
    jatos_create_study_codes(12, n = 2, type = "GeneralSingle"),
    "PersonalSingle",
    class = "jatosr_bad_argument"
  )
  expect_error(
    jatos_create_study_codes(12, type = "MTurk", comment = "x"),
    "PersonalSingle",
    class = "jatosr_bad_argument"
  )
  expect_length(rec$requests, 1)
})

test_that("an unknown type and a bad n error before any request", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/studies/12/studyCodes$" = mock_study_codes)

  expect_error(jatos_create_study_codes(12, type = "Prolific"), "PersonalSingle")
  expect_error(jatos_create_study_codes(12, n = 0), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(12, n = 1.5), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(12, n = c(1, 2)), "positive integer", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(12, comment = 1), "string", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(12, batch_id = c(1, 2)), "single id", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(-1), "positive id", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)
})

test_that("the server's limits on amount and comment are enforced before any request", {
  local_fake_credentials()
  rec <- local_jatos_mock("POST .*/studies/12/studyCodes$" = mock_study_codes)
  expect_error(jatos_create_study_codes(12, n = 1001, type = "PersonalMultiple"), "at most 1000", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(12, comment = strrep("x", 256)), "255", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(12, comment = "wave <b>2</b>"), "HTML", class = "jatosr_bad_argument")
  expect_error(jatos_create_study_codes(12, comment = "<script>"), "HTML", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)

  out <- suppressMessages(
    jatos_create_study_codes(12, n = 1000, type = "PersonalMultiple", comment = strrep("é", 255))
  )
  expect_equal(nrow(out), 1000)
  expect_equal(request_json_body(last_request(rec))$amount, 1000L)
  expect_length(rec$requests, 1)
})

test_that("a 403 with a server message surfaces it without the token", {
  local_fake_credentials()
  local_jatos_mock(
    "POST .*/studies/12/studyCodes$" = mock_json_body(
      list(apiVersion = "1.1.0", error = list(message = "Not a member of this study")),
      status = 403
    )
  )
  err <- expect_error(jatos_create_study_codes(12), class = "httr2_http_403")
  expect_match(conditionMessage(err), "Not a member of this study")
  expect_no_token(conditionMessage(err))
})

test_that("the study code message reports the count and type", {
  local_fake_credentials()
  local_jatos_mock("POST .*/studies/12/studyCodes$" = mock_study_codes)
  expect_message(
    jatos_create_study_codes(12, n = 2, type = "PersonalMultiple"),
    "2 PersonalMultiple study codes"
  )
  expect_message(
    jatos_create_study_codes(12, type = "GeneralSingle"),
    "1 GeneralSingle study code"
  )
})

# --- jatos_study_code -------------------------------------------------------------

test_that("jatos_study_code fetches and parses one code", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/studyCodes/code0001$" = mock_json("study-code.json"))

  out <- jatos_study_code("code0001")
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 1)
  expect_equal(
    names(out),
    c("study_code", "batch_id", "type", "comment", "active", "study_link", "study_entry_link")
  )
  expect_equal(out$study_code, "code0001")
  expect_equal(out$batch_id, 34L)
  expect_equal(out$type, "PersonalSingle")
  expect_equal(out$comment, "pilot 1")
  expect_true(out$active)
  expect_equal(out$study_link, paste0(fake_host, "/publix/code0001"))
  expect_equal(out$study_entry_link, paste0(fake_host, "/publix/run?code=code0001"))

  expect_length(rec$requests, 1)
  expect_equal(mock_method(last_request(rec)), "GET")
  expect_match(last_request(rec)$url, "/studyCodes/code0001$")
})

test_that("a null comment becomes NA and the server's base path is kept in the links", {
  local_fake_credentials(host = "https://jatos.example.org:8443/jatos-base")
  local_jatos_mock("GET .*/studyCodes/code0009$" = mock_json("study-code-general.json"))

  out <- jatos_study_code("code0009")
  expect_true(is.na(out$comment))
  expect_false(out$active)
  expect_equal(out$study_link, "https://jatos.example.org:8443/jatos-base/publix/code0009")
  expect_equal(out$study_entry_link, "https://jatos.example.org:8443/jatos-base/publix/run?code=code0009")
})

test_that("jatos_study_code takes a vector of codes, one request each", {
  local_fake_credentials()
  rec <- local_jatos_mock(
    "GET .*/studyCodes/code0001$" = mock_json("study-code.json"),
    "GET .*/studyCodes/code0009$" = mock_json("study-code-general.json")
  )
  out <- jatos_study_code(c("code0001", "code0009"))
  expect_equal(nrow(out), 2)
  expect_equal(out$study_code, c("code0001", "code0009"))
  expect_equal(out$batch_id, c(34L, 35L))
  expect_length(rec$requests, 2)
})

test_that("jatos_study_code validates codes before any request", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/studyCodes/.*" = mock_json("study-code.json"))
  expect_error(jatos_study_code(""), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_study_code(NA_character_), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_study_code(character()), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_study_code("code/0001"), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_study_code("code 0001"), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_study_code(1234), "study code", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)
  # the message names what the pattern admits
  err <- expect_error(check_codes("code 0001"), class = "jatosr_bad_argument")
  expect_match(conditionMessage(err), "letters, digits, `-` and `_`", fixed = TRUE)
  expect_equal(check_codes(c("Ab1-_", "x")), c("Ab1-_", "x"))
})

test_that("a 404 for an unknown code surfaces the server message", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/studyCodes/nope$" = mock_json_body(
      list(apiVersion = "1.1.0", error = list(message = "Study code not found")),
      status = 404
    )
  )
  err <- expect_error(jatos_study_code("nope"), class = "httr2_http_404")
  expect_match(conditionMessage(err), "Study code not found")
  expect_no_token(conditionMessage(err))
})

# --- activate / deactivate ---------------------------------------------------------

test_that("jatos_activate_study_code and jatos_deactivate_study_code PATCH the active flag", {
  local_fake_credentials()
  rec <- local_jatos_mock(
    "PATCH .*/studyCodes/code0001$" = function(req) {
      active <- request_json_body(req)$active
      mock_json_null(list(
        apiVersion = "1.1.0",
        data = list(
          studyCode = "code0001", batchId = 34L, type = "PersonalSingle",
          comment = NULL, active = active,
          studyLinkPath = "/publix/code0001", studyEntryPath = "/publix/run?code=code0001"
        )
      ))
    }
  )

  on <- jatos_activate_study_code("code0001")
  expect_true(on$active)
  expect_true(is.na(on$comment))
  expect_equal(on$study_link, paste0(fake_host, "/publix/code0001"))
  req <- last_request(rec)
  expect_equal(mock_method(req), "PATCH")
  expect_match(req$url, "/studyCodes/code0001$")
  expect_true(request_json_body(req)$active)

  off <- jatos_deactivate_study_code("code0001")
  expect_false(off$active)
  expect_false(request_json_body(last_request(rec))$active)
  expect_length(rec$requests, 2)
})

test_that("deactivating several codes sends one PATCH per code", {
  local_fake_credentials()
  rec <- local_jatos_mock(
    "PATCH .*/studyCodes/code000[0-9]$" = function(req) {
      code <- sub(".*/studyCodes/", "", httr2::url_parse(req$url)$path)
      mock_json_null(list(
        apiVersion = "1.1.0",
        data = list(
          studyCode = code, batchId = 34L, type = "PersonalMultiple",
          comment = "wave 2", active = request_json_body(req)$active,
          studyLinkPath = paste0("/publix/", code),
          studyEntryPath = paste0("/publix/run?code=", code)
        )
      ))
    }
  )
  out <- jatos_deactivate_study_code(c("code0002", "code0003"))
  expect_equal(out$study_code, c("code0002", "code0003"))
  expect_equal(out$active, c(FALSE, FALSE))
  expect_length(rec$requests, 2)
  expect_true(all(vapply(rec$requests, mock_method, character(1)) == "PATCH"))
})

test_that("activate and deactivate validate codes and surface a 403 without the token", {
  local_fake_credentials()
  rec <- local_jatos_mock(
    "PATCH .*/studyCodes/code0001$" = mock_json_body(
      list(apiVersion = "1.1.0", error = list(message = "Not allowed")),
      status = 403
    )
  )
  expect_error(jatos_activate_study_code(""), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_deactivate_study_code("a b"), "study code", class = "jatosr_bad_argument")
  expect_length(rec$requests, 0)
  err <- expect_error(jatos_activate_study_code("code0001"), class = "httr2_http_403")
  expect_match(conditionMessage(err), "Not allowed")
  expect_no_token(conditionMessage(err))
})

# --- jatos_study_links (pure) -------------------------------------------------------

test_that("jatos_study_links builds <host>/publix/<code> without any request", {
  local_fake_credentials()
  rec <- local_jatos_mock()
  links <- jatos_study_links(c("code0001", "code0002"))
  expect_equal(links, paste0(fake_host, "/publix/code000", 1:2))
  expect_length(rec$requests, 0)
  expect_no_token(links)
  expect_no_token(capture.output(print(links)))
})

test_that("jatos_study_links takes an explicit host and normalises it", {
  local_no_credentials()
  expect_equal(
    jatos_study_links("code0001", host = "https://other.example.org/"),
    "https://other.example.org/publix/code0001"
  )
  expect_equal(
    jatos_study_links("code0001", host = "https://other.example.org/jatos/api/v1"),
    "https://other.example.org/publix/code0001"
  )
  expect_equal(
    jatos_study_links("code0001", host = "https://other.example.org/base"),
    "https://other.example.org/base/publix/code0001"
  )
})

test_that("jatos_study_links follows the credential profile", {
  local_no_credentials()
  local_fake_credentials(host = "https://admin.example", profile = "lab_admin")
  expect_equal(jatos_study_links("code0001", profile = "lab_admin"), "https://admin.example/publix/code0001")
  expect_error(jatos_study_links("code0001"), "JATOS_HOST", class = "jatosr_no_host")
  withr::local_envvar(JATOS_PROFILE = "lab_admin")
  expect_equal(jatos_study_links("code0001"), "https://admin.example/publix/code0001")
})

test_that("jatos_study_links needs a host and valid codes", {
  local_no_credentials()
  expect_error(jatos_study_links("code0001"), "JATOS_HOST", class = "jatosr_no_host")
  local_fake_credentials()
  expect_error(jatos_study_links(""), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_study_links(c("code0001", NA)), "study code", class = "jatosr_bad_argument")
  expect_error(jatos_study_links("code/0001"), "study code", class = "jatosr_bad_argument")
})

test_that("jatos_study_links works on the study_code column of a create result", {
  local_fake_credentials()
  local_jatos_mock("POST .*/studies/12/studyCodes$" = mock_study_codes)
  codes <- suppressMessages(jatos_create_study_codes(12, n = 2, type = "PersonalMultiple"))
  expect_equal(jatos_study_links(codes$study_code), codes$study_link)
})
