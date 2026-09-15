# Download result data into a local cache

Fetches the `data.txt` of each component result in `metadata` that is
not yet on disk, or that has grown on the server, and stores it under
`<path>/batch_<batch_id>/study_result_<id>/comp-result_<id>/data.txt`.
The comparison is in raw bytes on both sides: `data_size` from the
metadata against [`file.size()`](https://rdrr.io/r/base/file.info.html)
of the local file. Component results are requested from
`POST /results/data` in chunks of `chunk_size` ids, one zip per chunk,
with a progress bar over the chunks, and every batch that received data
gets a fresh `metadata.json` afterwards (one `POST /results/metadata`
per batch) so that
[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
can rebuild the tibble offline later. That `batch_<id>/` layout is the
only one the package reads or writes: a directory holding a
`metadata.json` at its top level or `JATOS_DATA_<id>` folders (what
smartr left behind) is refused, since the server is the source of truth
and the data is downloaded again into a fresh directory; a zip exported
from the JATOS GUI is imported with
[`jatos_import_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_import_results.md).

## Usage

``` r
jatos_download_results(
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

  A metadata tibble from
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md).
  A tibble from
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
  carries the sizes of the cached `metadata.json`, so it finds nothing
  new; fetch fresh metadata first.

- path:

  The cache directory. Created when missing.

- incremental:

  If `FALSE`, every component result with a server size above `0` is
  fetched again, except `shrunk` ones unless `overwrite = TRUE`.

- chunk_size:

  Component result ids per request.

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

`metadata` with three columns added (replaced when present): `file`
(path of the local `data.txt`, `NA` when absent after the run),
`file_size` (its size in bytes, `NA` when absent) and `status` (one of
`fetched`, `unchanged`, `empty`, `shrunk`, `missing`, `failed`, or
`pending` in a dry run).

## Details

The incremental rule is asymmetric:

- server size `0`: nothing is requested, status `empty`, whether or not
  a 0-byte local file exists (a larger local file makes it `shrunk`, see
  below);

- no local file and server size above `0`, or server larger than local:
  fetched, status `fetched`;

- equal sizes above `0`: status `unchanged`, no request;

- server *smaller* than local: the local file stays, status `shrunk`,
  because it may be the last copy of that participant's data. Only
  `overwrite = TRUE` replaces it.

A row that was requested but not part of the server's answer has status
`missing` and a warning names it. A request that fails (a transport
error, an HTTP error, an answer that is not a zip file, or a zip that
cannot be unpacked in full) does not stop the run: its rows get status
`failed`, the remaining chunks are fetched, and one warning at the end
reports the count and the first error. After a `401` or `403` no further
request is made, since every one of them would fail the same way. Files
are written to a temporary name inside the batch directory and renamed
into place, so a partial download never sits under the real name.

Files that participants uploaded during a run (drawings, recordings) are
not part of the result data;
[`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md)
fetches them with the same rule, file by file.

## See also

[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
to rebuild the metadata from the cache,
[`jatos_cache_status()`](https://www.gfrischkorn.org/jatosr/reference/jatos_cache_status.md)
to summarise it,
[`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
to read the downloaded files,
[`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md)
for uploaded files.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
meta <- jatos_results_metadata(study_id = 12)
jatos_download_results(meta, "JATOS_data", dry_run = TRUE)   # what would be fetched
meta <- jatos_download_results(meta, "JATOS_data")
table(meta$status)
} # }
```
