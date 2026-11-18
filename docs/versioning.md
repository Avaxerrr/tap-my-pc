# Versioning and release guidelines

Follow this policy automatically when preparing app changes for delivery. Do not wait for the user to request a version bump. Explicit user version choices take precedence.

## Version format and ownership

Use `MAJOR.MINOR.PATCH` plus a monotonically increasing integer build number per app. Display, for example, `v0.3.1 (build 4)`; metadata may encode this as `0.3.1+4`.

Desktop/server and Android are independently versioned. Updating one does not require bumping or rebuilding the other. Keep them aligned only for a deliberately coordinated release. The product version is separate from the HTTP route version, QR payload version, and settings schema version: do not change those for UI polish or an ordinary app release.

| Component | Authoritative source | Derived metadata |
| --- | --- | --- |
| Windows desktop/server and shared .NET projects | `Version` and `BuildNumber` in `Directory.Build.props` | `AssemblyVersion = Version.0`, `FileVersion = Version.BuildNumber`, `InformationalVersion = Version+BuildNumber`; desktop heading and API `serverVersion` read compiled metadata |
| Android client | `version: MAJOR.MINOR.PATCH+BUILD` in `mobile/pubspec.yaml` | Flutter's version name/code and installed-package metadata; visible version UI must use installed metadata rather than a duplicated constant |

## Choosing the next version

| Change | Default decision | Example |
| --- | --- | --- |
| Bug fixes, small revisions, visual polish, clearer feedback, layout/accessibility improvements | Increment PATCH | `0.3.0 -> 0.3.1` |
| A new user capability, substantial UI overhaul, or a larger feature release | Increment MINOR; reset PATCH to zero | `0.3.1 -> 0.4.0` |
| Breaking public compatibility after 1.0 | Increment MAJOR; reset MINOR/PATCH | `1.4.2 -> 2.0.0` |
| Another test build within the same planned change set | Keep the planned version; increment BUILD | `0.3.1+4 -> 0.3.1+5` |
| Docs, comments, tests, or tooling changes that do not change delivered app behavior; rebuild/publish of unchanged source and settings | No automatic bump | Rebuilding `0.3.1+4` keeps that identity |

The project is still pre-1.0. Breaking pre-1.0 behavior normally increments MINOR and requires compatibility/migration notes. Do not declare 1.0 merely because the UI is modernized; 1.0 means an intentional stable release milestone. Security fixes normally receive PATCH unless a breaking compatibility change requires otherwise.

Treat a user-visible feature/fix batch as one deliverable. Choose the highest applicable version increment once for the batch, not per file, command, commit, failed build, or retry. For example, a batch of desktop dashboard/tray/banner polish and connection-visibility refinements can be consolidated into a PATCH release; a substantial Android UI overhaul normally targets its next MINOR release.

## When to increment the build

1. Before first publishing/installing a changed app deliverable, inspect the current metadata and the most recent delivered version in setup/verification docs and Git history.
2. Pick the semantic version using the table and increment the affected app's build number above its last delivered build. Never reset or reuse a delivered build number for different app source or build settings, even if an earlier build was only installed locally for testing.
3. While iterating within that planned version, additional changed builds that are installed or distributed receive new build numbers. Changes made before the first delivered build may share the batch's allocated version/build.
4. Retrying a failed build, rerunning tests, or republishing the exact same source/build settings does not consume another build number. A plain request to rebuild unchanged code does not require a version bump.
5. Do not rewrite historical verification entries or prior release identities. Update current-release summaries separately.

## Delivery workflow

- Make the metadata change before the release build. Keep the four .NET version values derived from the two authoritative properties; do not hard-code a separate version in XAML, Dart UI, or status responses.
- Update current-version summaries in README, setup, and implementation-plan docs for the affected component, including brief release notes and any compatibility limits. Distinguish declared, built, staged, and installed versions accurately.
- Run checks appropriate to the actual changes, then build/publish the affected component. Verify the produced binary/package metadata and the visible version where possible. For Windows, also verify the API assembly's product version because it supplies `serverVersion`.
- For Windows, publish to `artifacts/publish/TapMyPC-next` while the installed copy is running. Apply using `tools/Apply-Update.ps1` after a normal tray exit. Do not kill the host or silently cancel pending power timers to replace locked binaries. If it remains running, report that the update is staged and give the apply command.
- For Android, verify both version name and monotonically increasing version code after packaging/installing when Android work is in scope. Never assume the existing phone package matches the repository declaration.
- Include version metadata and release notes in the implementation commit. Commit/push, tag, publish externally, or install onto a device only when authorized by the task/session; this policy alone does not authorize those actions.
- In the completion message, report the affected version/build, relevant validation, and whether it was installed or only staged. Mention a known mismatch with the other app only when it matters to testing or compatibility.
