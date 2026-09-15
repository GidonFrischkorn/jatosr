# Connect to a JATOS server

Builds the connection object that every API function takes as its `conn`
argument. With no arguments, the host and token of the active credential
profile are looked up: the host from `JATOS_HOST` (or
`JATOS_HOST_<PROFILE>`) or the profile configuration file, the token
from `JATOS_TOKEN` (or `JATOS_TOKEN_<PROFILE>`) or the system credential
store (see
[`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md)
and
[`jatos_credentials_sitrep()`](https://www.gfrischkorn.org/jatosr/reference/jatos_credentials_sitrep.md)).
A named profile is how you keep tokens for several accounts on one
server, or for several servers, side by side. Explicit `host` and
`token` arguments take precedence over both.

## Usage

``` r
jatos_connection(
  profile = Sys.getenv("JATOS_PROFILE", "default"),
  host = NULL,
  token = NULL
)
```

## Arguments

- profile:

  Name of the credential profile, as given to
  [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md).
  Defaults to the `JATOS_PROFILE` environment variable, or `"default"`
  when that is unset, so a single-account setup never passes it.
  Case-insensitive.

- host:

  Base URL of the JATOS server, e.g. `"https://jatos.example.org"`.
  Defaults to the profile's host.

- token:

  Personal access token. Defaults to the profile's stored token. Kept
  for this connection and for this session only.

## Value

An object of class `jatos_connection` with elements `profile`, `host`,
`api_url`, `id`, `auth_from` and `user_agent`. There is no `token`
element.

## Details

Everything is resolved here rather than at the first request, so a
missing or unreadable token is an error where the connection is built,
and a credential store that has to be unlocked asks once. When
[`jatos_token_info()`](https://www.gfrischkorn.org/jatosr/reference/jatos_token_info.md)
has seen that the token expires within seven days, the next
`jatos_connection()` warns once per session.

## The connection holds no token

`conn` carries the profile name, the host and an opaque session id — not
the secret. The token itself stays in this R session, in an environment
the package owns, and is fetched only inside the request builder. So
`saveRDS(conn)`, [`save.image()`](https://rdrr.io/r/base/save.html), an
`.RData` written at the end of a session, a knitr cache or a targets
store may hold a connection without writing a token to disk. A
connection read back in another session has a dead id and resolves its
profile afresh, so it keeps working if that profile is still stored.

This is a guarantee about this package's own objects. A token you assign
to a variable yourself, or pass as `token =` and keep, is an ordinary
string and is saved like one.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
conn <- jatos_connection()
conn
admin <- jatos_connection("lab_admin")
jatos_studies(conn = admin)
} # }
```
