# Read one jsPsych result file

Parses a `data.txt` written by jsPsych (a JSON array of trial objects)
into a tibble with one row per trial. A file that holds several JSON
values back to back, which is what repeated `jatos.appendResultData()`
calls leave behind (arrays after arrays, or one object per call), is
split into its top-level values first and read as one array. An empty
file gives a tibble with no rows and no columns.

## Usage

``` r
jatos_read_json(file, flatten = FALSE)
```

## Arguments

- file:

  Path of the file.

- flatten:

  If `TRUE`, nested objects become columns named `outer.inner` (see
  [`jsonlite::fromJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html));
  otherwise they stay nested data-frame columns when every trial of the
  file carries the same object, and list columns otherwise.
  [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
  stores both as list columns before it binds files.

## Value

A tibble. A key that is the empty string (an unnamed form input) becomes
a column `unnamed_<position>`.

## See also

[`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
to read every file of a metadata tibble.

## Examples

``` r
file <- system.file("extdata", "data.txt", package = "jatosr")
trials <- jatos_read_json(file)
trials[, c("trial_index", "trial_type", "rt", "correct")]
#> # A tibble: 9 × 4
#>   trial_index trial_type                rt correct
#>         <int> <chr>                  <int> <lgl>  
#> 1           0 survey-html-form       14250 NA     
#> 2           1 html-keyboard-response   737 TRUE   
#> 3           2 html-keyboard-response   824 TRUE   
#> 4           3 html-keyboard-response   761 FALSE  
#> 5           4 html-keyboard-response   848 TRUE   
#> 6           5 html-keyboard-response   935 TRUE   
#> 7           6 html-keyboard-response   872 TRUE   
#> 8           7 html-keyboard-response   959 TRUE   
#> 9           8 html-keyboard-response  1046 FALSE  
jatos_read_json(file, flatten = TRUE)[1, ]
#> # A tibble: 1 × 11
#>      rt response         trial_type      trial_index plugin_version time_elapsed
#>   <int> <list>           <chr>                 <int> <chr>                 <int>
#> 1 14250 <named list [2]> survey-html-fo…           0 2.0.0                 14268
#> # ℹ 5 more variables: participant_id <chr>, stimulus <chr>, set_size <int>,
#> #   change <lgl>, correct <lgl>
```
