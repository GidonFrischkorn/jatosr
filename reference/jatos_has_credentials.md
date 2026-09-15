# Are JATOS credentials available?

Checks whether a host and a token can be found for a credential profile:
the host from `JATOS_HOST` (or `JATOS_HOST_<PROFILE>`) or the profile
configuration file, the token from `JATOS_TOKEN` (or
`JATOS_TOKEN_<PROFILE>`) or the system credential store. No secret is
retrieved and no request is made; use
[`jatos_token_info()`](https://www.gfrischkorn.org/jatosr/reference/jatos_token_info.md)
to find out whether the token also works.

## Usage

``` r
jatos_has_credentials(profile = Sys.getenv("JATOS_PROFILE", "default"))
```

## Arguments

- profile:

  Name of the credential profile, as given to
  [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md).
  Defaults to the `JATOS_PROFILE` environment variable, or `"default"`
  when that is unset, so a single-account setup never passes it.
  Case-insensitive.

## Value

`TRUE` or `FALSE`.

## Examples

``` r
if (FALSE) { # \dontrun{
# lists the machine's credential store
jatos_has_credentials()
jatos_has_credentials("lab_admin")
} # }
```
