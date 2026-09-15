# Captured cli output as one string, with the line wrapping undone.
#
# cli wraps a message at the console width, which testthat fixes at 80
# characters, so where the wrap falls depends on how long the paths
# interpolated into the message are - and those are temporary directories,
# whose length differs per platform and per run. A test that looks for a
# phrase in the output therefore passes or fails on the length of the
# session's temporary directory: "(not written yet)" broke across two lines
# under `R CMD check` on Linux, where the configuration path was 68
# characters, and stayed whole on the longer macOS one. Matching against
# this collapses every run of whitespace, so a phrase reads the same
# however it was wrapped.
message_text <- function(x) {
  gsub("[[:space:]]+", " ", paste(cli::ansi_strip(x), collapse = " "))
}
