; Vendored from nvim-treesitter/nvim-treesitter, rewritten to emit the canonical
; capture names used by the MacDown 2 theme key space.

(atx_heading) @markup.heading

(setext_heading) @markup.heading

[
  (link_title)
  (indented_code_block)
  (fenced_code_block)
] @markup.raw

(fenced_code_block_delimiter) @punctuation

(code_fence_content) @none

(link_destination) @markup.link

(link_label) @markup.link

[
  (list_marker_plus)
  (list_marker_minus)
  (list_marker_star)
  (list_marker_dot)
  (list_marker_parenthesis)
  (thematic_break)
] @punctuation

[
  (block_continuation)
  (block_quote_marker)
] @punctuation

(backslash_escape) @string
