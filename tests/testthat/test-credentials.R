test_that("read_credential prefers the explicit argument over the environment", {
  local_fake_credentials()
  expect_equal(read_credential(fake_tokens[["explicit"]], "JATOS_TOKEN", "token"), fake_tokens[["explicit"]])
  expect_equal(read_credential(NULL, "JATOS_TOKEN", "token"), fake_token)
})

test_that("read_credential aborts with guidance and without the token when unset", {
  local_no_credentials()
  err <- expect_error(
    read_credential(NULL, "JATOS_TOKEN", "token"),
    class = "jatosr_no_host"
  )
  expect_match(conditionMessage(err), "JATOS_TOKEN")
  expect_match(conditionMessage(err), "jatos_set_credentials")
  expect_no_token(conditionMessage(err))
})

test_that("read_credential rejects empty or non-string arguments", {
  expect_error(read_credential("", "JATOS_TOKEN", "token"), "single non-empty string", class = "jatosr_bad_argument")
  expect_error(read_credential(c("a", "b"), "JATOS_TOKEN", "token"), "single non-empty string", class = "jatosr_bad_argument")
  expect_error(read_credential(1, "JATOS_TOKEN", "token"), "single non-empty string", class = "jatosr_bad_argument")
})

test_that("jatos_secret masks the value on every output path", {
  secret <- new_secret(fake_token)
  expect_s3_class(secret, "jatos_secret")
  expect_no_token(format(secret))
  expect_match(format(secret), "jap_\\.\\.\\. \\(11 chars\\)")
  expect_no_token(capture.output(print(secret)))
  expect_no_token(capture.output(str(secret)))
  expect_error(as.character(secret), "Refusing")
  expect_error(paste(secret))
  expect_error(paste0("Bearer ", secret))
  expect_error(sprintf("%s", secret))
  expect_error(cat(secret))
  expect_no_token(capture.output(print(unclass(secret))))
  expect_equal(reveal_secret(secret), fake_token)
})

test_that("jatos_secret without the jap_ prefix shows no prefix", {
  expect_match(format(new_secret(fake_tokens[["short"]])), "^<jatos_secret: \\.\\.\\. \\(3 chars\\)>$")
})

test_that("jatos_has_credentials reflects the environment", {
  local_fake_credentials()
  expect_true(jatos_has_credentials())
  expect_false(jatos_has_credentials("lab_admin"))
  withr::local_envvar(JATOS_TOKEN = "")
  expect_false(jatos_has_credentials())
})

test_that("jatos_has_credentials follows JATOS_PROFILE and named profiles", {
  local_no_credentials()
  local_fake_credentials(profile = "lab_admin")
  expect_false(jatos_has_credentials())
  expect_true(jatos_has_credentials("lab_admin"))
  withr::local_envvar(JATOS_PROFILE = "lab_admin")
  expect_true(jatos_has_credentials())
})

test_that("check_profile lowers the name and credential_var builds the suffix", {
  expect_equal(check_profile("Lab_Admin"), "lab_admin")
  expect_equal(credential_var("HOST"), "JATOS_HOST")
  expect_equal(credential_var("TOKEN", "default"), "JATOS_TOKEN")
  expect_equal(credential_var("TOKEN", "Default"), "JATOS_TOKEN")
  expect_equal(credential_var("HOST", "lab_admin"), "JATOS_HOST_LAB_ADMIN")
  expect_equal(credential_var("TOKEN", "mindprobe2"), "JATOS_TOKEN_MINDPROBE2")
})

test_that("jatos_list_profiles lists every profile without tokens", {
  local_no_credentials()
  withr::local_envvar(
    JATOS_HOST_ZEBRA = "https://zebra.example",
    JATOS_TOKEN_ZEBRA = fake_tokens[["zebra"]],
    JATOS_TOKEN_ORPHAN = fake_tokens[["orphan"]],
    JATOS_HOST_NOTOKEN = "https://notoken.example"
  )
  expect_equal(nrow(jatos_list_profiles()), 3)
  local_fake_credentials()
  profiles <- jatos_list_profiles()
  expect_s3_class(profiles, "tbl_df")
  expect_equal(
    names(profiles),
    c("profile", "host", "has_token", "active", "auth_from")
  )
  expect_equal(profiles$profile, c("default", "notoken", "orphan", "zebra"))
  expect_equal(profiles$host, c(fake_host, "https://notoken.example", NA, "https://zebra.example"))
  expect_equal(profiles$has_token, c(TRUE, FALSE, TRUE, TRUE))
  expect_equal(profiles$active, c(TRUE, FALSE, FALSE, FALSE))
  expect_no_token(capture.output(print(profiles)))
  expect_false(any(grepl("jap_", unlist(profiles))))

  withr::local_envvar(JATOS_PROFILE = "Zebra")
  expect_equal(jatos_list_profiles()$active, c(FALSE, FALSE, FALSE, TRUE))
})

test_that("jatos_list_profiles ignores JATOS_PROFILE and empty values", {
  local_no_credentials()
  withr::local_envvar(JATOS_PROFILE = "x", JATOS_HOST = "", JATOS_TOKEN = "")
  profiles <- jatos_list_profiles()
  expect_equal(nrow(profiles), 0)
  expect_equal(
    names(profiles),
    c("profile", "host", "has_token", "active", "auth_from")
  )
  # the same column types at zero rows as at one: ifelse() on nothing used
  # to make auth_from a logical(0)
  expect_type(profiles$profile, "character")
  expect_type(profiles$host, "character")
  expect_type(profiles$has_token, "logical")
  expect_type(profiles$active, "logical")
  expect_type(profiles$auth_from, "character")
})

test_that("variables whose suffix is not a profile name are not profiles", {
  # JATOS_TOKEN_1ABC is a variable this package never reads. Listing it made
  # the "Configured profiles" hint suggest a name that check_profile() then
  # rejected.
  local_no_credentials()
  withr::local_envvar(
    JATOS_HOST_1ABC = fake_host,
    JATOS_TOKEN_1ABC = fake_tokens[["other"]],
    JATOS_HOST_LAB_ADMIN = fake_host,
    JATOS_TOKEN_LAB_ADMIN = fake_tokens[["admin"]]
  )

  expect_equal(jatos_list_profiles()$profile, "lab_admin")
  expect_equal(usable_profiles(), "lab_admin")
  err <- expect_error(jatos_connection(), class = "jatosr_no_host")
  expect_match(conditionMessage(err), "lab_admin")
  expect_false(grepl("1abc", conditionMessage(err), fixed = TRUE))
})

test_that("prompt_for_token uses askpass and treats a cancelled dialog as no token", {
  # askpass::askpass() mocked, not the helper around it, as in the other
  # interactive paths: askpass is in Imports, so this is the only prompt.
  withr::local_options(list(rlang_interactive = TRUE))
  local_mocked_bindings(askpass = function(prompt) fake_token, .package = "askpass")
  expect_equal(prompt_for_token(), fake_token)

  local_mocked_bindings(askpass = function(prompt) NULL, .package = "askpass")
  expect_error(prompt_for_token(), "No token was entered", class = "jatosr_no_token")
  local_mocked_bindings(askpass = function(prompt) "", .package = "askpass")
  expect_error(prompt_for_token(), "No token was entered", class = "jatosr_no_token")

  rlang::local_interactive(FALSE)
  expect_error(prompt_for_token(), class = "jatosr_needs_interactive")
})

# --- storing credentials -------------------------------------------------------

test_that("jatos_set_credentials stores the token and the host apart", {
  local_no_credentials()
  msgs <- capture_messages(
    out <- jatos_set_credentials(fake_host, fake_token, check = FALSE)
  )
  expect_equal(out, "default")
  expect_match(paste(msgs, collapse = "\n"), "credential store")
  expect_no_token(msgs)

  expect_equal(keyring_get("default"), fake_token)
  expect_equal(config_host("default"), fake_host)
  # the token is nowhere in the file that holds the host
  expect_no_token(readLines(config_path(), warn = FALSE))
})

test_that("jatos_set_credentials writes no .Renviron and sets no variable", {
  # The point of the credential store: nothing lands in the home filespace
  # and nothing is exported into the session environment.
  dir <- local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))

  expect_false(file.exists(file.path(dir, ".Renviron")))
  expect_false(file.exists(file.path(dir, "user.Renviron")))
  expect_equal(Sys.getenv("JATOS_TOKEN"), "")
  expect_equal(Sys.getenv("JATOS_HOST"), "")
})

test_that("a stored profile is immediately usable", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  conn <- jatos_connection()

  expect_equal(conn$host, fake_host)
  expect_equal(conn$auth_from, "keyring")
  expect_equal(reveal_secret(conn_token(conn)), fake_token)
})

test_that("jatos_set_credentials keeps profiles side by side", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  msgs <- capture_messages(
    jatos_set_credentials("https://admin.example/", fake_tokens[["admin"]],
      profile = "Lab_Admin", check = FALSE
    )
  )
  expect_match(paste(msgs, collapse = "\n"), 'jatos_connection\\("lab_admin"\\)')

  expect_equal(keyring_get("default"), fake_token)
  expect_equal(keyring_get("lab_admin"), fake_tokens[["admin"]])
  expect_equal(config_host("default"), fake_host)
  expect_equal(config_host("lab_admin"), "https://admin.example")
})

test_that("jatos_set_credentials replaces the token of the same profile", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_tokens[["old"]], check = FALSE))
  # read it once so that the old value is in the session cache
  expect_equal(reveal_secret(conn_token(jatos_connection())), fake_tokens[["old"]])

  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))

  expect_equal(keyring_get("default"), fake_token)
  # the cache was cleared, so the new token is the one that would be sent
  expect_equal(reveal_secret(conn_token(jatos_connection())), fake_token)
})

test_that("jatos_set_credentials writes the profile named by JATOS_PROFILE", {
  local_no_credentials()
  withr::local_envvar(JATOS_PROFILE = "lab_admin")
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))

  expect_equal(keyring_list(), "lab_admin")
  expect_equal(config_profiles(), "lab_admin")
})

test_that("jatos_set_credentials normalises the host and warns on odd tokens", {
  local_no_credentials()
  expect_warning(
    suppressMessages(jatos_set_credentials(
      "https://x.example/jatos/api/v1/", fake_tokens[["name_not_token"]],
      check = FALSE
    )),
    "jap_"
  )
  expect_equal(config_host("default"), "https://x.example")
})

test_that("jatos_set_credentials stores no token when the host cannot be written", {
  # The host is written first and the write is checked: an unwritable
  # configuration directory used to leave the token in the store, print
  # "The host went to ...", and pile up a profiles<hex>.json per attempt.
  local_no_credentials()
  blocker <- withr::local_tempfile(lines = "not a directory")
  withr::local_envvar(c(JATOSR_CONFIG_DIR = file.path(blocker, "config")))

  err <- expect_error(
    jatos_set_credentials(fake_host, fake_token, check = FALSE),
    class = "jatosr_config_write_failed"
  )
  expect_match(conditionMessage(err), "JATOSR_CONFIG_DIR")
  expect_no_token(conditionMessage(err))
  expect_equal(keyring_list(), character())
  expect_false(jatos_has_credentials())
})

test_that("jatos_set_credentials refuses when nothing durable is available", {
  # A headless Linux box, where keyring falls back to environment
  # variables. Storing there would look like it worked and be gone at the
  # next start of R.
  local_no_credentials()
  local_unusable_keyring()

  err <- expect_error(
    jatos_set_credentials(fake_host, fake_token, check = FALSE),
    "No persistent credential store",
    class = "jatosr_no_store"
  )
  expect_match(conditionMessage(err), "JATOS_TOKEN")
  expect_match(conditionMessage(err), "backend_file$new()$keyring_create(\"system\")", fixed = TRUE)
})

test_that("jatos_set_credentials refuses before asking for the token", {
  # There is no point prompting for a secret that cannot be kept.
  local_no_credentials()
  local_unusable_keyring()
  withr::local_options(list(rlang_interactive = TRUE))
  asked <- FALSE
  local_mocked_bindings(prompt_for_token = function(...) {
    asked <<- TRUE
    fake_token
  })

  expect_error(jatos_set_credentials(fake_host), class = "jatosr_no_store")
  expect_false(asked)
})

test_that("a store that cannot be listed is still asked, and undone when it refuses", {
  # A Secret Service that is reachable but locked. Whether a write still
  # works there, perhaps after an unlock dialog, depends on the backend, so
  # the setter does not refuse the store up front: it writes, and a refused
  # write leaves no host without a token behind.
  local_no_credentials()
  local_mocked_bindings(keyring_list = function() stop("Collection is locked"))

  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  expect_equal(keyring_get("default"), fake_token)
  expect_equal(config_host("default"), fake_host)

  local_mocked_bindings(keyring_set = function(profile, token) stop("Collection is locked"))
  err <- expect_error(
    jatos_set_credentials(fake_host, fake_tokens[["admin"]], profile = "lab_admin", check = FALSE),
    class = "jatosr_keyring_write_failed"
  )
  expect_match(conditionMessage(err), "Collection is locked", fixed = TRUE)
  expect_match(conditionMessage(err), "Unlock the credential store")
  expect_null(config_host("lab_admin"))
  expect_equal(config_host("default"), fake_host)
})

test_that("a failed store write leaves a new profile out of the configuration", {
  local_no_credentials()
  local_mocked_bindings(keyring_set = function(profile, token) {
    stop("The name org.freedesktop.secrets was not provided by any .service files")
  })

  err <- expect_error(
    jatos_set_credentials(fake_host, fake_token, check = FALSE),
    class = "jatosr_keyring_write_failed"
  )
  expect_match(conditionMessage(err), "org.freedesktop.secrets", fixed = TRUE)
  expect_no_token(conditionMessage(err))
  expect_false(file.exists(config_path()))
  expect_equal(jatos_list_profiles()$profile, character())
})

test_that("a failed store write restores the configuration as it was", {
  local_no_credentials()
  suppressMessages({
    jatos_set_credentials(fake_host, fake_token, check = FALSE)
    jatos_set_credentials(fake_host, fake_tokens[["admin"]], profile = "lab_admin", check = FALSE)
  })
  before <- readBin(config_path(), "raw", file.size(config_path()))
  local_mocked_bindings(keyring_set = function(profile, token) stop("Access denied"))

  expect_error(
    jatos_set_credentials("https://other.example.org", fake_tokens[["other"]],
      profile = "lab_admin", check = FALSE
    ),
    class = "jatosr_keyring_write_failed"
  )
  expect_identical(readBin(config_path(), "raw", file.size(config_path())), before)
  expect_equal(config_host("lab_admin"), fake_host)
  expect_equal(keyring_get("lab_admin"), fake_tokens[["admin"]])
})

test_that("a failed store write keeps what another session wrote meanwhile", {
  # Only this profile's entry is put back. Rewriting the whole file from
  # the snapshot taken before the write dropped a profile that another R
  # session stored while the credential store was being asked.
  local_no_credentials()
  suppressMessages({
    jatos_set_credentials(fake_host, fake_token, check = FALSE)
    jatos_set_credentials(fake_host, fake_tokens[["admin"]], profile = "lab_admin", check = FALSE)
  })
  local_mocked_bindings(keyring_set = function(profile, token) {
    config_set_host("gamma", "https://gamma.example.org")
    stop("Access denied")
  })

  expect_error(
    jatos_set_credentials("https://other.example.org", fake_tokens[["other"]],
      profile = "lab_admin", check = FALSE
    ),
    class = "jatosr_keyring_write_failed"
  )
  expect_setequal(config_profiles(), c("default", "lab_admin", "gamma"))
  expect_equal(config_host("lab_admin"), fake_host)
  expect_equal(config_host("gamma"), "https://gamma.example.org")
})

test_that("a failed store write for a new profile keeps a file another session started", {
  local_no_credentials()
  local_mocked_bindings(keyring_set = function(profile, token) {
    config_set_host("gamma", "https://gamma.example.org")
    stop("Access denied")
  })

  expect_error(
    jatos_set_credentials(fake_host, fake_token, check = FALSE),
    class = "jatosr_keyring_write_failed"
  )
  expect_equal(config_profiles(), "gamma")
})

test_that("a failed store write never repeats the token the store echoed", {
  # Neither backend is known to do this; the message must not depend on it.
  local_no_credentials()
  token <- fake_tokens[["plain"]]
  local_mocked_bindings(keyring_set = function(profile, token) {
    stop(paste("could not store", token, "and", fake_tokens[["foreign"]]))
  })

  err <- expect_error(
    # the token has no jap_ prefix, which warns; the warning is not under test
    suppressWarnings(jatos_set_credentials(fake_host, token, check = FALSE)),
    class = "jatosr_keyring_write_failed"
  )
  expect_no_token(conditionMessage(err))
  expect_match(conditionMessage(err), "could not store", fixed = TRUE)
})

test_that("a failed store write says so when the configuration cannot be put back", {
  # A file that existed is rewritten to put it back; the first move is the
  # setter's own write, the second the restore.
  local_no_credentials()
  suppressMessages(
    jatos_set_credentials(fake_host, fake_tokens[["admin"]], profile = "lab_admin", check = FALSE)
  )
  real_move <- move_file
  moves <- 0L
  local_mocked_bindings(
    keyring_set = function(profile, token) stop("Access denied"),
    move_file = function(from, to) {
      moves <<- moves + 1L
      if (moves == 1L) real_move(from, to) else cli::cli_abort("disk full")
    }
  )

  err <- expect_error(
    jatos_set_credentials(fake_host, fake_token, check = FALSE),
    class = "jatosr_keyring_write_failed"
  )
  expect_match(conditionMessage(err), "Access denied", fixed = TRUE)
  expect_match(conditionMessage(err), "could not be put back")
  expect_match(conditionMessage(err), "jatos_remove_credentials", fixed = TRUE)
  expect_no_token(conditionMessage(err))
})

test_that("jatos_set_credentials warns when a variable shadows what it stored", {
  local_no_credentials()
  withr::local_envvar(c(JATOS_TOKEN = fake_tokens[["stale"]]))
  msgs <- capture_messages(
    jatos_set_credentials(fake_host, fake_token, check = FALSE)
  )

  expect_match(paste(msgs, collapse = "\n"), "takes precedence")
  expect_no_token(msgs)
})

test_that("jatos_set_credentials reports the profile's account in the token check", {
  local_no_credentials()
  local_jatos_mock("GET .*/admin/token$" = mock_json("token.json"))
  msgs <- capture_messages(
    jatos_set_credentials(fake_host, fake_token, profile = "lab_admin")
  )
  expect_match(paste(msgs, collapse = "\n"), "analysis-laptop")
  expect_no_token(msgs)
})

test_that("jatos_set_credentials verifies the token once and reports name and expiry", {
  local_no_credentials()
  rec <- local_jatos_mock("GET .*/admin/token$" = mock_json("token.json"))
  msgs <- capture_messages(jatos_set_credentials(fake_host, fake_token))

  expect_match(paste(msgs, collapse = "\n"), "analysis-laptop")
  expect_match(paste(msgs, collapse = "\n"), "no expiry")
  expect_no_token(msgs)
  expect_length(rec$requests, 1)
  expect_match(last_request(rec)$url, "/admin/token$")
})

test_that("jatos_set_credentials reports a set expiry date", {
  local_no_credentials()
  local_jatos_mock("GET .*/admin/token$" = mock_json_body(list(
    apiVersion = "1.1.0",
    data = list(
      id = 1, name = "short-lived", username = "u", expiresAfter = 86400,
      expirationDate = 1756086400000, isExpired = FALSE, active = TRUE
    )
  )))
  msgs <- capture_messages(jatos_set_credentials(fake_host, fake_token))

  expect_match(paste(msgs, collapse = "\n"), "expires 2025-08-25")
})

test_that("jatos_set_credentials warns but still stores when the check fails", {
  local_no_credentials()
  local_jatos_mock("GET .*/admin/token$" = mock_json("error-401.json", status = 401))
  w <- expect_warning(
    suppressMessages(jatos_set_credentials(fake_host, fake_token)),
    "Could not verify"
  )

  expect_no_token(conditionMessage(w))
  expect_equal(keyring_get("default"), fake_token)
})

test_that("jatos_set_credentials leaves no copy of the token under the check connection", {
  # The connection built for the token check is not handed out, so its entry
  # in the session store has no reason to outlive the check.
  local_no_credentials()
  local_jatos_mock("GET .*/admin/token$" = mock_json("token.json"))
  suppressMessages(jatos_set_credentials(fake_host, fake_token))

  expect_length(the$conn_tokens, 0)
  # the stored token is still what a new connection sends
  expect_equal(reveal_secret(conn_token(jatos_connection())), fake_token)
})

test_that("jatos_set_credentials with check = FALSE issues no request", {
  local_no_credentials()
  rec <- local_jatos_mock()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))

  expect_length(rec$requests, 0)
})

test_that("jatos_set_credentials needs a token when not interactive", {
  local_no_credentials()
  rlang::local_interactive(FALSE)

  expect_error(jatos_set_credentials(fake_host), class = "jatosr_needs_interactive")
  expect_equal(keyring_list(), character())
})

test_that("jatos_set_credentials validates its arguments", {
  local_no_credentials()
  expect_error(
    jatos_set_credentials(fake_host, fake_token, profile = "lab-admin", check = FALSE),
    "underscores",
    class = "jatosr_bad_profile"
  )
  expect_error(
    jatos_set_credentials(fake_host, fake_token, profile = "https://x.example"),
    "host = ",
    class = "jatosr_bad_profile"
  )
  expect_error(jatos_set_credentials("x.example", fake_token), "https://", class = "jatosr_bad_argument")
  expect_error(jatos_set_credentials(fake_host, fake_token, check = NA), "`TRUE` or `FALSE`", class = "jatosr_bad_argument")
})

# --- removing credentials ------------------------------------------------------

test_that("jatos_remove_credentials deletes one profile and keeps the rest", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  suppressMessages(jatos_set_credentials(fake_host, fake_tokens[["admin"]],
    profile = "lab_admin", check = FALSE
  ))

  msgs <- capture_messages(jatos_remove_credentials(confirm = FALSE))
  expect_match(paste(msgs, collapse = "\n"), "Deleted the token")
  expect_match(paste(msgs, collapse = "\n"), "still valid")
  expect_no_token(msgs)

  expect_equal(keyring_list(), "lab_admin")
  expect_equal(config_profiles(), "lab_admin")
  expect_false(jatos_has_credentials())
  expect_true(jatos_has_credentials("lab_admin"))
})

test_that("jatos_remove_credentials is case-insensitive and clears the cache", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token,
    profile = "lab_admin", check = FALSE
  ))
  expect_equal(reveal_secret(conn_token(jatos_connection("lab_admin"))), fake_token)

  suppressMessages(jatos_remove_credentials(profile = "LAB_ADMIN", confirm = FALSE))

  expect_equal(keyring_list(), character())
  expect_null(token_cache_get("lab_admin"))
  expect_error(jatos_connection("lab_admin"), "JATOS_HOST_LAB_ADMIN", class = "jatosr_no_host")
})

test_that("jatos_remove_credentials removes the profile named by JATOS_PROFILE and warns", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token,
    profile = "lab_admin", check = FALSE
  ))
  withr::local_envvar(JATOS_PROFILE = "lab_admin")

  w <- expect_warning(
    suppressMessages(jatos_remove_credentials(confirm = FALSE)),
    "JATOS_PROFILE"
  )
  expect_match(conditionMessage(w), "still selects")
  expect_equal(keyring_list(), character())
})

test_that("jatos_remove_credentials warns when a variable still defines the profile", {
  # Deleting the entry settles nothing while an environment variable, which
  # wins over the store anyway, still names the same profile.
  dir <- local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  writeLines(
    c(sprintf('JATOS_HOST="%s"', fake_host), sprintf('JATOS_TOKEN="%s"', fake_token)),
    file.path(dir, "user.Renviron")
  )
  withr::local_envvar(c(JATOS_HOST = fake_host, JATOS_TOKEN = fake_token))

  w <- expect_warning(
    suppressMessages(jatos_remove_credentials(confirm = FALSE)),
    "still set"
  )
  expect_match(conditionMessage(w), "user.Renviron")
  expect_match(conditionMessage(w), "restart R")
  expect_no_token(conditionMessage(w))
})

test_that("jatos_remove_credentials keeps the token when the configuration cannot be rewritten", {
  # The configuration is dropped before the token is deleted, so a failed
  # rewrite leaves the profile whole rather than half removed.
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  local_mocked_bindings(move_file = function(from, to) cli::cli_abort("disk full"))

  expect_error(
    jatos_remove_credentials(confirm = FALSE),
    class = "jatosr_config_write_failed"
  )
  expect_equal(keyring_get("default"), fake_token)
  expect_equal(config_host("default"), fake_host)
  expect_true(jatos_has_credentials())
})

test_that("jatos_remove_credentials is idempotent and says when there is nothing to remove", {
  local_no_credentials()
  msgs <- capture_messages(out <- jatos_remove_credentials(confirm = FALSE))

  expect_equal(out, "default")
  expect_match(paste(msgs, collapse = "\n"), "Nothing to remove")
  expect_match(paste(msgs, collapse = "\n"), "jatos_list_profiles")

  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  suppressMessages(jatos_remove_credentials(confirm = FALSE))
  msgs <- capture_messages(jatos_remove_credentials(confirm = FALSE))
  expect_match(paste(msgs, collapse = "\n"), "Nothing to remove")
})

test_that("jatos_remove_credentials asks before removing and keeps everything on no", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))

  asked <- NULL
  local_mocked_bindings(
    confirm_removal = function(profile, backend) {
      asked <<- profile
      FALSE
    }
  )
  msgs <- capture_messages(jatos_remove_credentials(confirm = TRUE))
  expect_equal(asked, "default")
  expect_match(paste(msgs, collapse = "\n"), "Kept the credentials")
  expect_true(jatos_has_credentials())

  local_mocked_bindings(confirm_removal = function(profile, backend) TRUE)
  suppressMessages(jatos_remove_credentials(confirm = TRUE))
  expect_false(jatos_has_credentials())
})

test_that("jatos_remove_credentials refuses to prompt without a user", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))

  err <- expect_error(jatos_remove_credentials(confirm = TRUE), class = "jatosr_needs_interactive")
  expect_match(conditionMessage(err), "confirm = FALSE")
  expect_equal(keyring_get("default"), fake_token)
})

test_that("the default confirm never removes a token where no one can answer", {
  # A knitted document, a notebook chunk, a script: rlang::is_interactive()
  # is FALSE. The default used to follow it, so `jatos_remove_credentials()`
  # in a knit deleted the token without a word. The default is TRUE, the
  # prompt cannot be shown, so the call is an error and the token stays.
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  rlang::local_interactive(FALSE)

  err <- expect_error(jatos_remove_credentials(), class = "jatosr_needs_interactive")
  expect_match(conditionMessage(err), "confirm = FALSE")
  expect_equal(keyring_get("default"), fake_token)
  expect_equal(config_host("default"), fake_host)
})

test_that("the removal prompt is shown when the session can prompt", {
  # utils::menu() mocked, not the helper around it: the helper tested base
  # interactive(), which is FALSE under testthat and TRUE in a knit from
  # the console, so a session rlang calls interactive errored before the
  # menu, and one it calls non-interactive never asked.
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  withr::local_options(list(rlang_interactive = TRUE))
  choices <- NULL
  local_mocked_bindings(
    menu = function(choices_, ...) {
      choices <<- choices_
      2L
    },
    .package = "utils"
  )

  msgs <- capture_messages(jatos_remove_credentials())
  expect_match(choices, "No, keep them", all = FALSE)
  expect_match(paste(msgs, collapse = "\n"), "Kept the credentials")
  expect_equal(keyring_get("default"), fake_token)

  local_mocked_bindings(menu = function(...) 1L, .package = "utils")
  suppressMessages(jatos_remove_credentials())
  expect_equal(keyring_list(), character())
})

test_that("jatos_remove_credentials validates its arguments", {
  local_no_credentials()
  expect_error(
    jatos_remove_credentials(profile = "https://x.example", confirm = FALSE),
    "host = ",
    class = "jatosr_bad_profile"
  )
  expect_error(
    jatos_remove_credentials(profile = "lab-admin", confirm = FALSE),
    "underscores",
    class = "jatosr_bad_profile"
  )
  expect_error(jatos_remove_credentials(confirm = NA), "`TRUE` or `FALSE`", class = "jatosr_bad_argument")
})

# --- recognising a legacy .Renviron --------------------------------------------

test_that("renviron_has_vars finds a definition without matching a longer name", {
  lines <- c(
    'JATOS_HOST="https://a.example"',
    "  jatos_token = x",
    'JATOS_HOST_LAB_ADMIN="https://b.example"',
    "JATOS_TOKEN_LAB_ADMIN=y",
    "# JATOS_HOST=commented",
    "OTHER=1"
  )
  expect_true(renviron_has_vars(lines, c("JATOS_HOST", "JATOS_TOKEN")))
  expect_true(renviron_has_vars(lines, "JATOS_TOKEN_LAB_ADMIN"))
  expect_false(renviron_has_vars(lines[3:6], c("JATOS_HOST", "JATOS_TOKEN")))
  expect_false(renviron_has_vars(lines, "JATOS_TOKEN_OTHER"))
  expect_false(renviron_has_vars(character(), "JATOS_HOST"))
})

test_that("renviron_lines_for returns the lines a user has to delete, token values hidden", {
  lines <- c(
    'JATOS_HOST="https://a.example"',
    sprintf("  jatos_token = %s", fake_token),
    'JATOS_HOST_LAB_ADMIN="https://b.example"',
    sprintf('JATOS_TOKEN_LAB_ADMIN="%s"', fake_tokens[["admin"]]),
    "OTHER=1"
  )
  expect_equal(
    renviron_lines_for(lines, c("JATOS_HOST", "JATOS_TOKEN")),
    c('JATOS_HOST="https://a.example"', "jatos_token=<value hidden>")
  )
  expect_equal(
    renviron_lines_for(lines, c("JATOS_HOST_LAB_ADMIN", "JATOS_TOKEN_LAB_ADMIN")),
    c('JATOS_HOST_LAB_ADMIN="https://b.example"', "JATOS_TOKEN_LAB_ADMIN=<value hidden>")
  )
  expect_no_token(renviron_lines_for(lines, c("JATOS_HOST", "JATOS_TOKEN")))
  expect_equal(renviron_lines_for(character(), "JATOS_HOST"), character())
})
test_that("the credential helpers keep every test away from the real .Renviron", {
  # Eight sitrep tests used to read the developer's own ~/.Renviron and the
  # package directory's .Renviron, and could print a real token into a test
  # log. Both locations now live in a temporary directory for every test
  # that starts from either helper.
  dir <- local_no_credentials()
  expect_equal(renviron_path("user"), file.path(dir, "user.Renviron"))
  expect_equal(normalizePath(dirname(renviron_path("project"))), normalizePath(dir))
  expect_false(file.exists(renviron_path("user")))

  dir <- local_fake_credentials()
  expect_equal(renviron_path("user"), file.path(dir, "user.Renviron"))
  expect_equal(normalizePath(getwd()), normalizePath(dir))
  # and the fixtures are still found from inside the sandbox
  expect_true(file.exists(fixture_path("token.json")))
})

test_that("renviron_path honours R_ENVIRON_USER and scope", {
  withr::local_envvar(R_ENVIRON_USER = "/tmp/custom.Renviron")
  expect_equal(renviron_path("user"), "/tmp/custom.Renviron")
  withr::local_envvar(R_ENVIRON_USER = "")
  expect_equal(renviron_path("user"), path.expand("~/.Renviron"))
  expect_equal(renviron_path("project"), file.path(getwd(), ".Renviron"))
})
