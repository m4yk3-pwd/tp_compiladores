#ifndef UTILS_ERRORS_H
#define UTILS_ERRORS_H

/*
 * Error reporting and global error counters shared by the lexer, the parser
 * and the semantic analysis.
 */

extern int syntax_errors;      /* number of syntactic errors reported */
extern int syntax_suppressed;  /* a syntactic error was hidden behind a lexical one */
extern int semantic_errors;    /* number of semantic errors reported */

/* Reports a syntactic error at an explicit source position. */
void report_syntax_error(int line, int col, const char *msg);

/* Reports a semantic error with a printf-style formatted message. */
void report_semantic_error(int line, int col, const char *fmt, ...);

/* Bison error callback. */
void yyerror(const char *s);

#endif /* UTILS_ERRORS_H */
