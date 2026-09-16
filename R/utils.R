`%||%` <- rlang::`%||%`

check_string <- function(x,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  if (!rlang::is_string(x) || is.na(x) || !nzchar(x)) {
    cli::cli_abort("{.arg {arg}} must be a single non-empty string.", call = call, class = "jatosr_bad_argument")
  }
  invisible(x)
}

check_flag <- function(x,
                       arg = rlang::caller_arg(x),
                       call = rlang::caller_env()) {
  if (!rlang::is_bool(x)) {
    cli::cli_abort("{.arg {arg}} must be `TRUE` or `FALSE`.", call = call, class = "jatosr_bad_argument")
  }
  invisible(x)
}

check_ids <- function(x,
                      arg = rlang::caller_arg(x),
                      call = rlang::caller_env(),
                      allow_null = FALSE) {
  if (is.null(x)) {
    if (allow_null) {
      return(invisible(NULL))
    }
    cli::cli_abort("{.arg {arg}} must not be `NULL`.", call = call, class = "jatosr_bad_argument")
  }
  ok <- (is.numeric(x) || is.character(x)) && length(x) >= 1 && !anyNA(x)
  if (ok && is.character(x)) {
    ok <- all(grepl("^[0-9]+$", x))
  }
  if (ok && is.numeric(x)) {
    ok <- all(x == trunc(x)) && all(x > 0)
  }
  if (!ok) {
    cli::cli_abort(
      "{.arg {arg}} must be one or more positive integer ids without missing values.",
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  invisible(as.integer(x))
}

# Ids or uuids for the /results endpoints, which take `<name>Ids` and
# `<name>Uuids` as separate body fields: one or more positive integer ids, or
# one or more uuid strings (the `uuid_pattern` of studies.R), never both in
# one argument. Returns `ids` (integer) or `uuids` (character), the other
# NULL; both NULL for a NULL argument.
check_ids_or_uuids <- function(x,
                               arg = rlang::caller_arg(x),
                               call = rlang::caller_env()) {
  none <- list(ids = NULL, uuids = NULL)
  if (is.null(x)) {
    return(none)
  }
  if (is.character(x) && length(x) >= 1 && !anyNA(x)) {
    is_uuid <- grepl(uuid_pattern, x)
    if (all(is_uuid)) {
      return(list(ids = NULL, uuids = x))
    }
    if (any(is_uuid)) {
      cli::cli_abort(
        c(
          "{.arg {arg}} mixes ids and uuids.",
          "i" = "Give either integer ids or uuid strings in one call; the server takes them in separate fields."
        ),
        call = call,
        class = "jatosr_bad_argument"
      )
    }
  }
  ids <- check_ids(x, arg = arg, call = call)
  list(ids = ids, uuids = NULL)
}

check_id <- function(x,
                     arg = rlang::caller_arg(x),
                     call = rlang::caller_env()) {
  check_ids(x, arg = arg, call = call)
  if (length(x) != 1) {
    cli::cli_abort("{.arg {arg}} must be a single id.", call = call, class = "jatosr_bad_argument")
  }
  invisible(as.integer(x))
}

# A single whole number, positive by default, with an optional upper bound.
check_count <- function(x,
                        arg = rlang::caller_arg(x),
                        call = rlang::caller_env(),
                        allow_zero = FALSE,
                        max = NULL) {
  lowest <- if (allow_zero) 0 else 1
  what <- if (allow_zero) "a single non-negative integer" else "a single positive integer"
  if (!rlang::is_scalar_integerish(x) || is.na(x) || x < lowest) {
    cli::cli_abort("{.arg {arg}} must be {what}.", call = call, class = "jatosr_bad_argument")
  }
  if (!is.null(max) && x > max) {
    cli::cli_abort("{.arg {arg}} must be at most {max}, got {x}.", call = call, class = "jatosr_bad_argument")
  }
  invisible(as.integer(x))
}

# A character vector of names: non-empty strings without missing values.
check_column_names <- function(x,
                               allow_null = FALSE,
                               what = "column names",
                               arg = rlang::caller_arg(x),
                               call = rlang::caller_env()) {
  if (is.null(x) && allow_null) {
    return(invisible(NULL))
  }
  if (!is.character(x) || length(x) == 0 || anyNA(x) || !all(nzchar(x))) {
    cli::cli_abort("{.arg {arg}} must be a character vector of {what}.", call = call, class = "jatosr_bad_argument")
  }
  invisible(x)
}

drop_null <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}

# Text that was already rendered (or comes from outside) and goes back into
# a cli template as a bullet: braces are doubled so cli shows them as text.
cli_literal <- function(x) {
  gsub("([{}])", "\\1\\1", x)
}

# Bytes as a short human-readable string, for messages only.
format_bytes <- function(x) {
  units <- c("B", "kB", "MB", "GB", "TB")
  x <- as.numeric(x)
  power <- ifelse(x > 0, floor(log10(x) / 3), 0)
  power <- pmin(pmax(power, 0), length(units) - 1)
  value <- x / 1000^power
  digits <- ifelse(power == 0, 0, 1)
  text <- vapply(
    seq_along(x),
    function(i) formatC(value[[i]], format = "f", digits = digits[[i]], big.mark = ","),
    character(1)
  )
  paste(text, units[power + 1])
}

# The metadata contract is by column name. These columns are what every
# downstream rule keys on; callers add `needs` for anything else they use.
metadata_required_columns <- function() {
  c(
    "study_result_id", "component_result_id", "component_id", "batch_id",
    "component_state", "data_size"
  )
}

# `contract = FALSE` checks only the columns in `needs`, for a function that
# uses nothing else of the metadata (the reader touches `file` and the
# columns it joins).
check_metadata <- function(x,
                           needs = NULL,
                           contract = TRUE,
                           arg = rlang::caller_arg(x),
                           call = rlang::caller_env()) {
  if (!is.data.frame(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a data frame of result metadata, as returned by {.fn jatos_results_metadata}.",
        "i" = "A parsed {.code /results/metadata} answer becomes that tibble with {.fn jatos_flatten_metadata}."
      ),
      call = call,
      class = "jatosr_bad_metadata"
    )
  }
  required <- if (contract) metadata_required_columns() else character()
  missing <- setdiff(c(required, needs), names(x))
  if (length(missing) > 0) {
    cli::cli_abort(
      c(
        "{.arg {arg}} lacks the metadata column{?s} {.field {missing}}.",
        "i" = "Metadata tibbles come from {.fn jatos_results_metadata}, {.fn jatos_read_metadata} or {.fn jatos_flatten_metadata}."
      ),
      call = call,
      class = "jatosr_bad_metadata"
    )
  }
  # An id that is NA cannot be planned, requested or placed on disk: refuse
  # it here rather than let a row fall out of the chunks silently.
  id_cols <- intersect(metadata_id_columns(), c(required, needs))
  for (col in id_cols) {
    rows <- which(is.na(x[[col]]))
    if (length(rows) > 0) {
      cli::cli_abort(
        c(
          "{.arg {arg}} has {.code NA} in {.field {col}} in {cli::qty(length(rows))}row{?s} {rows}.",
          "i" = "Every study result, component result and batch id must be known; drop or fix {cli::qty(length(rows))}{?that row/those rows} first."
        ),
        call = call,
        class = "jatosr_bad_metadata"
      )
    }
  }
  invisible(x)
}

metadata_id_columns <- function() {
  c("study_result_id", "component_result_id", "batch_id")
}

check_path_exists <- function(path, arg = rlang::caller_arg(path), call = rlang::caller_env()) {
  if (!file.exists(path)) {
    cli::cli_abort("{.path {path}} does not exist.", call = call, class = "jatosr_bad_argument")
  }
  invisible(path)
}

snake_case <- function(x) {
  x <- gsub("([a-z0-9])([A-Z])", "\\1_\\2", x)
  tolower(x)
}

# Pull one scalar field out of a parsed JSON list, with a typed NA fallback.
# JSON null arrives as NULL (or as an empty list from some serialisers), and
# a field that is not a scalar must never leak into a tibble column.
pluck_scalar <- function(x, ..., na) {
  value <- purrr::pluck(x, ...)
  if (is.null(value) || length(value) == 0) {
    return(na)
  }
  if (is.list(value)) {
    value <- unlist(value, use.names = FALSE)
  }
  if (length(value) != 1) {
    return(na)
  }
  value
}

pluck_chr <- function(x, ...) {
  value <- pluck_scalar(x, ..., na = NA_character_)
  as.character(value)
}

pluck_int <- function(x, ...) {
  value <- pluck_scalar(x, ..., na = NA_integer_)
  as.integer(value)
}

pluck_lgl <- function(x, ...) {
  value <- pluck_scalar(x, ..., na = NA)
  as.logical(value)
}

pluck_dbl <- function(x, ...) {
  value <- pluck_scalar(x, ..., na = NA_real_)
  as.numeric(value)
}

# JATOS reports times as milliseconds since the epoch. `x` is a list of
# scalars or NULLs.
ms_to_posixct <- function(x) {
  ms <- vapply(
    x,
    function(v) if (is.null(v) || length(v) != 1 || is.na(v)) NA_real_ else as.numeric(v),
    numeric(1)
  )
  as.POSIXct(ms / 1000, origin = "1970-01-01", tz = "UTC")
}

# One epoch-millisecond field of a parsed JSON object as a length-one POSIXct.
pluck_time <- function(x, ...) {
  ms_to_posixct(list(purrr::pluck(x, ...)))
}
