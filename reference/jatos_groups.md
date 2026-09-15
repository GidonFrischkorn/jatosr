# Groups of a batch (group studies only)

Calls `GET /batches/{id}/groups`.

## Usage

``` r
jatos_groups(batch_id, conn = jatos_connection())
```

## Arguments

- batch_id:

  Batch id (integer) or uuid (string).

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A tibble with `group_id`, `group_state`, `n_active`, `n_history`,
`n_results`, `active_members`, `history_members` (list columns of study
result ids), `start_time`, `end_time`, `batch_id`.

## Server support

Like
[`jatos_batches()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batches.md),
this is a nested route under a resource, and the one server where those
were tested (`apiVersion` 1.0.1) has none of them. It was not confirmed
for this endpoint — no group study was available there — so treat a 404
as a possible missing route rather than a wrong batch id; the error
distinguishes the two from the server's own wording.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_groups(34)
} # }
```
