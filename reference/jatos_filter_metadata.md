# Keep the study results that belong in a dataset

Drops rows of a metadata tibble by study state, worker type, start time
and explicit exclusions, the filters every export makes before the
trials are read: unfinished runs (`study_state != "FINISHED"`), the
researcher's own test runs from the JATOS GUI
(`worker_type == "Jatos"`), runs before the study went live or after a
wave closed, and known test runs by their study result or worker id. The
filters work on the study result, the run of one participant, so every
component result of a dropped run goes with it. A message reports how
many study results each filter removed; no message when no filter is
given.

## Usage

``` r
jatos_filter_metadata(
  metadata,
  states = NULL,
  worker_types = NULL,
  since = NULL,
  until = NULL,
  exclude_study_result_id = NULL,
  exclude_worker_id = NULL,
  tz = "UTC"
)
```

## Arguments

- metadata:

  A metadata tibble from
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md)
  or
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md).

- states:

  Study states to keep, for example `"FINISHED"`. `NULL` keeps every
  state. JATOS states are `PRE`, `STARTED`, `DATA_RETRIEVED`,
  `FINISHED`, `ABORTED` and `FAIL`.

- worker_types:

  Worker types to keep, for example
  `c("PersonalSingle", "GeneralMultiple")`. `NULL` keeps every type; the
  GUI test runs are `"Jatos"`.

- since:

  Keep study results that started at or after this time: a `POSIXct`, a
  `Date`, or a string such as `"2025-08-24"` or `"2025-08-24 12:00:00"`,
  read in the time zone `tz`. Rows without a start time are dropped when
  `since` is given.

- until:

  Keep study results that started *before* this time, given like
  `since`; `since` and `until` together select a half-open interval, so
  `since = "2025-08-24", until = "2025-08-25"` is one day. Rows without
  a start time are dropped when `until` is given.

- exclude_study_result_id, exclude_worker_id:

  Study result ids, or worker ids, whose study results are dropped; for
  the researcher's own runs through a real link, which `worker_types`
  cannot tell apart.

- tz:

  Time zone in which date strings in `since` and `until` are read, and
  in which the message shows them. `"UTC"` by default, the zone the
  server reports times in;
  [`Sys.timezone()`](https://rdrr.io/r/base/timezones.html) for local
  time.

## Value

`metadata` without the dropped rows.

## See also

[`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md),
which applies the same filters before the download.

## Examples

``` r
meta <- jatos_flatten_metadata(
  system.file("extdata", "metadata.json", package = "jatosr")
)
jatos_filter_metadata(meta, states = "FINISHED", since = "2025-08-24")
#> ℹ Excluded 1 of 4 study results; 3 remain.
#> • 1 by study state (kept "FINISHED")
#> • 0 that started before 2025-08-24 00:00:00 UTC
#> # A tibble: 5 × 34
#>   study_id study_uuid   study_title study_result_id study_result_uuid study_code
#>      <int> <chr>        <chr>                 <int> <chr>             <chr>     
#> 1       12 1c2d3e4f-00… A03_ColorB…            9001 sr-9001           code9001  
#> 2       12 1c2d3e4f-00… A03_ColorB…            9002 sr-9002           code9002  
#> 3       12 1c2d3e4f-00… A03_ColorB…            9002 sr-9002           code9002  
#> 4       13 1c2d3e4f-00… A01_Regist…            9004 sr-9004           code9004  
#> 5       13 1c2d3e4f-00… A01_Regist…            9004 sr-9004           code9004  
#> # ℹ 28 more variables: worker_id <int>, worker_type <chr>, batch_id <int>,
#> #   batch_uuid <chr>, batch_title <chr>, group_id <int>, study_state <chr>,
#> #   study_start_time <dttm>, study_end_time <dttm>, study_duration <drtn>,
#> #   last_seen <dttm>, comment <chr>, study_message <chr>,
#> #   confirmation_code <chr>, quota_reached <lgl>, url_query <list>,
#> #   component_result_id <int>, component_id <int>, component_uuid <chr>,
#> #   component_state <chr>, component_start_time <dttm>, …
jatos_filter_metadata(meta, until = "2025-08-24 02:00", exclude_worker_id = 503)
#> ℹ Excluded 3 of 4 study results; 1 remains.
#> • 3 that started at or after 2025-08-24 02:00:00 UTC
#> • 0 by worker id (1 excluded)
#> # A tibble: 1 × 34
#>   study_id study_uuid   study_title study_result_id study_result_uuid study_code
#>      <int> <chr>        <chr>                 <int> <chr>             <chr>     
#> 1       12 1c2d3e4f-00… A03_ColorB…            9001 sr-9001           code9001  
#> # ℹ 28 more variables: worker_id <int>, worker_type <chr>, batch_id <int>,
#> #   batch_uuid <chr>, batch_title <chr>, group_id <int>, study_state <chr>,
#> #   study_start_time <dttm>, study_end_time <dttm>, study_duration <drtn>,
#> #   last_seen <dttm>, comment <chr>, study_message <chr>,
#> #   confirmation_code <chr>, quota_reached <lgl>, url_query <list>,
#> #   component_result_id <int>, component_id <int>, component_uuid <chr>,
#> #   component_state <chr>, component_start_time <dttm>, …
```
