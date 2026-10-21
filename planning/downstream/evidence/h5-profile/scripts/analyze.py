#!/usr/bin/env python3
"""analyze.py main.folded [label]: inclusive share of main-thread busy time by category, plus top self frames.
Categories match frame-name substrings; a sample counts once per category (inclusive)."""
import sys, collections

CATS = [
    ('Neon edit path: TreeSitterClient.didChangeContent', ['TreeSitterClient.didChangeContent']),
    ('  LanguageLayer.parse(with:affecting:resolveSublayers:)', ['LanguageLayer.parse(with:affecting:resolveSublayers:)']),
    ('    tree-sitter ts_parser_parse (Parser.parse)', ['Parser.parse(tree:encoding:readBlock:)']),
    ('      ts_parser__select_children (GLR merge)', ['ts_parser__select_children']),
    ('        ts_subtree_compare', ['ts_subtree_compare']),
    ('      ts_lexer_goto', ['ts_lexer_goto']),
    ('      ts_parser__lex (lexing incl. scanner)', ['ts_parser__lex']),
    ('      ts_parser__external_scanner_scan', ['ts_parser__external_scanner_scan']),
    ('      SwiftTreeSitter read callback (readFunction)', ['readFunction(payload:']),
    ('      ts_parser__reduce (incl. select_children)', ['ts_parser__reduce']),
    ('      ts_parser__condense_stack', ['ts_parser__condense_stack']),
    ('      ts_parser__breakdown_*', ['ts_parser__breakdown']),
    ('      ts_parser__balance_subtree', ['ts_parser__balance_subtree']),
    ('    ParseState.changedSet (ts_tree_get_changed_ranges)', ['ParseState.changedSet']),
    ('    old ParseState/Tree release (ts_tree_delete)', ['ts_tree_delete']),
    ('resolveSublayers (any caller)', ['resolveSublayers(with:']),
    ('  encorporateRanges', ['encorporateRanges']),
    ('  injection query (executeShallowQuery/injections)', ['executeShallowQuery', 'injections(with:']),
    ('Neon validation / styling (TextSystemStyler, Token validator)', ['TokenSystemValidator', 'ThreePhaseRangeValidator', 'SinglePhaseRangeValidator', 'TextSystemStyler', 'ThreePhaseTextSystemStyler']),
    ('  token query execution (highlights query, ts_query_cursor)', ['ts_query_cursor', 'executeQuery', 'highlights(', 'QueryCursor']),
    ('  TextKit setRenderingAttributes / apply styles', ['setRenderingAttributes', 'addRenderingAttribute', 'removeRenderingAttribute', 'applyStyles', 'applyStyle']),
    ('TextKit 2 layout (NSTextLayoutManager ensureLayout etc.)', ['ensureLayout', 'NSTextLayoutFragment layout', '_NSTextLayoutFragment']),
    ('MacDownKit code frames (NeonSyntaxHighlighter/HighlightingStorageGate/EditorTextView) inclusive', ['NeonSyntaxHighlighter', 'HighlightingStorageGate', 'EditorTextView']),
    ('malloc/free (any)', ['_xzm_', 'malloc', '_free']),
]

path = sys.argv[1]
label = sys.argv[2] if len(sys.argv) > 2 else path
tot = 0
inc = collections.Counter()
self_ = collections.Counter()
for line in open(path):
    k, v = line.rsplit(' ', 1)
    v = int(v)
    tot += v
    fr = k.split(';')
    for name, pats in CATS:
        if any(p in f for f in fr for p in pats):
            inc[name] += v
    self_[fr[-1]] += v
print(f'## {label}: main-thread busy samples = {tot // 1000} (1 ms each)')
for name, _ in CATS:
    print(f'{100 * inc[name] / tot:6.1f}%  {name}')
print('top self frames:')
for n, v in self_.most_common(12):
    print(f'{100 * v / tot:6.1f}%  {n[:110]}')
