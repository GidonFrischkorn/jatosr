# Walk the whole credential path against the real credential store of this
# operating system, once, by hand.
#
# The test suite runs against keyring's `env` backend. That exercises every
# `keyring::key_*()` call for real, but not the macOS keychain, the Windows
# credential store or the Secret Service, and not the unlock dialog that only
# a real store can show. Run this on each operating system before a release;
# beta testers run it on their own machines.
#
# With jatosr installed, from any R session:
#
#   source("https://raw.githubusercontent.com/GidonFrischkorn/jatosr/main/data-raw/check-keyring.R")
#
# or, in a source checkout, `Rscript data-raw/check-keyring.R`, which loads
# the checkout instead of the installed package.
#
# It stores a throwaway token under the profile `jatosr_selfcheck`, reads it
# back and deletes it again, also when a step fails. The host goes to a
# temporary configuration directory, so the profiles you actually use are
# never read or written. No request is sent to any server. The macOS keychain
# may ask once whether R may read the entry it just wrote. The script ends
# with a summary that holds no host, no path and no token, to paste into a
# beta test report.

check_keyring <- function() {
  # The checkout is loaded only when asked for: `Rscript data-raw/check-keyring.R`
  # from its root, or `options(jatosr.selfcheck_checkout = TRUE)` before
  # source(). A tester whose working directory happens to be an old checkout
  # still tests the installed package.
  asked <- "--file=data-raw/check-keyring.R" %in% commandArgs() ||
    isTRUE(getOption("jatosr.selfcheck_checkout"))
  in_checkout <- asked && file.exists("DESCRIPTION") &&
    identical(read.dcf("DESCRIPTION", fields = "Package")[[1]], "jatosr") &&
    requireNamespace("pkgload", quietly = TRUE)
  if (in_checkout) {
    pkgload::load_all(quiet = TRUE)
  } else {
    library(jatosr)
  }
  ns <- asNamespace("jatosr")

  profile <- "jatosr_selfcheck"
  host <- "https://jatos.example.org"
  # Assembled rather than written out, so that no token-shaped literal exists
  # in the repository: the canary test in tests/testthat/test-canary.R greps
  # for one, and a throwaway string it cannot tell apart from a real token
  # would make that test cry wolf.
  token <- paste0("jap", "_selfcheck_", format(Sys.time(), "%Y%m%d%H%M%S"))

  # The tripwire in R/keyring.R only fires under testthat, so this script
  # does not strictly need the opt-out. It is set anyway, in case the script
  # runs in a session where testthat has run, and restored on exit: left
  # behind, a later test run in the same session would find every
  # keyring_guard() disarmed and pass without checking anything.
  old_env <- Sys.getenv(c("JATOSR_REAL_KEYRING", "JATOSR_CONFIG_DIR"), unset = NA)
  config_dir <- tempfile("jatosr-selfcheck-")
  Sys.setenv(JATOSR_REAL_KEYRING = "true", JATOSR_CONFIG_DIR = config_dir)
  on.exit(
    {
      removed <- tryCatch(
        {
          if (profile %in% keyring::key_list("jatosr")$username) {
            keyring::key_delete("jatosr", username = profile)
          }
          TRUE
        },
        error = function(cnd) FALSE
      )
      if (!removed) {
        cli::cli_alert_warning(
          "Could not delete the {.val {profile}} entry; remove it with {.code keyring::key_delete(\"jatosr\", \"{profile}\")}."
        )
      }
      ns$token_cache_clear(profile)
      unlink(config_dir, recursive = TRUE)
      for (var in names(old_env)) {
        if (is.na(old_env[[var]])) Sys.unsetenv(var) else do.call(Sys.setenv, as.list(old_env[var]))
      }
    },
    add = TRUE
  )

  results <- character()
  step <- function(name, expr) {
    cli::cli_h2(name)
    outcome <- tryCatch(
      {
        force(expr)
        "PASS"
      },
      error = function(cnd) {
        cli::cli_alert_danger(gsub(token, "<token>", conditionMessage(cnd), fixed = TRUE))
        "FAIL"
      }
    )
    results[[name]] <<- outcome
    invisible(outcome == "PASS")
  }
  assert <- function(ok, what) {
    if (!isTRUE(ok)) stop(what, call. = FALSE)
    cli::cli_alert_success(what)
  }

  cli::cli_h1("jatosr credential store self-check")

  step("1 persistent, readable store", {
    status <- ns$keyring_status()
    cli::cli_text("Backend: {.val {status$backend}}")
    assert(status$usable, "The backend keeps a token across sessions.")
    assert(status$readable, "The store can be listed.")
  })

  step("2 store a token", {
    jatos_set_credentials(host, token, profile = profile, check = FALSE)
    assert(profile %in% keyring::key_list("jatosr")$username, "The entry is in the store.")
  })

  step("3 list without the token", {
    profiles <- jatos_list_profiles()
    assert(profile %in% profiles$profile, "The profile is listed.")
    assert(!any(grepl(token, unlist(profiles), fixed = TRUE)), "The listing holds no token.")
    config <- readLines(ns$config_path(), warn = FALSE)
    assert(!any(grepl(token, config, fixed = TRUE)), "profiles.json holds no token.")
  })

  step("4 read it back from the store", {
    # Emptied first, so the token is read from the store and not from the
    # copy this session kept when it was stored.
    ns$token_cache_clear(profile)
    conn <- jatos_connection(profile)
    assert(identical(conn$auth_from, "keyring"), "The connection takes its token from the store.")
    assert(identical(ns$reveal_secret(ns$conn_token(conn)), token), "The token read back is the one stored.")
  })

  step("5 the connection carries no token", {
    conn <- jatos_connection(profile)
    # serialize() is what saveRDS() writes before compressing; a grep over a
    # compressed file could not see a token at all. The control proves the
    # grep finds one where it is.
    control <- serialize(list(token), NULL)
    assert(length(grepRaw(charToRaw(token), control, fixed = TRUE)) > 0, "Control: a serialised token is found.")
    bytes <- serialize(conn, NULL)
    assert(length(grepRaw(charToRaw(token), bytes, fixed = TRUE)) == 0, "A serialised connection holds no token.")
  })

  step("6 remove it", {
    jatos_remove_credentials(profile = profile, confirm = FALSE)
    assert(!profile %in% keyring::key_list("jatosr")$username, "The entry is gone from the store.")
    assert(!profile %in% jatos_list_profiles()$profile, "The profile is no longer listed.")
  })

  sha <- ns$installed_remote_sha()
  backend <- tryCatch(keyring::default_backend()$name, error = function(cnd) "unknown")
  summary <- c(
    "jatosr credential store self-check",
    paste0(
      "jatosr ", utils::packageVersion("jatosr"),
      if (!is.null(sha)) paste0(" (commit ", substr(sha, 1, 7), ")"),
      ", keyring ", utils::packageVersion("keyring"),
      ", ", R.version.string
    ),
    paste0("Operating system: ", if (is.null(utils::osVersion)) R.version$platform else utils::osVersion),
    paste0("Backend: ", backend),
    paste0(names(results), ": ", results)
  )
  cli::cli_h1("Summary (paste this into the report)")
  cat("```\n", paste(summary, collapse = "\n"), "\n```\n", sep = "")
  invisible(results)
}

check_keyring()
