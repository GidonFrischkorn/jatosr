test_that("jatos_connection reads host and token from the environment", {
  local_fake_credentials()
  conn <- jatos_connection()
  expect_s3_class(conn, "jatos_connection")
  expect_equal(conn$host, fake_host)
  expect_equal(conn$api_url, paste0(fake_host, "/jatos/api/v1"))
  expect_null(conn$token)
  expect_equal(conn$auth_from, "env")
  expect_equal(reveal_secret(conn_token(conn)), fake_token)
  expect_match(conn$user_agent, "^jatosr/")
})

test_that("explicit arguments override the environment", {
  local_fake_credentials()
  conn <- jatos_connection(host = "https://other.example/", token = fake_tokens[["other"]])
  expect_equal(conn$host, "https://other.example")
  expect_equal(reveal_secret(conn_token(conn)), fake_tokens[["other"]])
  expect_equal(conn$auth_from, "argument")
  expect_equal(conn$profile, "default")
})

test_that("the token a connection sends is the token its label names", {
  # conn_token_peek() and resolve_token() are two lookups over the same
  # tiers; when their orders differed, a connection could print "from
  # JATOS_TOKEN" and send the credential-store token cached earlier. One
  # case per auth_from value, the wire token read the way jatos_req() reads
  # it.
  wire <- function(conn) reveal_secret(conn_token(conn))
  local_no_credentials()
  local_fake_keyring(list(default = fake_tokens[["admin"]]))
  config_set_host("default", fake_host)

  # keyring: nothing else set, the store's token is read and cached
  stored <- jatos_connection()
  expect_equal(stored$auth_from, "keyring")
  expect_equal(wire(stored), fake_tokens[["admin"]])
  expect_equal(reveal_secret(token_cache_get("default")$secret), fake_tokens[["admin"]])

  # env, set after the store's token was cached: the label says env, so the
  # wire token must be the variable's, not the cached one
  withr::local_envvar(c(JATOS_TOKEN = fake_tokens[["other"]]))
  expect_warning(conn <- jatos_connection(), "takes precedence")
  expect_equal(conn$auth_from, "env")
  expect_equal(wire(conn), fake_tokens[["other"]])
  # while the connection built before the variable was set keeps sending
  # what its print says it sends: the store's token
  expect_equal(stored$auth_from, "keyring")
  expect_equal(wire(stored), fake_tokens[["admin"]])
  expect_equal(scrub_secrets(paste("bad", fake_tokens[["admin"]]), stored), "bad <token redacted>")

  # argument, with both the variable and the cache populated
  conn <- jatos_connection(token = fake_tokens[["explicit"]])
  expect_equal(conn$auth_from, "argument")
  expect_equal(wire(conn), fake_tokens[["explicit"]])

  # prompt: the answer is cached under the profile, and is what is sent
  local_no_credentials()
  config_set_host("default", fake_host)
  withr::local_options(list(rlang_interactive = TRUE))
  local_mocked_bindings(prompt_for_token = function(...) fake_tokens[["zebra"]])
  conn <- jatos_connection()
  expect_equal(conn$auth_from, "prompt")
  expect_equal(wire(conn), fake_tokens[["zebra"]])

  # a connection read back in another session has a dead id and an empty
  # cache under its label, and falls through to a fresh resolution
  local_no_credentials()
  local_fake_keyring(list(default = fake_token))
  config_set_host("default", fake_host)
  revived <- new_connection(fake_host, auth_from = "argument")
  expect_null(conn_token_peek(revived))
  expect_equal(wire(revived), fake_token)
})

test_that("a named profile reads its own suffixed variables", {
  local_fake_credentials()
  local_fake_credentials(host = "https://admin.example", token = fake_tokens[["admin"]], profile = "lab_admin")
  conn <- jatos_connection("lab_admin")
  expect_equal(conn$profile, "lab_admin")
  expect_equal(conn$host, "https://admin.example")
  expect_equal(reveal_secret(conn_token(conn)), fake_tokens[["admin"]])
  expect_equal(jatos_connection()$host, fake_host)
  expect_equal(jatos_connection("LAB_ADMIN")$profile, "lab_admin")
})

test_that("JATOS_PROFILE selects the profile when none is passed", {
  local_fake_credentials()
  local_fake_credentials(host = "https://admin.example", token = fake_tokens[["admin"]], profile = "lab_admin")
  withr::local_envvar(JATOS_PROFILE = "lab_admin")
  expect_equal(jatos_connection()$host, "https://admin.example")
  expect_equal(jatos_connection("default")$host, fake_host)
  # the `conn = jatos_connection()` default of every endpoint follows it
  default_conn <- eval(formals(jatos_studies)$conn)
  expect_equal(default_conn$profile, "lab_admin")
})

test_that("a missing profile names its variables and the setter call", {
  local_fake_credentials()
  err <- expect_error(jatos_connection("nope"), "JATOS_HOST_NOPE", class = "jatosr_no_host")
  expect_match(conditionMessage(err), 'jatos_set_credentials\\(profile = "nope"\\)')
  expect_no_token(conditionMessage(err))
  withr::local_envvar(JATOS_PROFILE = "nope")
  err <- expect_error(jatos_connection(), "JATOS_HOST_NOPE", class = "jatosr_no_host")
  expect_match(conditionMessage(err), "JATOS_PROFILE")
})

test_that("a URL or an invalid name in profile is rejected with a hint", {
  local_fake_credentials()
  expect_error(jatos_connection("https://other.example"), "host = ", class = "jatosr_bad_profile")
  expect_error(jatos_connection("lab-admin"), "letters, digits and underscores", class = "jatosr_bad_profile")
  expect_error(jatos_connection("1lab"), "start with a letter", class = "jatosr_bad_profile")
  # "" is the default profile (an empty JATOS_PROFILE line), not an error
  expect_equal(jatos_connection("")$profile, "default")
  expect_error(jatos_connection(NA_character_), "single non-empty string", class = "jatosr_bad_argument")
})

test_that("jatos_connection aborts without credentials and never shows a token", {
  local_no_credentials()
  err <- expect_error(jatos_connection(), "JATOS_HOST", class = "jatosr_no_host")
  expect_no_token(conditionMessage(err))
  withr::local_envvar(JATOS_HOST = fake_host)
  err <- expect_error(jatos_connection(), "JATOS_TOKEN", class = "jatosr_no_token")
  expect_no_token(conditionMessage(err))
})

test_that("normalise_host strips slashes and a pasted API path", {
  expect_equal(normalise_host("https://x.example/"), "https://x.example")
  expect_equal(normalise_host("https://x.example//"), "https://x.example")
  expect_equal(normalise_host("https://x.example/jatos/api/v1"), "https://x.example")
  expect_equal(normalise_host("https://x.example/jatos/api/v1/studies"), "https://x.example")
  expect_equal(normalise_host("  https://x.example/jatos/ "), "https://x.example/jatos")
})

test_that("normalise_host rejects non-URLs and warns on plain http", {
  expect_error(normalise_host("x.example"), "https://", class = "jatosr_bad_argument")
  expect_error(normalise_host("ftp://x.example"), "https://", class = "jatosr_bad_argument")
  expect_warning(normalise_host("http://x.example"), "unencrypted")
  expect_no_warning(normalise_host("http://localhost:9000"))
  expect_no_warning(normalise_host("http://127.0.0.1:9000"))
})

test_that("tokens without the jap_ prefix produce a warning, once per token and session", {
  # jatos_connection() is the default argument of nearly every export; a
  # warning on each of them repeated once per API call.
  local_fake_credentials(token = fake_tokens[["plain"]])
  w <- capture_warnings(jatos_connection())
  expect_length(w, 1)
  expect_match(w, "jap_")
  expect_no_token(w)
  expect_no_warning(jatos_connection())

  # another token is another warning
  local_fake_credentials(token = fake_tokens[["name_not_token"]], profile = "other")
  expect_warning(jatos_connection("other"), "jap_")
  expect_no_warning(jatos_connection("other"))
})

test_that("an explicit host that is not the profile's warns once", {
  # The profile's token is about to be sent to another server: right for a
  # mirror, a leak for anything else, so it is said once per profile and host.
  local_no_credentials()
  local_fake_keyring(list(default = fake_token))
  config_set_host("default", fake_host)

  w <- capture_warnings(conn <- jatos_connection(host = "https://other.example/"))
  expect_length(w, 1)
  expect_match(w, "not the host of profile")
  expect_match(w, "https://other.example", fixed = TRUE)
  expect_match(w, fake_host, fixed = TRUE)
  expect_no_token(w)
  expect_equal(conn$host, "https://other.example")
  expect_equal(reveal_secret(conn_token(conn)), fake_token)
  expect_no_warning(jatos_connection(host = "https://other.example"))
  # a third host is a warning of its own
  expect_warning(jatos_connection(host = "https://third.example"), "not the host")

  # the profile's own host, an explicit token, or no configured host: silent
  expect_no_warning(jatos_connection(host = paste0(fake_host, "/")))
  expect_no_warning(jatos_connection(host = "https://fourth.example", token = fake_tokens[["explicit"]]))
  local_no_credentials()
  local_fake_keyring(list(default = fake_token))
  expect_no_warning(jatos_connection(host = "https://fifth.example"))
})

test_that("printing a connection masks the token", {
  local_fake_credentials()
  conn <- jatos_connection()
  out <- capture.output(print(conn))
  expect_match(out[1], "<jatos_connection>")
  expect_match(out[2], "profile: default")
  expect_true(any(grepl(fake_host, out, fixed = TRUE)))
  expect_no_token(out)
  expect_no_token(capture.output(str(conn)))
  expect_no_token(format(conn))
})

test_that("an empty JATOS_PROFILE means the default profile everywhere", {
  local_fake_credentials()
  withr::local_envvar(JATOS_PROFILE = "")
  # on Windows, setting a variable to "" removes it, so there the rest of
  # this block covers the unset case rather than the set-but-empty one
  expect_equal(
    Sys.getenv("JATOS_PROFILE", "default"),
    if (.Platform$OS.type == "windows") "default" else ""
  )
  conn <- expect_no_error(jatos_connection())
  expect_equal(conn$profile, "default")
  expect_true(jatos_has_credentials())
  profiles <- jatos_list_profiles()
  expect_true(profiles$active[profiles$profile == "default"])
  expect_equal(default_profile(), "default")
  expect_equal(check_profile(""), "default")
  expect_equal(credential_var("TOKEN", check_profile("")), "JATOS_TOKEN")
  expect_equal(jatos_study_links("abc", host = fake_host, profile = ""), "https://jatos.example.org/publix/abc")
})

test_that("check_connection rejects other objects", {
  expect_error(check_connection(list(host = "x")), "jatos_connection", class = "jatosr_bad_argument")
  local_fake_credentials()
  expect_invisible(check_connection(jatos_connection()))
})
