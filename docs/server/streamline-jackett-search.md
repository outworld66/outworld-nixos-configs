# Streamline and Jackett search

## Failure

On Streamline 3.2.0, choosing **Search for releases** for a movie called
`Shrek` sent `POST /api/v1/movies/1/search-now` and returned HTTP 500 with
`rss: no eligible release for movie`. The same problem affected the manual
release search because both paths use the same indexer search service.

The message was misleading: the movie was present in Jackett results when
searched by its title. TMDB authentication was working.

## Cause

For movie searches, Streamline's Torznab client sends both the text query and
the TMDB ID (`t=movie&tmdbid=…`). Jackett accepts different search parameters
for different trackers. The configured trackers rejected `tmdbid` with HTTP
400 (`Function Not Available: tmdbid is not supported for movie search by this
indexer`). A plain text query (`t=search&q=Shrek`) returned results.

Streamline 3.2.0 retried without the provider ID only when an ID-based request
succeeded with an empty result list. An HTTP 400 took the error path and skipped
that retry for the tracker. With every configured tracker rejecting the ID
query, Streamline saw no candidates and returned the `no eligible release`
error as HTTP 500.

## Fix in the fork

The [outworld66 Streamline fork](https://github.com/outworld66/streamline/tree/fix-jackett-tmdbid-fallback)
classifies HTTP 400 as a rejected query. If a narrowed search gets that status,
Streamline retries once using the bare title while retaining the movie or TV
search kind. Authentication errors, network failures and other HTTP statuses
do not trigger the retry. The existing title and quality checks still decide
which result can be grabbed. A completed search with no eligible release is
now treated as a normal no-match outcome instead of an internal-server error;
genuine indexer or download-client failures still return errors.

The Nix flake uses this branch as its Streamline input, and `flake.lock` pins
the exact fork revision. To update the fork later, push the fix branch and run
`nix flake lock --update-input streamline` before deploying Rico with
`task server-update -- rico`.

## Search actions

The movie menu action **Search for releases** calls `search-now`: Streamline
searches indexers and automatically sends its best eligible result to
qBittorrent. **Manual search** opens the release list so an operator can pick
one. If no result passes title and quality checks after the fallback, no
download is started and the API returns its accepted-search response. Use
**Manual search** to inspect candidates and choose a release yourself.
