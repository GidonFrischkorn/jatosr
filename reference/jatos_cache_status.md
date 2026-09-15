# Summarise a local cache batch by batch

Reads every `metadata.json` of a cache, as
[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
does, and reports per batch how many component results it lists, how
many are on disk, how many a run of
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
would fetch, and how many `data.txt` files sit in the batch directory
without a metadata row (orphans, counted inside that batch directory
only; a fresh download of the batch's metadata covers them). No request
is made.

## Usage

``` r
jatos_cache_status(path, batch_id = NULL)
```

## Arguments

- path:

  The cache directory, one `batch_<id>` directory inside it, or the path
  of a single `metadata.json` file.

- batch_id:

  Optional ids to keep only some batches.

## Value

A tibble with one row per `metadata.json`: `batch_id` (`NA` when the
file holds several batches), `path` (its directory), `n_results`
(component results listed), `n_downloaded` (with a local file),
`n_pending` (server size above `0` and no local file, or a local file
smaller than the server's), `n_shrunk` (local file larger than the
server's), `n_orphans` (data files without a metadata row) and `bytes`
(size of the local data files). With `batch_id`, the counts cover the
rows of those batches and a `metadata.json` without any of them is left
out; `n_orphans` still compares the directory with every row of its
`metadata.json`, so the files of another batch listed there are not
orphans.

## Examples

``` r
cache <- system.file("extdata", "JATOS_data", package = "jatosr")
jatos_cache_status(cache)
#> # A tibble: 1 × 8
#>   batch_id path        n_results n_downloaded n_pending n_shrunk n_orphans bytes
#>      <int> <chr>           <int>        <int>     <int>    <int>     <int> <dbl>
#> 1       34 /home/runn…         4            2         0        0         0  3584
jatos_cache_status(cache, batch_id = 34)
#> # A tibble: 1 × 8
#>   batch_id path        n_results n_downloaded n_pending n_shrunk n_orphans bytes
#>      <int> <chr>           <int>        <int>     <int>    <int>     <int> <dbl>
#> 1       34 /home/runn…         4            2         0        0         0  3584
```
