# Components of a study

Calls `GET /studies/{id}/components`.

## Usage

``` r
jatos_components(study_id, conn = jatos_connection())
```

## Arguments

- study_id:

  Study id (integer) or uuid (string).

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A tibble with `component_id`, `component_uuid`, `title`,
`html_file_path`, `active`, `reloadable`, `study_id`.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_components(12)
} # }
```
