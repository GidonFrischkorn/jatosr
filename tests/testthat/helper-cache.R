# Build a cache directory in the package layout from the fixture: one
# batch_<id> folder per batch, each with the metadata of that batch only.
local_cache <- function(.env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .env)
  parsed <- read_fixture_json("metadata.json")
  for (study in parsed$data) {
    for (sr in study$studyResults) {
      dir <- batch_dir(root, sr$batchId)
      dir.create(dir, showWarnings = FALSE)
      one_study <- study
      one_study$studyResults <- Filter(function(r) r$batchId == sr$batchId, study$studyResults)
      write_metadata_json(one_study, metadata_file(dir))
    }
  }
  root
}

write_metadata_json <- function(study, file) {
  jsonlite::write_json(
    list(apiVersion = "1.1.0", data = list(study)),
    file,
    auto_unbox = TRUE, null = "null", pretty = TRUE
  )
}

# A metadata tibble whose rows point at freshly written files. `texts` is a
# named list component_result_id -> file content; rows without an entry
# keep file = NA.
meta_with_files <- function(texts, .env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .env)
  meta <- jatos_flatten_metadata(fixture_path("metadata.json"))
  meta$file <- NA_character_
  meta$file_size <- NA_real_
  for (id in names(texts)) {
    i <- match(as.integer(id), meta$component_result_id)
    meta$file[i] <- write_data_file(root, meta$batch_id[i], meta$study_result_id[i], id, texts[[id]])
    meta$file_size[i] <- file.size(meta$file[i])
  }
  meta
}

# Write one data file where the cache layout expects it, creating the
# batch_<id> folder when needed.
write_data_file <- function(root, batch_id, study_result_id, component_result_id, text) {
  path <- local_data_path(batch_dir(root, batch_id), study_result_id, component_result_id)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw(text), path)
  path
}
