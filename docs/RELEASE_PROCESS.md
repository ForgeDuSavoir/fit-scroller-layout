# Release Process

This document defines how to publish an official Fit Scroller release.

The goal of a release is to let users install the Hyprland layout without
cloning the full repository. The official downloadable artifact contains only
the runtime layout files required by Hyprland.

## Release Artifact

Each release must provide a compressed archive attached to the GitHub release.
This attached archive is the official installation artifact.

GitHub also generates automatic "Source code" archives for every release. Those
archives contain the full repository and must not be presented as the preferred
installation path.

Artifact name:

```text
fit-scroller-layout-vX.Y.Z.tar.gz
```

Archive content:

```text
fit-scroller/
  init.lua
  hyprland_adapter.lua
  config.lua
  state.lua
  target_sync.lua
  commands.lua
  geometry.lua
  traversal.lua
  solver.lua
  viewport.lua
LICENSE
```

The `fit-scroller/` directory is generated from the repository's `layout/`
directory. The directory is renamed in the release artifact so users can extract
it directly into a Hyprland layouts directory without ending up with a generic
`layout/` folder.

Release artifacts are generated files. They are written under `dist/` locally
and are not committed to the repository.

## Versioning

Use Git tags as the source of release identity.

Tag format:

```text
vMAJOR.MINOR.PATCH
```

Examples:

```text
v0.1.0
v0.2.0
v1.0.0
```

Before `v1.0.0`, breaking behavior changes may still happen, but they must be
called out clearly in the GitHub release notes.

## Pre-Release Checklist

Before creating a release:

1. Ensure the working tree is clean:

```sh
git status --short
```

2. Run the test suite:

```sh
lua tests/run.lua
```

3. Review the user-facing installation guide:

```text
docs/USER_GUIDE_FOR_HYPRLAND_CUSTOM_LAYOUT.md
```

4. Decide the next version number and prepare release notes.

Release notes should mention:

- the version;
- user-visible changes;
- breaking changes, if any;
- known limitations worth exposing to users;
- the expected Hyprland version.

## Build The Artifact

From the repository root, set the release version:

```sh
VERSION=vX.Y.Z
```

Create the release archive:

```sh
rm -rf dist
mkdir -p "dist/fit-scroller-layout-$VERSION/fit-scroller"
cp layout/*.lua "dist/fit-scroller-layout-$VERSION/fit-scroller/"
cp LICENSE "dist/fit-scroller-layout-$VERSION/"
tar -C "dist/fit-scroller-layout-$VERSION" \
    -czf "dist/fit-scroller-layout-$VERSION.tar.gz" \
    fit-scroller LICENSE
```

Create a checksum file:

```sh
sha256sum "dist/fit-scroller-layout-$VERSION.tar.gz" \
    > "dist/fit-scroller-layout-$VERSION.tar.gz.sha256"
```

Verify the archive content:

```sh
tar -tzf "dist/fit-scroller-layout-$VERSION.tar.gz"
```

The archive must contain only `fit-scroller/` and `LICENSE`.

## Create The Git Release

Create and push the tag:

```sh
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"
```

Create a GitHub release for the pushed tag and attach:

```text
dist/fit-scroller-layout-vX.Y.Z.tar.gz
dist/fit-scroller-layout-vX.Y.Z.tar.gz.sha256
```

The GitHub release description should include a minimal installation example:

```sh
mkdir -p ~/.config/hypr/layouts
tar -C ~/.config/hypr/layouts -xzf fit-scroller-layout-vX.Y.Z.tar.gz
```

Then users can load:

```lua
dofile(os.getenv("HOME") .. "/.config/hypr/layouts/fit-scroller/init.lua")
```

and select:

```text
lua:fit-scroller
```

## Post-Release Verification

After publishing the GitHub release:

1. Download the attached archive from the release page.
2. Extract it into a temporary directory.
3. Confirm the archive contains `fit-scroller/init.lua` and the sibling runtime
   modules.
4. Confirm the checksum matches:

```sh
sha256sum -c fit-scroller-layout-vX.Y.Z.tar.gz.sha256
```

5. Install from the downloaded archive in a real or test Hyprland configuration.
6. Confirm Hyprland can select `lua:fit-scroller`.

Do not consider the release complete until the uploaded artifact has been
tested, not only the local files used to build it.

## User Installation Contract

The official installation path for users is:

1. Download the release archive from GitHub.
2. Extract `fit-scroller/` into a stable location, for example:

```text
~/.config/hypr/layouts/fit-scroller
```

3. Load `fit-scroller/init.lua` from the Hyprland Lua configuration.
4. Configure Hyprland to use `lua:fit-scroller`.

Users should not need to clone this repository unless they want to develop or
inspect the full project.
