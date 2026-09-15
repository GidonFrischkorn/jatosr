test_that("jatos_req builds the URL, bearer header and user agent", {
  local_fake_credentials()
  req <- jatos_req(jatos_connection(), "admin/token")
  expect_equal(req$url, paste0(fake_host, "/jatos/api/v1/admin/token"))
  expect_true("Authorization" %in% names(req$headers))
  expect_equal(req$headers$Accept, "application/json")
  expect_match(req$options$useragent, "^jatosr/")
  expect_no_token(capture.output(print(req)))
})

test_that("jatos_req takes the Accept header from `accept`", {
  local_fake_credentials()
  req <- jatos_req(jatos_connection(), "results", accept = "application/zip")
  expect_equal(req$headers$Accept, "application/zip")
  expect_true("Authorization" %in% names(req$headers))
})

test_that("jatos_req accepts a path given as pieces", {
  local_fake_credentials()
  req <- jatos_req(jatos_connection(), c("studies", "12", "batches"))
  expect_equal(req$url, paste0(fake_host, "/jatos/api/v1/studies/12/batches"))
})

test_that("jatos_query explodes vectors and drops NULLs", {
  local_fake_credentials()
  req <- jatos_req(jatos_connection(), "results/metadata") |>
    jatos_query(batchId = c(1, 2), studyId = NULL, download = "false")
  q <- request_query(req)
  expect_equal(unname(unlist(q[names(q) == "batchId"])), c("1", "2"))
  expect_false("studyId" %in% names(q))
  expect_equal(q$download, "false")
})

test_that("read requests carry a retry policy and `retry = FALSE` drops it", {
  # The policy on the request object, not the retries themselves: httr2
  # answers a mocked request before its retry loop (req_perform() returns
  # the mock's response first thing), so a mock can never show a retry.
  # What the policy will make httr2 do is documented; that it is there is
  # what is asserted.
  local_fake_credentials()
  conn <- jatos_connection()

  expect_equal(jatos_req(conn, "studies")$policies$retry_max_tries, 3)
  expect_null(jatos_req(conn, "studies", retry = FALSE)$policies$retry_max_tries)
})

test_that("a 429 says to wait", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/admin/token$" = httr2::response(status_code = 429, headers = list(`retry-after` = "0"))
  )
  err <- expect_error(jatos_token_info(), class = "httr2_http_429")
  expect_match(conditionMessage(err), "rate of requests")
  expect_match(conditionMessage(err), "Wait a moment")
  expect_no_token(conditionMessage(err))
})

test_that("a 401 JSON error surfaces the server message without the token", {
  local_fake_credentials()
  local_jatos_mock("GET .*/admin/token$" = mock_json("error-401.json", status = 401))
  err <- expect_error(jatos_token_info(), class = "httr2_http_401")
  expect_match(conditionMessage(err), "Invalid or expired API token")
  expect_no_token(conditionMessage(err))
})

test_that("a 200 HTML page is treated as an authentication failure", {
  local_fake_credentials()
  local_jatos_mock("GET .*/admin/token$" = mock_html_login())
  err <- expect_error(jatos_token_info(), class = "httr2_http")
  expect_match(conditionMessage(err), "HTML page")
  expect_no_token(conditionMessage(err))
})

test_that("a 401 without a body renders the hint as text, not as cli markup", {
  local_fake_credentials()
  local_jatos_mock("GET .*/admin/token$" = httr2::response(status_code = 401))
  err <- expect_error(jatos_token_info(), class = "httr2_http_401")
  msg <- conditionMessage(err)
  expect_match(msg, "jatos_list_profiles()", fixed = TRUE)
  expect_false(grepl("{.fn", msg, fixed = TRUE))
  expect_no_token(msg)

  local_jatos_mock("GET .*/admin/token$" = mock_html_login())
  html <- conditionMessage(expect_error(jatos_token_info(), class = "httr2_http"))
  expect_match(html, "`host`", fixed = TRUE)
  expect_false(grepl("{.arg", html, fixed = TRUE))
})

test_that("a server message with braces or an expression is shown verbatim without the token", {
  local_fake_credentials()
  texts <- c(
    'bad body {batchIds}',
    'boom {Sys.getenv("JATOS_TOKEN")}',
    "oops {reveal_secret(conn_token(conn))}"
  )
  for (text in texts) {
    local({
      # jatos_set_credentials() below stores a token, and the next round
      # would then find it shadowed by JATOS_TOKEN and warn about it. Each
      # round gets its own empty credential store instead.
      local_fake_keyring()
      local_jatos_mock(
        "GET .*/admin/token$" = mock_json_body(
          list(apiVersion = "1.1.0", error = list(message = text)),
          status = 500
        )
      )
      err <- expect_error(jatos_token_info(), class = "httr2_http_500")
      expect_match(conditionMessage(err), text, fixed = TRUE)
      expect_no_token(conditionMessage(err))

      # the same text through the credentials check is a warning, not an error
      w <- expect_warning(
        suppressMessages(jatos_set_credentials(fake_host, fake_token)),
        "Could not verify"
      )
      expect_match(conditionMessage(w), text, fixed = TRUE)
      expect_no_token(conditionMessage(w))
    })
  }
})

test_that("a transport error message with braces is shown verbatim", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/admin/token$" = function(req) stop('timeout {Sys.getenv("JATOS_TOKEN")}')
  )
  err <- expect_error(jatos_token_info(), "timeout", fixed = TRUE)
  expect_match(conditionMessage(err), "{Sys.getenv", fixed = TRUE)
  expect_no_token(conditionMessage(err))
})

test_that("a 404 without a body falls back to a generic hint", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/studies/99/properties$" = httr2::response(status_code = 404)
  )
  err <- expect_error(jatos_study(99), class = "httr2_http_404")
  expect_match(conditionMessage(err), "Nothing at this path")
})

test_that("a 403 with a nested error message is surfaced", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/batches/1$" = mock_json_body(
      list(apiVersion = "1.1.0", error = list(message = "Not a member of this study")),
      status = 403
    )
  )
  err <- expect_error(jatos_batch(1), class = "httr2_http_403")
  expect_match(conditionMessage(err), "Not a member")
})

test_that("transport failures are wrapped with a redacted URL", {
  local_fake_credentials()
  local_jatos_mock(
    "GET .*/admin/token$" = function(req) stop("could not resolve host")
  )
  err <- expect_error(jatos_token_info(), "could not resolve host")
  expect_no_token(conditionMessage(err))
})

test_that("redact_url drops the query string", {
  expect_equal(redact_url("https://x.example/a?b=1&c=2"), "https://x.example/a?...")
  expect_equal(redact_url("https://x.example/a"), "https://x.example/a")
})
