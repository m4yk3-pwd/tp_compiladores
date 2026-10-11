%{
#include <stdio.h>
#include <stdlib.h>

extern int yylex();
extern int yyparse();
extern FILE *yyin;
extern int lex_errors;

void yyerror(const char *s);
int syn_errors = 0;
%}

%union {
    int ival;
    float fval;
    char *sval;
}

/* Tokens definidos no Flex */
%token INT FLOAT VOID IF ELSE WHILE RETURN PRINCIPAL
%token <sval> FUNC_ID GLOBAL_ID LOCAL_ID STRING_LIT
%token <ival> INT_LIT
%token <fval> FLOAT_LIT
%token EQ NEQ LE GE AND OR

/* Precedência de operadores e associatividade */
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%right '='
%left OR
%left AND
%left EQ NEQ
%left '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'

%start programa

%%

programa:
    declaracoes
    ;

declaracoes:
    declaracoes declaracao
    | /* vazio */
    ;

declaracao:
    var_global_decl
    | funcao_decl
    ;

var_global_decl:
    tipo GLOBAL_ID ';'
    ;

tipo:
    INT | FLOAT | VOID
    ;

funcao_decl:
    tipo FUNC_ID '(' parametros ')' bloco
    | tipo PRINCIPAL '(' ')' bloco
    ;

parametros:
    param_lista
    | /* vazio */
    ;

param_lista:
    parametro
    | param_lista ',' parametro
    ;

parametro:
    tipo LOCAL_ID
    ;

bloco:
    '{' comandos '}'
    ;

comandos:
    comandos comando
    | /* vazio */
    ;

comando:
    var_local_decl
    | atribuicao ';'
    | condicional
    | repeticao
    | retorno ';'
    | chamada_funcao ';'
    | bloco
    ;

var_local_decl:
    tipo LOCAL_ID ';'
    ;

atribuicao:
    LOCAL_ID '=' expressao
    | GLOBAL_ID '=' expressao
    ;

condicional:
    IF '(' expressao ')' comando %prec LOWER_THAN_ELSE
    | IF '(' expressao ')' comando ELSE comando
    ;

repeticao:
    WHILE '(' expressao ')' comando
    ;

retorno:
    RETURN expressao
    | RETURN
    ;

chamada_funcao:
    FUNC_ID '(' argumentos ')'
    ;

argumentos:
    arg_lista
    | /* vazio */
    ;

arg_lista:
    expressao
    | arg_lista ',' expressao
    ;

expressao:
    expressao '+' expressao
    | expressao '-' expressao
    | expressao '*' expressao
    | expressao '/' expressao
    | expressao '%' expressao
    | expressao EQ expressao
    | expressao NEQ expressao
    | expressao '<' expressao
    | expressao '>' expressao
    | expressao LE expressao
    | expressao GE expressao
    | expressao AND expressao
    | expressao OR expressao
    | '(' expressao ')'
    | LOCAL_ID
    | GLOBAL_ID
    | INT_LIT
    | FLOAT_LIT
    | STRING_LIT
    | chamada_funcao
    ;

%%

void yyerror(const char *s) {
    extern int line, col; 
    /* Agora as variáveis são usadas no fprintf abaixo: */
    fprintf(stderr, "Erro sintatico (linha %d, coluna %d): %s\n", line, col, s);
    syn_errors++;
}

int main(int argc, char **argv) {
    if (argc > 1) {
        if (!(yyin = fopen(argv[1], "r"))) {
            perror(argv[1]);
            return 1;
        }
    }

    yyparse();

    if (lex_errors == 0 && syn_errors == 0) {
        printf("Analise lexica concluida.\n");
        printf("Analise sintatica concluida.\n");
        printf("Programa reconhecido com sucesso.\n");
    } else {
        printf("\nForam encontrados %d erro(s) lexico(s) e %d erro(s) sintatico(s).\n", lex_errors, syn_errors);
    }

    return (lex_errors || syn_errors) ? 1 : 0;
}