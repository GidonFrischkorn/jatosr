#' jatosr: Download and Manage 'JATOS' Study Data
#'
#' A client for the REST API of JATOS (Just Another Tool for Online Studies).
#' Tokens are stored in the credential store of the operating system, and
#' read from the `JATOS_TOKEN` environment variable where a platform injects
#' one, so that they never appear in scripts and are never written to disk in
#' the clear; several accounts or servers are kept apart as named profiles.
#' See `vignette("credentials")` for how to store them and
#' `vignette("jatosr")` for the download workflow, online and from the
#' cache.
#'
#' @section Function families:
#' * Credentials and connection: [jatos_connection()],
#'   [jatos_set_credentials()], [jatos_remove_credentials()],
#'   [jatos_has_credentials()], [jatos_list_profiles()],
#'   [jatos_credentials_sitrep()], [jatos_token_info()].
#' * Study structure: [jatos_studies()], [jatos_study()],
#'   [jatos_components()], [jatos_batches()], [jatos_batch()],
#'   [jatos_groups()], [jatos_study_log()].
#' * Result metadata: [jatos_results_metadata()],
#'   [jatos_flatten_metadata()], [jatos_study_results()],
#'   [jatos_filter_metadata()], [jatos_url_query()],
#'   [jatos_read_metadata()], [jatos_cache_status()].
#' * Result download, reading and export: [jatos_export_results()] (the
#'   pipeline in one call, online or from the cache), [jatos_download_results()],
#'   [jatos_extract_fields()], [jatos_read_json()], [jatos_read_results()],
#'   [jatos_write_results()], [jatos_write_raw()].
#' * Uploaded files, archives and import: [jatos_result_files()],
#'   [jatos_download_files()], [jatos_export_study()],
#'   [jatos_export_archive()], [jatos_import_results()].
#' * Study codes: [jatos_create_study_codes()], [jatos_study_code()],
#'   [jatos_activate_study_code()], [jatos_deactivate_study_code()],
#'   [jatos_study_links()].
#'
#' @section Conditions:
#' The errors of the credential, argument, cache and metadata layers carry a
#' class, so that a script can handle one kind and let the others through,
#' for example `tryCatch(jatos_connection(), jatosr_no_token = function(cnd)
#' NULL)`. Errors from the server keep the `httr2` classes (`httr2_http_401`
#' and so on); a file that is not valid JSON, a file that could not be
#' written and a request that never reached the server are plain errors.
#'
#' * `jatosr_bad_argument`: an argument of the wrong type, length or value,
#'   from any function.
#' * `jatosr_bad_profile`: a profile name that is not an identifier.
#' * `jatosr_no_host`: no host for the profile, from [jatos_connection()] and
#'   [jatos_study_links()].
#' * `jatosr_no_token`: no token for the profile anywhere, or a cancelled
#'   prompt, from [jatos_connection()].
#' * `jatosr_keyring_unreadable`: the credential store holds the profile's
#'   entry but cannot be read (locked, or a broken backend).
#' * `jatosr_keyring_write_failed`: the credential store refused the token,
#'   from [jatos_set_credentials()]; the profile configuration is put back
#'   as it was.
#' * `jatosr_no_store`: no persistent credential store on this system, from
#'   [jatos_set_credentials()].
#' * `jatosr_needs_interactive`: a prompt is needed and the session cannot
#'   show one, from [jatos_set_credentials()] without a `token` and
#'   [jatos_remove_credentials()] with `confirm = TRUE`.
#' * `jatosr_config_write_failed`: the profile configuration file could not
#'   be written; nothing was stored.
#' * `jatosr_bad_metadata`: not a metadata tibble, or one lacking columns or
#'   ids; a `metadata.json` that cannot be imported.
#' * `jatosr_cache_layout`: a directory that is not a cache written by
#'   jatosr, or a cache without a `metadata.json`.
#' * `jatosr_zip_unreadable`: an answer or a file that is not a zip, or one
#'   that cannot be unpacked.
#' * `jatosr_incomplete_download`: [jatos_export_results()] when a component
#'   result could not be downloaded.
#' * `jatosr_file_exists`: a target file or batch folder is in the way and
#'   `overwrite = FALSE`.
#'
#' One warning is classed: `jatosr_files_skipped`, from [jatos_read_results()]
#' with `on_error = "skip"`, with the skipped paths in its `files` field.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
