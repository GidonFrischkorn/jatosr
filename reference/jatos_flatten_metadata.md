# Flatten a `/results/metadata` answer into a tibble

Turns the nested JSON of `POST /results/metadata` (studies, their study
results, their component results) into a flat tibble with one row per
component result. Study-level and study-result-level values repeat down
their component results; every column name says which level it belongs
to, so `length(unique(meta$study_result_id))` counts participants while
`nrow(meta)` counts component results. Column names are snake case,
times are `POSIXct` in UTC, sizes are bytes.

## Usage

``` r
jatos_flatten_metadata(metadata)
```

## Arguments

- metadata:

  The metadata as the server sent it, not yet a tibble: a parsed answer
  (the whole envelope or its `data` element) as returned by
  `jsonlite::read_json(simplifyVector = FALSE)`, or the path of a
  `metadata.json` file.

## Value

A tibble with, per study: `study_id`, `study_uuid`, `study_title`; per
study result: `study_result_id`, `study_result_uuid`, `study_code`,
`worker_id`, `worker_type`, `batch_id`, `batch_uuid`, `batch_title`,
`group_id`, `study_state`, `study_start_time`, `study_end_time`,
`study_duration` (minutes), `last_seen`, `comment`, `study_message` (the
text shown when a run was aborted or failed), `confirmation_code`
(MTurk), `quota_reached`, `url_query` (list of the URL query parameters
the worker arrived with); per component result: `component_result_id`,
`component_id`, `component_uuid`, `component_state`,
`component_start_time`, `component_end_time`, `component_duration`
(minutes), `path` (location inside a result zip), `data_size` (bytes on
the server; 0 for reloads and unfinished runs), `data_file`, `n_files`
and `files` (list of attached-file entries).

## Examples

``` r
meta <- jatos_flatten_metadata(
  system.file("extdata", "metadata.json", package = "jatosr")
)
meta[, c("study_result_id", "component_result_id", "component_state", "data_size")]
#> # A tibble: 6 × 4
#>   study_result_id component_result_id component_state data_size
#>             <int>               <int> <chr>               <dbl>
#> 1            9001                7001 FINISHED             2048
#> 2            9002                7002 RELOADED                0
#> 3            9002                7003 FINISHED             1536
#> 4            9003                7004 STARTED                 0
#> 5            9004                7005 FINISHED              300
#> 6            9004                7006 FINISHED              700
```
