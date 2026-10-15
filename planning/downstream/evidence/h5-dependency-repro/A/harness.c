// Problem A harness: markdown_inline parse/reparse time vs number of included ranges N
// at fixed inline-content size. Usage: harness CONTENT_BYTES RUNS N1 N2 ...
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <tree_sitter/api.h>

const TSLanguage *tree_sitter_markdown_inline(void);
#ifdef COUNT
extern unsigned long long ts_goto_calls, ts_goto_iters;
#endif

static double now_ms(void) {
  struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}
static int cmpd(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y);
}
static TSPoint pt_of(const char *s, uint32_t off) { // row/col by scan (setup only)
  TSPoint p = {0, 0};
  for (uint32_t i = 0; i < off; i++) { if (s[i] == '\n') { p.row++; p.column = 0; } else p.column++; }
  return p;
}

int main(int argc, char **argv) {
  if (argc < 4) { fprintf(stderr, "usage\n"); return 1; }
  uint32_t content = (uint32_t)atol(argv[1]);
  int runs = atoi(argv[2]);
  static const char *pat = "Some *emph* and **strong** text with `code` and [a link](http://x.y) here. ";
  size_t plen = strlen(pat);
  printf("%8s %8s %10s %10s %10s %10s %10s %14s %14s\n", "N", "textB", "full_p50", "full_p95",
         "edit_p50", "edit_p95", "edit_max", "goto_calls", "goto_iters");
  for (int a = 3; a < argc; a++) {
    uint32_t N = (uint32_t)atol(argv[a]);
    uint32_t per = content / N; if (per < 1) per = 1;
    uint32_t len = N * (per + 1);
    char *text = malloc(len + 1);
    TSRange *r = malloc(sizeof(TSRange) * N);
    uint32_t pos = 0, k = 0;
    for (uint32_t i = 0; i < N; i++) {
      r[i].start_byte = pos;
      for (uint32_t j = 0; j < per; j++) text[pos++] = pat[k++ % plen];
      r[i].end_byte = pos;
      text[pos++] = '\n'; // excluded separator, like block structure between inline nodes
    }
    text[len] = 0;
    // points: incremental
    TSPoint p = {0, 0}; uint32_t last = 0;
    for (uint32_t i = 0; i < N; i++) {
      TSPoint d = pt_of(text + last, r[i].start_byte - last);
      if (d.row) { p.row += d.row; p.column = d.column; } else p.column += d.column;
      r[i].start_point = p; last = r[i].start_byte;
      d = pt_of(text + last, r[i].end_byte - last);
      if (d.row) { p.row += d.row; p.column = d.column; } else p.column += d.column;
      r[i].end_point = p; last = r[i].end_byte;
    }
    TSParser *parser = ts_parser_new();
    ts_parser_set_language(parser, tree_sitter_markdown_inline());
    if (!ts_parser_set_included_ranges(parser, r, N)) { printf("set_included_ranges FAILED N=%u\n", N); return 2; }
    double *full = malloc(sizeof(double) * runs), *edit = malloc(sizeof(double) * runs);
    unsigned long long gc = 0, gi = 0;
    for (int run = 0; run < runs; run++) {
      double t0 = now_ms();
      TSTree *tree = ts_parser_parse_string(parser, NULL, text, len);
      full[run] = now_ms() - t0;
      // one-character in-place replacement in the middle range (same length -> ranges unchanged)
      uint32_t mid = N / 2;
      uint32_t at = r[mid].start_byte + (r[mid].end_byte - r[mid].start_byte) / 2;
      char old = text[at]; text[at] = (old == 'x') ? 'y' : 'x';
      TSPoint ap = pt_of(text, at), bp = ap; bp.column++;
      TSInputEdit e = {at, at + 1, at + 1, ap, bp, bp};
      ts_tree_edit(tree, &e);
#ifdef COUNT
      ts_goto_calls = ts_goto_iters = 0;
#endif
      t0 = now_ms();
      TSTree *t2 = ts_parser_parse_string(parser, tree, text, len);
      edit[run] = now_ms() - t0;
#ifdef COUNT
      gc = ts_goto_calls; gi = ts_goto_iters;
#endif
      if (run == 0 && getenv("DUMP")) {
        char *a = ts_node_string(ts_tree_root_node(t2)); unsigned long h = 5381; for (char *c = a; *c; c++) h = h * 33 + (unsigned char)*c;
        uint32_t nr; const TSRange *ir = ts_tree_included_ranges(t2, &nr);
        fprintf(stderr, "N=%u sexp_len=%zu hash=%lx\n", N, strlen(a), h); free(a); free((void*)ir);
      }
      ts_tree_delete(tree); ts_tree_delete(t2);
    }
    qsort(full, runs, sizeof(double), cmpd); qsort(edit, runs, sizeof(double), cmpd);
    int p95 = (int)(runs * 0.95); if (p95 >= runs) p95 = runs - 1;
    printf("%8u %8u %10.2f %10.2f %10.3f %10.3f %10.3f %14llu %14llu\n", N, len, full[runs / 2], full[p95],
           edit[runs / 2], edit[p95], edit[runs - 1], gc, gi);
    fflush(stdout);
    ts_parser_delete(parser); free(text); free(r); free(full); free(edit);
  }
  return 0;
}
