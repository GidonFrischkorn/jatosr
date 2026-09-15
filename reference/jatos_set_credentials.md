# Store JATOS credentials in the system credential store

Stores the token of one credential profile in the credential store of
the operating system — the macOS keychain, the Windows credential store,
or the Secret Service on Linux — and the server's URL, which is not a
secret, in a small configuration file under
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html). Every
later R session on this machine can then connect without the token
appearing in any script, and without it being written anywhere in the
clear.

## Usage

``` r
jatos_set_credentials(
  host,
  token = NULL,
  profile = Sys.getenv("JATOS_PROFILE", "default"),
  check = TRUE
)
```

## Arguments

- host:

  Base URL of the JATOS server, e.g. `"https://jatos.example.org"`. A
  trailing slash or a pasted `/jatos/api/v1` is removed.

- token:

  Personal access token created in JATOS. If `NULL` and the session is
  interactive, you are prompted for it, with hidden input. Tokens
  usually start with `jap_`.

- profile:

  Name of the credential profile to write. `"default"` unless
  `JATOS_PROFILE` is set. Any other name must start with a letter and
  contain only letters, digits and underscores.

- check:

  If `TRUE` (the default), the token is verified once against the server
  with
  [`jatos_token_info()`](https://www.gfrischkorn.org/jatosr/reference/jatos_token_info.md)
  after it is stored, and its name and expiry are reported. A failed
  check is a warning, not an error, so credentials can be stored while
  the server is unreachable.

## Value

The profile name, invisibly.

## Details

A named profile keeps tokens for several accounts, or several servers,
side by side (see
[`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md)).
The profile name is the username of the keyring entry, so profiles and
entries map one to one.

## The configuration file

The host goes into `profiles.json` under
`tools::R_user_dir("jatosr", "config")`. It holds profile names and
hosts, never a token. Where that directory is not writable, or not
private (a container, a machine shared between users), set the
environment variable `JATOSR_CONFIG_DIR` to another directory before
calling this function; every function of the package then reads and
writes the configuration there.

## What this function does not do

It does not write the token to a file, and no other function in this
package does either. Environment variables are still read, and take
precedence over the credential store, so that continuous integration,
containers and cluster jobs can inject the token the way they inject
every other secret.

## See also

[`jatos_credentials_sitrep()`](https://www.gfrischkorn.org/jatosr/reference/jatos_credentials_sitrep.md)
to see where a token is coming from,
[`jatos_remove_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_remove_credentials.md)
to delete one, and
[`vignette("credentials")`](https://www.gfrischkorn.org/jatosr/articles/credentials.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_set_credentials("https://jatos.example.org")   # prompts for the token
jatos_set_credentials("https://jatos.example.org", profile = "lab_admin")
} # }
```
