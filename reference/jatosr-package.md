# jatosr: Download and Manage 'JATOS' Study Data

A client for the REST API of JATOS (Just Another Tool for Online
Studies). Tokens are stored in the credential store of the operating
system, and read from the `JATOS_TOKEN` environment variable where a
platform injects one, so that they never appear in scripts and are never
written to disk in the clear; several accounts or servers are kept apart
as named profiles. See
[`vignette("credentials")`](https://www.gfrischkorn.org/jatosr/articles/credentials.md)
for how to store them and
[`vignette("jatosr")`](https://www.gfrischkorn.org/jatosr/articles/jatosr.md)
for the download workflow, online and from the cache.

## Function families

- Credentials and connection:
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md),
  [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md),
  [`jatos_remove_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_remove_credentials.md),
  [`jatos_has_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_has_credentials.md),
  [`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md),
  [`jatos_credentials_sitrep()`](https://www.gfrischkorn.org/jatosr/reference/jatos_credentials_sitrep.md),
  [`jatos_token_info()`](https://www.gfrischkorn.org/jatosr/reference/jatos_token_info.md).

- Study structure:
  [`jatos_studies()`](https://www.gfrischkorn.org/jatosr/reference/jatos_studies.md),
  [`jatos_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study.md),
  [`jatos_components()`](https://www.gfrischkorn.org/jatosr/reference/jatos_components.md),
  [`jatos_batches()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batches.md),
  [`jatos_batch()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batch.md),
  [`jatos_groups()`](https://www.gfrischkorn.org/jatosr/reference/jatos_groups.md),
  [`jatos_study_log()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_log.md).

- Result metadata:
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md),
  [`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md),
  [`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md),
  [`jatos_filter_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_filter_metadata.md),
  [`jatos_url_query()`](https://www.gfrischkorn.org/jatosr/reference/jatos_url_query.md),
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md),
  [`jatos_cache_status()`](https://www.gfrischkorn.org/jatosr/reference/jatos_cache_status.md).

- Result download, reading and export:
  [`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
  (the pipeline in one call, online or from the cache),
  [`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md),
  [`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md),
  [`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md),
  [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md),
  [`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md),
  [`jatos_write_raw()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_raw.md).

- Uploaded files, archives and import:
  [`jatos_result_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_result_files.md),
  [`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md),
  [`jatos_export_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_study.md),
  [`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md),
  [`jatos_import_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_import_results.md).

- Study codes:
  [`jatos_create_study_codes()`](https://www.gfrischkorn.org/jatosr/reference/jatos_create_study_codes.md),
  [`jatos_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_code.md),
  [`jatos_activate_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_activate_study_code.md),
  [`jatos_deactivate_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_activate_study_code.md),
  [`jatos_study_links()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_links.md).

## Conditions

The errors of the credential, argument, cache and metadata layers carry
a class, so that a script can handle one kind and let the others
through, for example
`tryCatch(jatos_connection(), jatosr_no_token = function(cnd) NULL)`.
Errors from the server keep the `httr2` classes (`httr2_http_401` and so
on); a file that is not valid JSON, a file that could not be written and
a request that never reached the server are plain errors.

- `jatosr_bad_argument`: an argument of the wrong type, length or value,
  from any function.

- `jatosr_bad_profile`: a profile name that is not an identifier.

- `jatosr_no_host`: no host for the profile, from
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md)
  and
  [`jatos_study_links()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_links.md).

- `jatosr_no_token`: no token for the profile anywhere, or a cancelled
  prompt, from
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md).

- `jatosr_keyring_unreadable`: the credential store holds the profile's
  entry but cannot be read (locked, or a broken backend).

- `jatosr_keyring_write_failed`: the credential store refused the token,
  from
  [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md);
  the profile configuration is put back as it was.

- `jatosr_no_store`: no persistent credential store on this system, from
  [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md).

- `jatosr_needs_interactive`: a prompt is needed and the session cannot
  show one, from
  [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md)
  without a `token` and
  [`jatos_remove_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_remove_credentials.md)
  with `confirm = TRUE`.

- `jatosr_config_write_failed`: the profile configuration file could not
  be written; nothing was stored.

- `jatosr_bad_metadata`: not a metadata tibble, or one lacking columns
  or ids; a `metadata.json` that cannot be imported.

- `jatosr_cache_layout`: a directory that is not a cache written by
  jatosr, or a cache without a `metadata.json`.

- `jatosr_zip_unreadable`: an answer or a file that is not a zip, or one
  that cannot be unpacked.

- `jatosr_incomplete_download`:
  [`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
  when a component result could not be downloaded.

- `jatosr_file_exists`: a target file or batch folder is in the way and
  `overwrite = FALSE`.

One warning is classed: `jatosr_files_skipped`, from
[`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
with `on_error = "skip"`, with the skipped paths in its `files` field.

## See also

Useful links:

- <https://github.com/GidonFrischkorn/jatosr>

- <https://www.gfrischkorn.org/jatosr/>

- Report bugs at <https://github.com/GidonFrischkorn/jatosr/issues>

## Author

**Maintainer**: Gidon T. Frischkorn <gfrischkorn@icloud.com>
([ORCID](https://orcid.org/0000-0002-5055-9764))

Authors:

- Gidon T. Frischkorn <gfrischkorn@icloud.com>
  ([ORCID](https://orcid.org/0000-0002-5055-9764))
