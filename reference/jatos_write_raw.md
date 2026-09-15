# Copy the raw result files, one per participant

Copies every local `data.txt` of a metadata tibble byte for byte to
`<path>/<name>.json`, named by a column of the metadata (the study
result id by default, or `worker_id`, `query_prolific_pid`, or a field
from
[`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)),
which is the layout labs share raw JSON in. Nothing is parsed or
rewritten. A study result with several files (one per component) gets
`<name>_<component_result_id>.json` for each. When two different study
results share a name, for example a participant who ran twice, nothing
is written and the error lists the name and the study result ids, so
that duplicates are resolved on purpose rather than silently. Each copy
is written under a temporary name in `path` and renamed into place, so a
copy that fails never sits under the real name.

## Usage

``` r
jatos_write_raw(metadata, path, name_by = "study_result_id", overwrite = FALSE)
```

## Arguments

- metadata:

  A metadata tibble with the `file` column, from
  [`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
  or
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md).
  Rows without a local file are left out with a message.

- path:

  Directory to write into; created when missing.

- name_by:

  Name of the metadata column whose value names each file. `NA` values
  are refused, and so is a value that could leave `path`: one holding a
  slash or a backslash, or equal to `.` or `..`. The values may come
  from the participants themselves (a Prolific id in the URL, a field of
  the result data), so they are never trusted as paths.

- overwrite:

  If `TRUE`, existing files in `path` are replaced.

## Value

A tibble with `study_result_id`, `component_result_id`, `file` (the
source) and `path` (the copy), invisibly; a message reports the count.

## See also

[`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md)
for the server's own zip of the same files.

## Examples

``` r
cache <- system.file("extdata", "JATOS_data", package = "jatosr")
meta <- jatos_read_metadata(cache)

out <- tempfile("jatosr-example-")
jatos_write_raw(meta, out, name_by = "worker_id")
#> ℹ 2 rows have no local file.
#> ✔ Wrote 2 files to /tmp/RtmpHTC4Nw/jatosr-example-19043d2d7b22.
list.files(out)
#> [1] "501.json" "502.json"
unlink(out, recursive = TRUE)
```
