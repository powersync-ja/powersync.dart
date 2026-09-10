# PowerSync agent skill

This directory is vendored from [powersync-ja/agent-skills](https://github.com/powersync-ja/agent-skills)
and is installed into users' projects by [`package:skills`](https://pub.dev/packages/skills)
(`dart run skills@ get`). The `powersync` skill from that repository is renamed to
`powersync-sdk` because `package:skills` only installs skills prefixed with the
package name.

Do not edit these files here. Contribute to powersync-ja/agent-skills instead. A
Claude routine runs `tool/sync_skills.sh` and opens a PR here whenever agent-skills
publishes a release, and CI checks that these files match the recorded release.

Source release: https://github.com/powersync-ja/agent-skills/releases/tag/v1.5.0
Archive digest: sha256:f7f480fbec63b03aba4b9b54641405e5c73e057a6e49959351a934d917f9c741
