# Read the result files of a metadata tibble into one tibble

Reads every local `data.txt` listed in `metadata` with
[`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md)
(or with `reader`) and binds the trials of all files, filling columns
that some files lack with `NA`. Columns of the metadata are joined to
each file's trials, so that every row knows which study result and
component result it came from and carries the batch, component, worker
and study state of that run: first `id_cols`, then `metadata_cols`, then
the trial columns. The join costs nothing to look up, since one metadata
row is one file.

## Usage

``` r
jatos_read_results(
  metadata,
  ...,
  flatten = FALSE,
  id_cols = c("study_result_id", "component_result_id"),
  metadata_cols = default_metadata_cols(),
  reader = NULL,
  on_error = c("abort", "skip"),
  split = c("none", "component"),
  coerce = c("error", "character")
)
```

## Arguments

- metadata:

  A metadata tibble with a `file` column (from
  [`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
  or
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)),
  or a character vector of file paths. Of a metadata tibble only `file`
  and the columns named in `id_cols`, `metadata_cols` and, for the
  split, `component_id` are used.

- ...:

  Must be empty.

- flatten:

  Passed to
  [`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md);
  ignored with a `reader`.

- id_cols:

  Columns of `metadata` to prepend to each file's trials. Ignored when
  `metadata` is a character vector; the file path is then prepended as
  `file`.

- metadata_cols:

  Further columns of `metadata` to join after `id_cols`, for example a
  field added by
  [`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)
  that is not a trial column. `NULL` joins the id columns only. Ignored
  when `metadata` is a character vector.

- reader:

  `NULL` for
  [`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md),
  or a function of one file path returning a data frame with one row per
  trial.

- on_error:

  `"abort"` stops at the first file the reader cannot read. `"skip"`
  leaves such files out, reads the rest, and warns once with the files
  and the first error; a clash between trial and metadata columns still
  aborts.

- split:

  `"none"` returns one tibble. `"component"` returns a named list with
  one tibble per distinct `component_id` of `metadata`, in the order the
  ids first appear; needs a metadata tibble.

- coerce:

  What to do with a column whose atomic type differs between files:
  `"error"` stops with the column named; `"character"` converts that
  column to character in every file and reports it.

## Value

A tibble with one row per trial, or with `split = "component"` a named
list of such tibbles. Rows of `metadata` without a local file are left
out with a message.

## Details

A nested object in the trials (a survey `response`, say) comes out of
`jsonlite` as a data-frame column in a file where every trial carries an
object with the same keys, and as a list column in a file where the
objects differ, so two files of the same component can disagree on the
column's type. Before binding, every nested data-frame column is
therefore stored as a list column, one list per trial with the keys that
trial had (`NULL` where the trial had no object); a message names the
columns. A column whose *atomic* type differs between files (a number in
one file, a string in another) is an error naming the column; with
`coerce = "character"` such columns are converted to character in every
file, with a message, and the bind goes on.

A trial column that has the same name as a joined metadata column is an
error naming the column and the file; nothing is renamed or suffixed.
That happens, for example, when the experiment stored `worker_id` in the
data itself, or when a field extracted with
[`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)
is named in `metadata_cols` although it is a top-level field of every
trial already (the usual case for a `participant_id` set with
`jsPsych.data.addProperties()`). Leave such a column out of
`metadata_cols`; the trials carry it.

Result files that are not jsPsych JSON arrays (PsychoJS csv, OSWeb or
lab.js output) are read with a `reader` of your own, a function that
takes one file path and returns a data frame; the join and the binding
are the same. A study whose components write different columns is read
with `split = "component"`, one tibble per component, which also keeps a
column that changes type between components from blocking the bind.

## See also

[`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md)
to save the tibble,
[`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
for the whole pipeline in one call.

## Examples

``` r
cache <- system.file("extdata", "JATOS_data", package = "jatosr")
meta <- jatos_read_metadata(cache)
trials <- jatos_read_results(meta[meta$component_state == "FINISHED", ])

# a field that sits inside a survey response, not at the trial level
meta <- jatos_extract_fields(meta, "age")
trials <- jatos_read_results(meta, metadata_cols = c("worker_id", "age"))
#> ℹ 2 rows have no local file.
trials[, c("study_result_id", "worker_id", "age", "trial_index", "rt")]
#> # A tibble: 16 × 5
#>    study_result_id worker_id age   trial_index    rt
#>              <int>     <int> <chr>       <int> <int>
#>  1            9001       501 24              0 14250
#>  2            9001       501 24              1   737
#>  3            9001       501 24              2   824
#>  4            9001       501 24              3   761
#>  5            9001       501 24              4   848
#>  6            9001       501 24              5   935
#>  7            9001       501 24              6   872
#>  8            9001       501 24              7   959
#>  9            9001       501 24              8  1046
#> 10            9002       502 31              0 14250
#> 11            9002       502 31              1   737
#> 12            9002       502 31              2   824
#> 13            9002       502 31              3   761
#> 14            9002       502 31              4   848
#> 15            9002       502 31              5   935
#> 16            9002       502 31              6   872

# one tibble per component
parts <- jatos_read_results(meta, split = "component")
#> ℹ 2 rows have no local file.
names(parts)
#> [1] "121"

# PsychoJS writes csv, read with a reader of your own:
# trials <- jatos_read_results(meta, reader = function(file) utils::read.csv(file))
```
