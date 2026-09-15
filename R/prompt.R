# Interactive prompts, each in its own function so that tests can mock it.
# Every one refuses a session that cannot show a prompt rather than
# answering for the user.

# askpass is in Imports, so the prompt is always its hidden-input dialog;
# the readline() fallback that used to sit here could never run. A cancelled
# dialog returns NULL, which is an answer of its own.
prompt_for_token <- function(call = rlang::caller_env()) {
  if (!rlang::is_interactive()) {
    cli::cli_abort(
      "{.arg token} must be supplied in a non-interactive session.",
      call = call,
      class = "jatosr_needs_interactive"
    )
  }
  entered <- askpass::askpass("JATOS personal access token")
  if (!rlang::is_string(entered) || !nzchar(entered)) {
    cli::cli_abort("No token was entered.", call = call, class = "jatosr_no_token")
  }
  entered
}

# Interactive confirmation, in its own function so that tests can mock it.
# utils::menu() errors in a non-interactive session, so the check comes
# first: a script that asks to be prompted is refused, never answered for.
#
# rlang::is_interactive(), not base interactive(): the latter is TRUE inside
# a document knitted from the console, where no prompt can be shown. When
# `confirm` defaulted to rlang's answer and this function tested base R's,
# the two disagreed exactly there, and a knit deleted the token unasked.
# The default is now TRUE outright, so the only way to remove a token
# without a prompt is to write `confirm = FALSE`.
confirm_removal <- function(profile, backend, call = rlang::caller_env()) {
  if (!rlang::is_interactive()) {
    cli::cli_abort(
      c(
        "Cannot ask for confirmation in a non-interactive session.",
        "i" = "Pass {.code confirm = FALSE} to remove the credentials without a prompt."
      ),
      call = call,
      class = "jatosr_needs_interactive"
    )
  }
  cli::cli_inform(c(
    "!" = "About to remove the credentials of profile {.val {profile}} from the {.val {backend}} credential store.",
    "i" = "A token that is stored nowhere else cannot be recovered; JATOS shows it once."
  ))
  identical(utils::menu(c("Yes, remove them", "No, keep them")), 1L)
}
