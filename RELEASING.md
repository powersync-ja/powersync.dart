# Preparing Release

Bump the version of the packages to be released using `melos`:

```
melos version
```

if melos does not pick up changes or does not bump the version correctly, you can manually version the packages using

```
melos version -V ${PACKAGE_NAME}:m.m.p
for e.g melos version -V powersync:1.6.3
```

This will create a tag in the format of ${PACKAGE_NAME}-vm.m.p

```
e.g powersync-v1.6.4, powersync_attachments_helper-v0.6.3+1, etc.
```

# Perform Release

```
git push --follow-tags
```
