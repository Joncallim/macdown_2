#!/usr/bin/env python3
"""SCRATCH-ONLY instrumentation of a tree-sitter copy (H5 profile). instrument_ts.py <tree-sitter dir> [--ptr-eq]
Adds plain global counters and one stderr line per ts_parser_parse call when H5PROF_TS=1.
--ptr-eq additionally applies EXPERIMENT E1: ts_subtree_compare skips child pairs that are the
same subtree pointer (identical subtrees compare equal without descending)."""
import sys, re, pathlib

root = pathlib.Path(sys.argv[1]) / 'lib' / 'src'
ptr_eq = '--ptr-eq' in sys.argv

hdr = root / 'h5prof.h'
hdr.write_text('''#ifndef H5PROF_H
#define H5PROF_H
#include <stdint.h>
extern uint64_t h5_select_children, h5_compare_calls, h5_compare_nodes, h5_compare_equal,
  h5_lexer_goto, h5_lexer_goto_iters, h5_reuse_ok, h5_reuse_bytes, h5_advance,
  h5_advance_noreuse, h5_max_versions, h5_reduce, h5_ptr_skips, h5_vc[5];
#endif
''')


def patch(path, subs):
    s = path.read_text()
    for old, new in subs:
        if old not in s:
            raise SystemExit(f'pattern not found in {path.name}: {old[:60]!r}')
        s = s.replace(old, new, 1)
    path.write_text(s)


patch(root / 'parser.c', [
    ('#include "./reusable_node.h"\n', '#include "./reusable_node.h"\n#include "./h5prof.h"\n#include <stdio.h>\n#include <stdlib.h>\n#include <time.h>\n'
     'uint64_t h5_select_children, h5_compare_calls, h5_compare_nodes, h5_compare_equal, h5_lexer_goto, h5_lexer_goto_iters,'
     ' h5_reuse_ok, h5_reuse_bytes, h5_advance, h5_advance_noreuse, h5_max_versions, h5_reduce, h5_ptr_skips, h5_vc[5];\n'),
    ('''  const SubtreeArray *children
) {
  array_assign(&self->scratch_trees, children);''', '''  const SubtreeArray *children
) {
  h5_select_children++;
  array_assign(&self->scratch_trees, children);'''),
    ('''    LOG("reuse_node symbol:%s", TREE_NAME(result));
    ts_subtree_retain(result);''', '''    LOG("reuse_node symbol:%s", TREE_NAME(result));
    h5_reuse_ok++; h5_reuse_bytes += ts_subtree_total_bytes(result);
    ts_subtree_retain(result);'''),
    ('''  bool did_reuse = true;
  Subtree lookahead = NULL_SUBTREE;''', '''  bool did_reuse = true;
  h5_advance++; if (!allow_node_reuse) h5_advance_noreuse++;
  { unsigned vc = ts_stack_version_count(self->stack); h5_vc[vc >= 5 ? 4 : vc] ++; }
  Subtree lookahead = NULL_SUBTREE;'''),
    ('''  uint32_t initial_version_count = ts_stack_version_count(self->stack);
''', '''  uint32_t initial_version_count = ts_stack_version_count(self->stack);
  h5_reduce++; if (initial_version_count > h5_max_versions) h5_max_versions = initial_version_count;
'''),
    ('''  TSTree *result = NULL;
  if (!self->language || !input.read) return NULL;
''', '''  TSTree *result = NULL;
  if (!self->language || !input.read) return NULL;
  static int h5_on = -1; if (h5_on < 0) h5_on = getenv("H5PROF_TS") != NULL;
  uint64_t h5_t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
  h5_select_children = h5_compare_calls = h5_compare_nodes = h5_compare_equal = h5_lexer_goto = h5_lexer_goto_iters = 0;
  h5_reuse_ok = h5_reuse_bytes = h5_advance = h5_advance_noreuse = h5_max_versions = h5_reduce = h5_ptr_skips = 0; for (int i = 0; i < 5; i++) h5_vc[i] = 0;
  bool h5_had_old = old_tree != NULL;
'''),
    ('''exit:
  ts_parser_reset(self);
  return result;
}''', '''exit:
  if (h5_on) {
    fprintf(stderr, "H5TS syms=%u ranges=%u old=%d bytes=%u ms=%.3f advance=%llu noreuse=%llu reduce=%llu maxver=%llu "
      "reuse_ok=%llu reuse_bytes=%llu select_children=%llu compare=%llu compare_nodes=%llu compare_equal=%llu ptr_skips=%llu "
      "lexer_goto=%llu goto_iters=%llu vc1=%llu vc2=%llu vc3=%llu vc4+=%llu\\n",
      self->language->symbol_count, self->lexer.included_range_count, h5_had_old,
      result ? ts_subtree_total_bytes(result->root) : 0,
      (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - h5_t0) / 1e6,
      h5_advance, h5_advance_noreuse, h5_reduce, h5_max_versions, h5_reuse_ok, h5_reuse_bytes, h5_select_children,
      h5_compare_calls, h5_compare_nodes, h5_compare_equal, h5_ptr_skips, h5_lexer_goto, h5_lexer_goto_iters, h5_vc[1], h5_vc[2], h5_vc[3], h5_vc[4]);
  }
  ts_parser_reset(self);
  return result;
}'''),
])

sub_subs = [
    ('#include "./subtree.h"\n', '#include "./subtree.h"\n#include "./h5prof.h"\n'),
    ('''int ts_subtree_compare(Subtree left, Subtree right, SubtreePool *pool) {
  array_push''', '''int ts_subtree_compare(Subtree left, Subtree right, SubtreePool *pool) {
  h5_compare_calls++;
  array_push'''),
    ('''    left = ts_subtree_from_mut(array_pop(&pool->tree_stack));

    int result = 0;''', '''    left = ts_subtree_from_mut(array_pop(&pool->tree_stack));
    h5_compare_nodes++;

    int result = 0;'''),
    ('''      array_clear(&pool->tree_stack);
      return result;
    }
''', '''      array_clear(&pool->tree_stack);
      return result;
    }
'''),
    ('''  }

  return 0;
}

static inline void ts_subtree_set_has_changes''', '''  }

  h5_compare_equal++;
  return 0;
}

static inline void ts_subtree_set_has_changes'''),
]
if ptr_eq:
    sub_subs.append(('''      Subtree right_child = ts_subtree_children(right)[i - 1];
      array_push''', '''      Subtree right_child = ts_subtree_children(right)[i - 1];
      /* EXPERIMENT E1 (scratch): an identical subtree compares equal; do not descend. */
      if (!left_child.data.is_inline && left_child.ptr == right_child.ptr) { h5_ptr_skips++; continue; }
      array_push'''))
patch(root / 'subtree.c', sub_subs)

lex = (root / 'lexer.c').read_text()
lex = lex.replace('#include "./lexer.h"\n', '#include "./lexer.h"\n#include "./h5prof.h"\n', 1)
lex = lex.replace('''static void ts_lexer_goto(Lexer *self, Length position) {
''', '''static void ts_lexer_goto(Lexer *self, Length position) {
  h5_lexer_goto++;
''', 1)
# count iterations of the forward scan loop (both stock and A start with this line)
lex, n = re.subn(r'(  for \(unsigned i = (?:0|start_index); i < self->included_range_count; i\+\+\) \{\n    TSRange \*included_range = &self->included_ranges\[i\];\n)',
                 r'\1    h5_lexer_goto_iters++;\n', lex, count=1)
if n != 1:
    raise SystemExit('lexer loop not found')
(root / 'lexer.c').write_text(lex)
print('instrumented', root, 'ptr_eq' if ptr_eq else '')
