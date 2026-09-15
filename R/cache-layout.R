# The cache layout, spelled out once:
#
#   <path>/batch_<id>/metadata.json
#   <path>/batch_<id>/study_result_<id>/comp-result_<id>/data.txt
#   <path>/batch_<id>/study_result_<id>/comp-result_<id>/files/<filename>
#
# The `files/` folder is where the server puts a component result's uploaded
# files inside a result zip (ResultStreamer.addFilesToZip, verified
# 2026-09-06), so the cache mirrors the zip entry by entry.
#
# This is the only layout the package reads or writes. A directory that
# holds a `metadata.json` at its top level or `JATOS_DATA_<id>` folders (the
# two forms smartr left behind) is refused by `check_cache_layout()` at the
# entry of every function that opens a cache, before anything in it is read
# or written: the server is the source of truth, so such data is downloaded
# again into a fresh directory, or a results zip is fetched with
# `jatos_export_archive()` and imported with `jatos_import_results()`. The
# refusal says that nothing was touched, because the directory it points at
# may be the only local copy of a dataset. Every function that
# touches the cache builds directories with `batch_dir()` and paths with
# `local_data_path()` / `local_file_path()`.

batch_dir_pattern <- "^batch_([0-9]+)$"
foreign_dir_pattern <- "^JATOS_DATA_[0-9]+$"

# Zip entries and cache files are located by their suffix, so a top-level
# folder in a zip does not matter. Groups: 1 the path relative to the batch
# directory, 2 the study result id, 3 the component result id (and, for a
# file entry, 4 the file name).
data_entry_pattern <- "(study_result_([0-9]+)/comp-result_([0-9]+)/data\\.txt)$"
file_entry_pattern <- "(study_result_([0-9]+)/comp-result_([0-9]+)/files/(.+))$"

# One directory per batch id, vectorised.
batch_dir <- function(path, batch_id) {
  file.path(path, paste0("batch_", batch_id))
}

metadata_file <- function(batch_dir) {
  file.path(batch_dir, "metadata.json")
}

# The data file of one component result inside its batch directory.
local_data_path <- function(batch_dir, study_result_id, component_result_id) {
  file.path(
    batch_dir,
    paste0("study_result_", study_result_id),
    paste0("comp-result_", component_result_id),
    "data.txt"
  )
}

# One attached file of a component result inside its batch directory.
local_file_path <- function(batch_dir, study_result_id, component_result_id, filename) {
  file.path(
    batch_dir,
    paste0("study_result_", study_result_id),
    paste0("comp-result_", component_result_id),
    "files",
    filename
  )
}

# The batch directories of a cache, in id order.
list_batch_dirs <- function(path) {
  dirs <- list.dirs(path, full.names = TRUE, recursive = FALSE)
  dirs <- dirs[grepl(batch_dir_pattern, basename(dirs))]
  ids <- as.integer(sub(batch_dir_pattern, "\\1", basename(dirs)))
  dirs[order(ids)]
}

# Every `batch_<id>/metadata.json` of a cache, in id order.
list_metadata_files <- function(path) {
  files <- metadata_file(list_batch_dirs(path))
  files[file.exists(files)]
}

# Result data files under one batch directory, in the cache shape: a
# `data.txt` directly inside a `comp-result_<id>` folder. An uploaded file
# that happens to be called `data.txt` sits under `files/` and is not one.
list_data_files <- function(batch_dir) {
  files <- list.files(batch_dir, pattern = "^data\\.txt$", recursive = TRUE, full.names = TRUE)
  files[grepl(data_entry_pattern, files)]
}

# Refuse a directory that is not in the package layout. Called before a
# cache is read or written; a directory that does not exist yet is fine.
check_cache_layout <- function(path, arg = "path", call = rlang::caller_env()) {
  if (!dir.exists(path)) {
    return(invisible(path))
  }
  found <- character()
  if (file.exists(metadata_file(path))) {
    found <- c(found, "a {.path metadata.json} at the top level")
  }
  dirs <- list.dirs(path, full.names = FALSE, recursive = FALSE)
  foreign <- dirs[grepl(foreign_dir_pattern, dirs)]
  if (length(foreign) > 0) {
    found <- c(found, cli::format_inline("{length(foreign)} {.path JATOS_DATA_<id>} folder{?s} ({.path {foreign}})"))
  }
  if (length(found) == 0) {
    return(invisible(path))
  }
  found <- vapply(found, cli::format_inline, character(1), USE.NAMES = FALSE)
  cli::cli_abort(
    c(
      "{.arg {arg}} ({.path {path}}) is not a cache written by jatosr.",
      rlang::set_names(found, rep("x", length(found))),
      "i" = "Nothing in this directory has been read or changed.",
      "i" = "The package reads and writes {.path batch_<id>/} folders only.",
      "i" = "Download into a fresh directory with {.fn jatos_download_results}, or fetch a results zip with {.fn jatos_export_archive} and import it with {.fn jatos_import_results}."
    ),
    call = call,
    class = "jatosr_cache_layout"
  )
}
