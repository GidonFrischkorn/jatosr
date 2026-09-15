# A mocked server for the download pipeline. The fixture zip holds data.txt
# for 7001 (2048 B), 7003 (1536 B), 7005 (300 B) and 7006 (700 B), matching
# data_size in metadata.json; 7002 and 7004 have size 0 on the server.
# results-files.zip holds the drawing.png (4096 B) of 7003, the one file
# metadata.json lists, and an audio.webm of 7006 that it does not list.

# Routes given in `...` (named by their pattern) replace or extend the
# three defaults, so a test that fails one endpoint spells out only that.
local_download_mock <- function(..., .env = parent.frame()) {
  local_fake_credentials(.env = .env)
  routes <- list(
    "POST .*/results/data$" = mock_zip("results.zip"),
    "POST .*/results/files$" = mock_zip("results-files.zip"),
    "POST .*/results/metadata$" = mock_metadata_by_batch
  )
  # whole-value replacement: a response is a list, and a recursive merge
  # would splice the two responses together
  overrides <- rlang::list2(...)
  routes[names(overrides)] <- overrides
  local_jatos_mock(!!!routes, .env = .env)
}

request_paths <- function(rec) {
  vapply(rec$requests, function(r) httr2::url_parse(r$url)$path, character(1))
}

file_requests <- function(rec) {
  Filter(function(req) grepl("/results/files$", httr2::url_parse(req$url)$path), rec$requests)
}

fixture_metadata <- function() {
  jatos_flatten_metadata(fixture_path("metadata.json"))
}

data_requests <- function(rec) {
  Filter(function(req) grepl("/results/data$", httr2::url_parse(req$url)$path), rec$requests)
}

metadata_requests <- function(rec) {
  Filter(function(req) grepl("/results/metadata$", httr2::url_parse(req$url)$path), rec$requests)
}
