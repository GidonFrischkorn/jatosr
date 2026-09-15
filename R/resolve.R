# Resolving credentials: the host from its three tiers and the token from
# its five, the session cache, and the token a connection sends. Nothing
# here writes anywhere; the token lives in the operating system credential
# store (R/keyring.R) and the host in the configuration file (R/config.R).

# Resolve one non-secret credential: explicit argument > environment
# variable > `fallback` > error, or NA with `missing = "na"` for the callers
# that report rather than need it. `fallback` is a function returning a
# string or NULL; jatos_host() passes the profile configuration file. Secrets
# do not come through here — see resolve_token().
read_credential <- function(value,
                            env_var,
                            arg,
                            profile = "default",
                            fallback = NULL,
                            missing = c("abort", "na"),
                            call = rlang::caller_env()) {
  missing <- rlang::arg_match(missing, error_call = call)
  if (!is.null(value)) {
    check_string(value, arg = arg, call = call)
    return(value)
  }
  from_env <- Sys.getenv(env_var, unset = "")
  if (nzchar(from_env)) {
    return(from_env)
  }
  if (!is.null(fallback)) {
    stored <- fallback()
    if (!is.null(stored)) {
      return(stored)
    }
  }
  if (identical(missing, "na")) {
    return(NA_character_)
  }
  hints <- profile_hints(profile)
  cli::cli_abort(
    c(
      "No {.arg {arg}} supplied and the {.envvar {env_var}} environment variable is not set.",
      hints$bullets,
      "i" = "Run {.run {hints$setter}} once to store it.",
      "i" = "Or set the {.envvar {env_var}} environment variable."
    ),
    call = call,
    class = "jatosr_no_host"
  )
}

# The host of a profile: explicit argument > environment variable > the
# profile configuration file. No secret is involved, which is why
# jatos_study_links() keeps working with the credential store locked. The
# sitrep and the host-mismatch check ask with `missing = "na"`.
jatos_host <- function(profile = default_profile(),
                       host = NULL,
                       missing = c("abort", "na"),
                       call = rlang::caller_env()) {
  read_credential(
    host,
    credential_var("HOST", profile),
    arg = "host",
    profile = profile,
    fallback = function() config_host(profile),
    missing = missing,
    call = call
  )
}

# --- resolving a token ---------------------------------------------------------
#
# Five tiers, first hit wins:
#
#   1. an explicit `token =` argument
#   2. the environment variable JATOS_TOKEN / JATOS_TOKEN_<PROFILE>
#   3. the session cache
#   4. the operating system credential store
#   5. an interactive prompt
#
# The first design put the credential store above the session cache. It is
# the other way round here for one measured reason: `jatos_connection()` is the
# default argument of most exported functions, so it runs on nearly every
# call, and store-before-cache would mean a keychain read per API call. The
# price is a token rotated in the credential store mid-session; the 401 hint
# in R/request.R says to restart R, and both setters clear the cache.
#
# The environment variable stays above both. It is the CI, container and HPC
# path, where the platform injects the secret and there is no store at all.

# The cache remembers where the token came from, not only what it is. A
# connection built from a cached credential store read should say "from the
# credential store", which is the true answer and a stable one; "from the
# cache" would make an implementation detail into the thing a user reads.
token_cache_get <- function(profile) {
  the$token_cache[[tolower(profile)]]
}

token_cache_set <- function(profile, secret, source) {
  entry <- list(secret = secret, source = source)
  the$token_cache[[tolower(profile)]] <- entry
  invisible(entry)
}

# A connection's token, without resolving anything. NULL when none is within
# reach.
#
# This is the function that hands jatos_req() the token it sends, and
# resolve_token() is the function whose answer the connection prints as
# `auth_from`; the two must agree. So the source the label names is tried
# first: the explicit token for "argument", the environment variable for
# "env", the session cache for "keyring" and "prompt". A connection built
# from the credential store keeps sending the store's token after a
# Sys.setenv(JATOS_TOKEN = ) in the same session, which is what its print
# says it does; a connection built after that call is labelled "env" and
# sends the variable. Only when the pinned source is gone (a connection read
# back from an rds has a dead id and an empty cache) does the lookup fall
# back to resolve_token()'s order, explicit > variable > cache, and after
# that to conn_token()'s fresh resolution.
#
# scrub_secrets() calls this and must never call conn_token(): it runs in the
# error path, and resolving there would reach a locked credential store from
# inside an error handler.
conn_token_peek <- function(conn) {
  explicit <- the$conn_tokens[[conn$id]]
  from_env <- Sys.getenv(credential_var("TOKEN", conn$profile), unset = "")
  cached <- token_cache_get(conn$profile)
  pinned <- switch(conn$auth_from %||% "",
    argument = explicit,
    env = if (nzchar(from_env)) new_secret(from_env),
    keyring = ,
    prompt = cached$secret,
    NULL
  )
  if (!is.null(pinned)) {
    return(pinned)
  }
  if (!is.null(explicit)) {
    return(explicit)
  }
  if (nzchar(from_env)) {
    return(new_secret(from_env))
  }
  if (!is.null(cached)) {
    return(cached$secret)
  }
  NULL
}

# The token a request will use. Never prompts: a request is not the place to
# ask a question, and a connection built in this session has already put its
# token within reach of conn_token_peek().
conn_token <- function(conn, call = rlang::caller_env()) {
  peeked <- conn_token_peek(conn)
  if (!is.null(peeked)) {
    return(peeked)
  }
  resolve_token(conn$profile, prompt = FALSE, call = call)$secret
}

token_cache_clear <- function(profile = NULL) {
  if (is.null(profile)) {
    the$token_cache <- list()
  } else {
    the$token_cache[[tolower(profile)]] <- NULL
  }
  invisible(NULL)
}

# Returns the secret and where it came from; the source is what
# format.jatos_connection() and jatos_credentials_sitrep() report.
resolve_token <- function(profile = default_profile(),
                          token = NULL,
                          prompt = rlang::is_interactive(),
                          call = rlang::caller_env()) {
  profile <- tolower(profile)

  if (!is.null(token)) {
    check_string(token, arg = "token", call = call)
    return(list(secret = new_secret(token, call = call), source = "argument"))
  }

  env_var <- credential_var("TOKEN", profile)
  from_env <- Sys.getenv(env_var, unset = "")
  if (nzchar(from_env)) {
    # warn_env_token_once() reads the store itself, and only until it has
    # warned for this profile. Asking for the status here instead would put
    # a key_list() on every jatos_connection(), which is the default
    # argument of nearly every exported function.
    warn_env_token_once(profile, env_var)
    return(list(secret = new_secret(from_env, call = call), source = "env"))
  }

  cached <- token_cache_get(profile)
  if (!is.null(cached)) {
    return(cached)
  }

  status <- keyring_status()
  entry <- if (status$usable) keyring_has(profile, status = status)
  if (!is.null(entry)) {
    secret <- keyring_token(entry, call = call)
    return(token_cache_set(profile, secret, "keyring"))
  }

  if (prompt && rlang::is_interactive()) {
    entered <- prompt_for_token(call = call)
    check_string(entered, arg = "token", call = call)
    # warn_if_unusual_token() belongs to the callers, which all warn once on
    # whatever they resolved; warning here as well would double it.
    return(token_cache_set(profile, new_secret(entered, call = call), "prompt"))
  }

  abort_no_token(profile, env_var, status, call = call)
}

# An environment variable quietly winning over a freshly stored token is the
# one surprise the precedence order can produce, so say it — once per
# profile and session, and only when there is something to shadow, so that
# CI (an environment variable and no credential store) stays silent.
#
# "Is there something to shadow?" is asked once per profile per session, not
# once per request: `status` is a promise, and the profile joins the checked
# set whatever the answer, so the second call costs one match() and reads no
# credential store. resolve_token() relies on that — jatos_connection() is
# the default argument of nearly every export, and a CI run (an environment
# variable and no store) would otherwise pay a key_list() per request.
warn_env_token_once <- function(profile, env_var, status = keyring_status()) {
  if (profile %in% the$env_token_checked) {
    return(invisible(NULL))
  }
  the$env_token_checked <- c(the$env_token_checked, profile)
  if (!status$usable || is.null(keyring_has(profile, status = status))) {
    return(invisible(NULL))
  }
  cli::cli_warn(c(
    "{.envvar {env_var}} is set and takes precedence over the credential store.",
    "i" = "The token of profile {.val {profile}} in the credential store is not being used.",
    "i" = "Run {.run jatosr::jatos_credentials_sitrep()} to see where each token comes from."
  ))
  invisible(NULL)
}

abort_no_token <- function(profile, env_var, status, call = rlang::caller_env()) {
  hints <- profile_hints(profile, status)
  # Distinguish "nothing stored" from "nothing can be stored". On a headless
  # Linux box the credential store falls back to `env`, which keeps a secret
  # for the life of the session only, and telling that user to run the setter
  # sends them to a function that will refuse.
  unusable <- if (!status$usable) {
    c("i" = "No persistent credential store is available here; set {.envvar {env_var}} through your platform instead.")
  }
  unreadable <- if (status$usable && !status$readable) {
    reason <- status$reason
    c("x" = "The credential store could not be read: {reason}")
  }
  cli::cli_abort(
    c(
      "No token for profile {.val {profile}}.",
      hints$bullets,
      unreadable,
      unusable,
      if (is.null(unusable)) c("i" = "Run {.run {hints$setter}} once to store one, or set {.envvar {env_var}}.")
    ),
    call = call,
    class = "jatosr_no_token"
  )
}
