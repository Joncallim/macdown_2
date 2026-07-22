; Vendored from nvim-treesitter/nvim-treesitter, rewritten to emit the canonical
; capture names used by the MacDown 2 theme key space.

[
  (code_span)
  (link_title)
] @markup.raw

(emphasis) @markup.italic

(strong_emphasis) @markup.bold

[
  (link_destination)
  (uri_autolink)
] @markup.link

[
  (link_label)
  (link_text)
  (image_description)
] @markup.link

[
  (backslash_escape)
  (hard_line_break)
] @string

(image
  [
    "!"
    "["
    "]"
    "("
    ")"
  ] @punctuation)

(inline_link
  [
    "["
    "]"
    "("
    ")"
  ] @punctuation)

(shortcut_link
  [
    "["
    "]"
  ] @punctuation)

; NOTE: extension not enabled by default
; (wiki_link ["[" "|" "]"] @punctuation)
