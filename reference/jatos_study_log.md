# Recent entries of a study log

Calls `GET /studies/{id}/log?download=false&entryLimit=`. JATOS streams
the log as newline-delimited JSON; each line becomes one row. Column
names follow the log entry fields (converted to snake case), which vary
between JATOS versions and entry types, so downstream code should select
columns by name defensively.

## Usage

``` r
jatos_study_log(study_id, limit = 100, conn = jatos_connection())
```

## Arguments

- study_id:

  Study id (integer) or uuid (string).

- limit:

  Maximum number of most recent log lines to return.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A tibble with one row per log entry and a `study_id` column. Nested
values are kept as list columns.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_study_log(12, limit = 20)
} # }
```
