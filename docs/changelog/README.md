# Changelog

One file per release, newest first. Each file reads top-to-bottom as newest-first too, so a point release is prepended to the file it belongs to rather than starting a new one.

| Version | Date | Notes |
|---|---|---|
| [Unreleased](unreleased.md) | — | Work that is done and verified on hardware but **not published yet**. It ships in the next release. |
| [20260817](20260817.md) | 2026-08-17 | Encrypted `/data`, landscape by default, HDMI mirroring with sound, self-installing updates, SELinux policy. |
| [20260804](20260804.md) | 2026-08-04 | First public release. |

The version string is the build date, which is also the id of the [GitHub release](https://github.com/Keyaku/gpd-xdplus-customrom/releases) and the `ro.lineage.version` the device reports.

## Format

Every release file has the same shape, and [20260817](20260817.md) is the worked example to copy.

```
# <version>

<one line: which release this is, the date, the download link, the zip names.>
<one paragraph: what is new since the previous release, headline items first.>
<any ⚠️ warning that applies to installing this release at all.>

## Changelog          <- one bullet per category
## <Category>         <- the detail, one section per category
### <Change>          <- only where a category covers several distinct changes
```

### The `Changelog` list

One bullet per **category**, not per change — the list is a map of the release, so it stays roughly a dozen bullets however much shipped. Each bullet links to its own section and compacts everything that category changed into a sentence or two. A ⚠️ that a reader must act on (a wipe, a second zip, a card to keep in the device) is repeated here rather than left in the detail alone.

### The detail sections

- **One section per category, in the same order as the list.** Subdivide with `###` only when a category holds several genuinely separate changes — [Display out](20260817.md#display-out) and [Vulkan](20260817.md#vulkan) do; the rest do not.
- **A change belongs to exactly one section.** If it touches two, pick the one it is really about and mention it once. No `Fixes` or `Under the hood` catch-alls: something that fits nowhere is a sign the categories are wrong, not that a bin is needed.
- **Say what the user sees first, then why.** Lead with what changed for someone using the device; the cause, if it is worth telling, goes after.
- **Carry the caveats.** What is still broken, what needs a second zip, what takes effect only on the next boot — a section that fixed something is where the reader looks for what it did not fix.

### Writing rules

This is documentation for someone using the device, not for the people building it: no internal citations, no repository paths, no commit hashes, no bug-tracker numbers. Name a setting the way the screen names it. Anchor links are lowercase, punctuation dropped, spaces to hyphens — check every one resolves before publishing.
