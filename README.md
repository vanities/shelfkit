# ShelfKit

The plumbing shared by [Mango](https://github.com/vanities/mango) (manga, comics and light
novels) and Earmark (audiobooks) — two iOS apps that read your own files where they are,
including straight off a NAS.

Only code that is the same idea in both apps lives here. Each app keeps its own models,
parsers, scanners, reader or player, and UI.

| | |
|---|---|
| `Keychain` | Generic-password store for NAS logins, under a service the app pins |
| `BookmarkStore` | Security-scoped bookmarks for folders the user picked |
| `NASServer` | An SMB share — persisted in each app's library file |
| `String` helpers | Natural sort, matching and identity keys, display-name cleanup |
| `AppLock` | Face ID to open the app, drawn in its own window so it covers presented screens too |
| `Tombstones`, `UnionSync`, `Stamped`, `LatestWins` | Merging collections across devices so deletions and clears stick |
| `LocalMove` | Moving a book into the app's own folder: copy, check it arrived whole, then remove the originals — never over a different file |
| `URL.isInside` | Whether a file is inside a folder, whichever way the folder's path is written |

## Rules

- **App-specific values are passed in, never derived.** A Keychain service or file name that
  changes silently orphans a user's saved data, so the app owns it.
- **Persisted types keep their coding keys.** `NASServer` is decoded from files written by
  every earlier build of both apps.
- **Deleting is the last step, and only of what's been checked.** `LocalMove` removes an
  original only once its copy is whole, and counts a file already in the app's folder as the
  same only when every byte matches — same size isn't proof.
- **Each app pins a version.** A change lands here with tests and a new tag; each app moves to
  it when it's ready, so one never breaks the other mid-release.

```bash
swift test
```

Licensed under the GNU GPL v3, like both apps.
