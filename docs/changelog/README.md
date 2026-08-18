# Changelog

One file per release, newest first. Each file reads top-to-bottom as newest-first too, so a point release is prepended to the file it belongs to rather than starting a new one.

Each release file has the same two-part shape: a **Changelog** list with one bullet per category, briefly covering everything that category changed and linking to it, followed by the **detail sections**, one per category, subdivided where a category covers several distinct changes. A change belongs to exactly one section — if it touches two, pick the one it is really about and mention it once.

| Version | Date | Notes |
|---|---|---|
| [Unreleased](unreleased.md) | — | Work that is done and verified on hardware but **not published yet**. It ships in the next release. |
| [20260817](20260817.md) | 2026-08-17 | Encrypted `/data`, landscape by default, HDMI mirroring with sound, self-installing updates, SELinux policy. |
| [20260804](20260804.md) | 2026-08-04 | First public release. |

The version string is the build date, which is also the id of the [GitHub release](https://github.com/Keyaku/gpd-xdplus-customrom/releases) and the `ro.lineage.version` the device reports.
