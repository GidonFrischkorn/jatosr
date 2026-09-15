#' Write a trials tibble to disk
#'
#' Saves the tibble that [jatos_read_results()] returns (or any data frame)
#' as `.rds`, `.csv`, `.csv.gz`, `.tsv`, `.parquet` or `.RData` in one
#' call. The format is taken from the file extension or from `format` when
#' the file has no extension; a `format` that contradicts the extension is
#' an error, the file is not renamed. The file is written under a temporary
#' name in the same directory and renamed into place, and an existing file
#' is never replaced unless `overwrite = TRUE`.
#'
#' `rds` and `RData` keep every column as it is, list columns included.
#' `parquet` (through the arrow package, which must be installed) reads
#' from Python and other tools; it keeps a list column or nested
#' data-frame column when arrow can give it one type, and serialises a
#' column it cannot type (cells of different shapes, such as an object in
#' one trial and a vector in the next) to JSON strings the way csv does,
#' with a message naming the columns. `csv`, `csv.gz` (the same,
#' gzip-compressed) and `tsv` are written
#' in UTF-8 without row names, `NA` as an empty field, `POSIXct` columns as
#' ISO 8601 in UTC (`2025-08-24T01:46:40Z`), and every list column or
#' nested data-frame column serialised cell by cell to a JSON string with
#' `jsonlite::toJSON(auto_unbox = TRUE)`; a message names the columns that
#' were serialised. Read such a cell back with `jsonlite::fromJSON()`, or
#' read the trials with `flatten = TRUE` to get nested objects as columns
#' before writing.
#'
#' @param x A data frame, usually from [jatos_read_results()].
#' @param file Path of the file to write. With `split = "component"` it is
#'   the pattern: `results.rds` becomes `results_component_<id>.rds`.
#' @param ... Must be empty.
#' @param format `"rds"`, `"csv"`, `"csv.gz"`, `"tsv"`, `"parquet"` or
#'   `"rdata"`. `NULL` (the default) infers it from the extension of
#'   `file` (`.RData` and `.rda` are `"rdata"`).
#' @param object For `RData`: the name of the object in the file, so that
#'   `load()` is predictable; a syntactic name (see [make.names()]). With
#'   `split = "component"` each file holds `<object>_component_<id>`, the
#'   suffix of its file name.
#' @param split `"none"` writes one file. `"component"` writes one file per
#'   distinct `component_id` in `x`, with the id in the file name, for
#'   studies whose components have different columns.
#' @param overwrite If `TRUE`, existing files are replaced.
#'
#' @return The path(s) written, invisibly.
#' @seealso [jatos_export_results()] for metadata, download, read and write
#'   in one call.
#' @export
#' @examples
#' cache <- system.file("extdata", "JATOS_data", package = "jatosr")
#' trials <- jatos_read_results(jatos_read_metadata(cache))
#'
#' out <- tempfile("jatosr-example-")
#' dir.create(out)
#' jatos_write_results(trials, file.path(out, "study12.rds"))
#' jatos_write_results(trials, file.path(out, "study12.csv"))
#' jatos_write_results(trials, file.path(out, "study12.RData"), object = "study12")
#' list.files(out)
#' unlink(out, recursive = TRUE)
jatos_write_results <- function(x,
                                file,
                                ...,
                                format = NULL,
                                object = "trials",
                                split = c("none", "component"),
                                overwrite = FALSE) {
  rlang::check_dots_empty()
  if (!is.data.frame(x)) {
    cli::cli_abort("{.arg x} must be a data frame, as returned by {.fn jatos_read_results}.", class = "jatosr_bad_argument")
  }
  check_object_name(object)
  split <- rlang::arg_match(split)
  format <- check_write_target(file, format, overwrite, check_existing = split == "none")

  if (split == "component") {
    if (!"component_id" %in% names(x)) {
      cli::cli_abort("{.arg x} needs a {.field component_id} column for {.code split = \"component\"}.", class = "jatosr_bad_argument")
    }
    ids <- unique(x$component_id)
    files <- component_file_names(file, ids)
    objects <- paste0(object, "_component_", ids)
    parts <- purrr::map(ids, function(id) x[x$component_id %in% id, , drop = FALSE])
    refuse_existing(files, overwrite)
  } else {
    files <- file
    objects <- object
    parts <- list(x)
  }
  for (k in seq_along(files)) {
    write_one_file(parts[[k]], files[[k]], format = format, object = objects[[k]])
  }
  invisible(files)
}

# `load()` binds the object under the name given; a name that is not
# syntactic (`my data`) would need backticks or get() at every use.
check_object_name <- function(object, arg = rlang::caller_arg(object), call = rlang::caller_env()) {
  check_string(object, arg = arg, call = call)
  if (!identical(make.names(object), object)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a syntactic name, so that {.fn load} gives an object usable as it is.",
        "i" = "{.val {object}} is not; {.fn make.names} would make it {.val {make.names(object)}}."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  invisible(object)
}

write_formats <- c(
  rds = "rds", csv = "csv", `csv.gz` = "csv.gz", tsv = "tsv", parquet = "parquet",
  rdata = "rdata", rda = "rdata"
)
compound_extensions <- "csv.gz"

# Everything that can be known about a target file before anything is
# computed: a valid path, a format, an existing directory and, unless
# `check_existing = FALSE`, no file in the way. Returns the format, or NA
# with `resolve = FALSE` (an archive keeps the server's zip and has none).
# Shared by the writer, the export wrapper and the archive downloads, so the
# wrapper's promise that a mistake in `file` costs no request holds for the
# same checks the writer makes.
check_write_target <- function(file,
                               format = NULL,
                               overwrite = FALSE,
                               check_existing = TRUE,
                               resolve = TRUE,
                               call = rlang::caller_env()) {
  check_string(file, arg = "file", call = call)
  check_flag(overwrite, arg = "overwrite", call = call)
  format <- if (resolve) resolve_format(file, format, call = call) else NA_character_
  check_target_dir(file, call = call)
  if (check_existing) {
    refuse_existing(file, overwrite, call = call)
  }
  format
}

# The directory a file will be written into must exist; nothing here
# creates one, so a typo in the path is caught before any work.
check_target_dir <- function(file, call = rlang::caller_env()) {
  dir <- dirname(file)
  if (!dir.exists(dir)) {
    cli::cli_abort("The directory {.path {dir}} does not exist.", call = call, class = "jatosr_bad_argument")
  }
  invisible(dir)
}

# Combine the extension of `file` and the `format` argument into one format,
# refusing to guess when they disagree or when neither says anything.
resolve_format <- function(file, format, call = rlang::caller_env()) {
  if (!is.null(format)) {
    format <- rlang::arg_match0(format, unique(unname(write_formats)), error_call = call)
  }
  ext <- tolower(file_extension(file))
  inferred <- if (nzchar(ext)) unname(write_formats[ext]) else NA_character_
  if (is.null(format)) {
    if (is.na(inferred)) {
      cli::cli_abort(
        c(
          "Cannot tell the format of {.path {file}} from its extension.",
          "i" = "Use {.code .rds}, {.code .csv}, {.code .csv.gz}, {.code .tsv}, {.code .parquet}, {.code .RData} or {.code .rda}, or set {.arg format}."
        ),
        call = call,
        class = "jatosr_bad_argument"
      )
    }
    format <- inferred
  } else if (!is.na(inferred) && !identical(inferred, format)) {
    cli::cli_abort(
      c(
        "{.arg format} is {.val {format}} but {.path {file}} has the extension {.val {ext}}.",
        "i" = "Change one of them; the file is not renamed."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  if (identical(format, "parquet")) {
    rlang::check_installed("arrow", reason = "to write parquet files.", call = call)
  }
  format
}

# The extension of a file name (`tools::file_ext()`), with `.csv.gz` as
# one extension; "" when there is none. The case is kept, so a suffixed
# name keeps its spelling.
file_extension <- function(file) {
  base <- basename(file)
  lower <- tolower(base)
  for (ext in compound_extensions) {
    if (endsWith(lower, paste0(".", ext)) && nchar(lower) > nchar(ext) + 1) {
      return(substr(base, nchar(base) - nchar(ext) + 1, nchar(base)))
    }
  }
  tools::file_ext(base)
}

# `results.rds` with suffix `_component_131` is `results_component_131.rds`;
# a file without an extension keeps none. No suffix, no name.
suffix_file_name <- function(file, suffix, ext = file_extension(file)) {
  own <- file_extension(file)
  stem <- if (nzchar(own)) substr(file, 1, nchar(file) - nchar(own) - 1) else file
  paste0(stem, suffix, if (nzchar(ext)) paste0(".", ext) else "", recycle0 = TRUE)
}

component_file_names <- function(file, ids) {
  suffix_file_name(file, paste0("_component_", ids, recycle0 = TRUE))
}

metadata_file_name <- function(file) {
  suffix_file_name(file, "_metadata")
}

provenance_file_name <- function(file) {
  suffix_file_name(file, "_export", ext = "json")
}

refuse_existing <- function(files, overwrite, call = rlang::caller_env()) {
  if (length(files) == 0 || overwrite) {
    return(invisible(NULL))
  }
  existing <- files[file.exists(files)]
  if (length(existing) == 0) {
    return(invisible(NULL))
  }
  cli::cli_abort(
    c(
      "{.path {existing}} already exist{?s/}.",
      "i" = "{cli::qty(length(existing))}Set {.code overwrite = TRUE} to replace {?it/them}."
    ),
    call = call,
    class = "jatosr_file_exists"
  )
}

write_one_file <- function(x, file, format, object) {
  write_atomically(file, function(tmp) {
    switch(
      format,
      rds = saveRDS(x, tmp),
      csv = write_csv_file(x, tmp),
      `csv.gz` = write_csv_file(x, tmp, compress = TRUE),
      tsv = write_csv_file(x, tmp, sep = "\t"),
      parquet = arrow::write_parquet(prepare_parquet_columns(x), tmp),
      rdata = {
        env <- new.env(parent = emptyenv())
        assign(object, x, envir = env)
        save(list = object, envir = env, file = tmp)
      }
    )
  })
  invisible(file)
}

# csv, tsv and gzip-compressed csv share one writer: UTF-8, no row names,
# NA empty, quotes doubled, through a connection so that the compression
# and the encoding are the connection's business.
write_csv_file <- function(x, file, sep = ",", compress = FALSE) {
  out <- prepare_csv_columns(x)
  con <- if (compress) {
    gzfile(file, open = "w", encoding = "UTF-8")
  } else {
    file(file, open = "w", encoding = "UTF-8")
  }
  on.exit(close(con), add = TRUE)
  utils::write.table(out, con, sep = sep, row.names = FALSE, na = "", qmethod = "double")
}

prepare_csv_columns <- function(x) {
  out <- x
  serialised <- character()
  for (col in names(x)) {
    value <- x[[col]]
    if (inherits(value, "POSIXct")) {
      out[[col]] <- format(value, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    } else if (is.list(value)) {
      out[[col]] <- column_to_json(value)
      serialised <- c(serialised, col)
    }
  }
  inform_serialised(serialised)
  out
}

# arrow infers one type for a list column from its cells and refuses the
# column when a cell does not fit it (an object in one trial, a vector in
# the next: "Cannot convert to list type"). Such a column is written as
# JSON strings, the way csv writes every list column; a column arrow can
# type is left to arrow. The per-column probe uses the same converter as
# the table conversion, so what passes here passes `write_parquet()`.
prepare_parquet_columns <- function(x) {
  out <- x
  serialised <- character()
  for (col in names(x)) {
    value <- x[[col]]
    if (is.list(value) && !arrow_can_type(value)) {
      out[[col]] <- column_to_json(value)
      serialised <- c(serialised, col)
    }
  }
  inform_serialised(serialised, reason = "arrow cannot give {?it/them} one type")
  out
}

arrow_can_type <- function(value) {
  !inherits(tryCatch(arrow::as_arrow_array(value), error = function(e) e), "error")
}

# A nested data-frame column (`is.list()` too) becomes one JSON object per
# row; any other list column one JSON value per cell.
column_to_json <- function(value) {
  if (is.data.frame(value)) rows_to_json(value) else purrr::map_chr(value, cell_to_json)
}

inform_serialised <- function(serialised, reason = NULL) {
  if (length(serialised) == 0) {
    return(invisible(NULL))
  }
  n <- length(serialised)
  tail <- if (is.null(reason)) "." else paste0("; ", reason, ".")
  cli::cli_inform(c(
    "i" = paste0("{cli::qty(n)}Serialised the list column{?s} {.field {serialised}} to JSON strings", tail)
  ))
}

is_missing_cell <- function(cell) {
  is.null(cell) || (is.atomic(cell) && length(cell) == 1 && is.na(cell))
}

cell_to_json <- function(cell) {
  if (is_missing_cell(cell)) {
    return(NA_character_)
  }
  as.character(jsonlite::toJSON(cell, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
}

# A nested data-frame column (what jsonlite makes of an object that every
# trial of a file carries) becomes one JSON object per row; a row that the
# binding filled with NA becomes NA.
rows_to_json <- function(df) {
  if (nrow(df) == 0) {
    return(character())
  }
  # one jsonlite call for the whole column as an array of row objects,
  # split into rows by the reader's top-level splitter, in place of one
  # toJSON() per row (108 µs each); a row whose cells are all missing is NA
  missing <- Reduce(`&`, lapply(df, missing_cells))
  text <- as.character(jsonlite::toJSON(
    df,
    dataframe = "rows", auto_unbox = TRUE, null = "null", na = "null", digits = NA
  ))
  raw <- charToRaw(text)
  inner <- raw_as_utf8(raw[-c(1, length(raw))])
  values <- split_json_values(inner, separators = c(json_whitespace, as.raw(0x2c)))
  out <- vapply(values, raw_as_utf8, character(1))
  out[missing] <- NA_character_
  out
}

# Which cells of a column are missing: NA for an atomic column, NULL or a
# single NA for a list column, every cell missing for a nested data frame.
missing_cells <- function(col) {
  if (is.data.frame(col)) {
    if (ncol(col) == 0) rep(TRUE, nrow(col)) else Reduce(`&`, lapply(col, missing_cells))
  } else if (is.list(col)) {
    vapply(col, is_missing_cell, logical(1))
  } else {
    is.na(col)
  }
}
