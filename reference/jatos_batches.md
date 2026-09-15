# Batches of a study

Calls `GET /studies/{id}/batches`.

## Usage

``` r
jatos_batches(study_id, conn = jatos_connection())
```

## Arguments

- study_id:

  Study id (integer) or uuid (string).

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A tibble with `batch_id`, `batch_uuid`, `title`, `active`,
`max_total_workers`, `max_active_members`, `max_total_members`,
`allowed_worker_types` (list column), `study_id`.

## Server support

This endpoint does not exist on every JATOS. On a server whose API
reports `apiVersion` 1.0.1 it answers 404 for a study that
[`jatos_studies()`](https://www.gfrischkorn.org/jatosr/reference/jatos_studies.md)
has just listed, and the error says so. There is no version endpoint to
check in advance; `apiVersion` in the envelope of any successful answer
is the only signal.

`jatos_studies(with_batches = TRUE)` (the default) is the way round it,
and is cheaper anyway: it returns every study's batches as a nested
`batches` column in one request rather than one request per study.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_batches(12)
} # }
```
