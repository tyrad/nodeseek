# Iframe Link Block Design

## Goal

Support iframe embeds in post bodies and comments without inline-loading third-party pages. The app should show each iframe as a full-width link block that identifies the embed domain and opens the iframe target in Safari View Controller when tapped.

## Scope

- Applies to all HTML fragments rendered by `DTCoreTextHTMLContentRenderer`, including the main post body and comment bodies.
- Handles any `<iframe>` tag with a non-empty `src` attribute.
- Preserves the original `src` string for display and block data, including protocol-relative values such as `//player.bilibili.com/player.html?...`.
- Uses a tappable block presentation with 100% available content width.
- Does not inline-render iframe content with `WKWebView`.
- Does not add provider-specific video parsing or previews.

## Architecture

Add a new `RenderedContentBlock` case for iframe links, backed by a small value type containing the original `src`, a display domain, and an openable URL. The renderer will treat iframe tags like tables, pre blocks, and standalone image blocks: flush surrounding text into separate blocks, append the iframe block, then continue rendering the rest of the HTML.

The UI layer will add a dedicated AsyncDisplayKit node for the iframe block. It will fill the available content width, show a concise label such as `嵌入内容 · player.bilibili.com`, show the raw `src` below it, and forward taps through the existing `onLinkTapped` closure.

## URL Handling

- Absolute `http` and `https` iframe sources open as-is.
- Protocol-relative iframe sources keep their original display string but resolve to `https:<src>` for opening, because `SFSafariViewController` requires a URL scheme.
- Relative iframe sources resolve against the post detail `baseURL` for opening, while the original relative value remains visible.
- Iframes without an openable URL are ignored instead of producing a broken block.

## Rendering Behavior

Given:

```html
<p>before</p>
<p><iframe src="//player.bilibili.com/player.html?bvid=BV1GUdgBdESz"></iframe></p>
<p>after</p>
```

The renderer should produce text, iframe link, and text blocks in order. If the iframe is wrapped by a paragraph, the wrapper should not create an extra empty text block.

The same behavior applies when the fragment comes from a comment, because comments already use the same `makeRenderedContent` path as the post body.

## UI Details

- The iframe block node is a full-width rounded rectangular control within the current body/comment text column.
- Label text: `嵌入内容 · <domain>`.
- Secondary text: original `src`.
- Accessibility label includes the domain and original source.
- Tapping the block calls the existing link handler, so external iframe URLs ultimately open with `SFSafariViewController`.

## Tests

- Renderer test: iframe between text blocks becomes `.iframeLink` between two text blocks.
- Renderer test: protocol-relative `src` preserves raw source and resolves to an `https` open URL.
- Node factory test: iframe link block creates a display node whose calculated width matches the constrained width.
- Link handling test if needed: protocol-relative open URL is already normalized before passing through the existing link handler, so no extra SFSafari-specific test is required.

## Risks

- Regex-based block splitting must avoid swallowing surrounding wrapper text. This should follow the existing structured block and image block parsing style.
- `URL(string:)` does not accept protocol-relative strings as openable URLs, so the renderer must normalize only the open URL while preserving the raw display source.
- Unknown iframe domains may contain long URLs; the UI should allow wrapping and should not expand horizontally beyond the content column.
