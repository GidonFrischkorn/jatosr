# Package index

## Credentials and connection

Store the API token in the credential store of the operating system,
find out where a token is coming from, and check it against the server.

- [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md)
  : Connect to a JATOS server
- [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md)
  : Store JATOS credentials in the system credential store
- [`jatos_remove_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_remove_credentials.md)
  : Remove JATOS credentials from the credential store
- [`jatos_credentials_sitrep()`](https://www.gfrischkorn.org/jatosr/reference/jatos_credentials_sitrep.md)
  : Report where each token is coming from
- [`jatos_has_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_has_credentials.md)
  : Are JATOS credentials available?
- [`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md)
  : List the credential profiles on this machine
- [`jatos_token_info()`](https://www.gfrischkorn.org/jatosr/reference/jatos_token_info.md)
  : Check the token and show its metadata

## Study structure

Studies, components, batches and groups the token can see.

- [`jatos_studies()`](https://www.gfrischkorn.org/jatosr/reference/jatos_studies.md)
  : List the studies a token can see
- [`jatos_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study.md)
  : Properties of one study
- [`jatos_components()`](https://www.gfrischkorn.org/jatosr/reference/jatos_components.md)
  : Components of a study
- [`jatos_batches()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batches.md)
  : Batches of a study
- [`jatos_batch()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batch.md)
  : Properties of one batch
- [`jatos_groups()`](https://www.gfrischkorn.org/jatosr/reference/jatos_groups.md)
  : Groups of a batch (group studies only)
- [`jatos_study_log()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_log.md)
  : Recent entries of a study log

## Result metadata

One row per component result from the server or a local cache; one row
per study result on request; filters and the URL query parameters as
columns.

- [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md)
  : Result metadata, one row per component result

- [`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md)
  :

  Flatten a `/results/metadata` answer into a tibble

- [`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md)
  : One row per study result

- [`jatos_filter_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_filter_metadata.md)
  : Keep the study results that belong in a dataset

- [`jatos_url_query()`](https://www.gfrischkorn.org/jatosr/reference/jatos_url_query.md)
  : Widen the URL query parameters into columns

- [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
  : Rebuild result metadata from a local cache

- [`jatos_cache_status()`](https://www.gfrischkorn.org/jatosr/reference/jatos_cache_status.md)
  : Summarise a local cache batch by batch

## Result download, reading and export

Fetch result files into a local cache incrementally, pull single fields
out of them, read jsPsych JSON into one tibble with the metadata joined,
and save it; or do all of that in one call.

- [`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
  : Fetch, read and save the trials of a study in one call
- [`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
  : Download result data into a local cache
- [`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)
  : Extract scalar fields from result files without parsing them
- [`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md)
  : Read one jsPsych result file
- [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
  : Read the result files of a metadata tibble into one tibble
- [`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md)
  : Write a trials tibble to disk
- [`jatos_write_raw()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_raw.md)
  : Copy the raw result files, one per participant

## Uploaded files, archives and import

Files participants uploaded during a run, fetched with the same
incremental rule; the study archive (`.jzip`) that reproduces the
experiment; the results archive as the server builds it; and the import
of such a zip into a cache.

- [`jatos_result_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_result_files.md)
  : Files uploaded during a run, one row per file
- [`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md)
  : Download the files uploaded during runs into the cache
- [`jatos_export_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_study.md)
  : Download the study archive
- [`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md)
  : Download the results archive as the server produces it
- [`jatos_import_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_import_results.md)
  : Import a JATOS results zip into the cache

## Study codes

Generate, inspect, activate and deactivate study codes, and build the
run URLs participants open.

- [`jatos_create_study_codes()`](https://www.gfrischkorn.org/jatosr/reference/jatos_create_study_codes.md)
  : Generate study codes for a batch
- [`jatos_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_code.md)
  : Properties of study codes
- [`jatos_activate_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_activate_study_code.md)
  [`jatos_deactivate_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_activate_study_code.md)
  : Activate or deactivate study codes
- [`jatos_study_links()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_links.md)
  : Run URLs for study codes

## Package

- [`jatosr`](https://www.gfrischkorn.org/jatosr/reference/jatosr-package.md)
  [`jatosr-package`](https://www.gfrischkorn.org/jatosr/reference/jatosr-package.md)
  : jatosr: Download and Manage 'JATOS' Study Data
