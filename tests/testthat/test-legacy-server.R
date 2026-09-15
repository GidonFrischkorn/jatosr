# The 1771 tests of this suite ran against a mock built from the OpenAPI
# spec, and every one of them passed while a real JATOS at `apiVersion`
# 1.0.1 was breaking five ways. The payloads that server
# actually sends are in helper-legacy.R; these tests are the ones that would
# have caught them. Keep them running against the legacy profile, not
# against the spec routes: the point is the disagreement between the two.

test_that("a token whose expirationDate is the sentinel 0 has no expiry", {
  local_fake_credentials()
  local_legacy_mock()

  info <- jatos_token_info()
  expect_true(is.na(info$expires))
  expect_false(info$expired)
  expect_true(info$active)
  expect_equal(info$name, "no-expiry-token")
  # the fields this API version does not send at all
  expect_true(is.na(info$username))
  expect_true(is.na(info$user_id))
})

test_that("a non-expiring token does not warn on the next connection", {
  # The regression that mattered: the epoch was stored as the expiry, so
  # the next jatos_connection() of the session told the user that their
  # working token had expired in 1970.
  local_fake_credentials()
  local_legacy_mock()

  jatos_token_info()
  expect_no_warning(jatos_connection())
  expect_no_warning(jatos_token_info())
})

test_that("a past expiry the server calls not expired does not warn", {
  # Belt and braces for the next sentinel a JATOS invents: `isExpired` is
  # the server's own answer and it is in the same body as the date.
  local_fake_credentials()
  body <- read_fixture_json("token-legacy.json")
  body$data$expirationDate <- 1000 # 1970-01-01 00:00:01, and not a sentinel
  local_jatos_mock("GET .*/admin/token$" = mock_json_null(body))

  info <- jatos_token_info()
  expect_false(is.na(info$expires))
  expect_false(info$expired)
  expect_no_warning(jatos_connection())

  # a genuinely expired token still warns
  body$data$isExpired <- TRUE
  local_jatos_mock("GET .*/admin/token$" = mock_json_null(body))
  jatos_token_info()
  w <- capture_warnings(jatos_connection())
  expect_length(w, 1)
  expect_match(w, "expired on")
  expect_no_token(w)
})

test_that("the token check names no username when the API sends none", {
  local_fake_credentials()
  local_legacy_mock()

  msg <- capture_messages(
    jatos_set_credentials(fake_host, fake_token)
  )
  expect_match(msg, 'Token "no-expiry-token"', all = FALSE)
  expect_match(msg, "no expiry", all = FALSE)
  expect_false(any(grepl("for \"NA\"", msg, fixed = TRUE)))
  expect_no_token(msg)
})

test_that("a text/plain error body is used as the reason", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/admin/token$" = mock_text(
      legacy_error_bodies[["invalid_token"]],
      status = 401
    )
  )

  err <- expect_error(jatos_token_info(), class = "httr2_http_401")
  msg <- conditionMessage(err)
  expect_match(msg, "Invalid api token", fixed = TRUE)
  # the hint that names the tools to use survives alongside it
  expect_match(msg, "jatos_list_profiles()", fixed = TRUE)
  expect_no_token(msg)
})

test_that("the two 404 bodies of one server get different hints", {
  local_fake_credentials()

  # a route this JATOS does not have
  local_legacy_mock()
  err <- expect_error(jatos_batches(1834), class = "httr2_http_404")
  msg <- conditionMessage(err)
  expect_match(msg, "couldn't be found", fixed = TRUE)
  expect_match(msg, "missing route, not a missing id")
  expect_false(grepl("Check the id", msg, fixed = TRUE))
  # and the endpoint's own way round it, where the user meets the error
  expect_match(msg, "jatos_studies(with_batches = TRUE)", fixed = TRUE)

  # an id this JATOS does not have
  local_jatos_mock(
    "GET .*/studies/999999/properties$" = mock_text(
      legacy_error_bodies[["missing_id"]],
      status = 404
    )
  )
  err <- expect_error(jatos_study(999999), class = "httr2_http_404")
  msg <- conditionMessage(err)
  expect_match(msg, "Couldn't find study with ID 999999", fixed = TRUE)
  expect_false(grepl("missing route", msg, fixed = TRUE))
})

test_that("the batches of a legacy server are reachable through jatos_studies", {
  # The documented way round the missing route, and the reason the 404 on that route is
  # a message bug and not a data-access bug.
  local_fake_credentials()
  local_legacy_mock()

  studies <- jatos_studies()
  expect_gt(nrow(studies), 0)
  expect_equal(studies$batches[[1]]$batch_id, c(34L, 35L))
  expect_error(jatos_batches(studies$study_id[[1]]), class = "httr2_http_404")
})

test_that("an error names the profile it used", {
  local_fake_credentials(token = fake_tokens[["zebra"]], profile = "zebra")
  local_jatos_mock(
    "GET .*/admin/token$" = mock_text(
      legacy_error_bodies[["invalid_token"]],
      status = 401
    )
  )

  err <- expect_error(
    jatos_token_info(jatos_connection("zebra")),
    class = "httr2_http_401"
  )
  msg <- conditionMessage(err)
  expect_match(msg, 'Profile "zebra"', fixed = TRUE)
  expect_match(msg, fake_host, fixed = TRUE)
  expect_no_token(msg)

  # an HTML login page names it too, and a direct call without a
  # connection stays valid
  local_jatos_mock("GET .*/admin/token$" = mock_html_login())
  html <- conditionMessage(
    expect_error(jatos_token_info(jatos_connection("zebra")), class = "httr2_http")
  )
  expect_match(html, 'Profile "zebra"', fixed = TRUE)
  expect_no_token(html)
})

test_that("a token echoed by the server is scrubbed out of the message", {
  # The guarantee that no token reaches a condition message has to hold
  # even when the server puts one in its own error body. This server does
  # not, but that is an observation about one server.
  local_fake_credentials(token = fake_tokens[["echoed"]], profile = "echo")
  bodies <- list(
    text = mock_text(
      paste0("Invalid api token: ", fake_tokens[["echoed"]]),
      status = 401
    ),
    json = mock_json_body(
      list(
        apiVersion = "1.0.1",
        error = list(message = paste0("token ", fake_tokens[["echoed"]], " rejected"))
      ),
      status = 401
    )
  )

  for (body in bodies) {
    local({
      local_jatos_mock("GET .*/admin/token$" = body)
      err <- expect_error(
        jatos_token_info(jatos_connection("echo")),
        class = "httr2_http_401"
      )
      msg <- conditionMessage(err)
      expect_no_token(msg)
      expect_match(msg, "<token redacted>", fixed = TRUE)
    })
  }

  # a token-shaped string is scrubbed even when it is not this connection's
  expect_equal(
    scrub_secrets(paste0("Invalid api token: ", fake_tokens[["foreign"]])),
    "Invalid api token: <token redacted>"
  )
  # and a token without the jap_ prefix is scrubbed through the connection
  conn <- new_connection(fake_host, profile = "plain", token = fake_tokens[["plain"]])
  expect_equal(
    scrub_secrets(paste("rejected:", fake_tokens[["plain"]]), conn),
    "rejected: <token redacted>"
  )
})

test_that("a long or empty text body is not used as a message", {
  local_fake_credentials()
  long <- paste(rep("x", 600), collapse = "")
  local_jatos_mock("GET .*/admin/token$" = mock_text(long, status = 500))
  msg <- conditionMessage(expect_error(jatos_token_info(), class = "httr2_http_500"))
  expect_false(grepl("xxxx", msg, fixed = TRUE))

  local_jatos_mock("GET .*/admin/token$" = mock_text("   ", status = 500))
  msg <- conditionMessage(expect_error(jatos_token_info(), class = "httr2_http_500"))
  expect_match(msg, "HTTP 500")
})

test_that("credential lookup names the profiles that exist", {
  local_no_credentials()
  withr::local_envvar(c(
    JATOS_HOST_ALPHA = fake_host,
    JATOS_TOKEN_ALPHA = fake_tokens[["other"]],
    JATOS_HOST_BETA = fake_host,
    JATOS_TOKEN_BETA = fake_tokens[["admin"]]
  ))

  err <- expect_error(jatos_connection(), class = "jatosr_no_host")
  msg <- conditionMessage(err)
  expect_match(msg, "Configured profiles")
  expect_match(msg, "alpha")
  expect_match(msg, "beta")
  expect_match(msg, "JATOS_PROFILE")
  expect_no_token(msg)

  # the profile that failed is not offered as the way out of its own error
  err <- expect_error(jatos_connection("gamma"), class = "jatosr_no_host")
  msg <- conditionMessage(err)
  expect_match(msg, "alpha")
  expect_false(grepl("gamma\", \"", msg, fixed = TRUE))

  # nothing configured at all: no such bullet
  local_no_credentials()
  msg <- conditionMessage(expect_error(jatos_connection(), class = "jatosr_no_host"))
  expect_false(grepl("Configured profile", msg, fixed = TRUE))
})

test_that("the cache-layout refusal says nothing was touched and how to get the data", {
  legacy <- withr::local_tempdir()
  dir.create(file.path(legacy, "JATOS_DATA_36"), recursive = TRUE)
  before <- list.files(legacy, recursive = TRUE, all.files = TRUE)

  err <- expect_error(check_cache_layout(legacy), class = "jatosr_cache_layout")
  msg <- conditionMessage(err)
  expect_match(msg, "not a cache written by jatosr")
  expect_match(msg, "Nothing in this directory has been read or changed", fixed = TRUE)
  expect_match(msg, "jatos_export_archive")
  expect_match(msg, "jatos_import_results")
  expect_match(msg, "jatos_download_results")
  expect_equal(list.files(legacy, recursive = TRUE, all.files = TRUE), before)
})
