# The non-secret half of a credential profile: the host.
#
# The token goes in the operating system credential store (R/keyring.R); the
# host is not a secret and goes here, in one small JSON file under
# tools::R_user_dir("jatosr", "config") — the location R sanctions for
# user-specific configuration, and the reason this package writes nothing in
# the home filespace any more.
#
# Keeping the host out of the keyring is what lets jatos_list_profiles() and
# jatos_study_links() work with the credential store locked or absent: neither
# needs a token, and neither should open a keychain dialog to learn a URL.
#
# {
#   "version": 1,
#   "profiles": { "default": { "host": "https://jatos.example.org" } }
# }

config_version <- 1L

# JATOSR_CONFIG_DIR is a documented escape hatch, for containers and for
# shared machines where R_user_dir() is not writable or not private. The
# tests use it too, but it exists for users.
config_dir <- function() {
  from_env <- Sys.getenv("JATOSR_CONFIG_DIR", unset = "")
  if (nzchar(from_env)) {
    return(path.expand(from_env))
  }
  tools::R_user_dir("jatosr", "config")
}

config_path <- function() {
  file.path(config_dir(), "profiles.json")
}

# The profiles as the package reads them: keys lower-cased (profile names
# are case-insensitive, and a hand-edited `Default` used to be listed as a
# profile of its own that nothing could use or remove), keys that could not
# be profile names left out, so that a stray key is never suggested as a
# profile to select. The writers work from config_read_raw() instead, so
# that what is ignored here is not deleted there.
config_read <- function() {
  profiles <- config_read_raw()
  if (length(profiles) == 0) {
    return(list())
  }
  names(profiles) <- tolower(names(profiles))
  profiles <- profiles[grepl(profile_pattern, names(profiles))]
  profiles[!duplicated(names(profiles))]
}

# The profiles as the file spells them. A hand-edited file with a trailing
# comma must not take the package down with it: every function that resolves
# a host goes through here, so an abort would turn one bad character into
# "nothing works". Warn, and carry on as if no profile were configured.
config_read_raw <- function() {
  path <- config_path()
  if (!file.exists(path)) {
    return(list())
  }
  parsed <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(cnd) {
      reason <- conditionMessage(cnd)
      cli::cli_warn(c(
        "Could not read the profile configuration at {.file {path}}.",
        "x" = "{reason}",
        "i" = "Continuing as if no profile were configured; fix or delete the file."
      ))
      NULL
    }
  )
  if (!is.list(parsed) || !is.list(parsed$profiles)) {
    return(list())
  }
  warn_config_version(parsed$version, path)
  parsed$profiles
}

# Once per file and session: config_read() runs on every host resolution,
# and the file is not going to change between two of them.
warn_config_version <- function(version, path) {
  version <- if (rlang::is_scalar_atomic(version)) suppressWarnings(as.integer(version)) else NA_integer_
  if (is.na(version) || version <= config_version || path %in% the$config_warned) {
    return(invisible(NULL))
  }
  the$config_warned <- c(the$config_warned, path)
  cli::cli_warn(c(
    "The profile configuration at {.file {path}} was written by a newer jatosr (format version {version}; this version reads {config_version}).",
    "i" = "Profiles may be read incompletely. Update jatosr; storing a profile again with {.fn jatos_set_credentials} rewrites the file in this version's format."
  ))
  invisible(NULL)
}

# Written through a temporary file in the same directory, so an interrupted
# write cannot leave a half-file where the hosts used to be. A failure is an
# error of class `jatosr_config_write_failed`, never a silent return: the
# results of dir.create() and file.rename() used to be ignored, so a write
# into an unwritable directory returned the path, the setter reported "The
# host went to ...", and a profiles<hex>.json was left behind each time.
config_write <- function(profiles, call = rlang::caller_env()) {
  path <- config_path()
  dir <- dirname(path)
  if (!dir.exists(dir)) {
    dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  }
  if (!dir.exists(dir)) {
    abort_config_write(path, "The directory could not be created.", call = call)
  }
  tmp <- tempfile(pattern = "profiles", tmpdir = dir, fileext = ".json")
  # Whatever happens: after a successful move nothing is at `tmp` any more,
  # after a failure the half-file must not stay behind.
  on.exit(unlink(tmp), add = TRUE)
  reason <- tryCatch(
    withCallingHandlers(
      {
        jsonlite::write_json(
          list(version = config_version, profiles = profiles),
          tmp,
          auto_unbox = TRUE,
          pretty = TRUE
        )
        # The file holds no secret, but the list of servers says which
        # institutions a person works with; on a shared machine that is
        # nobody else's business.
        if (.Platform$OS.type == "unix") {
          Sys.chmod(tmp, mode = "0600")
        }
        move_file(tmp, path)
        NULL
      },
      # file() warns "cannot open file" before it errors; the error carries
      # the same text and is the one that is reported.
      warning = function(cnd) rlang::cnd_muffle(cnd)
    ),
    error = function(cnd) conditionMessage(cnd)
  )
  if (!is.null(reason)) {
    abort_config_write(path, reason, call = call)
  }
  invisible(path)
}

# `reason` comes from the file system or from another function's message, so
# it is interpolated as a value, never rendered as a cli template.
abort_config_write <- function(path, reason, call = rlang::caller_env()) {
  reason <- cli::ansi_strip(reason)
  cli::cli_abort(
    c(
      "Could not write the profile configuration to {.file {path}}.",
      "x" = "{reason}",
      "i" = "Make that directory writable, or point {.envvar JATOSR_CONFIG_DIR} at one that is."
    ),
    class = "jatosr_config_write_failed",
    call = call
  )
}

config_profiles <- function() {
  names(config_read()) %||% character()
}

config_host <- function(profile) {
  entry <- config_read()[[tolower(profile)]]
  if (!is.list(entry) || !rlang::is_string(entry$host)) {
    return(NULL)
  }
  entry$host
}

# The writers rewrite the file as it is, keys the package ignores included
# (a hand-edited entry is the user's, not this package's to delete), and
# replace every spelling of the profile they write with the lower-case one.
config_set_host <- function(profile, host) {
  profiles <- config_read_raw()
  profiles <- profiles[tolower(names(profiles)) != tolower(profile)]
  profiles[[tolower(profile)]] <- list(host = host)
  config_write(profiles)
}

# Put one profile's entry back as `before` had it, and leave every other
# entry as the file has it now: another session may have written it since
# `before` was read. A file that did not exist before and now holds nothing
# else is removed again.
config_restore_profile <- function(profile, before, existed) {
  now <- config_read_raw()
  others <- now[tolower(names(now)) != tolower(profile)]
  own <- before[tolower(names(before)) == tolower(profile)]
  if (!existed && length(others) == 0 && length(own) == 0) {
    unlink(config_path())
    return(invisible(NULL))
  }
  config_write(c(others, own))
}

# TRUE when the profile was there to remove.
config_drop_profile <- function(profile) {
  profiles <- config_read_raw()
  hit <- tolower(names(profiles)) == tolower(profile)
  if (!any(hit)) {
    return(FALSE)
  }
  config_write(profiles[!hit])
  TRUE
}
