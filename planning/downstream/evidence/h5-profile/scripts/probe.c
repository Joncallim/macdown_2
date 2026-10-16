// SCRATCH-ONLY probe (H5 profile): parse a string with tree-sitter-markdown-inline and print
// the instrumented parser counters (H5TS line). Usage: probe <file> [ranges: split at '\n\n']
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <tree_sitter/api.h>
const TSLanguage *tree_sitter_markdown_inline(void);
int main(int argc, char **argv) {
  FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *s = malloc(n + 1); fread(s, 1, n, f); s[n] = 0;
  TSParser *p = ts_parser_new(); ts_parser_set_language(p, tree_sitter_markdown_inline());
  if (argc > 2) { // one included range per paragraph
    TSRange *r = malloc(sizeof(TSRange) * (n / 2 + 1)); unsigned c = 0; long st = 0;
    for (long i = 0; i <= n; i++) if (i == n || (s[i] == '\n' && i + 1 < n && s[i + 1] == '\n')) {
      if (i > st) r[c++] = (TSRange){{0, 0}, {0, 0}, (uint32_t)st, (uint32_t)i}; st = i + 2; i++; }
    if (argv[2][0] == 's') { // EXPERIMENT E2 (scratch): one tree per range, full parse of each
      uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW), worst = 0;
      for (unsigned k = 0; k < c; k++) { uint64_t a = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        ts_parser_set_included_ranges(p, &r[k], 1); TSTree *tk = ts_parser_parse_string(p, NULL, s, n); ts_tree_delete(tk);
        uint64_t d = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - a; if (d > worst) worst = d; }
      fprintf(stderr, "SEPARATE trees=%u total_ms=%.3f worst_one_ms=%.4f\n", c, (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0) / 1e6, worst / 1e6);
      return 0;
    }
    ts_parser_set_included_ranges(p, r, c);
  }
  TSTree *t = ts_parser_parse_string(p, NULL, s, n);
  // edit one char in the middle and reparse incrementally
  long m = n / 2; s[m] = s[m] == 'x' ? 'y' : 'x';
  TSInputEdit e = {(uint32_t)m, (uint32_t)m + 1, (uint32_t)m + 1, {0, (uint32_t)m}, {0, (uint32_t)m + 1}, {0, (uint32_t)m + 1}};
  ts_tree_edit(t, &e);
  TSTree *t2 = ts_parser_parse_string(p, t, s, n);
  char *sx = ts_node_string(ts_tree_root_node(t2)); uint64_t h = 1469598103934665603ULL; for (char *q = sx; *q; q++) h = (h ^ (unsigned char)*q) * 1099511628211ULL;
  char *s1 = ts_node_string(ts_tree_root_node(t)); uint64_t h1 = 1469598103934665603ULL; for (char *q = s1; *q; q++) h1 = (h1 ^ (unsigned char)*q) * 1099511628211ULL;
  fprintf(stderr, "SEXP first=%016llx len=%zu incremental=%016llx len=%zu\n", h1, strlen(s1), h, strlen(sx));
  return 0;
}
