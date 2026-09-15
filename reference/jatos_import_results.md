# Import a JATOS results zip into the cache

Unpacks a zip that JATOS itself produced, from the GUI's "Export
Results" or from
[`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md),
into the cache layout that
[`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
writes: `metadata.json` at the zip root and
`study_result_<id>/comp-result_<id>/data.txt` (plus `files/<name>` for
uploads) become `<path>/batch_<id>/metadata.json` and
`<path>/batch_<id>/study_result_<id>/comp-result_<id>/...`, one batch
folder per batch id in the zip's `metadata.json`, each with a
`metadata.json` holding only that batch's study results. This is the one
way data that did not come through the package enters a cache; the
reader,
[`jatos_cache_status()`](https://www.gfrischkorn.org/jatosr/reference/jatos_cache_status.md)
and later incremental downloads then treat it like any other cache.
Entries whose study result the `metadata.json` does not list are left
out with a message.

## Usage

``` r
jatos_import_results(zip, path, overwrite = FALSE)
```

## Arguments

- zip:

  Path of the zip file.

- path:

  The cache directory. Created when missing; must be empty or in the
  package layout.

- overwrite:

  If `TRUE`, files of a batch that is already in the cache are replaced.

## Value

The metadata tibble of the imported batches as
[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
returns it, invisibly; a message reports the batches, component results
and files imported.

## Details

A batch folder that already exists in `path` is refused unless
`overwrite = TRUE`, which replaces its `metadata.json` and every file
the zip carries and leaves other files in place.

## See also

[`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md)
to fetch such a zip from the server,
[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
and
[`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
with `download = FALSE` to work from the cache.

## Examples

``` r
zip <- system.file("extdata", "results.zip", package = "jatosr")

cache <- tempfile("jatosr-example-")
jatos_import_results(zip, cache)
#> ✔ Imported batch 34 into /tmp/RtmpHTC4Nw/jatosr-example-190414a0b55c: 4
#>   component results listed, 2 data files and 0 uploaded files written.
jatos_cache_status(cache)
#> # A tibble: 1 × 8
#>   batch_id path        n_results n_downloaded n_pending n_shrunk n_orphans bytes
#>      <int> <chr>           <int>        <int>     <int>    <int>     <int> <dbl>
#> 1       34 /tmp/RtmpH…         4            2         0        0         0  3584
unlink(cache, recursive = TRUE)
```
