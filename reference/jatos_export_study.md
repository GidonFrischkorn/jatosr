# Download the study archive

Fetches the JATOS study archive of one study through `GET /studies/{id}`
and writes it to `file`. The archive is a zip that holds the study's
properties and components as JSON (a `.jas` file) next to the study
assets folder with the experiment's HTML, scripts and stimuli; JATOS
imports it as a `.jzip` file. Saved next to a dataset, it records the
exact version of the experiment that produced the data.

## Usage

``` r
jatos_export_study(
  study_id,
  file = NULL,
  overwrite = FALSE,
  conn = jatos_connection()
)
```

## Arguments

- study_id:

  Study id (integer) or uuid (string).

- file:

  Path to write, conventionally with the extension `.jzip`. Its
  directory must exist. `NULL` takes the server's file name in the
  working directory.

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
server sends (`jatos_study_<uuid>.jzip`, what a browser would save from
the GUI's export), reduced to its base name; `jatos_study_<id>.jzip`
when the server names none. A file in the way is then found only after
the answer, so a run that is refused has already downloaded the archive
once. The token needs the user role for this endpoint, not only the
viewer role.

## See also

[`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md),
whose `archive_study = TRUE` writes the archive next to the dataset.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_export_study(12, "data/study12_study.jzip")
jatos_export_study(12) # the server's name, here
} # }
```
