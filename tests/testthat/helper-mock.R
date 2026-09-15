# HTTP mocking on top of httr2::local_mocked_responses(). Routes are named by
# a regular expression matched against "<METHOD> <path>", e.g.
# "GET .*/admin/token$". A route value is either an httr2 response or a
# function(req) returning one. The returned recorder environment keeps every
# request seen, so tests can assert on method, path, query and JSON body.

local_jatos_mock <- function(..., .fallback = NULL, .env = parent.frame()) {
  routes <- rlang::list2(...)
  recorder <- new.env(parent = emptyenv())
  recorder$requests <- list()

  handler <- function(req) {
    recorder$requests[[length(recorder$requests) + 1]] <- req
    key <- paste(mock_method(req), httr2::url_parse(req$url)$path)
    for (pattern in names(routes)) {
      if (grepl(pattern, key)) {
        route <- routes[[pattern]]
        return(if (is.function(route)) route(req) else route)
      }
    }
    if (!is.null(.fallback)) {
      return(.fallback(req))
    }
    httr2::response_json(
      status_code = 404,
      body = list(apiVersion = "1.1.0", error = list(message = paste("no mock route for", key)))
    )
  }
  httr2::local_mocked_responses(handler, env = .env)
  recorder
}

mock_method <- function(req) {
  req$method %||% if (is.null(req$body)) "GET" else "POST"
}

# Serve a fixture file byte for byte, so JSON null stays null (response_json()
# would re-serialise it as {}).
mock_json <- function(fixture, status = 200) {
  path <- fixture_path(fixture)
  httr2::response(
    status_code = status,
    headers = list(`content-type` = "application/json"),
    body = readBin(path, "raw", n = file.size(path))
  )
}

# Serve a zip fixture as the server does for POST /results/data. Checked
# empirically (2026-09-05, httr2 1.3.0): local_mocked_responses() does not
# write the body to the `path` of req_perform(path =); the mock never sees
# `path`. perform_file() therefore writes a raw mocked body itself.
mock_zip <- function(fixture, status = 200, filename = NULL) {
  path <- fixture_path(fixture)
  headers <- list(`content-type` = "application/zip")
  if (!is.null(filename)) {
    headers$`content-disposition` <- sprintf('attachment; filename="%s"', filename)
  }
  httr2::response(
    status_code = status,
    headers = headers,
    body = readBin(path, "raw", n = file.size(path))
  )
}

# The metadata answer for one batch, filtered from the fixture (or from
# `parsed`, a modified copy of it) the way the server filters by `batchIds`,
# so a per-batch metadata.json holds only that batch. Falls back to the
# whole answer when the body names no batch.
mock_metadata_by_batch <- function(req, parsed = NULL) {
  body <- request_json_body(req)
  ids <- unlist(body$batchIds)
  if (is.null(parsed)) {
    if (is.null(ids)) {
      return(mock_json("metadata.json"))
    }
    parsed <- read_fixture_json("metadata.json")
  }
  if (is.null(ids)) {
    return(mock_json_null(parsed))
  }
  parsed$data <- lapply(parsed$data, function(study) {
    study$studyResults <- Filter(function(sr) sr$batchId %in% ids, study$studyResults)
    study
  })
  parsed$data <- Filter(function(study) length(study$studyResults) > 0, parsed$data)
  mock_json_null(parsed)
}

# Serve an R list as JSON through httr2's own serialiser (NULL becomes {}).
mock_json_body <- function(body, status = 200) {
  httr2::response_json(status_code = status, body = body)
}

# Serve an R list as JSON with `null` kept as null.
mock_json_null <- function(body, status = 200) {
  json <- jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA)
  httr2::response(
    status_code = status,
    headers = list(`content-type` = "application/json"),
    body = charToRaw(as.character(json))
  )
}

# Serve newline-delimited JSON, from a fixture or from text.
mock_ndjson <- function(fixture = NULL, text = NULL) {
  text <- text %||% paste(readLines(fixture_path(fixture), warn = FALSE), collapse = "\n")
  httr2::response(
    status_code = 200,
    headers = list(`content-type` = "application/x-ndjson"),
    body = charToRaw(text)
  )
}

# Serve a text/plain body, the way a JATOS at apiVersion 1.0.1 answers every
# error. The observed bodies are in helper-legacy.R.
mock_text <- function(text, status = 200, type = "text/plain") {
  httr2::response(
    status_code = status,
    headers = list(`content-type` = type),
    body = charToRaw(text)
  )
}

mock_html_login <- function() {
  html <- paste(readLines(fixture_path("login.html"), warn = FALSE), collapse = "\n")
  httr2::response(
    status_code = 200,
    headers = list(`content-type` = "text/html; charset=utf-8"),
    body = charToRaw(html)
  )
}

last_request <- function(recorder) {
  recorder$requests[[length(recorder$requests)]]
}

request_query <- function(req) {
  httr2::url_parse(req$url)$query
}

# httr2 keeps the R object in req$body$data and serialises it at perform
# time; round-trip it the same way so tests see what the server would.
request_json_body <- function(req) {
  data <- req$body$data
  if (!is.character(data)) {
    data <- jsonlite::toJSON(data, auto_unbox = TRUE, null = "null", digits = NA)
  }
  jsonlite::fromJSON(data, simplifyVector = FALSE)
}
