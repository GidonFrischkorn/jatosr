# Developer notes

This page is for two readers: someone who wants to change `jatosr`, and
someone who wants the same kind of package for a platform other than
JATOS (the server software that hosts online experiments, which `jatosr`
talks to over its REST API). It says where the package’s priorities come
from, how it is built, which parts of it have nothing to do with JATOS,
and how to use it as a template. It assumes
[`vignette("jatosr")`](https://www.gfrischkorn.org/jatosr/articles/jatosr.md)
and
[`vignette("credentials")`](https://www.gfrischkorn.org/jatosr/articles/credentials.md),
which introduce the functions this page only names.

I run my own online studies on JATOS and recruit through Prolific. That
workflow decides what gets built in `jatosr` and in which order. Other
hosting platforms are not on my list unless a study of mine ends up on
one. What I would welcome is that people who work on other platforms
build a sibling package from this one: the same shape, the same
conventions, the same rules about credentials and tests, so that a user
who knows one of them knows the others. In the long run such packages
could be attached together by a small `onlinestudies` bundle, the way
`tidyverse` attaches its members. That bundle is an idea, not a promise;
it needs a second package before it needs a name.

## Where the priorities come from

The functions that go beyond plain downloading exist because the JATOS
and Prolific combination needed them. Participants arrive through a
Prolific link that carries `PROLIFIC_PID`, `STUDY_ID` and `SESSION_ID`,
so
[`jatos_url_query()`](https://www.gfrischkorn.org/jatosr/reference/jatos_url_query.md)
turns the URL query parameters of every run into columns. Returners and
reloaded links produce several study results per person, so
[`jatos_study_results()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_results.md)
counts them as `n_runs`, keyed by the Prolific id when it is present. My
own test runs from the JATOS interface sit in the same batch (the
grouping of runs in JATOS; one batch per Prolific wave in my studies) as
the real data, so
[`jatos_filter_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_filter_metadata.md)
drops them by worker type. The study-code functions, which generate and
manage the links participants open, exist because every Prolific wave is
a JATOS batch with one general link.

Three things are not planned from my side. A package for another host,
for the reason above. A client for the Prolific API: Prolific recruits,
JATOS hosts, and a Prolific client would be a sibling of its own rather
than a part of this one. And a shared core package: none exists, and
none will be extracted before a second backend exists and shows which
pieces are actually common. Until then, this page records which pieces I
expect to be common.

## How the package is built

Each subsection starts with the file that holds the mechanism it
describes.

### Credentials and the secret

`R/profile.R`, `R/resolve.R`, `R/secret.R`, `R/credentials-store.R`,
`R/prompt.R`, `R/renviron.R`, `R/keyring.R`, `R/config.R`, `R/sitrep.R`.
A profile is a name for one host-and-token pair; `"default"` is the one
used when none is named. The two halves are kept in different places
because they are different kinds of thing. The token goes to the
operating system’s credential store through `keyring`, with the profile
name as the keyring username, so profiles and entries map one to one.
The host is not a secret and goes to `profiles.json` under
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html), which is
what lets
[`jatos_list_profiles()`](https://www.gfrischkorn.org/jatosr/reference/jatos_list_profiles.md)
and
[`jatos_study_links()`](https://www.gfrischkorn.org/jatosr/reference/jatos_study_links.md)
work with the credential store locked or absent. The package writes
nothing else, and nothing at all in the home filespace — the reason for
the whole arrangement is CRAN policy on one side and a plain-text file
of secrets in a synced directory on the other.

`resolve_token()` has five tiers: an explicit `token =` argument, the
environment variable `JATOS_TOKEN` / `JATOS_TOKEN_<PROFILE>`, the
session cache, the credential store, an interactive prompt. The
environment variable is above the store because that is the CI,
container and cluster path, where the platform injects the secret and no
store exists; the cost is that a leftover variable shadows a stored
token, which `warn_env_token_once()` and
[`jatos_credentials_sitrep()`](https://www.gfrischkorn.org/jatosr/reference/jatos_credentials_sitrep.md)
exist to surface. The session cache is above the store, rather than
below it as the design note proposed, because
[`jatos_connection()`](https://www.gfrischkorn.org/jatosr/reference/jatos_connection.md)
is the default argument of most exported functions and therefore runs on
nearly every call: reading the keychain first would mean one keychain
access per API call. The price is a token rotated outside R mid-session,
which the 401 hint names. `jatos_host()` is the same shape without the
last two tiers. Every credential-reading function takes
`profile = Sys.getenv("JATOS_PROFILE", "default")`, so the fallback is
visible in the signature. Profile names are identifiers (a letter, then
letters, digits and underscores; case-insensitive).

Every `keyring::` call is in one of five one-statement wrappers in
`R/keyring.R`; all the decisions sit above them, where the tests
exercise them as ordinary code. `keyring_has()` and `keyring_token()`
are separate on purpose: a missing entry is a normal miss that falls
through to the prompt, a locked store is an error that has to say
“unlock” rather than “store a token you have already stored”.
`keyring_guard()` aborts if a test reaches any backend other than `env`.

The connection object carries the profile, the host and an opaque
session id — never the token.
[`saveRDS()`](https://rdrr.io/r/base/readRDS.html) of a connection
therefore writes no secret, which is a property
`tests/testthat/test-canary.R` asserts against every file and every
condition the package produces, rather than a paragraph of documentation
asking the user to be careful. The token lives in a session-only
environment and is revealed inside `jatos_req()` alone. `new_secret()`
holds it as a closure rather than a classed string, because
[`paste()`](https://rdrr.io/r/base/paste.html),
[`sprintf()`](https://rdrr.io/r/base/sprintf.html) and
[`cat()`](https://rdrr.io/r/base/cat.html) skip S3 dispatch and would
print a classed string verbatim;
[`format()`](https://rdrr.io/r/base/format.html) and
[`print()`](https://rdrr.io/r/base/print.html) show the prefix and the
length, [`as.character()`](https://rdrr.io/r/base/character.html)
refuses.

Nothing in `R/profile.R` and `R/resolve.R` is specific to JATOS except
the variable names their callers pass in; `check_profile()`,
`credential_var()`, `read_credential()` and `resolve_token()` work for
any `<PLATFORM>_HOST` and `<PLATFORM>_TOKEN` pair, and a sibling package
needs its own service name and its own `<prefix>_credentials_sitrep()`.

### One request builder

`R/request.R`.
[`httr2::request()`](https://httr2.r-lib.org/reference/request.html) is
called in exactly one place, `jatos_req()`. It attaches the bearer
token, the `Accept` header, a user agent naming the package and its
version, a retry policy, and an error handler that maps the response
body to cli bullets (`jatos_error_body()`). Every endpoint goes through
it, which is what makes the mock in the tests complete: a request that
bypassed the builder would also bypass the mock and hit the network. A
JATOS installation that answers an authentication failure with a 200
HTML login page instead of a 4xx status is caught in the same handler.

### The metadata tibble

`R/utils.R`, `check_metadata()`. The central object is a plain tibble,
one row per result at the finest level the platform has. In JATOS a
study result is one participant’s run and consists of one component
result per component of the study, so the row is a component result. It
is not a vctrs subclass, because users filter it constantly and a
subclass would need methods to survive `[`, `dplyr::filter()` and
[`rbind()`](https://rdrr.io/r/base/cbind.html). The contract is by
column name, checked at function entry. Four kinds of column carry the
package; in JATOS they are six names, because the result id is three
ids:

| Column | Meaning | In JATOS |
|----|----|----|
| a result id | the id the download and the reader key on | `study_result_id`, `component_result_id`, `component_id` |
| a partition id | what the cache is partitioned by | `batch_id` |
| a state | so unfinished results can be told apart | `component_state` |
| a size in bytes | what the incremental rule compares against the local file | `data_size` |

Those six names are `metadata_required_columns()`. Every column name
carries its level when the platform has more than one: the tibble also
has a `study_state`, which the filters use but the contract does not
require. Nested server fields that the flattener does not interpret stay
in list columns rather than being dropped, so the tibble is a superset
of what the package itself uses. A function that touches only a few
columns asks for those with `check_metadata(contract = FALSE)`.

### The cache and the incremental rule

`R/cache-layout.R` and `R/results-download.R`. The layout is
`<path>/batch_<id>/study_result_<id>/comp-result_<id>/data.txt` (the
folder names are the ones JATOS uses in its own result exports), with
uploaded files under `files/` next to `data.txt`, plus one
`metadata.json` per batch. That file is the server’s own answer for the
batch stored byte for byte, never a re-serialisation of the tibble. It
is what makes a cache self-describing:
[`jatos_read_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_read_metadata.md)
on the cache root rebuilds the tibble offline, and a subset that was
filtered before the download does not lose the server fields the filter
did not use. Every function that touches the cache builds paths through
`batch_dir()` and its companions; no other file spells the layout out.

The incremental rule compares sizes in bytes on both sides and is
asymmetric: fetch when the local file is missing or the server is
larger; skip when equal; when the server is *smaller*, keep the local
file, report it, and replace it only on an explicit `overwrite = TRUE`,
because the local copy may be the last copy of a participant’s data.
Files are written to a temporary name inside the batch directory and
renamed into place, so a partial download never sits under the real
name.

### Tests without a network

`tests/testthat/helper-mock.R` and `helper-credentials.R`. HTTP is
mocked at the `httr2` layer: `local_jatos_mock()` keys routes by method
and path and records every request, so tests assert on query and body.
Fixtures are served byte for byte from files under
`tests/testthat/fixtures/`, so JSON `null` stays `null` (a re-serialised
`null` becomes [`{}`](https://rdrr.io/r/base/Paren.html) and empties
every column of a tibble). The token-like strings the tests need are all
in the `fake_tokens` vector of `helper-credentials.R` and nowhere else
in the repository; `expect_no_token()` asserts that none of them appears
in a print, [`format()`](https://rdrr.io/r/base/format.html),
[`str()`](https://rdrr.io/r/utils/str.html) or error path, and
`test-canary.R` greps the package sources, vignettes and help pages for
a token-shaped literal so that the rule is an assertion rather than a
convention.

No test touches a real credential store, and three separate things make
that true. `local_no_credentials()` and `local_fake_credentials()` empty
all three stores at once — the environment, an in-memory configuration
directory, and a credential store forced onto `keyring`’s `env` backend.
`tests/testthat/setup.R` fails the run if the configuration directory is
not inside [`tempdir()`](https://rdrr.io/r/base/tempfile.html). And
`keyring_guard()`, inside every wrapper, aborts if a `keyring::` call
reaches any other backend, so a test that loses its sandbox fails loudly
instead of writing into the developer’s login keychain.

Forcing the `env` backend rather than mocking the wrappers is
deliberate. That backend implements the whole interface the package uses
— set, get, list, delete — so the tests run through the real
`keyring::key_*()` calls, and a wrong service name or a wrong
`username =` argument cannot hide behind a mock. Only the backend *name*
is faked, because the package reads `"env"` as “nowhere durable to store
a token”; `keyring_guard()` reads the true backend, not the faked name.
Two states the `env` backend cannot produce — a locked store and an
unusable one — are the only places left that mock a binding.
`data-raw/check-keyring.R` walks the same path once against the real
credential store of the operating system, by hand, before a release; run
it on each platform you support.

A mock built from a specification tests the package against the
specification, not against a server. The first real JATOS this package
met disagreed with the spec in five places, all of them invisible to
1771 passing tests: a token whose expiry was the sentinel `0` rather
than an absent field, error bodies in `text/plain` rather than JSON, and
a nested route the spec has and the server does not. So there is a
second mock profile, `local_legacy_mock()` in `helper-legacy.R`, holding
what that server sends verbatim, and `test-legacy-server.R` asserts the
five behaviours against it. When a new server disagrees, its payloads go
there rather than into a patched spec fixture: the two profiles are the
record of what the package has actually seen, and a fix that only
satisfies the spec mock is a fix that will regress.

The same reasoning limits how far server text is trusted. Error messages
now carry the server’s own sentence, which means a condition message can
contain a third party’s text; `scrub_secrets()` in `R/request.R` removes
token-shaped strings from it first, and `fake_tokens` carries an
`echoed` entry that exists only to be scrubbed out of a deliberately
hostile fixture. The guarantee is a property of that function, not of
any server’s discretion.

### Style rules

- `conn = jatos_connection()` is the last, named argument of every
  function that makes a request. Functions that take a metadata tibble
  are data-first, so they pipe.
- Nouns are read-only
  ([`jatos_studies()`](https://www.gfrischkorn.org/jatosr/reference/jatos_studies.md),
  [`jatos_results_metadata()`](https://www.gfrischkorn.org/jatosr/reference/jatos_results_metadata.md));
  write verbs are explicit (`set_`, `create_`, `download_`, `activate_`,
  `deactivate_`).
- Errors come from
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  with the server’s message when there is one, and never contain the
  token or a query string.
- No dplyr, stringr or tidyr in `Imports`; the native pipe, `purrr` and
  `tibble` are enough.

## Using jatosr as a template

A sibling package for another host (Pavlovia, Gorilla, PsyToolkit,
Labvanced, SoSciSurvey or Qualtrics, to name the ones psychologists use)
uses its own prefix in place of `jatos_` and provides at least:

| Function | Purpose |
|----|----|
| `<prefix>_connection(profile, host, token)` | build the connection object; `host` and `token` override the profile’s variables |
| `<prefix>_set_credentials(host, token, profile)` | store the token in the operating system credential store and the host in the configuration file, verify once; never writes the token to a file |
| `<prefix>_remove_credentials(profile, confirm)` | the exact inverse, one profile at a time |
| `<prefix>_credentials_sitrep(profile)` | where the active token comes from, without printing it, and which `.Renviron` file sets a variable that takes precedence |
| `<prefix>_has_credentials(profile)` | is a token resolvable, without a request and without retrieving it |
| `<prefix>_list_profiles()` | the profiles known to the environment, the store and the configuration file, with hosts, never tokens |
| `<prefix>_token_info()` or an equivalent token check | the cheapest request that tells a wrong token from a wrong host |
| `<prefix>_studies()` | what the token can see |
| `<prefix>_results_metadata(...)` | what results exist, one row per result, without downloading data |
| `<prefix>_download_results(metadata, path, incremental = TRUE)` | fetch result files into a local cache |
| `<prefix>_read_results(metadata)` | read the cached files into one tibble |

What a sibling copies unchanged, with the file it lives in:

- the profiles and the resolvers, `R/profile.R` and `R/resolve.R`, the
  setter and remover, `R/credentials-store.R`, the prompts,
  `R/prompt.R`, and the read-only `.Renviron` access, `R/renviron.R`;
- the credential-store wrappers, the backend status and the test
  tripwire, `R/keyring.R`, with the service name changed to the
  package’s own;
- the situation report, `R/sitrep.R`;
- the secret, `new_secret()` and its methods, in `R/secret.R`;
- the single request builder and the error mapping, `R/request.R`, with
  the header and the base path changed;
- the plain tibble with a column contract, `check_metadata()` in
  `R/utils.R`, with the platform’s own column names;
- the incremental rule and the temporary-name write,
  `R/results-download.R`;
- the mock, the fixture serving and the token assertion from
  `tests/testthat/`;
- the style rules above.

What a sibling replaces: the endpoints, the result granularity (a survey
response where JATOS has a component result), the cache partition (a
wave or a project where JATOS has a batch), the reader (jsPsych JSON
here; a CSV or a JSON export elsewhere), and whether there are study
codes at all.

A workable start:

1.  Copy the repository and rename, in one pass: the prefix, the two
    environment variables, the keyring service name, the
    `*_REAL_KEYRING` opt-out and the `*_CONFIG_DIR` override. Keep
    `helper-credentials.R`, `helper-keyring.R`, `helper-mock.R` and
    `setup.R` as they are — the keyring tripwire is only a safeguard
    while every test reaches it.
2.  Read the platform’s API specification and write the fixtures from
    its examples, one file per endpoint the package will call, before
    any function.
3.  Build in the order this package was built: credentials and
    connection, token check, study listing, result metadata, download,
    reader.
4.  Keep the three vignettes and their structure (a get-started
    walk-through of the pipeline, a credentials page, and developer
    notes like this one), so that the pages of two sibling packages read
    the same way.

## Getting in touch

Open an issue at <https://github.com/GidonFrischkorn/jatosr> before
starting a sibling, saying which platform and where its API is
documented. That keeps the function names and the metadata columns
aligned across packages while there is still time to align them, and it
is where the `onlinestudies` bundle would be discussed once a second
package exists. `CONTRIBUTING.md` in the repository has the development
cycle and the rules for changes to `jatosr` itself.
