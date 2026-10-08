# RSSHub

NetNewsWire accepts `rsshub://` URLs as a feed address, so you can subscribe to
any of [RSSHub](https://docs.rsshub.app)’s routes:

```
rsshub://telegram/channel/zaihuanews
```

## What the scheme means

`rsshub://` is **not** defined by RSSHub — it appears nowhere in the RSSHub
source or docs. It’s a convention among self-hosted readers (Folo, feedoverflow,
Livo): `rsshub://<route>` means “resolve this route against the instance I have
configured.” There is no instance in the authority position, so
`rsshub://myhost.example/telegram/…` is not a supported form.

NetNewsWire expands the route against the instance configured in
**Preferences → RSSHub** (macOS) or **Settings → Feeds → RSSHub** (iOS):

| Instance | User enters | Feed is stored as |
|---|---|---|
| `https://rsshub.app` | `rsshub://telegram/channel/zaihuanews` | `https://rsshub.app/telegram/channel/zaihuanews` |

The feed is stored **expanded**, as a plain https URL. That keeps the database
primary key, the CloudKit record name, conditional GET, favicon derivation, and
OPML export all working unchanged, and it means exported OPML stays usable in
other readers. The cost: changing the instance later does not migrate existing
subscriptions — re-subscribe through Add Feed.

## Route parameters

Anything after the route is passed through verbatim, still percent-encoded, so
all of RSSHub’s query features work by typing them yourself:

```
rsshub://telegram/channel/zaihuanews?format=atom
rsshub://telegram/channel/zaihuanews/searchQuery=%23news
```

## Access keys

If the instance was started with `ACCESS_KEY`, set it in the RSSHub pane. On
macOS, the local downloader appends it as `?key=<value>` to requests inside
the configured instance's origin and path prefix. This includes expanded
subscriptions and directly pasted HTTP URLs on that instance. The key stays
in the keychain and is not added to the stored subscription or OPML export.
It is removed before a redirect leaves the instance. iOS request authorization
and service-side account credentials are not implemented by this change.

## Browser verification (macOS)

Use **Preferences → RSSHub → Verify Feed in Browser…**, enter a route such as
`rsshub://caixin/latest`, and complete the site's verification in the embedded
browser. **Check Feed and Save Session** then makes a separate URLSession
request with the browser's cookies and user agent and parses the returned feed.
Only a successful feed response enables the session. A cookie or HTTP 200
alone does not count as successful verification.

The browser uses a dedicated persistent WebKit data store. Cookies remain in
that store; preferences contain only the instance and user agent needed to
restore it. The session is local to this device and does not sync via CloudKit
or OPML. Both subscription downloads and subsequent local/iCloud account
refreshes use the session. Updating it bypasses the old cached download and
the corresponding refresh 4xx suppression without clearing unrelated feeds.

When adding a `rsshub://` feed to a local or iCloud account, access-denied or
challenge responses open the verification window; a successful check retries
the subscription once. Subscription progress is a nonblocking sheet: starting
the retry from the verification task must yield the main actor so the account's
download task can run. An application-modal `runModal` here blocks that task.
Background refreshes report that verification is needed
instead of opening a window. Challenge pages are identified using
`cf-mitigated: challenge`, including those returned with HTTP 200.

WebKit challenge completion and reuse of its session by URLSession require a
manual check against the target instance. Neither is guaranteed by unit tests.
When the check fails, the window leaves the session unaccepted and suggests
retrying verification or changing the instance. Feedbin, Feedly, and other
services that fetch feeds on their servers cannot use this device's session.

The manual macOS check successfully added `rsshub://mittrchina/hot`, loaded its
articles, and retained the subscription across an app restart. Subsequent
background refreshes and `/healthz` still returned HTTP 403 on `rsshub.app`.
Reliable ongoing session reuse on the demo instance remains unverified; this
implementation does not promise uninterrupted background refreshes there.

## About the default instance

`https://rsshub.app` is prefilled because it’s the only instance with official
long-term documentation, but it is a demo: it rate-limits aggressively and
rejects non-browser clients with `403`, which includes NetNewsWire. The RSSHub
pane has a **Test Connection** button that hits `<instance>/healthz`; use it
before blaming a route for failing. A self-hosted instance is far more
reliable — see the RSSHub deploy docs.

## Architecture

| Piece | Where |
|---|---|
| `FeedURLResolving` protocol + `FeedURLResolver` registry | `Modules/RSCore/Sources/RSCore/FeedURLResolver.swift` |
| Validation hooks in `String.mayBeURL` / `String.normalizedURL` | `Modules/RSCore/Sources/RSCore/String+RSCore.swift` |
| Settings (base URL in `UserDefaults`, key in keychain) | `Shared/RSSHub/RSSHubSettings.swift` |
| Route expansion | `Shared/RSSHub/RSSHubResolver.swift` |
| User-facing errors | `Shared/RSSHub/RSSHubError.swift` |
| Browser session, actual-feed probe | `Shared/RSSHub/RSSHubSession.swift` |
| Browser verification UI | `Mac/Preferences/RSSHub/RSSHubVerificationViewController.swift` |
| Per-request authorization and redirect scope | `Modules/RSWeb/Sources/RSWeb/FeedRequestAuthorization.swift` |
| Resolver installation | `Mac/AppDelegate.swift`, `iOS/AppDelegate.swift` |
| Resolution funnel (all account types) | `Modules/Account/Sources/Account/Account.swift` → `createFeed(url:…)` |

The resolver is installed at launch rather than referenced directly, because
RSCore cannot depend on `Modules/Secrets` where the keychain lives. Installing
it early also means a scheme nobody claims stays rejected exactly as before, so
the Add Feed button stays disabled rather than failing mysteriously later.

Adding a second scheme (`webcal://`, say) means writing one more
`FeedURLResolving` and registering it in the registry. `mayBeURL` and
`normalizedURL` need no changes.

## Deliberately not supported

- **RSSHub Radar** (mapping website URLs to routes via `/api/radar/rules`).
- Browsing the route catalog.
- `?code=md5(route + key)` access codes — you have the key, so `?key=` is enough.
- Registering `rsshub` as an incoming `CFBundleURLTypes` scheme. The scheme
  exists to be pasted, not clicked; claiming it would collide with other readers.
- Browser verification UI or request authorization on iOS.
- Transferring browser sessions to accounts that fetch feeds on a remote server.
