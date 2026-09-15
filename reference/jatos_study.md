# Properties of one study

Calls `GET /studies/{id}/properties` with components and batches
included.

## Usage

``` r
jatos_study(study_id, conn = jatos_connection())
```

## Arguments

- study_id:

  Study id (integer) or uuid (string).

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A one-row tibble in the shape of
[`jatos_studies()`](https://www.gfrischkorn.org/jatosr/reference/jatos_studies.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_study(12)
} # }
```
