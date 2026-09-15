# Widen the URL query parameters into columns

The `url_query` column of a metadata tibble holds, per study result, the
query parameters the worker arrived with, which for a Prolific study
link are `PROLIFIC_PID`, `STUDY_ID` and `SESSION_ID`. This turns them
into one character column per parameter, named in snake case with
`prefix` in front (`query_prolific_pid`, `query_study_id`,
`query_session_id`), so that the tibble joins to a Prolific export
without unnesting. Study results without a parameter get `NA`; a tibble
without any parameter is returned unchanged. Two parameters that differ
only in case or separators (`PROLIFIC_PID` and `prolific_pid`) would
share a column name; the second gets a numeric suffix and a warning
names both keys.

## Usage

``` r
jatos_url_query(metadata, prefix = "query_")
```

## Arguments

- metadata:

  A metadata tibble with a `url_query` list column.

- prefix:

  Prefix of the new column names. The default keeps `STUDY_ID` from
  colliding with the `study_id` column.

## Value

`metadata` with one column per parameter appended; `url_query` stays.

## Examples

``` r
meta <- jatos_flatten_metadata(
  system.file("extdata", "metadata.json", package = "jatosr")
)
jatos_url_query(meta)[, c("study_result_id", "query_prolific_pid", "query_session_id")]
#> # A tibble: 6 × 3
#>   study_result_id query_prolific_pid query_session_id
#>             <int> <chr>              <chr>           
#> 1            9001 NA                 NA              
#> 2            9002 NA                 NA              
#> 3            9002 NA                 NA              
#> 4            9003 NA                 NA              
#> 5            9004 p-0004             s-0004          
#> 6            9004 p-0004             s-0004          
```
