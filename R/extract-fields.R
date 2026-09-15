#' Extract scalar fields from result files without parsing them
#'
#' Reads one or more JSON keys (for example `participant_id`) out of every
#' downloaded `data.txt` by regular expression, which is several times faster
#' than parsing each file and works on files that are not valid JSON as a
#' whole. The pattern is anchored on the key position (`"field":`), so the
#' same text inside a value, say a URL query string, is not matched. All
#' key-position occurrences are collected, at any depth of the JSON: when
#' they agree the value is returned; when they disagree the value is `NA`
#' and the row is flagged.
#'
#' Every file where the regular expression found disagreeing values (status
#' `conflict`) is then parsed in full with the same parser
#' [jatos_read_json()] uses, every value stored under the key at any depth
#' is collected from the parsed objects, and the two readings are compared;
#' so is every file without the key (status `absent`) as long as the key was
#' found in some other file, since a key present in one file and missing
#' in the next may be an escaped spelling the regular expression does not
#' see. On a file with one agreeing value the regular expression cannot be
#' wrong, so those files are not parsed, and a key found in no file at all
#' is reported `absent` everywhere without parsing (read one file with
#' [jatos_read_json()] when that is a surprise). A disagreement means the
#' regular expression read a file differently from the parser (an escaped
#' key, an unusual encoding) and is a warning naming the files; a message
#' reports the tally. A file the parser refuses gets status `unparseable`,
#' which means exactly that [jatos_read_results()] would stop on it.
#'
#' A field whose name is already a column of `metadata` (`batch_id`,
#' `worker_id`, `file`, ...) is refused before any file is read, since the
#' extracted values would silently replace the server's. The two columns
#' of a previous extraction of the same field are replaced; which columns
#' came from an extraction is recorded in the attribute
#' `jatosr_extracted` of the returned tibble, so a column pair of your own
#' that happens to end in `_status` is never mistaken for one.
#'
#' @param metadata A metadata tibble with the local file column (from
#'   [jatos_download_results()] or [jatos_read_metadata()]).
#' @param fields Character vector of key names to extract.
#' @param warn If `FALSE`, the closing warnings (`conflict` and `unparseable`
#'   files, disagreements with the parser) are not raised; the status
#'   columns still say it all. Files without the key (`absent`) are reported
#'   in a message either way, since a key that only some components carry
#'   is not a fault.
#' @param file_col Name of the column holding the local file paths.
#'
#' @return `metadata` with two columns per field: `<field>` and
#'   `<field>_status`, and the attribute `jatosr_extracted` naming every
#'   extracted field. The value column is numeric when every value is a JSON
#'   number, logical when every value is `true` or `false`, character
#'   otherwise; JSON `null` is `NA`. The status is `unique` (all occurrences
#'   agree), `absent` (no occurrence), `conflict` (occurrences disagree, or an
#'   occurrence holds an array or object), or `unparseable` (the file has no
#'   unique value and the parser could not read it). Rows without a local
#'   file get `NA` in both columns.
#' @seealso [jatos_study_results()], which carries the value columns to the
#'   study-result level and flags component results that disagree.
#' @export
#' @examples
#' cache <- system.file("extdata", "JATOS_data", package = "jatosr")
#' meta <- jatos_read_metadata(cache)
#' meta <- jatos_extract_fields(meta, c("participant_id", "age"))
#' meta[, c("study_result_id", "participant_id", "participant_id_status", "age")]
jatos_extract_fields <- function(metadata,
                                 fields,
                                 warn = TRUE,
                                 file_col = "file") {
  check_string(file_col)
  check_metadata(metadata, needs = file_col)
  check_fields(fields)
  check_flag(warn)
  check_field_clash(fields, metadata)

  files <- metadata[[file_col]]
  readable <- !is.na(files) & file.exists(files)
  idx <- which(readable)

  # First pass, one file at a time: the occurrences of every field.
  occurrences <- purrr::map(rlang::set_names(fields), function(field) vector("list", length(files)))
  for (i in idx) {
    text <- read_text_file(files[[i]])
    for (field in fields) {
      occurrences[[field]][[i]] <- extract_field_occurrences(text, field)
    }
  }
  extracted <- purrr::map(occurrences, summarise_occurrences)

  # Second pass over exactly the files that need it: the conflict files of
  # every field, and its absent files when some file yielded a value (a key
  # found nowhere is taken as absent, not parsed everywhere). Deterministic,
  # no sample, no RNG.
  to_check <- sort(unique(unlist(purrr::map(extracted, files_to_cross_check))))
  if (length(to_check) > 0) {
    parsed <- purrr::map(to_check, function(i) parse_for_check(read_text_file(files[[i]])))
    for (field in fields) {
      extracted[[field]] <- cross_check_field(
        extracted[[field]], field, to_check, parsed,
        ids = metadata$component_result_id, warn = warn
      )
    }
    n_bad <- sum(vapply(parsed, is.null, logical(1)))
    cli::cli_inform(c(
      "i" = "Cross-checked {length(to_check)} file{?s} without a unique value with jsonlite: {length(to_check) - n_bad} parsed, {n_bad} unparseable."
    ))
  }

  out <- metadata
  for (field in fields) {
    out[[field]] <- extracted[[field]]$value
    out[[paste0(field, "_status")]] <- extracted[[field]]$status
  }
  attr(out, "jatosr_extracted") <- union(extracted_fields(metadata), fields)
  report_field_status(extracted, metadata$component_result_id, warn = warn)
  out
}

# The row indices one field's cross-check parses: see the roxygen above.
files_to_cross_check <- function(extracted) {
  status <- extracted$status
  # a conflict file found the key too, with disagreeing values
  found_somewhere <- any(status %in% c("unique", "conflict"))
  which(status == "conflict" | (found_somewhere & status == "absent"))
}

check_fields <- function(fields, arg = rlang::caller_arg(fields), call = rlang::caller_env()) {
  check_column_names(fields, what = "JSON key names", arg = arg, call = call)
  if (anyDuplicated(fields)) {
    cli::cli_abort("{.arg {arg}} must not repeat a key name.", call = call, class = "jatosr_bad_argument")
  }
  shadowed <- fields[paste0(fields, "_status") %in% fields]
  if (length(shadowed) > 0) {
    cli::cli_abort(
      c(
        "{.arg {arg}} names both {.val {shadowed}} and {.val {paste0(shadowed, '_status')}}.",
        "i" = "{.field <field>_status} is the status column of {.field <field>}; the second would overwrite the first."
      ),
      call = call,
      class = "jatosr_bad_argument"
    )
  }
  invisible(fields)
}

# The fields a previous jatos_extract_fields() call recorded on the tibble.
extracted_fields <- function(x) {
  fields <- attr(x, "jatosr_extracted", exact = TRUE)
  if (is.character(fields)) fields else character()
}

# Refuse a field whose value or status column already exists in the
# metadata, unless the pair was recorded as a previous extraction, which
# is being redone. A user's own `payment` / `payment_status` pair is
# therefore refused, not overwritten.
check_field_clash <- function(fields, metadata, call = rlang::caller_env()) {
  status_cols <- paste0(fields, "_status")
  previous <- fields %in% extracted_fields(metadata) &
    fields %in% names(metadata) & status_cols %in% names(metadata)
  taken <- c(fields[!previous], status_cols[!previous])
  clash <- intersect(taken, names(metadata))
  if (length(clash) == 0) {
    return(invisible(NULL))
  }
  cli::cli_abort(
    c(
      "{.arg fields} would overwrite the column{?s} {.field {clash}} of {.arg metadata}.",
      "i" = "Extracted values are stored under the field name; choose a key that is not a metadata column."
    ),
    call = call,
    class = "jatosr_bad_argument"
  )
}

# The whole file as one UTF-8 string. Read as bytes: readChar() stopped at
# an embedded NUL with a bare "truncating string" warning and handed back
# the part before it, so the rest of a corrupt file was lost without its
# name being said. A NUL is an error naming the file and the byte.
read_text_file <- function(path, call = rlang::caller_env()) {
  size <- file.size(path)
  if (is.na(size) || size == 0) {
    return("")
  }
  bytes <- readBin(path, "raw", n = size)
  nul <- match(as.raw(0), bytes)
  if (!is.na(nul)) {
    cli::cli_abort(
      c(
        "{.path {path}} holds a NUL byte at position {nul} of {size}, which no text file does.",
        "i" = "The file is corrupt or not text; jsPsych writes plain JSON. Inspect it with {.code readBin({.str {path}}, \"raw\", {size})}."
      ),
      call = call
    )
  }
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  text
}

# A quoted key followed by a colon; the lookbehind keeps an escaped quote
# (a key inside a string value) out. The value alternatives are, in order:
# a JSON string (its opening quote captured on its own, so that a matched
# empty string is told from an alternative that did not take part; the
# escapes allowed), a number (sign, decimals, exponent), a literal, or the
# opening bracket of an array or object. Groups: 1 the opening quote, 2 the
# string, 3 the number, 4 the literal, 5 the bracket.
field_pattern <- function(field) {
  key <- gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", field)
  paste0(
    '(?<!\\\\)"', key, '"\\s*:\\s*',
    '(?:(")((?:[^"\\\\]|\\\\.)*)"',
    "|(-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)",
    "|(true|false|null)",
    "|([\\[{]))"
  )
}

# Every key-position occurrence of `field` in `text`, as a data frame with
# the decoded value (character) and its kind: string, number, logical, null
# or nonscalar. One gregexec() per file gives every match with its groups as
# a matrix (a row per group, a column per hit), and the hits are classified
# as vectors; a string is decoded with jsonlite only when it holds a
# backslash.
#
# The match runs on bytes: with character offsets, R walks the UTF-8 string
# from the start for every match, which is quadratic in file size times
# hits and took 226 s for 300 files of a real study cache (2026-09-06); on
# bytes the same files take a few seconds. The pieces
# are cut at ASCII quotes out of UTF-8 text, so they are re-declared as
# UTF-8 rather than converted.
extract_field_occurrences <- function(text, field) {
  pattern <- field_pattern(field)
  m <- regmatches(text, gregexec(pattern, text, perl = TRUE, useBytes = TRUE))[[1]]
  if (length(m) == 0) {
    return(data.frame(value = character(), kind = character(), stringsAsFactors = FALSE))
  }
  # row 1 is the whole match; rows 2 to 6 are the groups. A group that did
  # not take part is "", which is why the string alternative captures its
  # opening quote: a matched empty string has the quote, the others do not
  # (scanning the whole match for its first colon read every value of a
  # key holding a colon as nonscalar, 2026-09-14).
  is_string <- nzchar(m[2, ])
  string <- as_utf8(m[3, ])
  number <- m[4, ]
  literal <- m[5, ]
  kind <- ifelse(
    is_string, "string",
    ifelse(
      nzchar(number), "number",
      ifelse(literal == "null", "null", ifelse(nzchar(literal), "logical", "nonscalar"))
    )
  )
  value <- rep(NA_character_, ncol(m))
  value[kind == "string"] <- string[kind == "string"]
  value[kind == "number"] <- number[kind == "number"]
  value[kind == "logical"] <- literal[kind == "logical"]
  escaped <- is_string & grepl("\\", string, fixed = TRUE)
  value[escaped] <- vapply(string[escaped], decode_json_string, character(1), USE.NAMES = FALSE)
  data.frame(value = value, kind = kind, stringsAsFactors = FALSE)
}

# Declare byte-cut pieces of a UTF-8 text as UTF-8 (no conversion).
as_utf8 <- function(x) {
  Encoding(x) <- "UTF-8"
  x
}

# The text between the quotes of a JSON string, with its escapes resolved;
# the raw text when jsonlite refuses it.
decode_json_string <- function(s) {
  tryCatch(
    jsonlite::fromJSON(paste0('"', s, '"')),
    error = function(e) s
  )
}

# One value and one status per file from its occurrences; the value column
# is typed once all files are known. The raw text and kind per file stay
# alongside for the cross-check, which compares typed values.
summarise_occurrences <- function(per_file) {
  status <- purrr::map_chr(per_file, function(occ) {
    if (is.null(occ)) {
      return(NA_character_)
    }
    if (nrow(occ) == 0) {
      return("absent")
    }
    if (any(occ$kind == "nonscalar")) {
      return("conflict")
    }
    # typed, so that 1e5 and 1E5, or 30 and 30.0, are one value
    typed <- mapply(typed_text, occ$value, occ$kind, USE.NAMES = FALSE)
    if (length(unique(paste(occ$kind, typed))) > 1) "conflict" else "unique"
  })
  value <- purrr::map_chr(per_file, function(occ) {
    if (is.null(occ) || nrow(occ) == 0) NA_character_ else occ$value[1]
  })
  kind <- purrr::map_chr(per_file, function(occ) {
    if (is.null(occ) || nrow(occ) == 0) NA_character_ else occ$kind[1]
  })
  value[is.na(status) | status != "unique"] <- NA_character_
  kinds <- unique(unlist(purrr::map(per_file, function(occ) {
    if (is.null(occ)) NULL else setdiff(occ$kind, "null")
  })))
  list(value = type_values(value, kinds), status = status, text = value, kind = kind)
}

# The regex text of one value as the R value jsonlite would give it, as
# character: `30.0`, `1e5` and `1.50` compare as numbers, `true` as TRUE.
typed_text <- function(text, kind) {
  if (is.na(text) || is.na(kind) || kind == "null") {
    return(NA_character_)
  }
  switch(
    kind,
    number = as.character(as.numeric(text)),
    logical = as.character(as.logical(text)),
    text
  )
}

type_values <- function(value, kinds) {
  if (length(kinds) == 0) {
    return(value)
  }
  if (identical(kinds, "number")) {
    return(as.numeric(value))
  }
  if (identical(kinds, "logical")) {
    return(as.logical(value))
  }
  value
}

# NULL when the text is not what the reader accepts (the same parser, so
# `unparseable` here means the reader would error), otherwise a list of the
# top-level array elements (an object counts as one element).
parse_for_check <- function(text) {
  parsed <- tryCatch(
    parse_result_json(text, simplify = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed) || !is.list(parsed)) {
    return(NULL)
  }
  if (!is.null(names(parsed))) list(parsed) else parsed
}

# Every value stored under `field` anywhere inside a parsed JSON value, as
# character: a JSON null is NA, an array or object is the nonscalar marker.
# One slot per element, joined once at the end: growing the result with
# c() at every hit was quadratic (3.5x the time for 2x the trials,
# 2026-09-14).
nonscalar_marker <- "\r<nonscalar>"

find_key_values <- function(x, field) {
  if (!is.list(x)) {
    return(character())
  }
  nms <- names(x)
  found <- vector("list", length(x))
  for (j in seq_along(x)) {
    value <- x[[j]]
    own <- if (!is.null(nms) && identical(nms[[j]], field)) scalar_as_character(value)
    below <- if (is.list(value)) find_key_values(value, field)
    found[[j]] <- c(own, below)
  }
  as.character(unlist(found, use.names = FALSE))
}

scalar_as_character <- function(value) {
  if (is.null(value)) {
    return(NA_character_)
  }
  if (is.list(value) || length(value) != 1) {
    return(nonscalar_marker)
  }
  as.character(value)
}

# Compare the regex reading with what jsonlite sees in the parsed files
# (any depth, nulls kept as NA, numbers as numbers); mark unparseable
# files and warn on disagreement.
cross_check_field <- function(extracted, field, idx, parsed, ids, warn) {
  disagree <- integer()
  for (k in seq_along(idx)) {
    i <- idx[k]
    elements <- parsed[[k]]
    if (is.null(elements)) {
      extracted$status[i] <- "unparseable"
      extracted$value[i] <- extracted$value[NA_integer_]
      next
    }
    seen <- find_key_values(elements, field)
    nonscalar <- any(seen == nonscalar_marker, na.rm = TRUE)
    distinct <- unique(seen)
    regex_value <- typed_text(extracted$text[i], extracted$kind[i])
    agrees <- switch(
      extracted$status[i],
      absent = length(seen) == 0,
      unique = !nonscalar && length(distinct) == 1 && same_value(distinct, regex_value),
      conflict = nonscalar || length(distinct) > 1,
      FALSE
    )
    if (!agrees) {
      disagree <- c(disagree, ids[i])
    }
  }
  if (length(disagree) > 0 && warn) {
    cli::cli_warn(c(
      "Regex and jsonlite disagree on {.field {field}} in {length(disagree)} file{?s}.",
      "i" = "{cli::qty(length(disagree))}Component result id{?s}: {disagree}. Read {?that file/those files} with {.fn jatos_read_json} and compare."
    ))
  }
  extracted
}

same_value <- function(a, b) {
  if (is.na(a) || is.na(b)) {
    return(is.na(a) && is.na(b))
  }
  identical(as.character(a), as.character(b))
}

# Closing report per field: conflict and unparseable files are a warning
# (when `warn`), absent files a message.
report_field_status <- function(extracted, ids, warn) {
  for (field in names(extracted)) {
    status <- extracted[[field]]$status
    status_col <- paste0(field, "_status")
    n_absent <- sum(status == "absent", na.rm = TRUE)
    if (n_absent > 0) {
      cli::cli_inform(c(
        "i" = "{n_absent} file{?s} without {.field {field}} (status {.code absent})."
      ))
    }
    bad <- !is.na(status) & status %in% c("conflict", "unparseable")
    if (!any(bad) || !warn) {
      next
    }
    tally <- table(status[bad])
    summary <- paste0(unname(tally), " ", names(tally), collapse = ", ")
    n <- sum(bad)
    bad_ids <- ids[bad]
    cli::cli_warn(c(
      "{n} file{?s} without a unique {.field {field}}: {summary}.",
      "i" = "{cli::qty(n)}Component result id{?s}: {bad_ids}. See the {.field {status_col}} column."
    ))
  }
}
