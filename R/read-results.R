#' Read one jsPsych result file
#'
#' Parses a `data.txt` written by jsPsych (a JSON array of trial objects)
#' into a tibble with one row per trial. A file that holds several JSON
#' values back to back, which is what repeated `jatos.appendResultData()`
#' calls leave behind (arrays after arrays, or one object per call), is
#' split into its top-level values first and read as one array. An empty
#' file gives a tibble with no rows and no columns.
#'
#' @param file Path of the file.
#' @param flatten If `TRUE`, nested objects become columns named
#'   `outer.inner` (see `jsonlite::fromJSON()`); otherwise they stay nested
#'   data-frame columns when every trial of the file carries the same
#'   object, and list columns otherwise. [jatos_read_results()] stores both
#'   as list columns before it binds files.
#'
#' @return A tibble. A key that is the empty string (an unnamed form input)
#'   becomes a column `unnamed_<position>`.
#' @seealso [jatos_read_results()] to read every file of a metadata tibble.
#' @export
#' @examples
#' file <- system.file("extdata", "data.txt", package = "jatosr")
#' trials <- jatos_read_json(file)
#' trials[, c("trial_index", "trial_type", "rt", "correct")]
#' jatos_read_json(file, flatten = TRUE)[1, ]
jatos_read_json <- function(file, flatten = FALSE) {
  check_string(file)
  check_flag(flatten)
  check_path_exists(file)
  text <- read_text_file(file)
  if (!grepl("\\S", text)) {
    return(tibble::tibble())
  }
  parsed <- parse_json_text(text, flatten = flatten, file = file)
  if (is.data.frame(parsed)) {
    return(tibble::as_tibble(parsed, .name_repair = repair_json_names))
  }
  if (length(parsed) == 0) {
    return(tibble::tibble())
  }
  cli::cli_abort(c(
    "{.path {file}} is not an array of objects.",
    "i" = "Pass a {.arg reader} to {.fn jatos_read_results}, or use {.fn jsonlite::fromJSON} directly, for other layouts."
  ))
}

# The one parser for result files: every top-level JSON value of the text
# (one array, several arrays, bare objects) is read as one array. A text
# that is not a sequence of complete values goes to jsonlite as it is, so
# the error is jsonlite's; the parser message may hold braces and is passed
# as a value.
parse_json_text <- function(text, flatten, file) {
  tryCatch(
    parse_result_json(text, flatten = flatten),
    error = function(e) {
      reason <- conditionMessage(e)
      cli::cli_abort(
        c("{.path {file}} is not valid JSON.", "x" = "{reason}"),
        parent = NA
      )
    }
  )
}

# Parse a result text as one array of its top-level values. With
# `simplify = FALSE` the elements come back as lists (the extractor's
# cross-check); otherwise as a data frame, jsonlite's default shape.
#
# A text that starts with `[` goes to jsonlite as it is first: one clean
# array is what nearly every file holds, and splitting it into bytes and
# rebuilding it cost twelve times the parse (0.41 s against 0.03 s on a
# 2.8 MB file of 20,000 trials, 2026-09-14). Only a text jsonlite refuses
# (arrays back to back, an object first) is split; when the splitter
# refuses it too, jsonlite's error on the original text is the error.
parse_result_json <- function(text, flatten = FALSE, simplify = TRUE) {
  parse <- function(json) jsonlite::fromJSON(json, flatten = flatten, simplifyVector = simplify)
  if (grepl("^\\s*\\[", text, perl = TRUE, useBytes = TRUE)) {
    first <- tryCatch(parse(text), error = function(e) e)
    if (!inherits(first, "error")) {
      return(first)
    }
    joined <- join_json_values(text)
    if (is.null(joined)) {
      stop(first)
    }
    return(parse(joined))
  }
  parse(join_json_values(text) %||% text)
}

# The top-level values of a JSON text as one array text, or NULL when the
# text is not a clean sequence of complete arrays and objects (a truncated
# file, a scalar, text between the values): the caller then hands the
# original text to jsonlite for the error.
join_json_values <- function(text) {
  values <- split_json_values(text)
  if (is.null(values) || length(values) == 0) {
    return(NULL)
  }
  inner <- lapply(values, function(v) {
    if (v[[1]] == as.raw(0x5b)) v[-c(1, length(v))] else v
  })
  inner <- inner[vapply(inner, function(v) any(!v %in% json_whitespace), logical(1))]
  parts <- vapply(inner, raw_as_utf8, character(1))
  paste0("[", paste(parts, collapse = ","), "]")
}

json_whitespace <- as.raw(c(0x20, 0x09, 0x0a, 0x0d))

# Split a JSON text into its top-level arrays and objects, as raw vectors.
# Works on bytes: the structural characters are ASCII, so multibyte UTF-8
# never collides with them. String state comes from the unescaped quotes
# (a quote after an odd run of backslashes is escaped), so a `][` or a `}{`
# inside a string value does not count; the bracket depth of the remaining
# brackets marks where each value starts and ends. NULL when brackets do
# not balance or when anything but `separators` (whitespace; the csv
# writer adds the comma to split the inside of an array) sits between
# the values.
split_json_values <- function(text, separators = json_whitespace) {
  raw <- charToRaw(text)
  n <- length(raw)
  if (n == 0) {
    return(list())
  }
  # backslashes: the length of the run that ends right before each position
  is_backslash <- raw == as.raw(0x5c)
  runs <- rle(is_backslash)
  run_ends <- cumsum(runs$lengths)
  run_before <- integer(n)
  after <- run_ends[runs$values] + 1L
  keep <- after <= n
  run_before[after[keep]] <- runs$lengths[runs$values][keep]
  quotes <- which(raw == as.raw(0x22))
  real_quotes <- quotes[run_before[quotes] %% 2L == 0L]

  brackets <- which(raw %in% as.raw(c(0x5b, 0x5d, 0x7b, 0x7d)))
  in_string <- findInterval(brackets, real_quotes) %% 2L == 1L
  brackets <- brackets[!in_string]
  if (length(brackets) == 0) {
    return(NULL)
  }
  delta <- ifelse(raw[brackets] %in% as.raw(c(0x5b, 0x7b)), 1L, -1L)
  depth <- cumsum(delta)
  if (any(depth < 0) || depth[[length(depth)]] != 0L) {
    return(NULL)
  }
  before <- c(0L, depth[-length(depth)])
  starts <- brackets[delta == 1L & before == 0L]
  ends <- brackets[depth == 0L]
  if (length(starts) != length(ends)) {
    return(NULL)
  }
  covered <- logical(n)
  for (k in seq_along(starts)) {
    covered[starts[[k]]:ends[[k]]] <- TRUE
  }
  if (any(!raw[!covered] %in% separators)) {
    return(NULL)
  }
  purrr::map2(starts, ends, function(s, e) raw[s:e])
}

raw_as_utf8 <- function(x) {
  out <- rawToChar(x)
  Encoding(out) <- "UTF-8"
  out
}

# A JSON key may be the empty string (an unnamed form input in a survey
# plugin writes one), which a tibble column may not be: such a column is
# named `unnamed_<position>`; a key repeated within one object gets a
# numeric suffix. Seen on real data (2026-09-06).
repair_json_names <- function(names) {
  empty <- is.na(names) | !nzchar(names)
  names[empty] <- paste0("unnamed_", which(empty))
  make.unique(names, sep = "_")
}

#' Read the result files of a metadata tibble into one tibble
#'
#' Reads every local `data.txt` listed in `metadata` with
#' [jatos_read_json()] (or with `reader`) and binds the trials of all files,
#' filling columns that some files lack with `NA`. Columns of the metadata
#' are joined to each file's trials, so that every row knows which study
#' result and component result it came from and carries the batch,
#' component, worker and study state of that run: first `id_cols`, then
#' `metadata_cols`, then the trial columns. The join costs nothing to look
#' up, since one metadata row is one file.
#'
#' A nested object in the trials (a survey `response`, say) comes out of
#' `jsonlite` as a data-frame column in a file where every trial carries an
#' object with the same keys, and as a list column in a file where the
#' objects differ, so two files of the same component can disagree on the
#' column's type. Before binding, every nested data-frame column is
#' therefore stored as a list column, one list per trial with the keys that
#' trial had (`NULL` where the trial had no object); a message names the
#' columns. A column whose *atomic* type differs between files (a number
#' in one file, a string in another) is an error naming the column; with
#' `coerce = "character"` such columns are converted to character in every
#' file, with a message, and the bind goes on.
#'
#' A trial column that has the same name as a joined metadata column is an
#' error naming the column and the file; nothing is renamed or suffixed.
#' That happens, for example, when the experiment stored `worker_id` in the
#' data itself, or when a field extracted with [jatos_extract_fields()] is
#' named in `metadata_cols` although it is a top-level field of every
#' trial already (the usual case for a `participant_id` set with
#' `jsPsych.data.addProperties()`). Leave such a column out of
#' `metadata_cols`; the trials carry it.
#'
#' Result files that are not jsPsych JSON arrays (PsychoJS csv, OSWeb or
#' lab.js output) are read with a `reader` of your own, a function that
#' takes one file path and returns a data frame; the join and the binding
#' are the same. A study whose components write different columns is read
#' with `split = "component"`, one tibble per component, which also keeps a
#' column that changes type between components from blocking the bind.
#'
#' @param metadata A metadata tibble with a `file` column (from
#'   [jatos_download_results()] or [jatos_read_metadata()]), or a character
#'   vector of file paths. Of a metadata tibble only `file` and the columns
#'   named in `id_cols`, `metadata_cols` and, for the split, `component_id`
#'   are used.
#' @param ... Must be empty.
#' @param flatten Passed to [jatos_read_json()]; ignored with a `reader`.
#' @param id_cols Columns of `metadata` to prepend to each file's trials.
#'   Ignored when `metadata` is a character vector; the file path is then
#'   prepended as `file`.
#' @param metadata_cols Further columns of `metadata` to join after
#'   `id_cols`, for example a field added by [jatos_extract_fields()] that is
#'   not a trial column. `NULL` joins the id columns only. Ignored when
#'   `metadata` is a character vector.
#' @param reader `NULL` for [jatos_read_json()], or a function of one file
#'   path returning a data frame with one row per trial.
#' @param on_error `"abort"` stops at the first file the reader cannot read.
#'   `"skip"` leaves such files out, reads the rest, and warns once with
#'   the files and the first error; a clash between trial and metadata
#'   columns still aborts.
#' @param split `"none"` returns one tibble. `"component"` returns a named
#'   list with one tibble per distinct `component_id` of `metadata`, in the
#'   order the ids first appear; needs a metadata tibble.
#' @param coerce What to do with a column whose atomic type differs between
#'   files: `"error"` stops with the column named; `"character"` converts
#'   that column to character in every file and reports it.
#'
#' @return A tibble with one row per trial, or with `split = "component"`
#'   a named list of such tibbles. Rows of `metadata` without a local file
#'   are left out with a message.
#' @seealso [jatos_write_results()] to save the tibble,
#'   [jatos_export_results()] for the whole pipeline in one call.
#' @export
#' @examples
#' cache <- system.file("extdata", "JATOS_data", package = "jatosr")
#' meta <- jatos_read_metadata(cache)
#' trials <- jatos_read_results(meta[meta$component_state == "FINISHED", ])
#'
#' # a field that sits inside a survey response, not at the trial level
#' meta <- jatos_extract_fields(meta, "age")
#' trials <- jatos_read_results(meta, metadata_cols = c("worker_id", "age"))
#' trials[, c("study_result_id", "worker_id", "age", "trial_index", "rt")]
#'
#' # one tibble per component
#' parts <- jatos_read_results(meta, split = "component")
#' names(parts)
#'
#' # PsychoJS writes csv, read with a reader of your own:
#' # trials <- jatos_read_results(meta, reader = function(file) utils::read.csv(file))
jatos_read_results <- function(metadata,
                               ...,
                               flatten = FALSE,
                               id_cols = c("study_result_id", "component_result_id"),
                               metadata_cols = default_metadata_cols(),
                               reader = NULL,
                               on_error = c("abort", "skip"),
                               split = c("none", "component"),
                               coerce = c("error", "character")) {
  rlang::check_dots_empty()
  check_flag(flatten)
  check_column_names(id_cols)
  check_column_names(metadata_cols, allow_null = TRUE)
  on_error <- rlang::arg_match(on_error)
  split <- rlang::arg_match(split)
  coerce <- rlang::arg_match(coerce)
  read_one <- if (is.null(reader)) {
    function(file) jatos_read_json(file, flatten = flatten)
  } else {
    check_reader(reader)
  }

  if (is.character(metadata)) {
    if (split == "component") {
      cli::cli_abort("{.code split = \"component\"} needs a metadata tibble with {.field component_id}, not file paths.", class = "jatosr_bad_argument")
    }
    files <- metadata
    ids <- tibble::tibble(file = metadata)
  } else {
    join_cols <- unique(c(id_cols, metadata_cols))
    needs <- c("file", join_cols, if (split == "component") "component_id")
    check_metadata(metadata, needs = unique(needs), contract = FALSE)
    files <- metadata$file
    ids <- tibble::as_tibble(metadata[, join_cols, drop = FALSE])
  }
  have <- !is.na(files)
  if (any(!have)) {
    cli::cli_inform(c("i" = "{sum(!have)} row{?s} {?has/have} no local file."))
  }
  rows <- which(have)
  # a loop, not purrr::map(), so that a reader or shadowing error reaches
  # the user without an "In index" wrapper
  parts <- vector("list", length(rows))
  skipped <- character()
  first_error <- NULL
  for (k in seq_along(rows)) {
    i <- rows[[k]]
    trials <- if (on_error == "abort") {
      read_one(files[[i]])
    } else {
      tryCatch(read_one(files[[i]]), error = function(cnd) cnd)
    }
    if (rlang::is_condition(trials)) {
      skipped <- c(skipped, files[[i]])
      first_error <- first_error %||% conditionMessage(trials)
      parts[k] <- list(tibble::tibble())
      next
    }
    trials <- check_reader_output(trials, files[[i]], reader)
    if (nrow(trials) > 0) {
      check_no_shadowing(trials, names(ids), files[[i]])
    }
    parts[[k]] <- trials
  }
  if (length(skipped) > 0) {
    cli::cli_warn(
      c(
        "{length(skipped)} file{?s} could not be read and {?was/were} skipped.",
        "x" = "First error: {first_error}",
        "i" = "{cli::qty(length(skipped))}File{?s}: {.path {skipped}}"
      ),
      class = "jatosr_files_skipped",
      files = skipped
    )
  }
  if (split == "component") {
    component <- metadata$component_id[rows]
    groups <- split(seq_along(parts), factor(component, levels = unique(component)))
    return(purrr::map(groups, function(g) bind_trials(parts[g], ids[rows[g], , drop = FALSE], coerce = coerce)))
  }
  bind_trials(parts, ids[rows, , drop = FALSE], coerce = coerce)
}

# The metadata columns joined to the trials by default, shared with
# jatos_export_results().
default_metadata_cols <- function() {
  c("batch_id", "component_id", "worker_id", "worker_type", "study_state", "study_start_time")
}

check_reader <- function(reader, call = rlang::caller_env()) {
  if (!is.function(reader)) {
    cli::cli_abort(
      "{.arg reader} must be a function of one file path that returns a data frame.",
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  reader
}

check_reader_output <- function(trials, file, reader, call = rlang::caller_env()) {
  if (!is.data.frame(trials)) {
    cli::cli_abort(
      c(
        "{.arg reader} returned {.obj_type_friendly {trials}} for {.path {file}}.",
        "i" = "It must return a data frame with one row per trial."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  tibble::as_tibble(trials)
}

check_no_shadowing <- function(trials, join_cols, file, call = rlang::caller_env()) {
  clash <- intersect(names(trials), join_cols)
  if (length(clash) == 0) {
    return(invisible(NULL))
  }
  cli::cli_abort(
    c(
      "{cli::qty(length(clash))}The trials of {.path {file}} already carry the column{?s} {.field {clash}}, which the metadata would overwrite.",
      "i" = "{cli::qty(length(clash))}Leave {?it/them} out of {.arg metadata_cols} (or {.arg id_cols}), or rename the metadata column{?s} before reading."
    ),
    call = call,
    class = "jatosr_bad_argument"
  )
}

# Bind the trials of several files and prepend the join columns once:
# `ids` has one row per part, repeated by that part's row count after the
# bind (one tibble per file cost 6.9 s for 9,000 files before).
bind_trials <- function(parts, ids, coerce = "error", call = rlang::caller_env()) {
  parts <- normalise_nested_columns(parts)
  n_rows <- vapply(parts, nrow, integer(1))
  bound <- bind_parts(parts, coerce = coerce, call = call)
  keys <- ids[rep(seq_len(nrow(ids)), n_rows), , drop = FALSE]
  tibble::tibble(!!!keys, bound)
}

# A nested data-frame column (an object with the same keys in every trial
# of a file) becomes a list column, one named list per trial without its
# NA entries, NULL for a trial that had no object; that is the shape
# jsonlite gives the same column in a file where the objects differ, so
# files of one component bind whatever mix they hold.
normalise_nested_columns <- function(parts) {
  converted <- character()
  for (k in seq_along(parts)) {
    part <- parts[[k]]
    nested <- names(part)[vapply(part, is.data.frame, logical(1))]
    for (col in nested) {
      part[[col]] <- df_rows_as_lists(part[[col]])
    }
    converted <- c(converted, nested)
    parts[[k]] <- part
  }
  converted <- unique(converted)
  if (length(converted) > 0) {
    cli::cli_inform(c(
      "i" = "{cli::qty(length(converted))}Stored the nested object column{?s} {.field {converted}} as list column{?s}, one list per trial."
    ))
  }
  parts
}

df_rows_as_lists <- function(df) {
  if (ncol(df) == 0) {
    # an object without keys in every trial: nothing to keep per row
    return(rep(list(NULL), nrow(df)))
  }
  # The keep mask is computed per column (vectorised), both transposes run
  # in C (.mapply), and the per-row work is one logical subset: 1.2 s for
  # 200,000 rows against 8.5 s with a per-row vapply() (2026-09-06).
  cols <- lapply(df, function(col) if (is.data.frame(col)) df_rows_as_lists(col) else as.list(col))
  keep <- lapply(seq_along(cols), function(j) {
    col <- df[[j]]
    if (is.data.frame(col)) {
      !vapply(cols[[j]], is.null, logical(1))
    } else if (is.list(col)) {
      !vapply(col, is_missing_cell, logical(1))
    } else {
      !is.na(col)
    }
  })
  rows <- .mapply(list, cols, NULL)
  keeps <- .mapply(c, keep, NULL)
  nms <- names(df)
  Map(function(row, k) {
    names(row) <- nms
    row <- row[k]
    if (length(row) == 0) NULL else row
  }, rows, keeps)
}

# purrr::list_rbind() with vctrs' type check; on a conflict, either the
# error naming the column, or (coerce = "character") the conflicting atomic
# columns converted to character everywhere and one more attempt.
bind_parts <- function(parts, coerce, call = rlang::caller_env()) {
  tryCatch(
    purrr::list_rbind(parts),
    vctrs_error_incompatible_type = function(e) {
      if (coerce == "character") {
        conflicting <- conflicting_columns(parts)
        if (length(conflicting) > 0) {
          cli::cli_inform(c(
            "i" = "{cli::qty(length(conflicting))}Coerced the column{?s} {.field {conflicting}} to character; the files disagreed on {?its/their} type."
          ))
          parts <- lapply(parts, function(part) {
            for (col in intersect(conflicting, names(part))) {
              part[[col]] <- as.character(part[[col]])
            }
            part
          })
          return(bind_parts(parts, coerce = "error", call = call))
        }
      }
      reason <- conditionMessage(e)
      cli::cli_abort(
        c(
          "The files disagree on a column's type, so their trials cannot be combined.",
          "x" = "{reason}",
          "i" = "Read with {.code coerce = \"character\"} to convert such columns to text, or with {.code split = \"component\"} when components differ."
        ),
        parent = NA,
        call = call
      )
    }
  )
}

# Atomic columns whose type family differs between parts: numbers (logical,
# integer, double) against strings. A logical column that is NA throughout
# (jsonlite's null) belongs to no family; a list column cannot be coerced
# and is left to the error.
conflicting_columns <- function(parts) {
  families <- list()
  for (part in parts) {
    for (col in names(part)) {
      fam <- type_family(part[[col]])
      if (!is.na(fam)) {
        families[[col]] <- union(families[[col]], fam)
      }
    }
  }
  atomic <- vapply(families, function(f) all(f %in% c("number", "character")), logical(1))
  names(families)[atomic & lengths(families) > 1]
}

type_family <- function(x) {
  if (is.data.frame(x) || is.list(x)) {
    return("list")
  }
  if (is.logical(x) && all(is.na(x))) {
    return(NA_character_)
  }
  if (is.character(x)) {
    return("character")
  }
  if (is.numeric(x) || is.logical(x)) {
    return("number")
  }
  class(x)[[1]]
}
