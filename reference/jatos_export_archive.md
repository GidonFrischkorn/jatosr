# Download the results archive as the server produces it

Fetches the zip that `POST /results` builds for the studies or batches
given (every result's `data.txt`, the uploaded files and one
`metadata.json` at the root, the same archive the JATOS GUI's "Export
Results" produces) and writes it to `file` untouched. This is an
archival verb: for a data deposit the artefact people trust is the zip
JATOS itself made, not a tibble. It is never the incremental path; the
server re-sends every result each time.
[`jatos_import_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_import_results.md)
turns such a zip into a cache.

## Usage

``` r
jatos_export_archive(
  study_id = NULL,
  batch_id = NULL,
  file = NULL,
  overwrite = FALSE,
  conn = jatos_connection()
)
```

## Arguments

- study_id, batch_id:

  One or more ids to select results by; at least one of the two must be
  given. `study_id` may also be one or more uuid strings. Several are
  combined as the server combines them (the union).

- file:

  Path to write, conventionally with the extension `.zip`. Its directory
  must exist. `NULL` takes the server's file name in the working
  directory.

- overwrite:

  If `TRUE`, an existing file is replaced.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

The path written, invisibly; a message reports it with the size.

## Details

The archive is written under a temporary name in the target directory
and renamed into place after the answer was checked to be a zip file; an
existing `file` is never replaced unless `overwrite = TRUE`. Without
`file`, the archive lands in the working directory under the name the
server sends (what a browser would save from the GUI's export), reduced
to its base name; `jatos_results.zip` when the server names none. A file
in the way is then found only after the answer, so a run that is refused
has already downloaded the archive once.

## See also

[`jatos_export_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_study.md)
for the study archive,
[`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
whose `archive_results = TRUE` writes this archive next to the dataset.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_export_archive(study_id = 12, file = "data/study12_results.zip")
jatos_export_archive(study_id = 12) # the server's name, here
} # }
```
