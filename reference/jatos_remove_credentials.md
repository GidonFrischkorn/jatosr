# Remove JATOS credentials from the credential store

Deletes one credential profile's token from the system credential store
and its host from the configuration file, the exact inverse of
[`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md).
Every other profile is kept. Use it to clear a profile that was set up
for a test, or after a token has been revoked in JATOS.

## Usage

``` r
jatos_remove_credentials(
  profile = Sys.getenv("JATOS_PROFILE", "default"),
  confirm = TRUE
)
```

## Arguments

- profile:

  Name of the credential profile to remove. `"default"` unless
  `JATOS_PROFILE` is set. Case-insensitive; see
  [`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md).

- confirm:

  Ask before deleting. With the default `TRUE`, an interactive session
  shows a prompt, and a session that cannot show one (a script, a
  document being knitted) is an error, never a silent removal: a token
  stored nowhere else cannot be recovered, because JATOS shows it once.
  Pass `confirm = FALSE` to remove without asking, which is what a
  script that means it does.

## Value

The profile name, invisibly.

## Details

This removes your local copy of the token. It does not revoke it: the
token keeps working for anyone who has it until you delete it in the
JATOS web interface, under *API tokens* in the user menu. Revoke there
first if the token may have leaked.

## Examples

``` r
if (FALSE) { # \dontrun{
# changes the machine's credential store
jatos_remove_credentials(profile = "lab_admin")
jatos_remove_credentials()                        # the default profile
jatos_list_profiles()
} # }
```
