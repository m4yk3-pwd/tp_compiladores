%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int yylex();
extern int yyparse();
extern FILE *yyin;
extern int lex_errors;

void yyerror(const char *s);
void erro_em(int l, int c, const char *msg);
int syn_errors = 0;
int syn_suprimido = 0;      /* 1 se o ULTIMO erro sintatico foi ocultado por ser cascata de erro lexico */
%}

%locations
%define parse.error verbose

%union {
    int ival;
    float fval;
    char *sval;
}

/* Tokens definidos no Flex */
%token INT FLOAT VOID IF ELSE WHILE FOR RETURN MAIN
%token SWITCH CASE DEFAULT BREAK
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
    | tipo MAIN '(' ')' bloco
    | tipo LOCAL_ID '(' parametros ')' bloco
        { erro_em(@2.first_line, @2.first_column,
                  "nome de funcao invalido: use verbo + Termo (ex.: calcularSoma)"); }
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
    | switch_stmt
    | BREAK ';'
    | retorno ';'
    | chamada_funcao ';'
    | bloco
    | error ';'     /* recuperacao: descarta ate o proximo ';' e continua */
    ;

var_local_decl:
    tipo LOCAL_ID ';'
    ;

atribuicao:
    LOCAL_ID '=' expressao
    | GLOBAL_ID '=' expressao
    | tipo LOCAL_ID '=' expressao
    ;

condicional:
    IF '(' expressao ')' comando %prec LOWER_THAN_ELSE
    | IF '(' expressao ')' comando ELSE comando
    ;

repeticao:
    WHILE '(' expressao ')' comando
    | FOR '(' for_init ';' for_cond ';' for_passo ')' comando
    ;

switch_stmt:
    SWITCH '(' expressao ')' '{' cases '}'
    ;

cases:
    cases case_stmt
    | /* vazio */
    ;

case_stmt:
    CASE expressao ':' comandos
    | DEFAULT ':' comandos
    ;

for_init:
    atribuicao
    | /* vazio */
    ;

for_cond:
    expressao
    | /* vazio */
    ;

for_passo:
    atribuicao
    | /* vazio */
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

void erro_em(int l, int c, const char *msg) {
    fprintf(stderr, "Erro sintatico (linha %d, coluna %d): %s\n", l, c, msg);
    syn_errors++;
    syn_suprimido = 0;
}

void yyerror(const char *s) {
    extern int token_line, token_col, last_lex_error_line;
    /* erro na MESMA linha de um erro lexico: quase certamente e cascata (token descartado) */
    if (token_line == last_lex_error_line) {
        syn_suprimido = 1;
        return;
    }
    erro_em(token_line, token_col, s);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        if (!(yyin = fopen(argv[1], "r"))) {
            perror(argv[1]);
            return 1;
        }
    }

    int rc = yyparse();
    int restante = 0;   /* tokens que sobraram quando o parser abortou */
    if (rc != 0) {
        /* o parser abortou (erro sem recuperacao): varre o resto so para achar erros lexicos */
        while (yylex() != 0) restante++;
    }

    if (lex_errors == 0 && syn_errors == 0) {
        printf("Analise lexica concluida.\n");
        printf("Analise sintatica concluida.\n");
        printf("Programa reconhecido com sucesso.\n");
    } else {
        printf("\nForam encontrados %d erro(s) lexico(s) e %d erro(s) sintatico(s).\n", lex_errors, syn_errors);
        if (rc != 0 && syn_suprimido && restante > 0)
            printf("Analise sintatica interrompida por erro lexico: corrija os erros lexicos e execute de novo para verificar o resto do programa.\n");
    }

    return (lex_errors || syn_errors) ? 1 : 0;
}