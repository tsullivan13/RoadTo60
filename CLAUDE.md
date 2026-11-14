# Road to 60

WoW Forever addon (Interface 16001). The addon itself lives in `RoadTo60/`; the repo root holds
packaging and listing files.

- GitHub: https://github.com/tsullivan13/RoadTo60 (public)
- CurseForge project ID: 1800957 (set as `## X-Curse-Project-ID` in `RoadTo60/RoadTo60.toc`)
- `CURSEFORGE.md`: listing text for the CurseForge project page
- `build.ps1`: builds `dist\RoadTo60-<version>.zip` locally for a manual upload (reads `## Version` from the .toc)

## Releasing

Releases go to CurseForge automatically through GitHub Actions
(`.github/workflows/release.yml`, using the BigWigs packager). Pushing a `v*` tag builds the zip,
uploads it to CurseForge with the changelog, and attaches it to a GitHub Release.

1. Bump `## Version` in `RoadTo60/RoadTo60.toc` and `ns.version` in `RoadTo60/Core.lua`
   (the in-game "loaded" message and settings footer read the latter).
2. Add a section for that version to `RoadTo60/CHANGELOG.md` (it becomes the CurseForge file changelog).
3. Commit, then tag and push:
   ```bash
   git tag v1.0.1 && git push origin main --tags
   ```
4. Check the run at https://github.com/tsullivan13/RoadTo60/actions; the file then appears under
   the project's Files on CurseForge.

Tag suffix sets the CurseForge release type: `v1.2.0` → Release, `v1.2.0-beta1` → Beta,
`v1.2.0-alpha1` → Alpha. Keep the tag and the .toc `## Version` in step.

Notes:
- 1.0.0 was uploaded manually, so automated releases start at 1.0.1.
- The game loads its own copy at `D:\World of Warcraft\_forever_\Interface\AddOns\RoadTo60`;
  copy `RoadTo60\` there to test. A changed .toc or file list needs a full client restart.
- Uploads need the repo secret `CF_API_KEY` (a CurseForge API token from
  https://authors.curseforge.com/account/api-tokens). Never commit the token.
- `.pkgmeta` controls the package: it lifts the `RoadTo60/` subfolder to the zip root and excludes
  `CLAUDE.md`, `CURSEFORGE.md`, `build.ps1`, `dist` and `screenshots`. Add new non-addon root files to its `ignore` list.
