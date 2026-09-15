# Run URLs for study codes

Turns study codes into the links participants open,
`<host>/publix/<code>`. No request is made. The pattern is the
`GET /publix/:studyCode` route of the JATOS publix module
(`modules/publix/conf/publix.routes` in the JATOS repository, and the
`studyLinkPath` field of `GET /studyCodes/{code}` in `jatos-api.yaml`,
both read 2026-09-05). Any base path under which JATOS is served is part
of `host`.

## Usage

``` r
jatos_study_links(
  code,
  host = NULL,
  profile = Sys.getenv("JATOS_PROFILE", "default")
)
```

## Arguments

- code:

  One or more study codes.

- host:

  Base URL of the JATOS server. Defaults to the host variable of the
  credential profile (`JATOS_HOST` for the default profile); the token
  is not needed.

- profile:

  Name of the credential profile, as given to
  [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md).
  Defaults to the `JATOS_PROFILE` environment variable, or `"default"`
  when that is unset, so a single-account setup never passes it.
  Case-insensitive.

## Value

A character vector of URLs, one per code.

## Examples

``` r
jatos_study_links(c("8kw0pFV5M1e", "Qm3xYtb9Lc2"), host = "https://jatos.example.org")
#> [1] "https://jatos.example.org/publix/8kw0pFV5M1e"
#> [2] "https://jatos.example.org/publix/Qm3xYtb9Lc2"
```
