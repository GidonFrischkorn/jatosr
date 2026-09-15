# Result metadata, one row per component result

Calls `POST /results/metadata` with the ids as a JSON body, so any
number of ids fits in one request. Results the token cannot see are left
out by the server without an error. The answer is flattened with
[`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md);
see there for the columns.

## Usage

``` r
jatos_results_metadata(
  study_id = NULL,
  batch_id = NULL,
  component_id = NULL,
  study_result_id = NULL,
  component_result_id = NULL,
  group_id = NULL,
  conn = jatos_connection()
)
```

## Arguments

- study_id, component_id:

  Ids (integer) or uuids (string) to select results by, one kind per
  argument; `NULL` (the default) means no restriction on that dimension.
  Uuids go to the server as `studyUuids` and `componentUuids`.

- batch_id, study_result_id, component_result_id, group_id:

  Ids to select results by. `NULL` (the default) means no restriction on
  that dimension. The server takes no uuid for these.

- conn:

  A
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

## Value

A metadata tibble, one row per component result, with the columns
documented in
[`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md).

## Details

Every id argument accepts one or more integer ids; `study_id` and
`component_id` also accept uuid strings, which survive a study's export
and import on another server while its id changes. At least one must be
given; several are combined as the server combines them (the union of
everything selected). A message reports the host, the number of study
results and component results, and how many component results are not
`FINISHED`; silence it with `options(rlib_message_verbosity = "quiet")`
or [`suppressMessages()`](https://rdrr.io/r/base/message.html).

## See also

[`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md)
for one row per study result,
[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
to rebuild the same tibble from a local cache.

## Examples

``` r
if (FALSE) { # \dontrun{
# needs a JATOS server and a stored API token
meta <- jatos_results_metadata(study_id = 12)
meta[meta$component_state == "FINISHED" & meta$data_size > 0, ]
} # }
```
