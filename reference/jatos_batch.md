# Properties of one batch

Calls `GET /batches/{id}`.

## Usage

``` r
jatos_batch(batch_id, conn = jatos_connection())
```

## Arguments

- batch_id:

  Batch id (integer) or uuid (string).

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A one-row tibble in the shape of
[`jatos_batches()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batches.md);
`study_id` is `NA` because the endpoint does not report it.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_batch(34)
} # }
```
