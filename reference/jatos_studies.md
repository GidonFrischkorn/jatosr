# List the studies a token can see

Calls `GET /studies/properties`. Each row is one study; its components
and batches are nested as list columns of tibbles, so
`tidyr::unnest(studies, batches)` gives one row per batch.

## Usage

``` r
jatos_studies(
  with_components = TRUE,
  with_batches = TRUE,
  conn = jatos_connection()
)
```

## Arguments

- with_components, with_batches:

  Include full component and batch properties (`TRUE`, the default) or
  only their ids and uuids.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A tibble with one row per study: `study_id`, `study_uuid`, `title`,
`description`, `active`, `locked`, `group_study`, `linear_study`,
`allow_preview`, `dir_name`, `end_redirect_url`, `members` (list of
usernames), `components` and `batches` (list columns of tibbles in the
shape returned by
[`jatos_components()`](https://www.gfrischkorn.org/jatosr/reference/jatos_components.md)
and
[`jatos_batches()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batches.md)).

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
studies <- jatos_studies()
studies[grepl("Binding", studies$title), ]
} # }
```
