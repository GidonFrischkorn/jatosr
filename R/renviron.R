# Read-only access to `.Renviron`, for the sitrep and the remover to say
# which file still defines a credential. Nothing here writes one.

read_renviron <- function(path) {
  if (!file.exists(path)) {
    return(character())
  }
  readLines(path, warn = FALSE)
}

# Does this .Renviron define any of `vars`? The package never writes such a
# line, but it has to recognise one: a variable set there silently wins over
# the credential store, so jatos_credentials_sitrep() and the remover name
# the file.
#
# The rule: optional leading whitespace, the name, optional whitespace, "=".
# Names are matched case-insensitively because Windows treats them that way,
# and the "=" anchor keeps `JATOS_HOST` from matching `JATOS_HOST_LAB_ADMIN`.
# `vars` holds environment variable names only, never regex metacharacters
# (see `profile_pattern`).
renviron_has_vars <- function(lines, vars) {
  if (length(lines) == 0) {
    return(FALSE)
  }
  pattern <- sprintf("^\\s*(%s)\\s*=", paste(vars, collapse = "|"))
  any(grepl(pattern, lines, ignore.case = TRUE))
}

# The lines of an .Renviron that define one of `vars`, for showing the user
# what to delete by hand. The package never deletes them itself, and never
# shows the value of a token line: the sitrep promises that no token reaches
# its output, and a line copied from the file verbatim was the one place
# where one did. The user needs the name to find the line, not the value.
renviron_lines_for <- function(lines, vars) {
  if (length(lines) == 0) {
    return(character())
  }
  pattern <- sprintf("^\\s*(%s)\\s*=", paste(vars, collapse = "|"))
  lines <- trimws(lines[grepl(pattern, lines, ignore.case = TRUE)])
  secret <- grepl("^[^=]*TOKEN[^=]*=", lines, ignore.case = TRUE)
  lines[secret] <- sub(
    "^([^=[:space:]]+)[[:space:]]*=.*$", "\\1=<value hidden>",
    lines[secret]
  )
  lines
}

# The .Renviron files, user then project, that define one of `vars`; for
# telling a user which file to edit by hand.
renviron_files_defining <- function(vars) {
  files <- unique(c(renviron_path("user"), renviron_path("project")))
  files[purrr::map_lgl(files, function(path) {
    renviron_has_vars(read_renviron(path), vars)
  })]
}

renviron_path <- function(scope) {
  if (scope == "project") {
    return(file.path(getwd(), ".Renviron"))
  }
  user_file <- Sys.getenv("R_ENVIRON_USER", unset = "")
  if (nzchar(user_file)) {
    return(path.expand(user_file))
  }
  path.expand("~/.Renviron")
}
