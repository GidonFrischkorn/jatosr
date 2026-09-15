# Rebuild result metadata from a local cache

Reads the `metadata.json` files that
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
stores in `<path>/batch_<id>/` and returns the same tibble that
[`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md)
returned when they were fetched, plus two columns describing the data
file on disk. No network is needed, so a pipeline can be replayed
offline. Each batch is read once, from its own
`batch_<id>/metadata.json`; a directory in another layout (a
`metadata.json` at the top level, `JATOS_DATA_<id>` folders) is refused,
see
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md).

## Usage

``` r
jatos_read_metadata(path, batch_id = NULL)
```

## Arguments

- path:

  The cache directory, one `batch_<id>` directory inside it, or the path
  of a single `metadata.json` file.

- batch_id:

  Optional ids to keep only some batches.

## Value

A metadata tibble as documented in
[`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md),
with `file` (path of the local `data.txt`, `NA` when it has not been
downloaded) and `file_size` (its size in bytes, `NA` when absent).

## See also

[`jatos_cache_status()`](https://www.gfrischkorn.org/jatosr/reference/jatos_cache_status.md)
for a per-batch summary of the same cache.

## Examples

``` r
cache <- system.file("extdata", "JATOS_data", package = "jatosr")
meta <- jatos_read_metadata(cache)
meta[, c("study_result_id", "component_result_id", "data_size", "file_size")]
#> # A tibble: 4 × 4
#>   study_result_id component_result_id data_size file_size
#>             <int>               <int>     <dbl>     <dbl>
#> 1            9001                7001      2048      2048
#> 2            9002                7002         0        NA
#> 3            9002                7003      1536      1536
#> 4            9003                7004         0        NA
meta[is.na(meta$file) & meta$data_size > 0, ]   # still to download: none
#> # A tibble: 0 × 36
#> # ℹ 36 variables: study_id <int>, study_uuid <chr>, study_title <chr>,
#> #   study_result_id <int>, study_result_uuid <chr>, study_code <chr>,
#> #   worker_id <int>, worker_type <chr>, batch_id <int>, batch_uuid <chr>,
#> #   batch_title <chr>, group_id <int>, study_state <chr>,
#> #   study_start_time <dttm>, study_end_time <dttm>, study_duration <drtn>,
#> #   last_seen <dttm>, comment <chr>, study_message <chr>,
#> #   confirmation_code <chr>, quota_reached <lgl>, url_query <list>, …
```
