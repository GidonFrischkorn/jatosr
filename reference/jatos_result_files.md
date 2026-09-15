# Files uploaded during a run, one row per file

Widens the `files` list column of a metadata tibble into one row per
attached file, so that what a study's participants uploaded (drawings,
audio recordings, anything sent with `jatos.uploadResultFile()`) can be
listed, filtered and planned before a download. Component results
without files contribute no row.

## Usage

``` r
jatos_result_files(metadata)
```

## Arguments

- metadata:

  A metadata tibble from
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md),
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
  or
  [`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md).
  Only its id columns and `files` are used.

## Value

A tibble with `study_result_id`, `component_result_id`, `component_id`,
`batch_id`, `filename` and `size` (bytes on the server).

## See also

[`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md)
to fetch them.

## Examples

``` r
meta <- jatos_flatten_metadata(
  system.file("extdata", "metadata.json", package = "jatosr")
)
jatos_result_files(meta)
#> # A tibble: 1 × 6
#>   study_result_id component_result_id component_id batch_id filename     size
#>             <int>               <int>        <int>    <int> <chr>       <dbl>
#> 1            9002                7003          121       34 drawing.png  4096
```
