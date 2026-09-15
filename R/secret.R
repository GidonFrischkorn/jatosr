# --- masked secret -----------------------------------------------------------
#
# The token is held in a closure rather than a classed string: base functions
# such as paste(), sprintf() and cat() do not dispatch on S3 classes and would
# print a classed string verbatim, but they refuse to coerce a function.
# Only reveal_secret() (internal) reads the value.

new_secret <- function(x, call = rlang::caller_env()) {
  check_string(x, arg = "token", call = call)
  force(x)
  structure(function() x, class = "jatos_secret")
}

reveal_secret <- function(x) {
  unclass(x)()
}

#' @export
format.jatos_secret <- function(x, ...) {
  value <- reveal_secret(x)
  prefix <- if (startsWith(value, "jap_")) "jap_" else ""
  sprintf("<jatos_secret: %s... (%d chars)>", prefix, nchar(value))
}

#' @export
print.jatos_secret <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}

#' @export
str.jatos_secret <- function(object, ...) {
  cat(" ", format(object), "\n", sep = "")
  invisible(NULL)
}

#' @export
as.character.jatos_secret <- function(x, ...) {
  cli::cli_abort(c(
    "Refusing to convert a {.cls jatos_secret} to a character string.",
    "i" = "The token stays in the session; it is not part of any object you can save."
  ))
}

# `once = TRUE` for jatos_connection(), which is the default argument of
# nearly every export and would otherwise repeat the warning on every API
# call of a session; the setter warns each time, since each call is one
# deliberate act of storing.
warn_if_unusual_token <- function(token, once = FALSE, call = rlang::caller_env()) {
  if (startsWith(token, "jap_")) {
    return(invisible(token))
  }
  if (once) {
    key <- rlang::hash(token)
    if (key %in% the$unusual_warned) {
      return(invisible(token))
    }
    the$unusual_warned <- c(the$unusual_warned, key)
  }
  cli::cli_warn(
    c(
      "JATOS personal access tokens usually start with {.code jap_}.",
      "i" = "Check that you copied the token, not its name."
    ),
    call = call
  )
  invisible(token)
}
