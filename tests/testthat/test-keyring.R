test_that("the wrappers round-trip through a real keyring backend", {
  # Not a mock: local_fake_keyring() puts keyring on its `env` backend, so
  # keyring::key_set_with_value(), key_get(), key_list() and key_delete()
  # all really run. Only the backend *name* is faked, because the package
  # treats "env" as "nowhere durable to store a token".
  local_fake_keyring()

  expect_equal(keyring_list(), character())

  keyring_set("default", fake_token)
  keyring_set("lab_admin", fake_tokens[["admin"]])

  expect_setequal(keyring_list(), c("default", "lab_admin"))
  expect_equal(keyring_get("default"), fake_token)
  expect_equal(keyring_get("lab_admin"), fake_tokens[["admin"]])

  keyring_delete("default")
  expect_equal(keyring_list(), "lab_admin")
})

test_that("local_fake_keyring() seeds entries and cleans up after itself", {
  vars_before <- keyring_env_vars()
  local({
    local_fake_keyring(list(default = fake_token))
    expect_equal(keyring_get("default"), fake_token)
  })
  expect_equal(keyring_env_vars(), vars_before)
})

test_that("keyring_status() reports the backend, and `env` is not usable", {
  local_fake_keyring(list(default = fake_token), backend = "macos")
  status <- keyring_status()

  expect_equal(status$backend, "macos")
  expect_true(status$usable)
  expect_true(status$readable)
  expect_equal(status$entries, "default")
  expect_true(is.na(status$reason))
})

test_that("the env backend is reported as unusable", {
  # It holds a token for the life of the session only, so storing there
  # would look like it worked and be gone at the next start of R.
  local_unusable_keyring()

  expect_equal(keyring_status()$backend, "env")
  expect_false(keyring_status()$usable)
})

test_that("keyring_has() finds an entry without retrieving it and returns its stored name", {
  local_fake_keyring(list(lab_admin = fake_tokens[["admin"]]))

  expect_equal(keyring_has("lab_admin"), "lab_admin")
  expect_equal(keyring_has("LAB_ADMIN"), "lab_admin")
  expect_null(keyring_has("default"))
})

test_that("an entry stored under another spelling is read and deleted by that spelling", {
  # Profiles are case-insensitive, the store is not. An entry created by
  # hand as `Lab_Admin` used to be listed as usable, fail to read with
  # "unlock the credential store", and survive a removal that said
  # "Deleted".
  local_no_credentials()
  local_fake_keyring(list(Lab_Admin = fake_tokens[["admin"]]))
  config_set_host("lab_admin", fake_host)

  expect_equal(keyring_has("lab_admin"), "Lab_Admin")
  expect_true(jatos_has_credentials("lab_admin"))

  resolved <- resolve_token("lab_admin", prompt = FALSE)
  expect_equal(resolved$source, "keyring")
  expect_equal(reveal_secret(resolved$secret), fake_tokens[["admin"]])
  expect_equal(reveal_secret(conn_token(jatos_connection("lab_admin"))), fake_tokens[["admin"]])

  msgs <- capture_messages(jatos_remove_credentials("lab_admin", confirm = FALSE))
  expect_match(paste(msgs, collapse = "\n"), "Deleted the token")
  expect_equal(keyring_list(), character())
  expect_false(jatos_has_credentials("lab_admin"))
})

test_that("keyring_has() picks one spelling deterministically when the store holds two", {
  # The fake store is the env backend, and Windows environment-variable names
  # are case-insensitive, so two spellings collapse into one entry there.
  skip_on_os("windows")
  local_fake_keyring(list(Lab_Admin = fake_tokens[["admin"]], lab_admin = fake_tokens[["other"]]))

  expect_setequal(keyring_matches("LAB_ADMIN"), c("Lab_Admin", "lab_admin"))
  expect_equal(keyring_has("lab_admin"), "lab_admin")
  expect_equal(keyring_has("Lab_Admin"), "Lab_Admin")
  # neither spelling asked for: the lower-case one the setter writes
  expect_equal(keyring_has("LAB_ADMIN"), "lab_admin")

  # neither exact nor lower-case present: sorted order, not key_list() order
  local_fake_keyring(list(LAB_admin = fake_tokens[["admin"]], Lab_Admin = fake_tokens[["other"]]))
  expect_equal(keyring_has("lab_admin"), "LAB_admin")
})

test_that("the setter replaces an entry under the spelling the store holds", {
  # Writing `lab_admin` next to a hand-made `Lab_Admin` left two entries, one
  # of them shadowed and invisible to jatos_list_profiles().
  local_no_credentials()
  local_fake_keyring(list(Lab_Admin = fake_tokens[["old"]]))

  suppressMessages(jatos_set_credentials(fake_host, fake_tokens[["admin"]],
    profile = "lab_admin", check = FALSE
  ))

  expect_equal(keyring_list(), "Lab_Admin")
  expect_equal(keyring_get("Lab_Admin"), fake_tokens[["admin"]])
  expect_equal(reveal_secret(conn_token(jatos_connection("lab_admin"))), fake_tokens[["admin"]])
})

test_that("the remover deletes every spelling the store holds for a profile", {
  # One left behind resolved to a token right after "Deleted the token".
  local_no_credentials()
  local_fake_keyring(list(Lab_Admin = fake_tokens[["admin"]], lab_admin = fake_tokens[["other"]]))
  config_set_host("lab_admin", fake_host)

  msgs <- capture_messages(jatos_remove_credentials("lab_admin", confirm = FALSE))

  expect_match(paste(msgs, collapse = "\n"), "Deleted the token")
  expect_equal(keyring_list(), character())
  expect_false(jatos_has_credentials("lab_admin"))
  expect_error(resolve_token("lab_admin", prompt = FALSE), "No token for profile", class = "jatosr_no_token")
})

test_that("keyring_token() returns a masked secret", {
  local_fake_keyring(list(default = fake_token))
  secret <- keyring_token("default")

  expect_s3_class(secret, "jatos_secret")
  expect_equal(reveal_secret(secret), fake_token)
  expect_no_token(format(secret))
})

test_that("a locked credential store says unlock, not store it again", {
  # The whole reason keyring_has() and keyring_token() are separate. An
  # entry that is present but unreadable is not a missing entry, and
  # "run jatos_set_credentials()" would send the user to store a token
  # they have already stored.
  local_locked_keyring(list(default = fake_token))

  expect_equal(keyring_has("default"), "default")
  expect_error(keyring_token("default"), class = "jatosr_keyring_unreadable")
  expect_error(keyring_token("default"), "Unlock the credential store", class = "jatosr_keyring_unreadable")
  expect_error(keyring_token("default"), "-25308", class = "jatosr_keyring_unreadable")
})

test_that("a locked store does not leak the token into the error", {
  local_locked_keyring(list(default = fake_token))
  err <- rlang::catch_cnd(keyring_token("default"))

  expect_no_token(conditionMessage(err))
})

test_that("the guard stops a test from reaching a real credential store", {
  # keyring_guard() reads the true backend, not the mocked name, so this
  # fires before any keychain call is made.
  #
  # The opt-out is pinned off here as well as in setup.R: these are the
  # tests of the safety mechanism itself, and one left set in the session
  # would make them pass by not running rather than by working.
  withr::local_envvar(c(JATOSR_REAL_KEYRING = NA))
  withr::local_options(list(keyring_backend = "macos"))

  expect_error(keyring_list(), "reached the .*macos.* keyring backend", class = "jatosr_keyring_guard")
  expect_error(keyring_backend(), "local_fake_keyring", class = "jatosr_keyring_guard")
})

test_that("setup.R clears a stale opt-out before the run", {
  # data-raw/check-keyring.R sets this variable. If it leaks into a test
  # session, every keyring_guard() call returns early and the suite goes on
  # passing with its keychain protection switched off.
  expect_equal(Sys.getenv("JATOSR_REAL_KEYRING", unset = ""), "")
})

test_that("JATOSR_REAL_KEYRING opts a test back in", {
  withr::local_options(list(keyring_backend = "macos"))
  withr::local_envvar(c(JATOSR_REAL_KEYRING = "true"))

  expect_no_error(keyring_guard())
})

test_that("the guard survives being wrapped in tryCatch", {
  # keyring_status() and keyring_token() both catch errors from the
  # wrappers. If either swallowed the guard, the tripwire would be dead
  # and a test could write into the developer's login keychain.
  withr::local_envvar(c(JATOSR_REAL_KEYRING = NA))
  withr::local_options(list(keyring_backend = "macos"))

  expect_error(keyring_status(), "keyring backend", class = "jatosr_keyring_guard")
  expect_error(keyring_has("default"), "keyring backend", class = "jatosr_keyring_guard")
})
