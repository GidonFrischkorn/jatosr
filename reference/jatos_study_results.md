# One row per study result

Collapses a metadata tibble (one row per component result) to one row
per study result, which is the unit that means "one run by one
participant". Counts of people, duplicate detection and quality flags
belong at this level; a participant who reloaded a component has several
component results but one study result.

## Usage

``` r
jatos_study_results(metadata, participant = NULL)
```

## Arguments

- metadata:

  A metadata tibble from
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md),
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
  or
  [`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md).

- participant:

  Name of the column that identifies a participant, for `n_runs`; `NULL`
  uses `query_prolific_pid` when present.

## Value

A tibble with the study and study-result columns of `metadata`, plus
`n_component_results`, `n_components` (distinct component ids),
`n_finished` (component results in state `FINISHED`), `data_size`
(bytes, summed), `n_files`, `first_component_start`,
`last_component_end`, `n_runs` (when a participant key is available;
`NA` where the key is `NA`), any extra columns of `metadata`, and
`conflicts` (list of column names; only present when `metadata` has
extra columns).

## Details

Columns that are not part of the metadata contract (for example
`participant_id` added by
[`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md),
or a column you joined yourself) are carried over with their first
non-`NA` value per study result. When the component results of one study
result disagree on such a column, the value becomes `NA`, the column
name is listed in `conflicts`, and a warning names the study results
concerned. The `<field>_status` columns of
[`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)
(recorded in the `jatosr_extracted` attribute) and the local `file`,
`file_size` and `status` columns are left out.

Prolific returners and reloaded links produce several study results per
person. When a participant key is available, `n_runs` counts the study
results per key value, so duplicates are visible before N is counted:
`participant` names the column (a `query_*` column from
[`jatos_url_query()`](https://www.gfrischkorn.org/jatosr/reference/jatos_url_query.md),
a field from
[`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md),
or `worker_id`); with `participant = NULL` the column
`query_prolific_pid` is used when present, and `n_runs` is left out
otherwise. A message reports how many keys have more than one run.

## Examples

``` r
meta <- jatos_flatten_metadata(
  system.file("extdata", "metadata.json", package = "jatosr")
)
jatos_study_results(meta)[, c("study_result_id", "n_component_results", "data_size")]
#> # A tibble: 4 × 3
#>   study_result_id n_component_results data_size
#>             <int>               <int>     <dbl>
#> 1            9001                   1      2048
#> 2            9002                   2      1536
#> 3            9003                   1         0
#> 4            9004                   2      1000
jatos_study_results(meta, participant = "worker_id")[, c("study_result_id", "worker_id", "n_runs")]
#> # A tibble: 4 × 3
#>   study_result_id worker_id n_runs
#>             <int>     <int>  <int>
#> 1            9001       501      1
#> 2            9002       502      1
#> 3            9003       503      1
#> 4            9004       504      1
```
