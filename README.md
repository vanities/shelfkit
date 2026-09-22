# ShelfKit

The plumbing shared by [Mango](https://github.com/vanities/mango) (manga, comics and light
novels) and Earmark (audiobooks) — two iOS apps that read your own files where they are,
including straight off a NAS.

Only code that is the same idea in both apps lives here. Each app keeps its own models,
parsers, scanners, reader or player, and screens — the views here are the few pieces both
apps draw identically, so the two look alike by construction.

| | |
|---|---|
| `Keychain` | Generic-password store for NAS logins, under a service the app pins |
| `BookmarkStore` | Security-scoped bookmarks for folders the user picked |
| `NASServer` | An SMB share — persisted in each app's library file |
| `NASClient`, `NASEntry`, `NASError` | SMB over AMSMB2: listing, bounded ranged reads (never aborted mid-stream — that crashed), resumable downloads, uploads |
| `NASSetupForm` | Adding a share: checks the port, tests the connection, and adds it only once it answers |
| `JSONStore`, `SalvageableLibrary` | The library file and other JSON: an unreadable file is moved aside, never lost, and merged back once a build can read it |
| `String` helpers | Natural sort, matching and identity keys, display-name cleanup |
| `AppLock` | Face ID to open the app, drawn in its own window so it covers presented screens too |
| `Tombstones`, `UnionSync`, `Stamped`, `LatestWins` | Merging collections across devices so deletions and clears stick |
| `CloudKeyValueStore` | The user's own iCloud key-value store: JSON per key, unchanged writes skipped, iCloud's size cap respected |
| `LocalMove` | Moving a book into the app's own folder: copy, check it arrived whole, then remove the originals — never over a different file |
| `URL.isInside` | Whether a file is inside a folder, whichever way the folder's path is written |
| `CopyPlace`, `PlaceBackground`, `PlaceLegend`, `StorageBar`, `TransferRing` | How a source's page draws where each copy is — the same in both apps |
| `SourceRowView`, `TransferRowView`, `TipRowView` | The rows of the Sources screen; each app supplies the words |
| `StatCard`, `StatTile`, `GoalRing` | The Stats screen's cards, headline tiles and yearly goal (with its pace line) |
| `ActivitySession`, `DayActivity`, `DayKey`, `DeviceActivity`, `ActivityStats` | Time spent with books: day totals synced one slot per device (so never counted twice), streaks, the last months as a calendar, time of day, and the books that took the most time |
| `ActivityTimeView`, `ActivityHeatmap`, `ActivityHabitsView` | Stats' time, calendar and habits cards; each app supplies its words ("Average sitting", "Average session") |

## Rules

- **App-specific values are passed in, never derived.** A Keychain service or file name that
  changes silently orphans a user's saved data, so the app owns it.
- **Persisted types keep their coding keys.** `NASServer` is decoded from files written by
  every earlier build of both apps, and `DayActivity` from what Mango has synced since before
  it was shared.
- **Deleting is the last step, and only of what's been checked.** `LocalMove` removes an
  original only once its copy is whole, and counts a file already in the app's folder as the
  same only when every byte matches — same size isn't proof.
- **Each app pins a version.** A change lands here with tests and a new tag; each app moves to
  it when it's ready, so one never breaks the other mid-release.

```bash
swift test
# NASClient against a real share (skipped unless one is named):
SHELFKIT_SMB_HOST=… SHELFKIT_SMB_PORT=… SHELFKIT_SMB_SHARE=… SHELFKIT_SMB_USER=… SHELFKIT_SMB_PASSWORD=… \
  swift test --filter NASClientIntegrationTests
```

ShelfKit depends on [AMSMB2](https://github.com/amosavian/AMSMB2), a dynamic framework: each
app lists it too and embeds it, or it dies at launch on a device.

Licensed under the GNU GPL v3, like both apps.
