# Builds the binary and text fixtures under tests/testthat/fixtures/ that the
# download and reader tests use. Run from the package root:
#
#   source("data-raw/make-fixtures.R")
#
# results.zip mirrors what POST /results/data returns for the component
# results 7001, 7003, 7005 and 7006 of fixtures/metadata.json:
#
#   study_result_<id>/comp-result_<id>/data.txt
#
# Every data.txt is padded with a `filler` field so that its byte length is
# exactly the `data.size` recorded in metadata.json (2048, 1536, 300, 700).
# Values contain non-ASCII characters, so byte length and character count
# differ, which is what the incremental rule must compare correctly.
#
# results-files.zip mirrors what POST /results/files returns (verified in
# ResultStreamer.addFilesToZip, 2026-09-06): the uploaded files of a
# component result under
#
#   study_result_<id>/comp-result_<id>/files/<filename>
#
# It holds the drawing.png of component result 7003 (4096 bytes, as listed
# in metadata.json) and an audio.webm of 7006 that metadata.json does not
# list, which the file download must leave in the zip.
#
# results-decoy.zip holds one entry only, an uploaded file named `data.txt`
# under `study_result_9001/comp-result_7001/files/`; the data download must
# not take it for the result data of 7001.
#
# data-concatenated.txt is what repeated `jatos.appendResultData()` calls
# leave behind: two JSON arrays back to back.

fixture_dir <- file.path("tests", "testthat", "fixtures")
stopifnot(dir.exists(fixture_dir))

# One string per component result; %FILL% is replaced by the padding.
templates <- list(
  # sr 9001: a two-trial jsPsych task with a non-ASCII value
  "7001" = list(
    study_result_id = 9001,
    size = 2048,
    text = paste0(
      '[{"trial_index":0,"trial_type":"html-keyboard-response",',
      '"participant_id":"P1","city":"Zürich","rt":512.5,"correct":true},',
      '{"trial_index":1,"trial_type":"html-keyboard-response",',
      '"participant_id":"P1","city":"Zürich","rt":-1,"correct":false,',
      '"filler":"%FILL%"}]'
    )
  ),
  # sr 9002: a URL query string carrying the field name in value position
  "7003" = list(
    study_result_id = 9002,
    size = 1536,
    text = paste0(
      '[{"trial_index":0,"trial_type":"survey","participant_id":"P2",',
      '"url":"https://jatos.example.org/publix/run?participant_id=DECOY&letter-firstname=n",',
      '"city":"Genève","rt":1200},',
      '{"trial_index":1,"trial_type":"survey","participant_id":"P2",',
      '"rt":950,"filler":"%FILL%"}]'
    )
  ),
  # sr 9004, component 131: escaped JSON inside a string value
  "7005" = list(
    study_result_id = 9004,
    size = 300,
    text = paste0(
      '[{"trial_index":0,"trial_type":"instructions","participant_id":"P4",',
      '"raw":"{\\"participant_id\\":\\"ESC\\"}","city":"Basel","rt":2100,',
      '"filler":"%FILL%"}]'
    )
  ),
  # sr 9004, component 132: a survey with columns the task files lack
  "7006" = list(
    study_result_id = 9004,
    size = 700,
    text = paste0(
      '[{"trial_index":0,"trial_type":"survey-html-form","participant_id":"P4",',
      '"response":{"age":"31","handedness":"rechts"},"question_order":[1,2],',
      '"rt":8800,"filler":"%FILL%"}]'
    )
  )
)

pad_to_bytes <- function(text, size) {
  base <- nchar(sub("%FILL%", "", text, fixed = TRUE), type = "bytes")
  n <- size - base
  stopifnot(n >= 0)
  sub("%FILL%", strrep("x", n), text, fixed = TRUE)
}

build_dir <- tempfile("results-")
dir.create(build_dir)
entries <- character()
for (id in names(templates)) {
  t <- templates[[id]]
  rel <- file.path(
    paste0("study_result_", t$study_result_id),
    paste0("comp-result_", id),
    "data.txt"
  )
  dir.create(dirname(file.path(build_dir, rel)), recursive = TRUE)
  text <- pad_to_bytes(t$text, t$size)
  bytes <- charToRaw(enc2utf8(text))
  stopifnot(length(bytes) == t$size)
  jsonlite::fromJSON(text) # must be valid JSON
  writeBin(bytes, file.path(build_dir, rel))
  entries <- c(entries, rel)
}

zip_path <- file.path(normalizePath(fixture_dir), "results.zip")
if (file.exists(zip_path)) file.remove(zip_path)
old <- setwd(build_dir)
status <- utils::zip(zip_path, files = entries, flags = "-9XDq")
setwd(old)
stopifnot(status == 0)

# Cross-check the sizes against metadata.json.
meta <- jsonlite::read_json(file.path(fixture_dir, "metadata.json"))
sizes <- unlist(lapply(meta$data, function(study) {
  lapply(study$studyResults, function(sr) {
    setNames(
      lapply(sr$componentResults, function(cr) cr$data$size),
      vapply(sr$componentResults, function(cr) as.character(cr$id), "")
    )
  })
}))
listed <- utils::unzip(zip_path, list = TRUE)
for (id in names(templates)) {
  entry <- listed[grepl(paste0("comp-result_", id, "/data.txt$"), listed$Name), ]
  stopifnot(nrow(entry) == 1, entry$Length == sizes[[id]])
}

writeBin(
  charToRaw('[{"trial_index":0,"rt":300,"participant_id":"P7"}][{"trial_index":1,"rt":420,"participant_id":"P7"}]'),
  file.path(fixture_dir, "data-concatenated.txt")
)

# Attached files: a PNG signature followed by padding, and a second file
# that the metadata does not list.
attachments <- list(
  list(rel = "study_result_9002/comp-result_7003/files/drawing.png", size = 4096,
       head = as.raw(c(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))),
  list(rel = "study_result_9004/comp-result_7006/files/audio.webm", size = 500,
       head = as.raw(c(0x1A, 0x45, 0xDF, 0xA3)))
)
files_dir <- tempfile("results-files-")
dir.create(files_dir)
file_entries <- character()
for (a in attachments) {
  target <- file.path(files_dir, a$rel)
  dir.create(dirname(target), recursive = TRUE)
  bytes <- c(a$head, as.raw(rep(0x2E, a$size - length(a$head))))
  stopifnot(length(bytes) == a$size)
  writeBin(bytes, target)
  file_entries <- c(file_entries, a$rel)
}
files_zip_path <- file.path(normalizePath(fixture_dir), "results-files.zip")
if (file.exists(files_zip_path)) file.remove(files_zip_path)
old <- setwd(files_dir)
status <- utils::zip(files_zip_path, files = file_entries, flags = "-9XDq")
setwd(old)
stopifnot(status == 0)
listed_files <- utils::unzip(files_zip_path, list = TRUE)
stopifnot(
  nrow(listed_files) == 2,
  listed_files$Length[listed_files$Name == attachments[[1]]$rel] == 4096
)

# results-export.zip mirrors what POST /results (and the GUI's "Export
# Results") returns: metadata.json at the zip root, every data.txt and the
# uploaded drawing.png. It is built from the same padded texts, so the
# sizes match metadata.json and an import yields a consistent cache.
export_dir <- tempfile("results-export-")
dir.create(export_dir)
file.copy(file.path(fixture_dir, "metadata.json"), file.path(export_dir, "metadata.json"))
export_entries <- "metadata.json"
for (id in names(templates)) {
  t <- templates[[id]]
  rel <- file.path(paste0("study_result_", t$study_result_id), paste0("comp-result_", id), "data.txt")
  dir.create(dirname(file.path(export_dir, rel)), recursive = TRUE)
  writeBin(charToRaw(enc2utf8(pad_to_bytes(t$text, t$size))), file.path(export_dir, rel))
  export_entries <- c(export_entries, rel)
}
a <- attachments[[1]]
dir.create(dirname(file.path(export_dir, a$rel)), recursive = TRUE)
writeBin(c(a$head, as.raw(rep(0x2E, a$size - length(a$head)))), file.path(export_dir, a$rel))
export_entries <- c(export_entries, a$rel)
export_zip_path <- file.path(normalizePath(fixture_dir), "results-export.zip")
if (file.exists(export_zip_path)) file.remove(export_zip_path)
old <- setwd(export_dir)
status <- utils::zip(export_zip_path, files = export_entries, flags = "-9XDq")
setwd(old)
stopifnot(status == 0, nrow(utils::unzip(export_zip_path, list = TRUE)) == 6)

# The decoy: an upload called data.txt under files/, and nothing else.
decoy_dir <- tempfile("results-decoy-")
decoy_rel <- "study_result_9001/comp-result_7001/files/data.txt"
dir.create(dirname(file.path(decoy_dir, decoy_rel)), recursive = TRUE)
writeBin(charToRaw("not result data"), file.path(decoy_dir, decoy_rel))
decoy_zip_path <- file.path(normalizePath(fixture_dir), "results-decoy.zip")
if (file.exists(decoy_zip_path)) file.remove(decoy_zip_path)
old <- setwd(decoy_dir)
status <- utils::zip(decoy_zip_path, files = decoy_rel, flags = "-9XDq")
setwd(old)
stopifnot(status == 0, nrow(utils::unzip(decoy_zip_path, list = TRUE)) == 1)

# study.jzip mirrors the study archive of GET /studies/{id} (verified in
# ImportExportService.createStudyExportZipFile, 2026-09-06): the study's
# JSON (`<title>.jas`) next to its assets folder.
study_dir <- tempfile("study-")
dir.create(file.path(study_dir, "A03_ColorBinding"), recursive = TRUE)
jsonlite::write_json(
  list(
    version = "3",
    data = list(
      uuid = "1c2d3e4f-0000-4000-8000-000000000012",
      title = "A03_ColorBinding",
      dirName = "A03_ColorBinding",
      componentList = list(list(uuid = "c000-121", title = "task", htmlFilePath = "index.html"))
    )
  ),
  file.path(study_dir, "A03_ColorBinding.jas"),
  auto_unbox = TRUE, pretty = TRUE
)
writeLines("<!doctype html><title>A03_ColorBinding</title>", file.path(study_dir, "A03_ColorBinding", "index.html"))
study_zip_path <- file.path(normalizePath(fixture_dir), "study.jzip")
if (file.exists(study_zip_path)) file.remove(study_zip_path)
old <- setwd(study_dir)
status <- utils::zip(study_zip_path, files = c("A03_ColorBinding.jas", "A03_ColorBinding/index.html"), flags = "-9XDq")
setwd(old)
stopifnot(status == 0, nrow(utils::unzip(study_zip_path, list = TRUE)) == 2)

message("wrote ", zip_path, ", ", files_zip_path, ", ", export_zip_path, ", ", decoy_zip_path, ", ", study_zip_path, " and data-concatenated.txt")

# --- inst/extdata/: what the runnable examples read ----------------------------
#
# The help pages cannot reach a server, so the offline half of the pipeline
# runs on a small synthetic cache shipped with the package:
#
#   inst/extdata/data.txt                     one jsPsych result file
#   inst/extdata/JATOS_data/batch_34/         a cache holding batch 34 of
#     metadata.json                           inst/extdata/metadata.json
#     study_result_9001/comp-result_7001/data.txt
#     study_result_9002/comp-result_7003/data.txt
#   inst/extdata/results.zip                  the same batch as a results
#                                             export: metadata.json at the
#                                             root and the two data.txt
#
# The cache sits in its own folder because a directory with a metadata.json
# at the top level is not a cache (check_cache_layout()), and
# inst/extdata/metadata.json is there already. inst/extdata/metadata.json
# is the same file as tests/testthat/fixtures/metadata.json.
#
# The result files are readable jsPsych trials rather than a `filler` field:
# they print in the help pages. Each is exactly as many bytes as the
# `data.size` its metadata records (2048 and 1536), made up with trailing
# whitespace after the last trial, so that jatos_cache_status() reports
# nothing pending. Participants, hosts and values are invented.

extdata_dir <- file.path("inst", "extdata")
stopifnot(dir.exists(extdata_dir))

# A change-detection task: a survey, then trials until the next one would
# not fit into `size` bytes.
jspsych_trials <- function(participant_id, age, size) {
  survey <- list(
    rt = 14250, response = list(age = age, handedness = "right"),
    trial_type = "survey-html-form", trial_index = 0, plugin_version = "2.0.0",
    time_elapsed = 14268, participant_id = participant_id
  )
  trial <- function(i) {
    set_size <- c(2L, 4L, 6L)[(i %% 3) + 1]
    change <- i %% 2 == 0
    correct <- (i %% 5) != 3
    list(
      rt = 600 + 37 * i + 25 * set_size, stimulus = paste0("array_", i, ".html"),
      response = if (change == correct) "d" else "s",
      trial_type = "html-keyboard-response", trial_index = i,
      plugin_version = "2.0.0", time_elapsed = 14268 + 2500 * i,
      participant_id = participant_id, set_size = set_size,
      change = change, correct = correct
    )
  }
  to_text <- function(trials) {
    as.character(jsonlite::toJSON(trials, auto_unbox = TRUE, digits = NA))
  }
  trials <- list(survey)
  repeat {
    longer <- c(trials, list(trial(length(trials))))
    if (nchar(to_text(longer), type = "bytes") > size) break
    trials <- longer
  }
  text <- to_text(trials)
  paste0(text, "\n", strrep(" ", size - nchar(text, type = "bytes") - 1))
}

write_bytes <- function(text, path, size = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  bytes <- charToRaw(enc2utf8(text))
  stopifnot(is.null(size) || length(bytes) == size)
  jsonlite::fromJSON(text) # must be valid JSON
  writeBin(bytes, path)
}

# the batch-34 subset of the metadata, as jatos_import_results() and the
# download store it
full <- jsonlite::read_json(file.path(extdata_dir, "metadata.json"))
subset <- full
subset$data <- Filter(
  function(study) length(study$studyResults) > 0,
  lapply(full$data, function(study) {
    study$studyResults <- Filter(function(sr) identical(sr$batchId, 34L), study$studyResults)
    study
  })
)
stopifnot(length(subset$data) == 1, length(subset$data[[1]]$studyResults) == 3)

cache_files <- list(
  "7001" = list(study_result_id = 9001, participant_id = "P501", age = "24", size = 2048),
  "7003" = list(study_result_id = 9002, participant_id = "P502", age = "31", size = 1536)
)

cache_root <- file.path(extdata_dir, "JATOS_data")
unlink(cache_root, recursive = TRUE)
batch <- file.path(cache_root, "batch_34")
dir.create(batch, recursive = TRUE)
jsonlite::write_json(subset, file.path(batch, "metadata.json"),
  auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE
)

zip_dir <- tempfile("extdata-zip-")
dir.create(zip_dir)
file.copy(file.path(batch, "metadata.json"), file.path(zip_dir, "metadata.json"))
zip_entries <- "metadata.json"
for (id in names(cache_files)) {
  f <- cache_files[[id]]
  rel <- file.path(paste0("study_result_", f$study_result_id), paste0("comp-result_", id), "data.txt")
  text <- jspsych_trials(f$participant_id, f$age, f$size)
  write_bytes(text, file.path(batch, rel), size = f$size)
  write_bytes(text, file.path(zip_dir, rel), size = f$size)
  zip_entries <- c(zip_entries, rel)
}

# the standalone file: the first participant's trials, without the padding
write_bytes(
  trimws(jspsych_trials("P501", "24", 2048), which = "right"),
  file.path(extdata_dir, "data.txt")
)

extdata_zip <- file.path(normalizePath(extdata_dir), "results.zip")
if (file.exists(extdata_zip)) file.remove(extdata_zip)
old <- setwd(zip_dir)
status <- utils::zip(extdata_zip, files = zip_entries, flags = "-9XDq")
setwd(old)
stopifnot(status == 0, nrow(utils::unzip(extdata_zip, list = TRUE)) == 3)

message("wrote ", extdata_zip, ", ", cache_root, " and ", file.path(extdata_dir, "data.txt"))
