test_that("jatos_token_info returns one masked-free row of token metadata", {
  local_fake_credentials()
  rec <- local_jatos_mock("GET .*/admin/token$" = mock_json("token.json"))
  info <- jatos_token_info()
  expect_s3_class(info, "tbl_df")
  expect_equal(nrow(info), 1)
  expect_equal(info$token_id, 7L)
  expect_equal(info$name, "analysis-laptop")
  expect_equal(info$username, "researcher@example.org")
  expect_equal(info$user_id, 3L)
  expect_s3_class(info$created, "POSIXct")
  expect_equal(as.numeric(info$created), 1756000000)
  expect_true(is.na(info$expires))
  expect_false(info$expired)
  expect_true(info$active)
  expect_equal(info$roles[[1]], "USER")
  expect_length(rec$requests, 1)
  expect_equal(mock_method(last_request(rec)), "GET")
})

test_that("jatos_connection warns once per session when the token expires within seven days", {
  local_fake_credentials()
  # `isExpired` follows the date, the way a server reports it: a past
  # expiry with `isExpired = FALSE` is the contradiction that means "never
  # expires" on some JATOS versions, and warn_expiring_token() declines to
  # warn about it (see test-legacy-server.R).
  soon <- function(days) {
    body <- read_fixture_json("token.json")
    body$data$expiresAfter <- 3600
    body$data$expirationDate <- round(as.numeric(Sys.time() + days * 86400) * 1000)
    body$data$isExpired <- days < 0
    mock_json_null(body)
  }

  # nothing seen yet: no warning; a distant expiry: none either
  expect_no_warning(jatos_connection())
  local_jatos_mock("GET .*/admin/token$" = soon(30))
  expect_false(is.na(jatos_token_info()$expires))
  expect_no_warning(jatos_connection())

  # within seven days: one warning, then silence for the same token
  local_jatos_mock("GET .*/admin/token$" = soon(3))
  jatos_token_info()
  w <- capture_warnings(conn <- jatos_connection())
  expect_length(w, 1)
  expect_match(w, "expires on")
  expect_match(w, "days from now")
  expect_match(w, 'profile "default"')
  expect_match(w, "jatos_set_credentials")
  expect_no_token(w)
  expect_no_warning(jatos_connection())
  expect_no_warning(jatos_token_info(conn))

  # another token is another key: its own warning, and an expired one says so
  local_fake_credentials(token = fake_tokens[["other"]], profile = "other")
  expect_no_warning(jatos_connection("other"))
  local_jatos_mock("GET .*/admin/token$" = soon(-1))
  jatos_token_info(jatos_connection("other"))
  w <- capture_warnings(jatos_connection("other"))
  expect_length(w, 1)
  expect_match(w, "expired on")
  expect_match(w, 'profile "other"')
  expect_no_token(w)
  # the record holds hashes, never the token
  expect_no_token(names(the$token_expiry))
  expect_no_token(the$expiry_warned)
})

test_that("a token the server calls expired warns even without an expiry date", {
  # `isExpired` is the server's direct answer. warn_expiring_token() used to
  # return on a missing date before it looked at the flag, so an expired
  # token on a server that sends no date never warned.
  local_fake_credentials()
  body <- read_fixture_json("token.json")
  body$data$isExpired <- TRUE
  local_jatos_mock("GET .*/admin/token$" = mock_json_null(body))

  info <- jatos_token_info()
  expect_true(is.na(info$expires))
  expect_true(info$expired)

  w <- capture_warnings(jatos_connection())
  expect_length(w, 1)
  expect_match(w, "as expired")
  expect_match(w, 'profile "default"')
  expect_match(w, "jatos_set_credentials")
  expect_no_token(w)
  # once per token and session
  expect_no_warning(jatos_connection())
})

test_that("parse_token_info converts a set expiry date", {
  x <- list(id = 1, expiresAfter = 3600, expirationDate = 1756003600000, isExpired = FALSE, active = TRUE, roles = list("USER", "ADMIN"))
  info <- parse_token_info(x)
  expect_equal(as.numeric(info$expires), 1756003600)
  expect_equal(info$roles[[1]], c("USER", "ADMIN"))
  expect_true(is.na(info$name))
})
