# Fetch, read and save the trials of a study in one call

Runs the whole pipeline:
[`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md)
for the ids given,
[`jatos_filter_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_filter_metadata.md)
with `states`, `worker_types`, `since`, `until` and the two exclusion
lists,
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
into `cache`,
[`jatos_url_query()`](https://www.gfrischkorn.org/jatosr/reference/jatos_url_query.md),
[`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)
when `fields` is given,
[`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
with the metadata joined, and
[`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md)
to `file`. Nothing happens here that those functions do not do on their
own; run them separately when a step needs an argument this wrapper does
not pass on (`chunk_size` of the download, `flatten` of the reader).
`reader`, `split`, `coerce` and `on_error` go to the reader as they are;
with `on_error = "skip"` a file the reader cannot read is left out of
the trials with a warning, and the final message and the provenance
count only the files that were read. Files that participants uploaded
are not part of a trials dataset; fetch them with
[`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md).

## Usage

``` r
jatos_export_results(
  study_id = NULL,
  batch_id = NULL,
  ...,
  cache,
  file,
  download = TRUE,
  fields = NULL,
  states = NULL,
  worker_types = NULL,
  since = NULL,
  until = NULL,
  exclude_study_result_id = NULL,
  exclude_worker_id = NULL,
  tz = "UTC",
  reader = NULL,
  coerce = c("error", "character"),
  on_error = c("abort", "skip"),
  metadata_cols = default_metadata_cols(),
  format = NULL,
  split = c("none", "component"),
  metadata_file = TRUE,
  provenance = TRUE,
  archive_study = FALSE,
  archive_results = FALSE,
  overwrite = FALSE,
  conn = jatos_connection()
)
```

## Arguments

- study_id, batch_id:

  One or more ids to select results by; at least one of the two must be
  given for a download. Passed to
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md);
  `study_id` may also be one or more uuid strings. With
  `download = FALSE` both may be `NULL`, which exports the whole cache.

- ...:

  Must be empty.

- cache:

  The local cache directory, see
  [`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md).

- file:

  Path of the trials file to write, see
  [`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md).
  Its directory must exist.

- download:

  If `FALSE`, nothing is requested: the metadata is read from the cache
  and the dataset is built from the files already there.

- fields:

  JSON keys to extract with
  [`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)
  and join to every trial row. For values that do not sit at the top
  level of the trial objects, for example inside a survey response; a
  field that already is a trial column is reported as a clash by
  [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md).

- states:

  Study states to keep, for example `"FINISHED"`. `NULL` keeps every
  state. JATOS states are `PRE`, `STARTED`, `DATA_RETRIEVED`,
  `FINISHED`, `ABORTED` and `FAIL`.

- worker_types:

  Worker types to keep, for example
  `c("PersonalSingle", "GeneralMultiple")`. `NULL` keeps every type; the
  GUI test runs are `"Jatos"`.

- since:

  Keep study results that started at or after this time: a `POSIXct`, a
  `Date`, or a string such as `"2025-08-24"` or `"2025-08-24 12:00:00"`,
  read in the time zone `tz`. Rows without a start time are dropped when
  `since` is given.

- until:

  Keep study results that started *before* this time, given like
  `since`; `since` and `until` together select a half-open interval, so
  `since = "2025-08-24", until = "2025-08-25"` is one day. Rows without
  a start time are dropped when `until` is given.

- exclude_study_result_id, exclude_worker_id:

  Study result ids, or worker ids, whose study results are dropped; for
  the researcher's own runs through a real link, which `worker_types`
  cannot tell apart.

- tz:

  Time zone in which date strings in `since` and `until` are read, and
  in which the message shows them. `"UTC"` by default, the zone the
  server reports times in;
  [`Sys.timezone()`](https://rdrr.io/r/base/timezones.html) for local
  time.

- reader:

  `NULL` for
  [`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md),
  or a function of one file path returning a data frame with one row per
  trial.

- coerce:

  What to do with a column whose atomic type differs between files:
  `"error"` stops with the column named; `"character"` converts that
  column to character in every file and reports it.

- on_error:

  `"abort"` stops at the first file the reader cannot read. `"skip"`
  leaves such files out, reads the rest, and warns once with the files
  and the first error; a clash between trial and metadata columns still
  aborts.

- metadata_cols:

  Metadata columns joined to every trial row after the ids, see
  [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md);
  the `query_*` columns and the extracted `fields` are added to whatever
  is given here. `NULL` joins only those.

- format:

  Format of the trials file, passed to
  [`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md);
  `NULL` infers it from the extension of `file`. The default metadata
  file shares it; a metadata file given as a path takes its format from
  its own extension.

- split:

  `"none"` writes one trials file. `"component"` reads and writes one
  file per component id (`<stem>_component_<id>.<ext>`), see
  [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md);
  the metadata file is written once.

- metadata_file:

  `TRUE` writes the study-result table next to `file` as
  `<stem>_metadata.<ext>`; a path writes it there, in the format of that
  path's extension (a `.csv` next to an `.rds` trials file is fine);
  `FALSE` skips it.

- provenance:

  If `TRUE`, write `<stem>_export.json` with the host, profile, ids,
  filters, fields, cache, package version, time, counts and the paths
  written.

- archive_study:

  If `TRUE`, the study archive is downloaded with
  [`jatos_export_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_study.md)
  and written next to the dataset: as `<stem>_study.jzip` for the one
  study named in `study_id`, as `<stem>_study_<id>.jzip` per study when
  several are named or when only `batch_id` is given and the studies
  come from the metadata. The archive records the experiment that
  produced the data; the provenance record lists it.

- archive_results:

  If `TRUE`, the results archive that the server builds for the same ids
  (`POST /results`: every `data.txt`, the uploaded files and the
  `metadata.json`, see
  [`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md))
  is written next to the dataset as `<stem>_results.zip`, and the
  provenance record lists it with its size and md5 checksum. An archival
  copy, fetched in full each time; the incremental download into `cache`
  is unchanged.

- overwrite:

  Passed to
  [`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md)
  for every file written. The download keeps its own guard for local
  files larger than the server's copy.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md);
  not used with `download = FALSE`.

## Value

The trials tibble, invisibly (with `split = "component"` a named list of
tibbles); a message reports the row count and the paths written.

## Details

With `download = FALSE` the same dataset is built from the cache alone:
the metadata comes from the cache's `metadata.json` files through
[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
(restricted to `study_id` and `batch_id` when given, the whole cache
otherwise), no request is made and no connection is needed, and the
provenance record says `offline: true` and lists the metadata files with
their modification times. That is the path for an analysis machine
without credentials, for CI, or for rebuilding a dataset after the study
left the server; rows whose data file is not in the cache are skipped
with a message, as
[`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
does. `archive_study` needs the server and is refused offline.

Three files come out of one call, one more each with
`archive_study = TRUE` and `archive_results = TRUE`. The trials file
holds one row per trial with the ids, `batch_id`, `component_id`,
`worker_id`, `worker_type`, `study_state`, `study_start_time`, the URL
query parameters as `query_*` columns and the extracted `fields` in
front of the trial columns. The metadata file (`<stem>_metadata.<ext>`
by default) holds one row per study result from
[`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md),
which is where exclusions, payments and the participant count of a
methods section come from; it covers the same study results as the
trials file. The provenance file (`<stem>_export.json`) records host,
ids, filters, package version, time and the counts of the export.

Run it again later and only new or grown results are downloaded; the
files are then rewritten from the whole cache, which is why `overwrite`
exists. `file`, `format`, the target directory, the sidecar paths and
`fields` are checked before the first request, so a mistake there costs
no download; every path the call will write (with `split = "component"`
the part files, whose names come from the component ids of the metadata)
is checked once more right after the metadata answer, before the
download. A component result whose download failed, or that the server's
answer did not contain, stops the export before anything is written,
since the dataset would be incomplete; the files fetched so far stay in
the cache for the next run.

## See also

[`jatos_filter_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_filter_metadata.md),
[`jatos_url_query()`](https://www.gfrischkorn.org/jatosr/reference/jatos_url_query.md),
[`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md)
for the pieces this adds to the five steps.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
trials <- jatos_export_results(
  study_id = 12, cache = "JATOS_data", file = "data/study12.rds",
  states = "FINISHED"
)

# one batch, as csv, without the researcher's own GUI runs, with a field
# that sits inside a survey response
jatos_export_results(
  batch_id = 34, cache = "JATOS_data", file = "data/batch34.csv",
  worker_types = c("PersonalSingle", "GeneralMultiple"),
  fields = "age", overwrite = TRUE
)

# the same dataset from the cache alone, without credentials
jatos_export_results(
  study_id = 12, cache = "JATOS_data", file = "data/study12.rds",
  states = "FINISHED", download = FALSE, overwrite = TRUE
)
} # }
```
