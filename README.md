# hmos_app_template

Minimal-buildable HarmonyOS (HMOS) project skeleton used by the
`hmos-impl-from-spec` skill. Each time the skill converts a new Android app
spec into an HMOS project, it `cp -r`s this template into
`harmony_output/<App>/`, replaces the `${TEMPLATE_*}` placeholders, then
populates `entry/src/main/ets/pages/` with generated page code.

The template by itself (placeholders substituted) must compile cleanly via
`hvigor` even with zero business pages 鈥?it is the smallest viable HMOS
shell.

## What is in the template

- `build-profile.json5` 鈥?project-level build profile (HarmonyOS 6.0.2(22)).
- `code-linter.json5` 鈥?strict ArkTS linting on.
- `hvigorfile.ts` 鈥?standard `appTasks` entry.
- `oh-package.json5` 鈥?project-level dev deps (`@ohos/hypium`, `@ohos/hamock`).
- `.gitignore` 鈥?standard OpenHarmony ignores.
- `AppScope/app.json5` 鈥?app-level identity (placeholders).
- `AppScope/resources/base/element/string.json` 鈥?declares `app_name`.
- `AppScope/resources/base/media/.gitkeep` 鈥?empty media dir; the
  `android2hmos_resources_convert` skill writes `app_icon.png` etc. here later.

## Placeholder table

All placeholders share one canonical set across the entire template
(project-root, AppScope, and entry/ subagents all use the same names):

| Placeholder                       | Meaning                                                 | Example                                          |
| --------------------------------- | ------------------------------------------------------- | ------------------------------------------------ |
| `com.dd3boh.outertune.hmos`         | HMOS bundle name (reverse-DNS, ends in `.hmos`)         | `com.beemdevelopment.aegis.hmos`                 |
| `OuterTune`              | Vendor / publisher name (usually app name)              | `Aegis`                                          |
| `1`        | Integer version code                                    | `1`                                              |
| `1.0.0`        | Semver version string                                   | `1.0.0`                                          |
| `OuterTune`           | Display name shown on the launcher                      | `Aegis`                                          |
| `outertune`      | Lowercase, no-space identifier for `oh-package.json5`   | `aegis`                                          |
| `OuterTune music player for HarmonyOS` | One-line project description                            | `Aegis 2FA authenticator for HarmonyOS`          |
| `OuterTune main module`         | Description for `entry/src/main/module.json5` (module)  | `Aegis main module`                              |
| `OuterTune main entry ability`        | Description for `entry/src/main/module.json5` (ability) | `Aegis main entry ability`                       |

## Usage example

```bash
APP=Aegis
DEST=harmony_output/${APP}

cp -r hmos_app_template "${DEST}"

# POSIX in-place replacement
find "${DEST}" -type f \( -name '*.json5' -o -name '*.json' -o -name '*.ts' -o -name '*.ets' -o -name '*.md' \) \
  -exec sed -i \
    -e 's|com.dd3boh.outertune.hmos|com.beemdevelopment.aegis.hmos|g' \
    -e 's|OuterTune|Aegis|g' \
    -e 's|1|1|g' \
    -e 's|1.0.0|1.0.0|g' \
    -e 's|OuterTune|Aegis|g' \
    -e 's|outertune|aegis|g' \
    -e 's|OuterTune music player for HarmonyOS|Aegis 2FA authenticator for HarmonyOS|g' \
    -e 's|OuterTune main module|Aegis main module|g' \
    -e 's|OuterTune main entry ability|Aegis main entry ability|g' \
    {} +
```

PowerShell equivalent:

```powershell
$APP = 'Aegis'
$DEST = "harmony_output/$APP"
Copy-Item hmos_app_template $DEST -Recurse

$map = @{
  'com.dd3boh.outertune.hmos'         = 'com.beemdevelopment.aegis.hmos'
  'OuterTune'              = 'Aegis'
  '1'        = '1'
  '1.0.0'        = '1.0.0'
  'OuterTune'           = 'Aegis'
  'outertune'      = 'aegis'
  'OuterTune music player for HarmonyOS' = 'Aegis 2FA authenticator for HarmonyOS'
  'OuterTune main module'         = 'Aegis main module'
  'OuterTune main entry ability'        = 'Aegis main entry ability'
}
Get-ChildItem $DEST -Recurse -File -Include *.json5,*.json,*.ts,*.ets,*.md | ForEach-Object {
  $c = Get-Content $_.FullName -Raw
  foreach ($k in $map.Keys) { $c = $c.Replace($k, $map[$k]) }
  Set-Content $_.FullName $c -NoNewline
}
```

## Notes & caveats

1. **Resource keys are not placeholders.** `AppScope/app.json5` references
   `$media:app_icon` and `$string:app_name`. These are resource keys read by
   the HMOS runtime, not template variables. Do **not** substitute them.
2. **`AppScope/resources/base/media/` is intentionally empty** (only a
   `.gitkeep`). The `android2hmos_resources_convert` skill (run later by
   `hmos-impl-from-spec`) will inject `app_icon.png`, `background.png`,
   `foreground.png`, `layered_image.json`, `startIcon.png`.
3. **Project-level `oh-package.json5` carries no business deps** 鈥?only the
   two dev deps (`hypium`, `hamock`). All app-level dependencies belong in
   `entry/oh-package.json5` so they don't pollute every future template
   instance.
4. **`signingConfigs` is `[]`** 鈥?DevEco Studio fills this in on first build
   via auto-signing; CI builds inject signing material from a separate
   profile.
5. **Downstream pipeline (handled by `hmos-impl-from-spec` skill, not this
   template):**
   - Step A 鈥?copy template, substitute placeholders.
   - Step B 鈥?call `android2hmos_resources_convert` to populate `entry/`
     resources + `AppScope/resources/base/media/`.
   - Step C 鈥?generate ArkTS pages under `entry/src/main/ets/pages/` from
     the spec.
   - Step D 鈥?register pages in `entry/src/main/resources/base/profile/main_pages.json`.
   - Step E 鈥?call `hmos-build-fix` to drive the project to a green build.
