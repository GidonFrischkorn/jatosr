#' Download the study archive
#'
#' Fetches the JATOS study archive of one study through `GET /studies/{id}`
#' and writes it to `file`. The archive is a zip that holds the study's
#' properties and components as JSON (a `.jas` file) next to the study
#' assets folder with the experiment's HTML, scripts and stimuli; JATOS
#' imports it as a `.jzip` file. Saved next to a dataset, it records the
#' exact version of the experiment that produced the data.
#'
#' The archive is written under a temporary name in the target directory
#' and renamed into place after the answer was checked to be a zip file; an
#' existing `file` is never replaced unless `overwrite = TRUE`. Without
#' `file`, the archive lands in the working directory under the name the
#' server sends (`jatos_study_<uuid>.jzip`, what a browser would save from
#' the GUI's export), reduced to its base name; `jatos_study_<id>.jzip`
#' when the server names none. A file in the way is then found only after
#' the answer, so a run that is refused has already downloaded the archive
#' once. The token needs the user role for this endpoint, not only the
#' viewer role.
#'
#' @param study_id Study id (integer) or uuid (string).
#' @param file Path to write, conventionally with the extension `.jzip`.
#'   Its directory must exist. `NULL` takes the server's file name in the
#'   working directory.
#' @param overwrite If `TRUE`, an existing file is replaced.
#' @param conn A [jatos_connection()].
#'
#' @return The path written, invisibly; a message reports it with the size.
#' @seealso [jatos_export_results()], whose `archive_study = TRUE` writes
#'   the archive next to the dataset.
#' @export
#' @examples
#' \dontrun{
#' # needs a JATOS server and a stored API token
#' jatos_export_study(12, "data/study12_study.jzip")
#' jatos_export_study(12) # the server's name, here
#' }
jatos_export_study <- function(study_id, file = NULL, overwrite = FALSE, conn = jatos_connection()) {
  ref <- check_ref(study_id)
  check_archive_target(file, overwrite)
  check_connection(conn)

  file <- fetch_archive(
    file, overwrite,
    route = paste0("GET /studies/", ref), fallback = paste0("jatos_study_", ref, ".jzip"),
    fetch = function(tmp) {
      jatos_req(conn, c("studies", ref), accept = "application/zip") |>
        perform_file(path = tmp)
    }
  )
  size <- format_bytes(file.size(file))
  cli::cli_inform(c("v" = "Wrote the archive of study {ref} to {.path {file}} ({size})."))
  invisible(file)
}

# The writer's target checks without a format to resolve (an archive keeps
# the server's zip). NULL (the server's name) leaves everything but the flag
# to fetch_archive(), since the name is known only after the answer.
check_archive_target <- function(file, overwrite, call = rlang::caller_env()) {
  check_flag(overwrite, arg = "overwrite", call = call)
  if (is.null(file)) {
    return(invisible(NULL))
  }
  check_write_target(file, overwrite = overwrite, resolve = FALSE, call = call)
  invisible(file)
}

# Fetch a zip archive into `file`, or, when `file` is NULL, into the working
# directory under the name the server sends in Content-Disposition
# (`fallback` when it sends none). `fetch(tmp)` performs the request with
# `path = tmp` and returns the response. The answer is written under a
# temporary name in the target directory, checked to be a zip file and
# renamed into place, so a partial download never sits under the real name.
# Returns the path written: `file`, or the bare name in the working
# directory.
fetch_archive <- function(file, overwrite, route, fallback, fetch, call = rlang::caller_env()) {
  named_by_server <- is.null(file)
  dir <- if (named_by_server) "." else dirname(file)
  tmp <- tempfile(".archive-", tmpdir = dir)
  on.exit(unlink(tmp), add = TRUE)
  resp <- fetch(tmp)
  check_zip_answer(tmp, resp, route, call = call)
  if (named_by_server) {
    header <- httr2::resp_header(resp, "content-disposition")
    file <- content_disposition_filename(header) %||% fallback
    refuse_existing(file, overwrite, call = call)
  }
  move_file(tmp, file)
  file
}

# The file name of a Content-Disposition header: the RFC 5987 `filename*=`
# form (percent-decoded) first, then a quoted, then a bare `filename=`.
# Only the base name survives, so a server (or a proxy) cannot name a path
# outside the working directory. NULL when there is no usable name.
content_disposition_filename <- function(header) {
  if (is.null(header) || !nzchar(header)) {
    return(NULL)
  }
  first_group <- function(pattern) {
    m <- regmatches(header, regexec(pattern, header, perl = TRUE))[[1]]
    if (length(m) == 2) m[[2]] else NULL
  }
  encoded <- first_group("filename\\*=(?i:utf-8)''([^;]+)")
  name <- if (!is.null(encoded)) {
    decoded <- utils::URLdecode(encoded)
    Encoding(decoded) <- "UTF-8"
    decoded
  } else {
    first_group("filename=\"([^\"]*)\"") %||% first_group("filename=([^;]+)")
  }
  if (is.null(name)) {
    return(NULL)
  }
  name <- sub(".*[\\\\/]", "", trimws(name))
  if (!nzchar(name) || name %in% c(".", "..")) {
    return(NULL)
  }
  name
}

# Archive names next to a trials file: `<stem>_study.jzip` for the one
# study the caller named, `<stem>_study_<id>.jzip` when there are several
# or when the ids were read from the metadata.
study_archive_names <- function(file, study_ids, named = TRUE) {
  if (named && length(study_ids) == 1) {
    return(suffix_file_name(file, "_study", ext = "jzip"))
  }
  suffix_file_name(file, paste0("_study_", study_ids), ext = "jzip")
}
