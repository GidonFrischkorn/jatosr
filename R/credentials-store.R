# The credential-store setter and remover, and the warnings they raise.
# Nothing here writes a token to a file.

#' Store JATOS credentials in the system credential store
#'
#' Stores the token of one credential profile in the credential store of the
#' operating system — the macOS keychain, the Windows credential store, or
#' the Secret Service on Linux — and the server's URL, which is not a secret,
#' in a small configuration file under [tools::R_user_dir()]. Every later R
#' session on this machine can then connect without the token appearing in
#' any script, and without it being written anywhere in the clear.
#'
#' A named profile keeps tokens for several accounts, or several servers,
#' side by side (see [jatos_list_profiles()]). The profile name is the
#' username of the keyring entry, so profiles and entries map one to one.
#'
#' @section The configuration file:
#' The host goes into `profiles.json` under
#' `tools::R_user_dir("jatosr", "config")`. It holds profile names and hosts,
#' never a token. Where that directory is not writable, or not private (a
#' container, a machine shared between users), set the environment variable
#' `JATOSR_CONFIG_DIR` to another directory before calling this function;
#' every function of the package then reads and writes the configuration
#' there.
#'
#' @section What this function does not do:
#' It does not write the token to a file, and no other function in this
#' package does either. Environment variables are still read, and take
#' precedence over the credential store, so that continuous integration,
#' containers and cluster jobs can inject the token the way they inject
#' every other secret.
#'
#' @param host Base URL of the JATOS server, e.g. `"https://jatos.example.org"`.
#'   A trailing slash or a pasted `/jatos/api/v1` is removed.
#' @param token Personal access token created in JATOS. If `NULL` and the
#'   session is interactive, you are prompted for it, with hidden input.
#'   Tokens usually start with `jap_`.
#' @param profile Name of the credential profile to write. `"default"` unless
#'   `JATOS_PROFILE` is set. Any other name must start with a letter and
#'   contain only letters, digits and underscores.
#' @param check If `TRUE` (the default), the token is verified once against the
#'   server with [jatos_token_info()] after it is stored, and its name
#'   and expiry are reported. A failed check is a warning, not an error, so
#'   credentials can be stored while the server is unreachable.
#'
#' @return The profile name, invisibly.
#' @seealso [jatos_credentials_sitrep()] to see where a token is coming from,
#'   [jatos_remove_credentials()] to delete one, and
#'   `vignette("credentials")`.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_set_credentials("https://jatos.example.org")   # prompts for the token
#' jatos_set_credentials("https://jatos.example.org", profile = "lab_admin")
#' }
jatos_set_credentials <- function(host,
                                  token = NULL,
                                  profile = Sys.getenv("JATOS_PROFILE", "default"),
                                  check = TRUE) {
  check_flag(check)
  profile <- check_profile(profile)
  host <- normalise_host(host)

  # Refused before the token is asked for: there is no point prompting for a
  # secret that cannot be kept. The `env` backend holds it for the life of
  # the session, which would look like storing and be gone at the next start
  # of R.
  status <- keyring_status()
  if (!status$usable) {
    cli::cli_abort(c(
      "No persistent credential store is available on this system.",
      "i" = "Set {.envvar {credential_var('TOKEN', profile)}} through your platform instead, on a server or in CI.",
      "i" = "Or create an encrypted file keyring once with {.code keyring::backend_file$new()$keyring_create(\"system\")}.",
      "i" = "See {.code vignette(\"credentials\", package = \"jatosr\")}."
    ), class = "jatosr_no_store")
  }
  token <- token %||% prompt_for_token()
  check_string(token)
  warn_if_unusual_token(token)

  # The host first: a configuration directory that cannot be written aborts
  # here (class jatosr_config_write_failed), and then nothing has been
  # stored. The other way round left a token in the store under a profile
  # with no host, which is a profile nothing can use and the sitrep reports
  # as half there. A store that refuses the token afterwards gets this
  # profile's entry put back as it was (see store_token()).
  #
  # A store that cannot be listed (a locked Secret Service) is not refused
  # here: whether a write into it still works, perhaps after an unlock
  # dialog, depends on the backend, and a refused write is undone anyway.
  config_before <- config_read_raw()
  config_existed <- file.exists(config_path())
  config_set_host(profile, host)
  # Under the spelling the store already holds for this profile, if any:
  # writing `lab_admin` next to a hand-made `Lab_Admin` would leave two
  # entries, one of them shadowed and invisible to jatos_list_profiles().
  store_token(
    keyring_has(profile, status = status) %||% profile, token, status$backend,
    restore = function() config_restore_profile(profile, config_before, config_existed)
  )
  # The old token of this profile may be sitting in the cache of this
  # session, and would otherwise go on being used until R restarts.
  token_cache_clear(profile)

  usage <- if (!identical(profile, "default")) {
    c("i" = "Use it with {.code jatos_connection(\"{profile}\")} or set {.envvar JATOS_PROFILE} to {.val {profile}}.")
  }
  shadow <- if (nzchar(Sys.getenv(credential_var("TOKEN", profile), unset = ""))) {
    c("!" = "{.envvar {credential_var('TOKEN', profile)}} is set and takes precedence over what was just stored.")
  }
  cli::cli_inform(c(
    "v" = "Stored the token of profile {.val {profile}} in the {.val {status$backend}} credential store.",
    "i" = "The host went to {.file {config_path()}}.",
    usage,
    shadow
  ))
  if (check) {
    # The check connection carries the token it was just given, so its label
    # is "argument"; a "keyring" label here would have the wire token and
    # the label disagree (see conn_token_peek()). Its entry in the session
    # store is dropped afterwards: the connection is not handed out, and a
    # copy of the token under a dead id has no reason to outlive the check.
    conn <- new_connection(host = host, profile = profile, token = token, auth_from = "argument")
    report_token_check(conn)
    the$conn_tokens[[conn$id]] <- NULL
  }
  invisible(profile)
}

# The write into the store, after the host is already in the configuration.
# When the store refuses, `restore()` puts the configuration back, so that a
# failed call leaves the profile as it was and not as a host without a token.
# The store's message comes from another system: the token is taken out of
# it before it reaches the condition, and it is interpolated as a value,
# never rendered as a cli template.
store_token <- function(entry, token, backend, restore, call = rlang::caller_env()) {
  tryCatch(
    keyring_set(entry, token),
    error = function(cnd) {
      rethrow_keyring_guard(cnd)
      reason <- scrub_secrets(gsub(token, "<token redacted>", conditionMessage(cnd), fixed = TRUE))
      restored <- tryCatch(
        {
          restore()
          TRUE
        },
        error = function(e) FALSE
      )
      cli::cli_abort(
        c(
          "Could not store the token of profile {.val {entry}} in the {.val {backend}} credential store.",
          "x" = "{reason}",
          if (restored) {
            c("i" = "Nothing was stored; the profile configuration is as it was.")
          } else {
            c(
              "!" = "The profile configuration could not be put back: {.file {config_path()}} names a host for this profile without a token.",
              "i" = "Remove it with {.run jatosr::jatos_remove_credentials(\"{entry}\", confirm = FALSE)}."
            )
          },
          "i" = "Unlock the credential store and try again."
        ),
        call = call,
        class = "jatosr_keyring_write_failed"
      )
    }
  )
}

#' Remove JATOS credentials from the credential store
#'
#' Deletes one credential profile's token from the system credential store
#' and its host from the configuration file, the exact inverse of
#' [jatos_set_credentials()]. Every other profile is kept. Use it to clear a
#' profile that was set up for a test, or after a token has been revoked in
#' JATOS.
#'
#' This removes your local copy of the token. It does not revoke it: the
#' token keeps working for anyone who has it until you delete it in the
#' JATOS web interface, under *API tokens* in the user menu. Revoke there
#' first if the token may have leaked.
#'
#' @param profile Name of the credential profile to remove. `"default"`
#'   unless `JATOS_PROFILE` is set. Case-insensitive; see
#'   [jatos_list_profiles()].
#' @param confirm Ask before deleting. With the default `TRUE`, an
#'   interactive session shows a prompt, and a session that cannot show one
#'   (a script, a document being knitted) is an error, never a silent
#'   removal: a token stored nowhere else cannot be recovered, because JATOS
#'   shows it once. Pass `confirm = FALSE` to remove without asking, which
#'   is what a script that means it does.
#'
#' @return The profile name, invisibly.
#' @export
#' @examples
#' \dontrun{
#' # changes the machine's credential store
#' jatos_remove_credentials(profile = "lab_admin")
#' jatos_remove_credentials()                        # the default profile
#' jatos_list_profiles()
#' }
jatos_remove_credentials <- function(profile = Sys.getenv("JATOS_PROFILE", "default"),
                                     confirm = TRUE) {
  check_flag(confirm)
  profile <- check_profile(profile)
  status <- keyring_status()
  # every spelling the store holds for this profile; key_delete() takes each
  # verbatim, and one left behind would resolve to a token after "Deleted"
  entries <- if (status$usable) keyring_matches(profile, status = status) else character()
  in_store <- length(entries) > 0
  in_config <- tolower(profile) %in% config_profiles()

  if (!in_store && !in_config) {
    cli::cli_inform(c(
      "i" = "Nothing to remove: profile {.val {profile}} is not in the credential store or the configuration.",
      "i" = "{.fn jatos_list_profiles} shows what is set."
    ))
    return(invisible(profile))
  }

  if (confirm && !confirm_removal(profile, status$backend)) {
    cli::cli_inform(c("i" = "Kept the credentials of profile {.val {profile}}."))
    return(invisible(profile))
  }

  # The configuration first, as in the setter: if it cannot be rewritten the
  # abort comes before the token is gone, and the profile is still whole.
  if (in_config) {
    config_drop_profile(profile)
  }
  for (entry in entries) {
    keyring_delete(entry)
  }
  token_cache_clear(profile)

  cli::cli_inform(c(
    if (in_store) {
      c("v" = "Deleted the token of profile {.val {profile}} from the {.val {status$backend}} credential store.")
    },
    if (in_config) c("v" = "Removed its host from {.file {config_path()}}."),
    "i" = "The token itself is still valid; delete it in the JATOS user menu under {.emph API tokens} to revoke it."
  ))

  warn_credentials_elsewhere(profile)
  warn_removed_active_profile(profile)
  invisible(profile)
}

# Deleting the entry from the credential store settles nothing if an
# environment variable defines the same profile: that variable wins over the
# store anyway, so the profile is still there, and will be there again at the
# next start of R if an .Renviron sets it.
warn_credentials_elsewhere <- function(profile, call = rlang::caller_env()) {
  vars <- c(credential_var("HOST", profile), credential_var("TOKEN", profile))
  set <- vars[nzchar(Sys.getenv(vars, unset = ""))]
  if (length(set) == 0) {
    return(invisible(NULL))
  }
  from_file <- renviron_files_defining(vars)
  cli::cli_warn(
    c(
      "{cli::qty(length(set))}The environment variable{?s} {.envvar {set}} {?is/are} still set.",
      "i" = "An environment variable takes precedence over the credential store, so the profile is still in use.",
      if (length(from_file) > 0) {
        c("i" = "{cli::qty(length(from_file))}Defined in {.file {from_file}}; remove the line{?s} there and restart R.")
      }
    ),
    call = call
  )
  invisible(NULL)
}

# JATOS_PROFILE is a line of its own and is never rewritten here, so it can
# outlive the profile it names.
warn_removed_active_profile <- function(profile, call = rlang::caller_env()) {
  selected <- Sys.getenv("JATOS_PROFILE", unset = "")
  if (!nzchar(selected) || !identical(tolower(selected), profile)) {
    return(invisible(NULL))
  }
  cli::cli_warn(
    c(
      "{.envvar JATOS_PROFILE} still selects the profile {.val {profile}}.",
      "i" = "Calls without a {.arg conn} will fail until you unset it or store the profile again."
    ),
    call = call
  )
  invisible(NULL)
}

# One GET /admin/token at the moment the user asks "does this token work".
# The httr2 error bullets come from jatos_error_body() and never carry the
# token, so the condition message can be shown; it is interpolated as a
# value because server text may hold braces or look like an expression.
report_token_check <- function(conn, call = rlang::caller_env()) {
  info <- tryCatch(jatos_token_info(conn), error = function(cnd) cnd)
  if (rlang::is_condition(info)) {
    reason <- conditionMessage(info)
    cli::cli_warn(
      c(
        "Could not verify the token against {.url {conn$host}}.",
        "x" = "{reason}",
        "i" = "The credentials were written anyway; run {.fn jatos_token_info} once the server is reachable."
      ),
      call = call
    )
    return(invisible(NULL))
  }
  expiry <- if (is.na(info$expires)) {
    "no expiry"
  } else {
    paste("expires", format(info$expires, "%Y-%m-%d", tz = "UTC"))
  }
  # A JATOS at apiVersion 1.0.1 sends no `username` field, so the clause is
  # dropped rather than rendered as "for NA". The finished line is passed as
  # a value, not as a template: the token name comes from the server.
  msg <- paste0(
    cli::format_inline("Token {.val {info$name}}"),
    if (!is.na(info$username)) cli::format_inline(" for {.val {info$username}}"),
    cli::format_inline(" accepted by {.url {conn$host}} ({expiry}).")
  )
  cli::cli_inform(c("v" = "{msg}"))
  invisible(info)
}
