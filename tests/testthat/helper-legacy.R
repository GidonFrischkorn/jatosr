# What a real JATOS at `apiVersion` 1.0.1 sends. Observed 2026-09-08/09
# against one server, hosts and token names redacted; the payloads were
# recorded from that server by hand. The routes in helper-mock.R model the OpenAPI spec, which describes
# a later API, so these are the answers the package had never been tested
# against: a token whose expiry is the sentinel `0` rather than absent
# (fixture `token-legacy.json`), error bodies in `text/plain` instead of
# JSON, and `GET /studies/{id}/batches` missing altogether.
#
# Keep the strings verbatim. They are what the assertions in
# test-legacy-server.R are worth: the difference between the two 404 bodies
# is the only signal the server gives for "no such route" against "no such
# id", and jatosr's message now depends on it.

legacy_error_bodies <- c(
  invalid_token = "Invalid api token",
  missing_route = "Requested page /jatos/api/v1/studies/1834/batches couldn't be found.",
  missing_id = "Couldn't find study with ID 999999"
)

# A 404 for a route this server does not have, phrased the way the server
# phrases it, with the path that was actually requested.
legacy_missing_route <- function(req) {
  path <- httr2::url_parse(req$url)$path
  mock_text(paste0("Requested page ", path, " couldn't be found."), status = 404)
}

# The legacy-server mock profile: JSON for the endpoints that exist at
# 1.0.1, and a text/plain 404 for every other path, so a call to an endpoint
# added in a later JATOS fails here the way it fails there. Routes given by
# the caller are matched first and override these.
local_legacy_mock <- function(..., .env = parent.frame()) {
  routes <- c(
    rlang::list2(...),
    list(
      "GET .*/admin/token$" = mock_json("token-legacy.json"),
      "GET .*/studies/properties$" = mock_json("studies.json"),
      "GET .*/studies/[^/]+/properties$" = mock_json("study.json")
    )
  )
  rlang::inject(
    local_jatos_mock(!!!routes, .fallback = legacy_missing_route, .env = .env)
  )
}
