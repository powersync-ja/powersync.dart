# Preparing Release

Bump the version of the packages to be released using `melos`:

```
melos version
```

if melos does not pick up changes or does not bump the version correctly, you can manually version the packages using

```
melos version -V ${PACKAGE_NAME}:M.M.P
for e.g melos version -V powersync:1.6.3
```

This will create a tag for all packages updated in the format of ${PACKAGE_NAME}-vM.M.P

```
e.g powersync-v1.6.4, powersync_attachments_helper-v0.6.3+1, etc.
```

# Perform Release

```
git push --follow-tags
```

**Note: This will launch the `release.yaml` and `publish.yaml` github actions in `.github/workflows`. So only run it when you are absolutely sure you want to release.**

A version bump and tag push for `powersync` will also create a Github release for the PowerSync web workers. Verify the release exists and is published in the [releases](https://github.com/powersync-ja/powersync.dart/releases).
