test_that("jatos_read_metadata rebuilds the tibble from every batch folder", {
  root <- local_cache()
  meta <- jatos_read_metadata(root)
  expect_equal(names(meta), c(metadata_columns(), "file", "file_size"))
  expect_equal(sort(meta$component_result_id), c(7001L, 7002L, 7003L, 7004L, 7005L, 7006L))
  expect_equal(sort(unique(meta$batch_id)), c(34L, 36L))
  expect_true(all(is.na(meta$file)))
  expect_true(all(is.na(meta$file_size)))
  expect_equal(nrow(jatos_read_metadata(root, batch_id = 36)), 2)
})

test_that("jatos_read_metadata attaches local data files and their byte sizes", {
  root <- local_cache()
  p1 <- write_data_file(root, 34, 9001, 7001, "[{\"a\": \"äöü\"}]")
  p2 <- write_data_file(root, 36, 9004, 7006, "[{\"b\": 1}]")
  meta <- jatos_read_metadata(root)
  i1 <- match(7001L, meta$component_result_id)
  i2 <- match(7006L, meta$component_result_id)
  expect_equal(normalizePath(meta$file[i1]), normalizePath(p1))
  expect_equal(meta$file_size[i1], file.size(p1))
  expect_equal(meta$file_size[i1], 17)
  expect_equal(meta$file_size[i2], 10)
  expect_equal(sum(!is.na(meta$file)), 2)
})

test_that("jatos_read_metadata accepts a single metadata.json or one batch directory", {
  root <- local_cache()
  one <- jatos_read_metadata(file.path(root, "batch_36", "metadata.json"))
  expect_equal(one$component_result_id, c(7005L, 7006L))
  expect_equal(jatos_read_metadata(file.path(root, "batch_36")), one)
  expect_equal(batch_dir(root, c(36, 34, 36)), file.path(root, c("batch_36", "batch_34", "batch_36")))
  expect_equal(basename(list_batch_dirs(root)), c("batch_34", "batch_36"))
  # id order, not lexical order
  dir.create(file.path(root, "batch_100"))
  expect_equal(basename(list_batch_dirs(root)), c("batch_34", "batch_36", "batch_100"))
  # each batch is read once, however many rows it holds
  meta <- jatos_read_metadata(root)
  expect_equal(nrow(meta), 6)
  expect_false(anyDuplicated(meta$component_result_id) > 0)
})

test_that("jatos_read_metadata errors clearly on a missing cache", {
  root <- withr::local_tempdir()
  expect_error(jatos_read_metadata(file.path(root, "nope")), "does not exist", class = "jatosr_bad_argument")
  expect_error(jatos_read_metadata(root), "No metadata.json", class = "jatosr_cache_layout")
  expect_error(jatos_cache_status(root), "No metadata.json", class = "jatosr_cache_layout")
})

test_that("jatos_cache_status counts rows, files, pending, shrunk and orphans per batch", {
  root <- local_cache()
  write_data_file(root, 34, 9001, 7001, strrep("a", 2048))   # complete
  write_data_file(root, 34, 9002, 7003, strrep("a", 1000))   # smaller than the server's 1536
  write_data_file(root, 36, 9004, 7005, strrep("a", 999))    # larger than the server's 300
  write_data_file(root, 36, 9999, 8888, "[]")                # no metadata row
  status <- jatos_cache_status(root)
  expect_s3_class(status, "tbl_df")
  expect_equal(
    names(status),
    c("batch_id", "path", "n_results", "n_downloaded", "n_pending", "n_shrunk", "n_orphans", "bytes")
  )
  expect_equal(status$batch_id, c(34L, 36L))
  # list.dirs() writes forward slashes where a Windows tempdir() has
  # backslashes; compare the normalised paths
  expect_equal(
    normalizePath(status$path, winslash = "/"),
    normalizePath(file.path(root, c("batch_34", "batch_36")), winslash = "/")
  )
  expect_equal(status$n_results, c(4L, 2L))
  expect_equal(status$n_downloaded, c(2L, 1L))
  # 34: 7003 is smaller than the server's copy; 36: 7006 has no file yet
  expect_equal(status$n_pending, c(1L, 1L))
  expect_equal(status$n_shrunk, c(0L, 1L))
  expect_equal(status$n_orphans, c(0L, 1L))
  expect_equal(status$bytes, c(3048, 999))

  # orphans are counted inside their batch folder only: a second orphan in
  # batch_34 and an upload named data.txt under files/ change one count
  write_data_file(root, 34, 9998, 8887, "[]")
  upload <- file.path(root, "batch_36", "study_result_9004", "comp-result_7005", "files", "data.txt")
  dir.create(dirname(upload), recursive = TRUE)
  writeLines("drawing", upload)
  again <- jatos_cache_status(root)
  expect_equal(again$n_orphans, c(1L, 1L))
  expect_equal(again$n_downloaded, c(2L, 1L))

  # a batch folder whose metadata.json lists several batches reports NA for the id
  whole <- withr::local_tempdir()
  dir.create(file.path(whole, "batch_34"))
  file.copy(fixture_path("metadata.json"), file.path(whole, "batch_34", "metadata.json"))
  expect_true(is.na(jatos_cache_status(whole)$batch_id))
  expect_equal(jatos_cache_status(whole)$n_results, 6L)
})

test_that("jatos_cache_status keeps the batches named in batch_id", {
  root <- local_cache()
  write_data_file(root, 34, 9001, 7001, strrep("a", 2048))
  write_data_file(root, 36, 9004, 7005, strrep("a", 999))
  write_data_file(root, 36, 9999, 8888, "[]")
  all <- jatos_cache_status(root)
  expect_equal(jatos_cache_status(root, batch_id = 36), all[all$batch_id == 36L, ])
  expect_equal(jatos_cache_status(root, batch_id = c(36, 34)), all)
  none <- jatos_cache_status(root, batch_id = 99)
  expect_equal(nrow(none), 0L)
  expect_equal(names(none), names(all))
  expect_equal(vapply(none, typeof, character(1)), vapply(all, typeof, character(1)))
  expect_error(jatos_cache_status(root, batch_id = "a"), "batch_id", class = "jatosr_bad_argument")

  # an empty batch directory is kept by its directory id
  dir.create(file.path(root, "batch_40"))
  jsonlite::write_json(list(apiVersion = "1.0.0", data = list()), file.path(root, "batch_40", "metadata.json"), auto_unbox = TRUE)
  empty <- jatos_cache_status(root, batch_id = 40)
  expect_equal(empty$batch_id, 40L)
  expect_equal(empty$n_results, 0L)

  # one metadata.json listing both batches: rows of the other batch are
  # filtered out of the counts, but their files are still listed, not orphans
  whole <- withr::local_tempdir()
  dir.create(file.path(whole, "batch_34"))
  file.copy(fixture_path("metadata.json"), file.path(whole, "batch_34", "metadata.json"))
  write_data_file(whole, 34, 9001, 7001, strrep("a", 2048))
  write_data_file(whole, 34, 9004, 7005, strrep("a", 300))
  both <- jatos_cache_status(whole)
  only_36 <- jatos_cache_status(whole, batch_id = 36)
  expect_equal(only_36$batch_id, 36L)
  expect_equal(only_36$n_results, 2L)
  expect_equal(only_36$n_downloaded, 1L)
  expect_equal(only_36$bytes, 300)
  expect_equal(only_36$n_orphans, both$n_orphans)
  expect_equal(only_36$n_orphans, 0L)
})
