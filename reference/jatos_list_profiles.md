# List the credential profiles on this machine

A profile is a named pair of a host and a token, so that one machine can
hold credentials for several accounts on one server, or for several
servers, side by side. The profile `"default"` is the one used when none
is named.

## Usage

``` r
jatos_list_profiles()
```

## Value

A tibble with one row per profile: `profile` (lower-case name), `host`
(`NA` when no host is known), `has_token`, `active` (`TRUE` for the
profile that
[`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md)
uses when called without a `profile` argument, from `JATOS_PROFILE` or
`"default"`), and `auth_from`, which of `"env"` or `"keyring"` a token
would be taken from. The default profile comes first, the rest are
sorted by name. Zero rows when nothing is set.

`active` is `FALSE` in *every* row on a machine that holds named
profiles only: there is no unsuffixed `JATOS_HOST` / `JATOS_TOKEN` pair
and `JATOS_PROFILE` is unset, so nothing is selected and a bare
[`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md)
has no credentials to read. That is a valid setup, not a fault; name a
profile with `jatos_connection("<name>")`, or set `JATOS_PROFILE` to
make one of them active.

## Details

Profiles are collected from all three places the package reads: the
environment variables of this session (`JATOS_HOST_<PROFILE>` and
`JATOS_TOKEN_<PROFILE>`, or the unsuffixed pair for `"default"`), the
profile configuration file written by
[`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md),
and the system credential store. It makes no request, retrieves no
secret, and never returns a token — the credential store is asked for
its entry names only, so nothing is unlocked.

## Examples

``` r
if (FALSE) { # \dontrun{
# lists the machine's credential store
jatos_list_profiles()
} # }
```
