# Changelog

## jatosr 0.1.0

First release: an R client for the JATOS REST API, from credentials to
an analysis-ready dataset. The JATOS retrieval workflow is modelled on
the smartr package by Chenyu Li.

- [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md)
  stores the API token in the credential store of the operating system,
  through the keyring package, and the server’s URL in a configuration
  file under
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) (or
  `JATOSR_CONFIG_DIR`). No token is written to disk in the clear.
  Optionally under a named profile, so several servers or accounts can
  live side by side
  ([`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md),
  [`jatos_has_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_has_credentials.md),
  [`jatos_token_info()`](https://www.gfrischkorn.org/jatosr/reference/jatos_token_info.md)).

- `JATOS_TOKEN` and `JATOS_HOST` (or a named profile’s pair) are still
  read, and take precedence over the credential store, so continuous
  integration, containers and cluster jobs inject the token the way they
  inject any secret.

- [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md)
  builds a connection that carries the profile name, the host and an
  opaque session id — never the token, which stays in the session and is
  fetched only inside the request builder. So a connection can be
  serialised, cached by knitr or stored by targets without writing a
  secret to disk, and no print, message or error can show one. This
  relies on `httr2` 1.2.0 or later, which no longer serialises a
  redacted header.

- [`jatos_credentials_sitrep()`](https://www.gfrischkorn.org/jatosr/reference/jatos_credentials_sitrep.md)
  reports which of the three places each profile’s host and token would
  be taken from, without printing a token, and names an `.Renviron` file
  whose variables take precedence over the credential store.

- [`jatos_remove_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_remove_credentials.md)
  deletes one profile from the credential store and the configuration
  again, keeping every other profile. It asks first, and where no prompt
  can be shown it stops rather than deleting; a script passes
  `confirm = FALSE`.

- [`jatos_studies()`](https://www.gfrischkorn.org/jatosr/reference/jatos_studies.md),
  [`jatos_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study.md),
  [`jatos_components()`](https://www.gfrischkorn.org/jatosr/reference/jatos_components.md),
  [`jatos_batches()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batches.md),
  [`jatos_batch()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batch.md),
  [`jatos_groups()`](https://www.gfrischkorn.org/jatosr/reference/jatos_groups.md)
  and
  [`jatos_study_log()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_log.md)
  list what the token can see, by id or uuid.

- [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md)
  returns result metadata as a tibble with one row per component result,
  with
  [`jatos_flatten_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_flatten_metadata.md),
  [`jatos_url_query()`](https://www.gfrischkorn.org/jatosr/reference/jatos_url_query.md)
  and
  [`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md)
  (one row per run) to reshape it.

- [`jatos_filter_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_filter_metadata.md)
  selects runs by state, worker type, start time and explicit exclusions
  before anything is downloaded.

- [`jatos_download_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_results.md)
  and
  [`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md)
  fetch result data and participant uploads incrementally into a local
  cache, skipping what is already there and reporting a per-row status;
  [`jatos_cache_status()`](https://www.gfrischkorn.org/jatosr/reference/jatos_cache_status.md)
  summarises the cache batch by batch and
  [`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
  rebuilds the metadata from it offline, both for every batch or for
  those named in `batch_id`.

- [`jatos_result_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_result_files.md)
  lists the files participants uploaded, one row per file with the
  component result it belongs to, before
  [`jatos_download_files()`](https://www.gfrischkorn.org/jatosr/reference/jatos_download_files.md)
  fetches them.

- [`jatos_import_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_import_results.md)
  unpacks a results zip exported from the JATOS GUI into the same cache
  layout, so data that never came through the API can be used with the
  rest of the package.

- A zip, downloaded or imported, with an entry whose name would leave
  the target directory (a `..` component or an absolute name) is refused
  before anything is extracted.
  [`utils::unzip()`](https://rdrr.io/r/utils/unzip.html) itself skips
  such an entry only from R 4.5.1 on.

- [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md)
  reads the cached jsPsych files into one trial-level tibble with the
  run’s metadata joined to every row,
  [`jatos_read_json()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_json.md)
  reads a single file, and a `reader` argument handles other formats
  such as PsychoJS csv.

- [`jatos_extract_fields()`](https://www.gfrischkorn.org/jatosr/reference/jatos_extract_fields.md)
  pulls scalar JSON fields (a participant code, a condition) out of the
  result files without parsing them in full.

- [`jatos_write_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_results.md)
  saves the dataset as `.rds`, `.csv`, `.csv.gz`, `.tsv`, `.parquet` or
  `.RData` (one file per component on request, with the component in the
  file and object names), and
  [`jatos_write_raw()`](https://www.gfrischkorn.org/jatosr/reference/jatos_write_raw.md)
  copies the raw result files under names taken from a metadata column,
  refusing a name that could leave the directory.

- [`jatos_export_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_results.md)
  runs the whole pipeline in one call and writes the trials, the
  study-result table and a provenance record; `download = FALSE`
  rebuilds the same dataset from the cache with no network access.
  `reader`, `split`, `coerce` and `on_error` are passed to
  [`jatos_read_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_results.md),
  so a column whose type differs between files or a file that cannot be
  read need not stop the export.

- [`jatos_export_study()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_study.md)
  and
  [`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md)
  download the study archive and the full results archive for a data
  deposit.

- [`jatos_create_study_codes()`](https://www.gfrischkorn.org/jatosr/reference/jatos_create_study_codes.md),
  [`jatos_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_code.md),
  [`jatos_activate_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_activate_study_code.md),
  [`jatos_deactivate_study_code()`](https://www.gfrischkorn.org/jatosr/reference/jatos_activate_study_code.md)
  and
  [`jatos_study_links()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_links.md)
  manage study codes and build the run URLs.

- Three vignettes:
  [`vignette("jatosr")`](https://www.gfrischkorn.org/jatosr/articles/jatosr.md)
  walks the whole pipeline,
  [`vignette("credentials")`](https://www.gfrischkorn.org/jatosr/articles/credentials.md)
  covers tokens and profiles, and
  [`vignette("developer-notes")`](https://www.gfrischkorn.org/jatosr/articles/developer-notes.md)
  documents how the package is built.

- [`jatos_set_credentials()`](https://www.gfrischkorn.org/jatosr/reference/jatos_set_credentials.md)
  puts the profile’s entry in the configuration back as it was when the
  credential store refuses the token, and says so (class
  `jatosr_keyring_write_failed`), instead of leaving a host without a
  token behind the error of the store. On a machine without a persistent
  store it names the command that creates a file keyring there,
  `keyring::backend_file$new()$keyring_create("system")`.

- [`jatos_credentials_sitrep()`](https://www.gfrischkorn.org/jatosr/reference/jatos_credentials_sitrep.md)
  starts with the jatosr, keyring, R and operating system versions, and
  the commit of a package installed from GitHub, so its output can go
  into a bug report as it is.

- The examples of the offline functions (reading, extracting, writing,
  importing, the cache status) run on a small synthetic cache shipped
  under `inst/extdata/`; the examples that need a server or the
  machine’s credential store say so in a comment.

- Built against a mock of the OpenAPI spec, then run against a real
  JATOS reporting `apiVersion` 1.0.1, which disagrees with that spec in
  five places; the test suite also runs a second mock profile that
  answers the way that server does. The changes that followed are the
  next items.

- [`jatos_token_info()`](https://www.gfrischkorn.org/jatosr/reference/jatos_token_info.md)
  reads a token with no expiry as `expires = NA` again when the server
  spells “never expires” as `expirationDate: 0` rather than as an absent
  field. It used to report `1970-01-01`, which then made the next
  [`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md)
  of the session warn that a working token had expired. A past expiry
  that the server’s own `isExpired` calls false no longer warns at all,
  whatever sentinel a future version invents.

- `jatos_set_credentials(check = TRUE)` no longer prints `for "NA"` on
  an API version that sends no `username` field.

- Request errors carry the server’s own sentence when it arrives as
  `text/plain` rather than as JSON — every error body of that server
  does. Token-shaped strings are scrubbed out of any server text before
  it becomes part of a message, so the guarantee that no token reaches a
  print, message or error path does not depend on the server’s
  discretion.

- A 404 tells the two cases apart: a route this JATOS does not have (an
  endpoint added in a later version) no longer says “check the id”, and
  [`jatos_batches()`](https://www.gfrischkorn.org/jatosr/reference/jatos_batches.md)
  names `jatos_studies(with_batches = TRUE)` as the way round it. Both
  it and
  [`jatos_groups()`](https://www.gfrischkorn.org/jatosr/reference/jatos_groups.md)
  document which servers have the endpoint.

- Request errors name the credential profile and host they used, which
  is the fact that identifies a call aimed at the wrong one of two
  accounts on one server.

- A failed credential lookup names the profiles that are configured,
  instead of only advising how to create a default one that the setup
  deliberately does not have;
  [`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md)
  documents that `active` is `FALSE` in every row when no profile is
  selected.

- The `check_cache_layout()` refusal says that nothing in the directory
  was read or changed, and names
  [`jatos_export_archive()`](https://www.gfrischkorn.org/jatosr/reference/jatos_export_archive.md)
  as the way to get the zip that
  [`jatos_import_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_import_results.md)
  wants.

- The errors of the credential, argument, cache and metadata layers
  carry a condition class (`jatosr_no_token`, `jatosr_file_exists`,
  `jatosr_bad_argument` and ten more, listed under
  [`?jatosr`](https://www.gfrischkorn.org/jatosr/reference/jatosr-package.md)),
  so a script can handle one kind with
  [`tryCatch()`](https://rdrr.io/r/base/conditions.html) and let the
  rest through. Errors from the server keep the `httr2` classes.
