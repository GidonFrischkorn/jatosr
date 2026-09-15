# Write a trials tibble to disk

Saves the tibble that
[`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
returns (or any data frame) as `.rds`, `.csv`, `.csv.gz`, `.tsv`,
`.parquet` or `.RData` in one call. The format is taken from the file
extension or from `format` when the file has no extension; a `format`
that contradicts the extension is an error, the file is not renamed. The
file is written under a temporary name in the same directory and renamed
into place, and an existing file is never replaced unless
`overwrite = TRUE`.

## Usage

``` r
jatos_write_results(
  x,
  file,
  ...,
  format = NULL,
  object = "trials",
  split = c("none", "component"),
  overwrite = FALSE
)
```

## Arguments

- x:

  A data frame, usually from
  [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md).

- file:

  Path of the file to write. With `split = "component"` it is the
  pattern: `results.rds` becomes `results_component_<id>.rds`.

- ...:

  Must be empty.

- format:

  `"rds"`, `"csv"`, `"csv.gz"`, `"tsv"`, `"parquet"` or `"rdata"`.
  `NULL` (the default) infers it from the extension of `file` (`.RData`
  and `.rda` are `"rdata"`).

- object:

  For `RData`: the name of the object in the file, so that
  [`load()`](https://rdrr.io/r/base/load.html) is predictable; a
  syntactic name (see
  [`make.names()`](https://rdrr.io/r/base/make.names.html)). With
  `split = "component"` each file holds `<object>_component_<id>`, the
  suffix of its file name.

- split:

  `"none"` writes one file. `"component"` writes one file per distinct
  `component_id` in `x`, with the id in the file name, for studies whose
  components have different columns.

- overwrite:

  If `TRUE`, existing files are replaced.

## Value

The path(s) written, invisibly.

## Details

`rds` and `RData` keep every column as it is, list columns included.
`parquet` (through the arrow package, which must be installed) reads
from Python and other tools; it keeps a list column or nested data-frame
column when arrow can give it one type, and serialises a column it
cannot type (cells of different shapes, such as an object in one trial
and a vector in the next) to JSON strings the way csv does, with a
message naming the columns. `csv`, `csv.gz` (the same, gzip-compressed)
and `tsv` are written in UTF-8 without row names, `NA` as an empty
field, `POSIXct` columns as ISO 8601 in UTC (`2025-08-24T01:46:40Z`),
and every list column or nested data-frame column serialised cell by
cell to a JSON string with `jsonlite::toJSON(auto_unbox = TRUE)`; a
message names the columns that were serialised. Read such a cell back
with
[`jsonlite::fromJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html),
or read the trials with `flatten = TRUE` to get nested objects as
columns before writing.

## See also

[`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
for metadata, download, read and write in one call.

## Examples

``` r
cache <- system.file("extdata", "JATOS_data", package = "jatosr")
trials <- jatos_read_results(jatos_read_metadata(cache))
#> ℹ 2 rows have no local file.

out <- tempfile("jatosr-example-")
dir.create(out)
jatos_write_results(trials, file.path(out, "study12.rds"))
jatos_write_results(trials, file.path(out, "study12.csv"))
#> ℹ Serialised the list column response to JSON strings.
jatos_write_results(trials, file.path(out, "study12.RData"), object = "study12")
list.files(out)
#> [1] "study12.RData" "study12.csv"   "study12.rds"  
unlink(out, recursive = TRUE)
```
