# Activate or deactivate study codes

Calls `PATCH /studyCodes/{code}` with `{"active": true}` or
`{"active": false}` once per code. A deactivated code no longer admits a
participant; the study link stays valid and can be activated again.

## Usage

``` r
jatos_activate_study_code(code, conn = jatos_connection())

jatos_deactivate_study_code(code, conn = jatos_connection())
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

A tibble in the shape of
[`jatos_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_code.md)
with the new state.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
codes <- jatos_create_study_codes(12, n = 5, type = "PersonalMultiple")
jatos_deactivate_study_code(codes$study_code)
} # }
```
