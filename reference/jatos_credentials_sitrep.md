# Report where each token is coming from

Prints, for every credential profile on this machine, which of the three
places the package reads a host and a token would actually be taken
from: an environment variable, the system credential store, or the
profile configuration file. It never prints a token, and never a hash, a
prefix or a length of one.

## Usage

``` r
jatos_credentials_sitrep(profile = NULL)
```

## Arguments

- profile:

  Report only this profile. `NULL`, the default, reports every profile
  found in any of the three places.

## Value

A tibble, invisibly, with one row per profile: `profile`, `host`,
`host_from` (`"env"`, `"config"` or `"none"`), `auth_from` (`"env"`,
`"keyring"` or `"none"`), `shadowed` (an environment variable is hiding
a stored token), `renviron_line` (an `.Renviron` file defines this
profile) and `renviron_file`. No column holds a token.

## Details

Use it when a call fails with credentials that look correct, and when
two profiles might be confused. The report starts with the versions of
jatosr, `keyring`, R and the operating system (and the commit, for a
package installed from GitHub), so that it can be pasted into a bug
report as it is, once the host is replaced if the server is private.

An environment variable wins over the credential store. When a user or
project `.Renviron` file defines the variables of a profile, the report
names the file and the lines, with the token's value hidden, because a
token stored with
[`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md)
is not used while such a line sets the variable. The file is only read,
never edited.

## See also

[`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md),
[`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md),
[`vignette("credentials")`](https://www.gfrischkorn.org/jatosr/articles/credentials.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# lists the machine's credential store
jatos_credentials_sitrep()
jatos_credentials_sitrep("lab_admin")
} # }
```
