#include <stdio.h>

#include "parser.tab.h"
#include "utils/symbol_table.h"
#include "utils/tac.h"
#include "utils/errors.h"

int yylex(void);
int yyparse(void);
extern FILE *yyin;

/* Lexical error counter (defined in lexico/lexer.l). */
extern int lex_errors;

int main(int argc, char **argv) {
    if (argc > 1) {
        if (!(yyin = fopen(argv[1], "r"))) {
            perror(argv[1]);
            return 1;
        }
    }

    int rc = yyparse();

    /* Drain the remaining tokens so lexical errors past the first syntax error
     * are still counted and reported. */
    int remaining = 0;
    if (rc != 0) {
        while (yylex() != 0) remaining++;
    }

    if (lex_errors == 0 && syntax_errors == 0 && semantic_errors == 0) {
        printf("Analise lexica concluida.\n");
        printf("Analise sintatica concluida.\n");
        printf("Analise semantica concluida.\n");
        printf("Programa reconhecido com sucesso.\n");

        print_symbol_table();
        print_quadruples();
        print_tac_code();
    } else {
        printf("\nForam encontrados %d erro(s) lexico(s), %d erro(s) sintatico(s) e %d erro(s) semantico(s).\n",
               lex_errors, syntax_errors, semantic_errors);
        if (rc != 0 && syntax_suppressed && remaining > 0)
            printf("Analise sintatica interrompida por erro lexico: corrija os erros lexicos e execute de novo para verificar o resto do programa (restaram: %d tokens)\n",
                   remaining);
    }

    if (yyin && yyin != stdin) fclose(yyin);
    return (lex_errors || syntax_errors || semantic_errors) ? 1 : 0;
}
