# Download the files uploaded during runs into the cache

Fetches every file listed by
[`jatos_result_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_result_files.md)
that is not yet on disk, or that has grown on the server, and stores it
next to the result data as
`<path>/batch_<batch_id>/study_result_<id>/comp-result_<id>/files/<filename>`,
which is the layout the server uses inside its result zips. The rule is
the one of
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md),
applied per file: a file is fetched when it is missing locally and has a
size above `0` on the server, or when the server's copy is larger; equal
sizes are `unchanged`; a server copy that is *smaller* than the local
file leaves the local file alone with status `shrunk` unless
`overwrite = TRUE`. A file whose size the metadata does not give counts
as `0`, so it is not fetched, and a warning names it.

## Usage

``` r
jatos_download_files(
  metadata,
  path,
  incremental = TRUE,
  chunk_size = 50,
  overwrite = FALSE,
  dry_run = FALSE,
  conn = jatos_connection()
)
```

## Arguments

- metadata:

  A metadata tibble with the `files` column, from
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md)
  or
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md).
  A tibble that
  [`jatos_result_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_result_files.md)
  already widened is not accepted; pass the metadata.

- path:

  The cache directory. Created when missing.

- incremental:

  If `FALSE`, every component result with a server size above `0` is
  fetched again, except `shrunk` ones unless `overwrite = TRUE`.

- chunk_size:

  Component results per request.

- overwrite:

  If `TRUE`, `shrunk` rows are fetched and replaced.

- dry_run:

  If `TRUE`, no request is made and nothing is written: the rows that a
  real run would fetch get status `pending`, and a message per batch
  reports their count, their size on the server and the number of
  requests. `conn` is not needed.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

The tibble of
[`jatos_result_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_result_files.md)
with `file` (local path, `NA` when absent after the run), `file_size`
(bytes, `NA` when absent) and `status` (`fetched`, `unchanged`, `empty`,
`shrunk`, `missing`, `failed`, or `pending` in a dry run) added. With
`dry_run = TRUE` the same tibble says, without a request, which files
are on disk.

## Details

Files are requested from `POST /results/files` with the component result
ids in the body, up to `chunk_size` component results per request (the
files of one component result always travel in one request), one zip per
chunk, with a progress bar. Only the files that were planned are taken
out of a zip. A planned file that the server's answer does not contain
has status `missing`; a request that fails marks its files `failed` and
the run goes on, with one warning at the end; after a `401` or `403` no
further request is made. Every batch that received files gets a fresh
`metadata.json`, as in
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md).

## See also

[`jatos_result_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_result_files.md),
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
meta <- jatos_results_metadata(study_id = 12)
jatos_download_files(meta, "JATOS_data", dry_run = TRUE)
files <- jatos_download_files(meta, "JATOS_data")
files[files$status == "fetched", c("component_result_id", "filename", "file")]
} # }
```
