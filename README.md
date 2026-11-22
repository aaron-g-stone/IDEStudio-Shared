# IDEStudioShared

File-format models that [IDE Studio](https://github.com/aaron-g-stone/IDEStudio) (private) and its
Splunk add-on both compile, so the two read and write the same files the same way:

| File | What it models |
| --- | --- |
| `ConfFile.swift` | Splunk `.conf` files, keeping comments, blank lines and order, so one edited setting changes one line |
| `JSONValue.swift` | JSON that keeps its keys in the order written and numbers as written (`globalConfig.json`, Dashboard Studio definitions) |
| `SimpleXML.swift` | Simple XML dashboards (`<dashboard version="1.1">`, `<form>`), keeping what it does not model as raw XML |
| `StudioDashboard.swift` | Dashboard Studio dashboards: the XML wrapper and its JSON definition, blocks, inputs and checks |
| `Navigation.swift` | An app's navigation bar (`default/data/ui/nav/default.xml`) |
| `AddonSignature.swift` | An add-on's `signature.json`: the SHA-256 of each file and an Ed25519 signature over them, its id and version; building the signed message and checking a folder against it (signing itself is the release tool's) |

Foundation and CryptoKit only; macOS 14 or later.

## Using it

    .package(url: "https://github.com/aaron-g-stone/IDEStudio-Shared.git", from: "1.0.0")

and `import IDEStudioShared`. In Xcode: File › Add Package Dependencies… with the same address.

## Changing it

1. Change the code here and run `swift test`.
2. Commit, then tag a new version: a fix or addition raises the minor or patch number
   (`git tag v1.1.0`); a change that breaks existing callers raises the major number.
3. `git push --follow-tags`, then in IDE Studio and the add-on update the package
   (Xcode: File › Packages › Update to Latest Package Versions; the add-on: `swift package update`).

To try a change in IDE Studio before tagging it, drag this folder into IDE Studio's Xcode project:
a local copy of a package takes the place of the downloaded one until it is removed.
