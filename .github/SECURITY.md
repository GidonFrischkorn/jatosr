# Security policy

jatosr handles JATOS API tokens, which give access to study data. A token
that reaches a message, a log, a file the package writes, or a saved object
is a security bug.

## If a token has leaked

1. Revoke it first, in the JATOS user interface under *API tokens* in the
   user menu. Removing it with `jatos_remove_credentials()` deletes only
   your local copy; the token keeps working until it is revoked.
2. Create a new token and store it with `jatos_set_credentials()`.

## Reporting a vulnerability

Report a way in which jatosr exposes a token, or any other security problem,
privately through GitHub: the *Security* tab of this repository, then
*Report a vulnerability*. Do not open a public issue, and do not include a
working token in the report; a revoked one, or a description of where it
appeared, is enough.

## Supported versions

The `main` branch of this repository and, once there is one, the latest
release on CRAN.
