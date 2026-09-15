# The five tiers of resolve_token(), one test per tier and per precedence
# pair. Every test starts from local_no_credentials(), which empties all
# three stores, so a tier is only reached because the test put something
# there.

test_that("an explicit token wins over everything", {
  local_no_credentials()
  withr::local_envvar(c(JATOS_TOKEN = fake_tokens[["other"]]))
  local_fake_keyring(list(default = fake_tokens[["admin"]]))

  resolved <- resolve_token("default", token = fake_tokens[["explicit"]])

  expect_equal(resolved$source, "argument")
  expect_equal(reveal_secret(resolved$secret), fake_tokens[["explicit"]])
})

test_that("an explicit token is not cached for the profile", {
  # It belongs to the one call that passed it, not to the profile.
  local_no_credentials()
  resolve_token("default", token = fake_tokens[["explicit"]])

  expect_null(token_cache_get("default"))
})

test_that("the environment variable is read when nothing else is set", {
  local_no_credentials()
  withr::local_envvar(c(JATOS_TOKEN = fake_token))

  resolved <- resolve_token("default")

  expect_equal(resolved$source, "env")
  expect_equal(reveal_secret(resolved$secret), fake_token)
})

test_that("a named profile reads its suffixed variable", {
  local_no_credentials()
  withr::local_envvar(c(JATOS_TOKEN_LAB_ADMIN = fake_tokens[["admin"]]))

  resolved <- resolve_token("lab_admin")

  expect_equal(resolved$source, "env")
  expect_equal(reveal_secret(resolved$secret), fake_tokens[["admin"]])
})

test_that("the environment variable wins over the credential store", {
  # The CI, container and HPC path: the platform injects the secret and
  # there may be no store at all.
  local_no_credentials()
  local_fake_keyring(list(default = fake_tokens[["admin"]]))
  withr::local_envvar(c(JATOS_TOKEN = fake_token))

  expect_warning(resolved <- resolve_token("default"), "takes precedence")
  expect_equal(resolved$source, "env")
  expect_equal(reveal_secret(resolved$secret), fake_token)
})

test_that("the shadowing warning fires once per profile and session", {
  local_no_credentials()
  local_fake_keyring(list(default = fake_token))
  withr::local_envvar(c(JATOS_TOKEN = fake_token))

  expect_warning(resolve_token("default"), "takes precedence")
  expect_no_warning(resolve_token("default"))
})

test_that("an environment variable with nothing to shadow is silent", {
  # This is CI. A warning on every run there would be noise about a
  # situation that is entirely correct.
  local_no_credentials()
  withr::local_envvar(c(JATOS_TOKEN = fake_token))

  expect_no_warning(resolve_token("default"))
})

test_that("an environment-variable token reads the credential store once", {
  # jatos_connection() is the default argument of nearly every exported
  # function, so a store read per call is a keychain round trip per request.
  # The answer to "is anything being shadowed?" is the same all session, so
  # it is asked once per profile, whatever the answer.
  local_no_credentials()
  local_fake_keyring()
  withr::local_envvar(c(JATOS_TOKEN = fake_token))

  reads <- 0L
  testthat::local_mocked_bindings(
    keyring_list = function() {
      reads <<- reads + 1L
      character()
    }
  )

  for (i in 1:5) {
    expect_equal(resolve_token("default")$source, "env")
  }
  expect_equal(reads, 1L)

  # A second profile is a question of its own, asked once as well.
  withr::local_envvar(c(JATOS_TOKEN_LAB_ADMIN = fake_tokens[["admin"]]))
  expect_equal(resolve_token("lab_admin")$source, "env")
  expect_equal(resolve_token("lab_admin")$source, "env")
  expect_equal(reads, 2L)
})

test_that("a token that resolves nowhere reads the credential store once", {
  # The hints in the abort name the configured profiles from the status the
  # resolver already holds; listing them used to cost a second key_list().
  local_no_credentials()
  local_fake_keyring()

  reads <- 0L
  testthat::local_mocked_bindings(
    keyring_list = function() {
      reads <<- reads + 1L
      character()
    }
  )

  expect_error(resolve_token("default", prompt = FALSE), "No token for profile", class = "jatosr_no_token")
  expect_equal(reads, 1L)
})

test_that("the credential store is read when no variable is set", {
  local_no_credentials()
  local_fake_keyring(list(default = fake_token))

  resolved <- resolve_token("default")

  expect_equal(resolved$source, "keyring")
  expect_equal(reveal_secret(resolved$secret), fake_token)
})

test_that("a store read is cached, so the next call does not repeat it", {
  # jatos_connection() is the default argument of most exported functions,
  # so without this there is one keychain read per API call.
  local_no_credentials()
  local_fake_keyring(list(default = fake_token))

  expect_equal(resolve_token("default")$source, "keyring")
  # the cached answer still says where the token came from, so what a
  # connection reports does not change on the second call
  expect_equal(resolve_token("default")$source, "keyring")
  expect_equal(reveal_secret(token_cache_get("default")$secret), fake_token)
})

test_that("the cache is per profile", {
  local_no_credentials()
  local_fake_keyring(list(default = fake_token, lab_admin = fake_tokens[["admin"]]))

  resolve_token("default")

  expect_equal(resolve_token("lab_admin")$source, "keyring")
  expect_equal(reveal_secret(token_cache_get("lab_admin")$secret), fake_tokens[["admin"]])
})

test_that("token_cache_clear() drops one profile or all of them", {
  local_no_credentials()
  token_cache_set("default", new_secret(fake_token), "keyring")
  token_cache_set("lab_admin", new_secret(fake_tokens[["admin"]]), "keyring")

  token_cache_clear("default")
  expect_null(token_cache_get("default"))
  expect_false(is.null(token_cache_get("lab_admin")))

  token_cache_clear()
  expect_null(token_cache_get("lab_admin"))
})

test_that("a store that cannot store is skipped, not consulted", {
  # The `env` backend keeps a secret for the life of the session only.
  local_no_credentials()
  local_unusable_keyring(list(default = fake_token))

  expect_error(resolve_token("default", prompt = FALSE), "No token for profile", class = "jatosr_no_token")
})

test_that("a locked store aborts instead of asking for the token again", {
  local_no_credentials()
  local_locked_keyring(list(default = fake_token))

  expect_error(resolve_token("default", prompt = FALSE), class = "jatosr_keyring_unreadable")
})

test_that("the prompt is the last resort and its answer is cached", {
  local_no_credentials()
  withr::local_options(list(rlang_interactive = TRUE))
  local_mocked_bindings(prompt_for_token = function(...) fake_token)

  resolved <- resolve_token("default", prompt = TRUE)

  expect_equal(resolved$source, "prompt")
  expect_equal(reveal_secret(resolved$secret), fake_token)
  expect_equal(resolve_token("default")$source, "prompt")
})

test_that("resolving does not warn about an unusual token", {
  # The callers warn once on whatever they resolved; warning here too
  # would double it.
  local_no_credentials()
  withr::local_options(list(rlang_interactive = TRUE))
  local_mocked_bindings(prompt_for_token = function(...) fake_tokens[["plain"]])

  expect_no_warning(resolve_token("default", prompt = TRUE))
})

test_that("a non-interactive session with nothing stored aborts", {
  local_no_credentials()

  expect_error(resolve_token("default", prompt = FALSE), "No token for profile", class = "jatosr_no_token")
})

test_that("the abort names the variable and the setter", {
  local_no_credentials()
  err <- rlang::catch_cnd(resolve_token("lab_admin", prompt = FALSE))
  message <- cli::ansi_strip(paste(conditionMessage(err), collapse = "\n"))

  expect_match(message, "JATOS_TOKEN_LAB_ADMIN")
  expect_match(message, 'jatos_set_credentials\\(profile = "lab_admin"\\)')
})

test_that("the abort names the other configured profiles", {
  local_no_credentials()
  local_fake_keyring(list(lab_admin = fake_tokens[["admin"]]))
  config_set_host("lab_admin", fake_host)

  err <- rlang::catch_cnd(resolve_token("default", prompt = FALSE))
  message <- cli::ansi_strip(paste(conditionMessage(err), collapse = "\n"))

  expect_match(message, "Configured profile")
  expect_match(message, "lab_admin")
})

test_that("the abort says so when no persistent store exists at all", {
  # A headless Linux box. Sending this user to jatos_set_credentials()
  # would send them to a function that refuses.
  local_no_credentials()
  local_unusable_keyring()

  err <- rlang::catch_cnd(resolve_token("default", prompt = FALSE))
  message <- cli::ansi_strip(paste(conditionMessage(err), collapse = "\n"))

  expect_match(message, "No persistent credential store")
  expect_no_match(message, "Run .*jatos_set_credentials")
})

test_that("no abort or warning on any tier carries the token", {
  local_no_credentials()
  local_locked_keyring(list(default = fake_token))
  expect_no_token(conditionMessage(rlang::catch_cnd(resolve_token("default", prompt = FALSE))))

  local_no_credentials()
  expect_no_token(conditionMessage(rlang::catch_cnd(resolve_token("zz", prompt = FALSE))))
})

# --- the host, which is not a secret ------------------------------------------

test_that("the host comes from the configuration file when no variable is set", {
  local_no_credentials()
  config_set_host("default", fake_host)

  expect_equal(jatos_host("default"), fake_host)
})

test_that("the host variable wins over the configuration file", {
  local_no_credentials()
  config_set_host("default", "https://jatos.example.net")
  withr::local_envvar(c(JATOS_HOST = fake_host))

  expect_equal(jatos_host("default"), fake_host)
})

test_that("an explicit host wins over both", {
  local_no_credentials()
  config_set_host("default", "https://jatos.example.net")
  withr::local_envvar(c(JATOS_HOST = "https://jatos.example.com"))

  expect_equal(jatos_host("default", host = fake_host), fake_host)
})

test_that("a host for a named profile is kept apart", {
  local_no_credentials()
  config_set_host("lab_admin", fake_host)

  expect_equal(jatos_host("lab_admin"), fake_host)
  expect_error(jatos_host("default"), "JATOS_HOST", class = "jatosr_no_host")
})

test_that("missing = 'na' answers NA where the default aborts, and the tiers still apply", {
  # the sitrep and the host-mismatch check report a host; they must not fail
  # for a profile that has none
  local_no_credentials()

  expect_identical(jatos_host("default", missing = "na"), NA_character_)
  config_set_host("default", "https://jatos.example.net")
  expect_equal(jatos_host("default", missing = "na"), "https://jatos.example.net")
  withr::local_envvar(c(JATOS_HOST = fake_host))
  expect_equal(jatos_host("default", missing = "na"), fake_host)
  expect_error(jatos_host("default", missing = "maybe"), "`missing` must be one of")
})

test_that("resolving a host needs no credential store", {
  # jatos_study_links() takes this path and must keep working with the
  # keychain locked.
  local_no_credentials()
  config_set_host("default", fake_host)
  local_locked_keyring(list(default = fake_token))

  expect_equal(jatos_host("default"), fake_host)
})
