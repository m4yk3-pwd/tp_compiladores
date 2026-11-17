#include <stdio.h>
#include <stdarg.h>

#include "utils/errors.h"

/* Diagnostic state owned by the lexer (defined in lexico/lexer.l). */
extern int token_line, token_col;
extern int last_lex_error_line;
extern int lex_unclosed_comment;

int syntax_errors = 0;
int syntax_suppressed = 0;
int semantic_errors = 0;

void report_syntax_error(int line, int col, const char *msg) {
    fprintf(stderr, "Erro sintatico (linha %d, coluna %d): %s\n", line, col, msg);
    syntax_errors++;
    syntax_suppressed = 0;
}

void report_semantic_error(int line, int col, const char *fmt, ...) {
    va_list args;
    fprintf(stderr, "Erro semantico (linha %d, coluna %d): ", line, col);
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
    semantic_errors++;
}

void yyerror(const char *s) {
    /* Suppress syntactic noise that is really a consequence of a lexical error
     * on the same line (or of an unterminated comment). */
    if (lex_unclosed_comment || token_line == last_lex_error_line) {
        syntax_suppressed = 1;
        return;
    }
    report_syntax_error(token_line, token_col, s);
}
