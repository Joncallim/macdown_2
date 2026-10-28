# Textual image-loader interception probe (#121)

## Owner summary

The pinned Markdown renderer exposes image references to an app-supplied loader
when a real preview is mounted. This lets the planned folder grant control
image reads, provided the app replaces the default loader before exposing the
chooser. This spike changes no live preview behavior or permission.

The branch starts from the frozen integration candidate
`c4b9013b254af3421701b39ce182aa8e3a022393` and follows the separate
contained child-directory spike at `1d272e378de16e43fd90832ebe7a47ad2bd31b5c`.
The production Textual pin remains `01b51875a5406eefc95f52a058cb059e7bc94dc4`.

## Evidence and limits

`TextualAttachmentInterceptionTests` mounts `StructuredText` in an
`NSHostingView` and visible `NSWindow` with the current
`PreviewMarkupParser(baseURL:)`. A recording, in-memory `AttachmentLoader`
received all four authored forms: relative path, explicit HTTPS, explicit
file URL, and network-path authority. The focused forced-pin test passed on
macOS 26.5.1 / Xcode 26.6. No network or filesystem bytes are requested by
this test loader.

The test establishes the interception route and the preserved
`url.relativeString` spelling, not the complete product security contract.
The current app still uses Textual's default loader. A follow-on hosted test
must prove that a held old completion cannot publish after grant, document or
source-revision changes; it must also cover image sizing, selection, copy,
retained payload lifetime and bounded admission. The HTML reader remains
separate. No chooser should be exposed until both readers use the same
contained authority.
