# Properties of study codes

Calls `GET /studyCodes/{code}` once per code. The server reports the
link paths relative to its base path (`studyLinkPath`, `studyEntryPath`
in `jatos-api.yaml`); they are joined to the origin of `conn$host` to
give full URLs.

## Usage

``` r
jatos_study_code(code, conn = jatos_connection())
```

## Arguments

- code:

  One or more study codes, as returned by
  [`jatos_create_study_codes()`](https://www.gfrischkorn.org/jatosr/reference/jatos_create_study_codes.md)
  or shown in the JATOS GUI.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A tibble with one row per code: `study_code`, `batch_id`, `type`,
`comment`, `active`, `study_link` (`<origin>/publix/<code>`) and
`study_entry_link` (`<origin>/publix/run?code=<code>`, the form JATOS
uses for its own study entry page).

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_study_code("8kw0pFV5M1e")
} # }
```
