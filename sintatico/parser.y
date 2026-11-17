%code top {
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
}

%code requires {
#include "utils/types.h"
}

%locations
%define parse.error verbose

%union {
    int ival;
    float fval;
    char *sval;
    DataType dtype;
    ExprAttr expr;
    ArgList args;
    struct {
        char *l_cond;
        char *l_passo;
        char *l_body;
        char *l_fim;
    } loop_lbl;
}

%code {
#include "utils/type_system.h"
#include "utils/symbol_table.h"
#include "utils/tac.h"
#include "utils/expr_gen.h"
#include "utils/semantic_actions.h"
#include "utils/errors.h"

int yylex(void);
}

%token INT FLOAT STRING VOID IF ELSE WHILE FOR RETURN MAIN
%token SWITCH CASE DEFAULT BREAK
%token <sval> FUNC_ID GLOBAL_ID LOCAL_ID STRING_LIT
%token <ival> INT_LIT
%token <fval> FLOAT_LIT
%token EQ NEQ LE GE AND OR

%type <dtype> tipo tipo_retorno
%type <expr> expressao case_value for_cond chamada_funcao
%type <args> argumentos arg_lista
%type <sval> if_prefix

%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE
%left OR
%left AND
%left EQ NEQ
%left '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'
%right '!' UMINUS

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
        {
            declare_global($2, $1, @2.first_line, @2.first_column);
        }
    ;

tipo:
    INT      { $$ = TYPE_INT; }
    | FLOAT  { $$ = TYPE_FLOAT; }
    | STRING { $$ = TYPE_STRING; }
    ;

tipo_retorno:
    VOID   { $$ = TYPE_VOID; }
    | tipo { $$ = $1; }
    ;

funcao_decl:
    tipo_retorno FUNC_ID '('
        {
            begin_function($2, $1, @2.first_line, @2.first_column);
        }
    parametros ')'
        {
            in_func_header = 1;
        }
    bloco
        {
            end_function($2);
        }
    | INT MAIN '(' ')'
        {
            begin_main(@2.first_line, @2.first_column);
        }
    bloco
        {
            end_main();
        }
    | tipo_retorno LOCAL_ID
        {
            report_syntax_error(@2.first_line, @2.first_column,
                                "nome de funcao invalido: use verbo + Termo (ex.: calcularSoma)");
            current_func = NULL;
            enter_scope();
        }
      '(' parametros ')'
        {
            in_func_header = 1;
        }
      bloco
        {
            exit_scope();
        }
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
        {
            declare_param($2, $1, @2.first_line, @2.first_column);
        }
    ;

bloco:
    '{'
        {
            int is_func_body = in_func_header;
            in_func_header = 0;
            if (!is_func_body) enter_scope();
            $<ival>$ = is_func_body;
        }
    comandos '}'
        {
            if (!$<ival>2) exit_scope();
        }
    ;

comandos:
    comandos comando
    | /* vazio */
    ;

comando:
    var_local_decl
    | declaracao_init ';'
    | atribuicao ';'
    | condicional
    | repeticao
    | switch_stmt
    | BREAK ';'
        {
            emit_break(@1.first_line, @1.first_column);
        }
    | retorno ';'
    | chamada_funcao ';'
    | bloco
    | error ';'
    ;

var_local_decl:
    tipo LOCAL_ID ';'
        {
            declare_local($2, $1, @2.first_line, @2.first_column);
        }
    ;

declaracao_init:
    tipo LOCAL_ID '=' expressao
        {
            declare_init($2, $1, $4,
                         @2.first_line, @2.first_column,
                         @3.first_line, @3.first_column);
        }
    ;

atribuicao:
    LOCAL_ID '=' expressao
        {
            assign_local($1, $3,
                         @1.first_line, @1.first_column,
                         @2.first_line, @2.first_column);
        }
    | GLOBAL_ID '=' expressao
        {
            assign_global($1, $3,
                          @1.first_line, @1.first_column,
                          @2.first_line, @2.first_column);
        }
    ;

if_prefix:
    IF '(' expressao ')'
        {
            $$ = begin_if($3, @3.first_line, @3.first_column);
        }
    ;

condicional:
    if_prefix comando %prec LOWER_THAN_ELSE
        {
            emit_quad("label", "", "", $1);
        }
    | if_prefix comando ELSE
        {
            char *l_end = new_label();
            emit_quad("goto", "", "", l_end);
            emit_quad("label", "", "", $1);
            $<sval>$ = l_end;
        }
      comando
        {
            emit_quad("label", "", "", $<sval>4);
        }
    ;

repeticao:
    WHILE
        {
            char *l_ini = new_label();
            emit_quad("label", "", "", l_ini);
            $<sval>$ = l_ini;
        }
    '(' expressao ')'
        {
            check_condition($4, "while", @4.first_line, @4.first_column);
            char *l_fim = new_label();
            emit_quad("ifFalse", $4.addr, "", l_fim);
            push_break(l_fim);
            $<sval>$ = l_fim;
        }
    comando
        {
            emit_quad("goto", "", "", $<sval>2);
            emit_quad("label", "", "", $<sval>6);
            pop_break();
        }
    | FOR '(' for_init ';'
        {
            char *l_cond = new_label();
            emit_quad("label", "", "", l_cond);
            $<sval>$ = l_cond;
        }
      for_cond ';'
        {
            if ($6.addr != NULL) {
                check_condition($6, "for", @6.first_line, @6.first_column);
            }
            $<loop_lbl>$.l_cond  = $<sval>5;
            $<loop_lbl>$.l_passo = new_label();
            $<loop_lbl>$.l_body  = new_label();
            $<loop_lbl>$.l_fim   = new_label();

            if ($6.addr != NULL) {
                emit_quad("ifFalse", $6.addr, "", $<loop_lbl>$.l_fim);
            }
            emit_quad("goto", "", "", $<loop_lbl>$.l_body);
            emit_quad("label", "", "", $<loop_lbl>$.l_passo);
            push_break($<loop_lbl>$.l_fim);
        }
      for_passo ')'
        {
            emit_quad("goto", "", "", $<loop_lbl>8.l_cond);
            emit_quad("label", "", "", $<loop_lbl>8.l_body);
        }
      comando
        {
            emit_quad("goto", "", "", $<loop_lbl>8.l_passo);
            emit_quad("label", "", "", $<loop_lbl>8.l_fim);
            pop_break();
        }
    ;

for_init:
    atribuicao
    | declaracao_init
    | /* vazio */
    ;

for_cond:
    expressao     { $$ = $1; }
    | /* vazio */ { $$.type = TYPE_INT; $$.addr = NULL; }
    ;

for_passo:
    atribuicao
    | /* vazio */
    ;

switch_stmt:
    SWITCH '(' expressao ')'
        {
            switch_begin($3, @3.first_line, @3.first_column);
        }
    '{' cases '}'
        {
            switch_end();
        }
    ;

cases:
    cases case_stmt
    | /* vazio */
    ;

case_stmt:
    CASE case_value ':'
        {
            switch_case($2, @2.first_line, @2.first_column);
        }
    comandos
    | DEFAULT ':'
        {
            switch_default();
        }
    comandos
    ;

case_value:
    INT_LIT       { $$ = make_int_lit($1); }
    | '-' INT_LIT { $$ = make_int_lit(-$2); }
    | STRING_LIT  { $$ = make_string_lit($1); }
    ;

retorno:
    RETURN expressao
        {
            check_return_value($2,
                               @1.first_line, @1.first_column,
                               @2.first_line, @2.first_column);
        }
    | RETURN
        {
            check_return_void(@1.first_line, @1.first_column);
        }
    ;

chamada_funcao:
    FUNC_ID '(' argumentos ')'
        {
            $$ = check_and_emit_call($1, $3,
                                     @1.first_line, @1.first_column,
                                     @3.first_line, @3.first_column);
        }
    ;

argumentos:
    arg_lista     { $$ = $1; }
    | /* vazio */ { $$ = arg_list_empty(); }
    ;

arg_lista:
    expressao
        {
            $$ = arg_list_add(arg_list_empty(), $1);
        }
    | arg_lista ',' expressao
        {
            $$ = arg_list_add($1, $3);
        }
    ;

expressao:
    expressao '+' expressao   { $$ = gen_arith("+", $1, $3, @2.first_line, @2.first_column); }
    | expressao '-' expressao { $$ = gen_arith("-", $1, $3, @2.first_line, @2.first_column); }
    | expressao '*' expressao { $$ = gen_arith("*", $1, $3, @2.first_line, @2.first_column); }
    | expressao '/' expressao { $$ = gen_arith("/", $1, $3, @2.first_line, @2.first_column); }
    | expressao '%' expressao { $$ = gen_mod($1, $3, @2.first_line, @2.first_column); }
    | expressao EQ expressao  { $$ = gen_eq("==", $1, $3, @2.first_line, @2.first_column); }
    | expressao NEQ expressao { $$ = gen_eq("!=", $1, $3, @2.first_line, @2.first_column); }
    | expressao '<' expressao { $$ = gen_rel("<", $1, $3, @2.first_line, @2.first_column); }
    | expressao '>' expressao { $$ = gen_rel(">", $1, $3, @2.first_line, @2.first_column); }
    | expressao LE expressao  { $$ = gen_rel("<=", $1, $3, @2.first_line, @2.first_column); }
    | expressao GE expressao  { $$ = gen_rel(">=", $1, $3, @2.first_line, @2.first_column); }
    | expressao AND expressao { $$ = gen_logic("&&", $1, $3, @2.first_line, @2.first_column); }
    | expressao OR expressao  { $$ = gen_logic("||", $1, $3, @2.first_line, @2.first_column); }
    | '-' expressao %prec UMINUS { $$ = gen_unary_minus($2, @1.first_line, @1.first_column); }
    | '!' expressao              { $$ = gen_not($2, @1.first_line, @1.first_column); }
    | '(' expressao ')'          { $$ = $2; }
    | LOCAL_ID   { $$ = load_variable($1, 0, @1.first_line, @1.first_column); }
    | GLOBAL_ID  { $$ = load_variable($1, 1, @1.first_line, @1.first_column); }
    | INT_LIT    { $$ = make_int_lit($1); }
    | FLOAT_LIT  { $$ = make_float_lit($1); }
    | STRING_LIT { $$ = make_string_lit($1); }
    | chamada_funcao
        {
            $$ = check_call_in_expr($1, @1.first_line, @1.first_column);
        }
    ;

%%
