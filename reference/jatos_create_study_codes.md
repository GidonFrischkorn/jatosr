# Generate study codes for a batch

Calls `POST /studies/{id}/studyCodes`. A study code is what JATOS puts
at the end of a study link (`<host>/publix/<code>`); each code belongs
to one batch and one worker type. For the personal types
(`PersonalSingle`, `PersonalMultiple`) the server creates `n` new codes,
each with its own worker and the optional `comment`. For the general
types (`GeneralSingle`, `GeneralMultiple`, `MTurk`) a batch has exactly
one code, which the server creates on first request and returns
unchanged afterwards; `n` must be `1` and `comment` `NULL` for them,
checked before any request is made.

## Usage

``` r
jatos_create_study_codes(
  study_id,
  batch_id = NULL,
  n = 1,
  type = c("PersonalSingle", "PersonalMultiple", "GeneralSingle", "GeneralMultiple",
    "MTurk"),
  comment = NULL,
  conn = jatos_connection()
)
```

## Arguments

- study_id:

  Study id (integer) or uuid (string).

- batch_id:

  Batch id. `NULL` (the default) uses the study's default batch; the
  returned `batch_id` is then `NA` because the server does not report
  which batch that is.

- n:

  Number of codes to generate, `1` to `1000` (the server's limit);
  personal types only.

- type:

  Worker type of the codes. One of `"PersonalSingle"`,
  `"PersonalMultiple"`, `"GeneralSingle"`, `"GeneralMultiple"`,
  `"MTurk"`.

- comment:

  Optional comment stored with each worker; personal types only. Plain
  text up to 255 characters, no HTML.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A tibble with one row per code: `study_code`, `study_id` (`NA` when
`study_id` was a uuid), `batch_id`, `type`, `comment`, and `study_link`,
the run URL built by
[`jatos_study_links()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_links.md).

## Details

The server answers with the codes only (verified against
`jatos-api.yaml`, 2026-09-05). Whether a code is active, and its batch
when `batch_id` was not given, come from
[`jatos_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_code.md).

## See also

[`jatos_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_code.md)
for the properties of a code,
[`jatos_deactivate_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_activate_study_code.md)
to close one,
[`jatos_study_links()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_links.md)
for the run URLs.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
codes <- jatos_create_study_codes(12, batch_id = 34, n = 20, comment = "wave 2")
writeLines(codes$study_link)
} # }
```
