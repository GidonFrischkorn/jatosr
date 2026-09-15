# Nothing this package produces may contain a token.
#
# The connection object no longer carries one, which is what makes the first
# few of these writable at all: before, `saveRDS(conn)` wrote the token to
# disk in the clear and the only defence was a paragraph of documentation.
# These tests are the standing proof, and they are deliberately written
# against whole directories and whole condition streams rather than against
# named fields, so that a file or a message added later is covered without
# anyone remembering to come back here.

# One expectation per call, whatever the number of files, so that the
# positive control below can say "exactly one failure" about it. Raw bytes,
# not rawToChar(): an rds, a parquet file and a zip all contain NUL bytes,
# and a string with an embedded NUL breaks fixed-string matching.
expect_no_token_in_file <- function(path) {
  files <- if (dir.exists(path)) {
    list.files(path, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  } else {
    path
  }
  files <- files[!dir.exists(files)]
  hits <- character()
  for (file in files) {
    found <- token_hits(file)
    if (length(found) > 0) {
      hits <- c(hits, sprintf("%s (%s)", basename(file), paste(found, collapse = ", ")))
    }
  }
  message <- if (length(files) == 0) {
    sprintf("No file to scan under %s.", path)
  } else {
    paste0("A token was found in: ", paste(hits, collapse = "; "))
  }
  testthat::expect(length(files) > 0 && length(hits) == 0, message)
  invisible(path)
}

# The names of the scannable tokens that occur in one file, read the way R
# reads it: an rds or RData is a gzip, bzip2 or xz stream, and a token planted
# in one is invisible to a grep over the compressed bytes (which is how four
# tests here passed vacuously for eight sessions). A zip is scanned entry by
# entry.
token_hits <- function(file) {
  magic <- readBin(file, "raw", n = 4)
  if (identical(magic, charToRaw("PK\003\004"))) {
    return(token_hits_in_zip(file))
  }
  bytes <- decompressed_bytes(file)
  names(scannable_tokens)[vapply(
    scannable_tokens,
    function(token) length(grepRaw(charToRaw(token), bytes, fixed = TRUE)) > 0,
    logical(1)
  )]
}

# gzfile() reads gzip, bzip2 and xz and passes an uncompressed file through
# unchanged; anything it cannot open at all is scanned as raw bytes.
decompressed_bytes <- function(file) {
  tryCatch(
    {
      con <- gzfile(file, open = "rb")
      on.exit(close(con), add = TRUE)
      bytes <- raw()
      repeat {
        chunk <- readBin(con, "raw", n = 1e6)
        if (length(chunk) == 0) {
          break
        }
        bytes <- c(bytes, chunk)
      }
      bytes
    },
    error = function(cnd) readBin(file, "raw", n = file.size(file))
  )
}

token_hits_in_zip <- function(file) {
  dir <- withr::local_tempdir()
  entries <- utils::unzip(file, exdir = dir)
  unique(unlist(lapply(entries, token_hits)))
}

test_that("the canary sees into compressed files", {
  # The control that was missing for eight sessions: a token planted in an
  # rds or RData is compressed on disk, and a grep over the compressed bytes
  # found nothing, so the four tests below passed whether or not the
  # connection carried the token. Every absence assertion needs a presence
  # control; this is it, for every compression R writes.
  dir <- withr::local_tempdir()
  planted <- list(token = fake_token)
  saveRDS(planted, file.path(dir, "planted-gzip.rds"))
  saveRDS(planted, file.path(dir, "planted-bzip2.rds"), compress = "bzip2")
  saveRDS(planted, file.path(dir, "planted-xz.rds"), compress = "xz")
  save(planted, file = file.path(dir, "planted.RData"))
  writeLines(fake_token, file.path(dir, "planted.txt"))
  con <- gzfile(file.path(dir, "planted.txt.gz"), "w")
  writeLines(fake_token, con)
  close(con)

  for (file in list.files(dir, full.names = TRUE)) {
    expect_failure(expect_no_token_in_file(file), label = basename(file))
  }
  expect_failure(expect_no_token_in_file(dir))

  # and a file without a token still passes, so the reader is not failing
  # on everything
  clean <- withr::local_tempdir()
  saveRDS(list(token = "none"), file.path(clean, "clean.rds"))
  expect_success(expect_no_token_in_file(clean))
})

test_that("the canary sees into zip entries", {
  skip_if_not(nzchar(Sys.which("zip")), "no zip binary")
  dir <- withr::local_tempdir()
  writeLines(fake_token, file.path(dir, "planted.txt"))
  zip_file <- file.path(dir, "planted.zip")
  withr::with_dir(dir, utils::zip(zip_file, "planted.txt", flags = "-q"))
  unlink(file.path(dir, "planted.txt"))

  expect_failure(expect_no_token_in_file(zip_file))
})

test_that("a serialised connection holds no token", {
  # The reason the connection carries an opaque id instead of the secret.
  local_fake_credentials()
  conn <- jatos_connection()
  file <- withr::local_tempfile(fileext = ".rds")
  saveRDS(conn, file)

  expect_no_token_in_file(file)
  expect_no_token(rawToChar(serialize(conn, NULL, ascii = TRUE)))
})

test_that("a connection built with an explicit token holds no token either", {
  local_fake_credentials()
  conn <- jatos_connection(token = fake_tokens[["explicit"]])
  file <- withr::local_tempfile(fileext = ".rds")
  saveRDS(conn, file)

  expect_no_token_in_file(file)
})

test_that("a serialised request holds no token", {
  # An httr2 request carries the bearer header, and a targets pipeline or a
  # knitr cache that stored one would write it out.
  local_fake_credentials()
  req <- jatos_req(jatos_connection(), "studies")
  file <- withr::local_tempfile(fileext = ".rds")
  saveRDS(req, file)

  expect_no_token_in_file(file)
})

test_that("save.image() writes no token", {
  local_fake_credentials()
  dir <- withr::local_tempdir()
  env <- new.env()
  env$conn <- jatos_connection()
  env$profiles <- jatos_list_profiles()
  save(list = ls(env), envir = env, file = file.path(dir, "workspace.RData"))

  expect_no_token_in_file(dir)
})

test_that("the profile configuration file holds the host and no token", {
  local_no_credentials()
  suppressMessages(jatos_set_credentials(fake_host, fake_token, check = FALSE))

  expect_no_token_in_file(config_path())
  expect_match(readLines(config_path(), warn = FALSE), fake_host, all = FALSE)
})

test_that("the whole export writes no token anywhere", {
  # Every file of one full run at once — the cache tree, the data file, the
  # metadata sidecar and the provenance record — scanned recursively, so a
  # file added to any of them later is covered without editing this test.
  local_download_mock()
  root <- withr::local_tempdir()
  suppressMessages(jatos_export_results(
    study_id = 12,
    cache = file.path(root, "cache"),
    file = file.path(root, "study12.rds")
  ))

  expect_true(file.exists(file.path(root, "study12_export.json")))
  expect_no_token_in_file(root)
})

test_that("every export format writes no token", {
  local_download_mock()
  root <- withr::local_tempdir()
  formats <- c("rds", "csv", "RData", "tsv")
  for (format in formats) {
    # one directory each: the provenance record has a fixed name and the
    # second format would otherwise refuse to overwrite the first one's
    dir <- file.path(root, format)
    dir.create(dir)
    suppressMessages(jatos_export_results(
      study_id = 12,
      cache = file.path(root, "cache"),
      file = file.path(dir, paste0("study12.", format))
    ))
  }

  expect_no_token_in_file(root)
})

test_that("a parquet export writes no token", {
  skip_if_not_installed("arrow")
  local_download_mock()
  root <- withr::local_tempdir()
  suppressMessages(jatos_export_results(
    study_id = 12,
    cache = file.path(root, "cache"),
    file = file.path(root, "study12.parquet")
  ))

  expect_no_token_in_file(root)
})

test_that("a downloaded archive holds no token", {
  local_fake_credentials()
  local_jatos_mock("GET .*/studies/12$" = mock_zip("results.zip"))
  file <- withr::local_tempfile(fileext = ".jzip")
  suppressMessages(jatos_export_study(12, file = file))

  expect_no_token_in_file(file)
})

test_that("raw files written out of the cache hold no token", {
  local_download_mock()
  root <- withr::local_tempdir()
  cache <- file.path(root, "cache")
  metadata <- suppressMessages(
    jatos_download_results(jatos_results_metadata(study_id = 12), path = cache)
  )
  suppressMessages(jatos_write_raw(metadata, path = file.path(root, "raw")))

  expect_no_token_in_file(root)
})

test_that("no printed representation shows a token", {
  dir <- local_no_credentials()
  withr::local_envvar(c(JATOS_HOST = fake_host, JATOS_TOKEN = fake_token))
  # an .Renviron defining the default profile, so that the sitrep
  # takes the one path on which it shows lines of a file
  writeLines(
    c(sprintf('JATOS_HOST="%s"', fake_host), sprintf('JATOS_TOKEN="%s"', fake_token)),
    file.path(dir, "user.Renviron")
  )
  suppressMessages(jatos_set_credentials(fake_host, fake_tokens[["admin"]],
    profile = "lab_admin", check = FALSE
  ))
  conn <- jatos_connection()

  expect_no_token(capture.output(print(conn)))
  expect_no_token(format(conn))
  expect_no_token(capture.output(str(conn)))
  expect_no_token(capture.output(print(unclass(conn))))
  expect_no_token(capture.output(print(jatos_list_profiles())))
  expect_no_token(capture_messages(jatos_credentials_sitrep()))
  expect_no_token(capture.output(print(jatos_req(conn, "studies"))))
})

test_that("no condition raised during a full run carries a token", {
  # The messages, warnings and errors of one whole pipeline, collected and
  # checked together rather than one assertion per call site.
  local_download_mock()
  root <- withr::local_tempdir()
  conditions <- character()
  # suppressMessages() outside, not inside: calling handlers run innermost
  # first, so a suppressor established inside would muffle every condition
  # before the collector ever saw it.
  suppressMessages(suppressWarnings(withCallingHandlers(
    jatos_export_results(
      study_id = 12,
      cache = file.path(root, "cache"),
      file = file.path(root, "study12.rds")
    ),
    message = function(cnd) conditions <<- c(conditions, conditionMessage(cnd)),
    warning = function(cnd) conditions <<- c(conditions, conditionMessage(cnd))
  )))

  expect_gt(length(conditions), 0)
  expect_no_token(conditions)
})

test_that("no condition raised on the credential paths carries a token", {
  local_no_credentials()
  conditions <- character()
  collect <- function(expr) {
    suppressMessages(suppressWarnings(withCallingHandlers(
      try(expr, silent = TRUE),
      message = function(cnd) conditions <<- c(conditions, conditionMessage(cnd)),
      warning = function(cnd) conditions <<- c(conditions, conditionMessage(cnd))
    )))
  }

  collect(jatos_connection())
  collect(jatos_set_credentials(fake_host, fake_token, check = FALSE))
  collect(jatos_set_credentials(fake_host, fake_tokens[["plain"]],
    profile = "odd", check = FALSE
  ))
  collect(jatos_credentials_sitrep())
  collect(jatos_remove_credentials(confirm = FALSE))
  collect(jatos_connection("nope"))

  expect_gt(length(conditions), 0)
  expect_no_token(conditions)
})

test_that("no token literal lives in the code, the documentation or the tests", {
  # The project rule made into an assertion rather than a convention:
  # package code, vignettes, help pages, the fixture builder, the example
  # files under inst/, README, NEWS and the tests themselves. The one file allowed to spell a token is
  # helper-credentials.R, which defines every fake one; a test that needs a
  # token-shaped string takes it from `fake_tokens` by name, so that
  # expect_no_token() knows to look for it.
  skip_on_cran()
  root <- package_root
  dirs <- file.path(root, c("R", "vignettes", "man", "data-raw", "inst", "tests"))
  files <- c(
    list.files(dirs[dir.exists(dirs)], recursive = TRUE, full.names = TRUE),
    file.path(root, c("README.md", "NEWS.md"))
  )
  files <- files[file.exists(files)]
  files <- files[!dir.exists(files)]
  files <- files[basename(files) != "helper-credentials.R"]
  # text only: readLines() on the logo or a fixture zip warns about embedded
  # nuls, and a token cannot hide in a png anyway
  files <- files[grepl("[.](R|r|Rmd|Rd|md|yml|yaml|json|txt|csv)$", files)]

  offenders <- Filter(
    function(file) {
      any(grepl("jap_[A-Za-z0-9]", readLines(file, warn = FALSE)))
    },
    files
  )

  expect_equal(basename(offenders), character())
})
