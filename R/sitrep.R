#' Report where each token is coming from
#'
#' Prints, for every credential profile on this machine, which of the three
#' places the package reads a host and a token would actually be taken from:
#' an environment variable, the system credential store, or the profile
#' configuration file. It never prints a token, and never a hash, a prefix or
#' a length of one.
#'
#' Use it when a call fails with credentials that look correct, and when two
#' profiles might be confused. The report starts with the versions of
#' jatosr, `keyring`, R and the operating system (and the commit, for a
#' package installed from GitHub), so that it can be pasted into a bug
#' report as it is, once the host is replaced if the server is private.
#'
#' An environment variable wins over the credential store. When a user or
#' project `.Renviron` file defines the variables of a profile, the report
#' names the file and the lines, with the token's value hidden, because a
#' token stored with [jatos_set_credentials()] is not used while such a line
#' sets the variable. The file is only read, never edited.
#'
#' @param profile Report only this profile. `NULL`, the default, reports
#'   every profile found in any of the three places.
#'
#' @return A tibble, invisibly, with one row per profile: `profile`, `host`,
#'   `host_from` (`"env"`, `"config"` or `"none"`), `auth_from` (`"env"`,
#'   `"keyring"` or `"none"`), `shadowed` (an environment variable is hiding a
#'   stored token), `renviron_line` (an `.Renviron` file defines this
#'   profile) and `renviron_file`. No column holds a token.
#' @seealso [jatos_list_profiles()], [jatos_set_credentials()],
#'   `vignette("credentials")`.
#' @export
#' @examples
#' \dontrun{
#' # lists the machine's credential store
#' jatos_credentials_sitrep()
#' jatos_credentials_sitrep("lab_admin")
#' }
jatos_credentials_sitrep <- function(profile = NULL) {
  if (!is.null(profile)) {
    profile <- check_profile(profile)
  }
  status <- keyring_status()
  report <- sitrep_table(profile, status)

  cli::cli_h1("jatosr credentials")
  sitrep_system()
  sitrep_stores(status)

  if (nrow(report) == 0) {
    cli::cli_alert_info("No credential profile found.")
    cli::cli_bullets(c(
      "i" = "Store one with {.run jatosr::jatos_set_credentials(\"https://your.jatos\")}."
    ))
    return(invisible(report))
  }

  for (row in seq_len(nrow(report))) {
    sitrep_profile(report[row, ])
  }
  invisible(report)
}

# What a bug report about the credential store needs besides the store: the
# versions, and the commit when the package came from GitHub rather than
# from CRAN, so that a report can be matched to the code it ran.
sitrep_system <- function() {
  sha <- installed_remote_sha()
  jatosr <- paste0(
    "jatosr ", utils::packageVersion("jatosr"),
    if (!is.null(sha)) paste0(" (commit ", substr(sha, 1, 7), ")")
  )
  keyring <- paste0("keyring ", utils::packageVersion("keyring"))
  os <- utils::osVersion %||% R.version$platform
  cli::cli_bullets(c(
    "*" = "Packages: {jatosr}, {keyring}",
    "*" = "{R.version.string}",
    "*" = "Operating system: {os}"
  ))
  invisible(NULL)
}

# NULL for an installation that did not come from a remote (CRAN, a local
# source build, devtools::load_all()).
installed_remote_sha <- function() {
  sha <- utils::packageDescription("jatosr", fields = "RemoteSha")
  if (!rlang::is_string(sha) || !nzchar(sha)) {
    return(NULL)
  }
  sha
}

sitrep_stores <- function(status) {
  cli::cli_bullets(c(
    "*" = "Credential store: {.val {status$backend}}{if (!status$usable) ' (not persistent)' else ''}",
    if (status$usable && !status$readable) {
      reason <- status$reason
      c("x" = "The store could not be read: {reason}")
    },
    "*" = "Profile configuration: {.file {config_path()}}{if (!file.exists(config_path())) ' (not written yet)' else ''}"
  ))
  if (!status$usable) {
    cli::cli_bullets(c(
      "i" = "Tokens cannot be stored here. Set the environment variables through your platform, or create an encrypted file keyring with {.code keyring::backend_file$new()$keyring_create(\"system\")}."
    ))
  }
  invisible(NULL)
}

# One row per profile. Everything here is derived from names and paths; no
# secret is retrieved from anywhere.
sitrep_table <- function(profile = NULL, status) {
  profiles <- list_profiles(status)
  names <- profiles$profile
  if (!is.null(profile)) {
    names <- intersect(names, profile)
  }
  if (length(names) == 0) {
    names <- profile %||% character()
  }

  rows <- purrr::map(names, function(name) {
    host_var <- credential_var("HOST", name)
    token_var <- credential_var("TOKEN", name)
    from_env_host <- nzchar(Sys.getenv(host_var, unset = ""))
    from_env_token <- nzchar(Sys.getenv(token_var, unset = ""))
    in_store <- status$usable && !is.null(keyring_has(name, status = status))
    in_config <- !is.null(config_host(name))
    found <- renviron_files_defining(c(host_var, token_var))
    tibble::tibble(
      profile = name,
      host = jatos_host(name, missing = "na"),
      host_from = if (from_env_host) "env" else if (in_config) "config" else "none",
      auth_from = if (from_env_token) "env" else if (in_store) "keyring" else "none",
      shadowed = from_env_token && in_store,
      renviron_line = length(found) > 0,
      renviron_file = if (length(found) > 0) found[[1]] else NA_character_,
      active = identical(name, tolower(default_profile()))
    )
  })
  if (length(rows) == 0) {
    return(tibble::tibble(
      profile = character(), host = character(), host_from = character(),
      auth_from = character(), shadowed = logical(),
      renviron_line = logical(), renviron_file = character(), active = logical()
    ))
  }
  purrr::list_rbind(rows)
}

sitrep_profile <- function(row) {
  cli::cli_h2("Profile {.val {row$profile}}{if (row$active) ' (active)' else ''}")
  cli::cli_bullets(c(
    "*" = if (is.na(row$host)) {
      "Host: not set"
    } else {
      paste0("Host: {.url {row$host}} (from ", row$host_from, ")")
    },
    "*" = switch(row$auth_from,
      env = paste0("Token: from {.envvar ", credential_var("TOKEN", row$profile), "}"),
      keyring = "Token: from the credential store",
      "Token: not found"
    )
  ))

  if (row$auth_from == "none") {
    cli::cli_bullets(c(
      "i" = "Store one with {.run jatosr::jatos_set_credentials(\"https://your.jatos\", profile = \"{row$profile}\")}."
    ))
  }
  if (row$shadowed) {
    cli::cli_bullets(c(
      "!" = "The environment variable hides a token that is in the credential store.",
      "i" = "The stored one is not being used."
    ))
  }
  if (row$renviron_line) {
    sitrep_renviron(row)
  }
  invisible(NULL)
}

# The .Renviron file that defines the profile's variables, and its lines with
# the token's value hidden. Nothing here writes to .Renviron: rewriting a
# user's file risks damaging unrelated entries.
sitrep_renviron <- function(row) {
  file <- row$renviron_file
  vars <- c(
    credential_var("HOST", row$profile),
    credential_var("TOKEN", row$profile)
  )
  lines <- renviron_lines_for(read_renviron(file), vars)
  cli::cli_bullets(c(
    "!" = "{.file {file}} defines this profile:",
    rlang::set_names(lines, rep(" ", length(lines))),
    "i" = "An environment variable takes precedence over the credential store. To use a stored token instead, delete {cli::qty(length(lines))}{?this line/these lines} and restart R; jatosr never edits the file."
  ))
  invisible(NULL)
}
