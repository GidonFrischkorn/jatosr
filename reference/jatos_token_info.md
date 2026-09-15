# Check the token and show its metadata

Calls `GET /admin/token`, which any token may use to inspect itself.
This is the cheapest way to verify that the host and token of a profile
work: a wrong token gives a 401 error, a wrong host a 404 or an HTML
page.

## Usage

``` r
jatos_token_info(conn = jatos_connection())
```

## Arguments

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A one-row tibble with `token_id`, `name`, `username`, `user_id`,
`created`, `expires` (both POSIXct, UTC; `expires` is `NA` for tokens
without expiry), `expired`, `active`, and `roles` (list column).

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
jatos_token_info()
} # }
```
