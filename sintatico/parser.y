%code top {
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
}

%code requires {
    typedef enum {
        TYPE_INT,
        TYPE_FLOAT,
        TYPE_STRING,
        TYPE_VOID,
        TYPE_ERROR
    } DataType;

    typedef struct {
        DataType type;
        char *addr;
    } ExprAttr;

    typedef struct {
        DataType types[32];
        int count;
    } ArgList;
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
int yylex(void);
extern FILE *yyin;
extern int lex_errors, token_line, token_col;
extern int last_lex_error_line, lex_unclosed_comment;

void yyerror(const char *s);
void erro_em(int l, int c, const char *msg);
void erro_semantico(int l, int c, const char *fmt, ...);

int syn_errors = 0;
int syn_suprimido = 0;
int sem_errors = 0;

/* =========================================================================
 * 1. TABELA DE SIMBOLOS E CONTROLE DE ESCOPO
 * ========================================================================= */
#define MAX_SYMBOLS 1000
#define MAX_PARAMS  32

typedef enum {
    SYM_GLOBAL,
    SYM_LOCAL,
    SYM_PARAM,
    SYM_FUNC
} SymbolKind;

typedef struct {
    char *name;
    SymbolKind kind;
    DataType type;
    int scope;
    int active;
    int line;
    int param_count;
    DataType param_types[MAX_PARAMS];
} Symbol;

Symbol sym_table[MAX_SYMBOLS];
int sym_count = 0;
int current_scope = 0;
int in_func_header = 0;
Symbol *current_func = NULL;

const char* type_name(DataType t) {
    switch (t) {
        case TYPE_INT:    
            return "int";
        case TYPE_FLOAT:  
            return "float";
        case TYPE_STRING: 
            return "string";
        case TYPE_VOID:   
            return "void";
        default:          
            return "erro";
    }
}

const char* kind_name(SymbolKind k) {
    switch (k) {
        case SYM_GLOBAL:
            return "GLOBAL";
        case SYM_LOCAL:
            return "LOCAL";
        case SYM_PARAM:
            return "PARAM";
        case SYM_FUNC:
            return "FUNC";
        default:
            return "?";
    }
}

void enter_scope(void) {
    current_scope++;
}

void exit_scope(void) {
    for (int i = 0; i < sym_count; i++) {
        if (sym_table[i].active && sym_table[i].scope == current_scope) {
            sym_table[i].active = 0;
        }
    }
    if (current_scope > 0) current_scope--;
}

/* Busca apenas no escopo atual (detecta declaracoes duplicadas) */
Symbol* lookup_current_scope(const char *name) {
    for (int i = sym_count - 1; i >= 0; i--) {
        if (sym_table[i].active && sym_table[i].scope == current_scope && strcmp(sym_table[i].name, name) == 0) {
            return &sym_table[i];
        }
    }
    return NULL;
}

/* Busca do escopo mais interno ate o global */
Symbol* lookup_symbol(const char *name) {
    for (int i = sym_count - 1; i >= 0; i--) {
        if (sym_table[i].active && strcmp(sym_table[i].name, name) == 0) {
            return &sym_table[i];
        }
    }
    return NULL;
}

Symbol* insert_symbol(const char *name, SymbolKind kind, DataType type, int line, int col) {
    if (lookup_current_scope(name) != NULL) {
        erro_semantico(line, col, "declaracao duplicada de '%s' no mesmo escopo", name);
        return NULL;
    }
    if (sym_count >= MAX_SYMBOLS) {
        fprintf(stderr, "Erro fatal: limite da tabela de simbolos atingido.\n");
        exit(1);
    }
    Symbol *s = &sym_table[sym_count++];
    s->name = strdup(name);
    s->kind = kind;
    s->type = type;
    s->scope = current_scope;
    s->active = 1;
    s->line = line;
    s->param_count = 0;
    return s;
}

int is_numeric(DataType t) {
    return (t == TYPE_INT || t == TYPE_FLOAT);
}

/* Verifica se 'rhs' pode ser atribuido a 'lhs' */
int is_assignable(DataType lhs, DataType rhs) {
    if (lhs == TYPE_ERROR || rhs == TYPE_ERROR) return 1;
    if (lhs == rhs) return 1;
    if (lhs == TYPE_FLOAT && rhs == TYPE_INT) return 1; /* promocao int -> float */
    return 0;
}

void print_symbol_table(void) {
    printf("\n=== TABELA DE SIMBOLOS ===\n");
    printf("%-20s | %-8s | %-8s | %-6s | %-5s | %s\n",
           "Identificador", "Categ.", "Tipo", "Escopo", "Linha", "Parametros");
    printf("----------------------------------------------------------------------------\n");
    for (int i = 0; i < sym_count; i++) {
        Symbol *s = &sym_table[i];
        printf("%-20s | %-8s | %-8s | %-6d | %-5d | ",
               s->name, kind_name(s->kind), type_name(s->type), s->scope, s->line);
        if (s->kind == SYM_FUNC) {
            if (s->param_count == 0) {
                printf("(void)");
            } else {
                printf("(");
                for (int p = 0; p < s->param_count; p++) {
                    printf("%s%s", type_name(s->param_types[p]),
                           (p + 1 < s->param_count) ? ", " : "");
                }
                printf(")");
            }
        } else {
            printf("-");
        }
        printf("\n");
    }
}

// 2. QUADRUPLAS, TEMPORARIOS E ROTULOS (CODIGO DE TRES ENDERECOS)
#define MAX_QUADS 10000

typedef struct {
    char *op;
    char *arg1;
    char *arg2;
    char *result;
} Quadrupla;

Quadrupla quads[MAX_QUADS];
int quad_count = 0;

static int temp_count = 0;
static int label_count = 0;

char* new_temp(void) {
    char *temp_name = (char *)malloc(16);
    snprintf(temp_name, 16, "_temp%d", temp_count++);
    return temp_name;
}

char* new_label(void) {
    char *lbl = (char *)malloc(16);
    snprintf(lbl, 16, "L%d", label_count++);
    return lbl;
}

void emit_quad(const char *op, const char *arg1, const char *arg2, const char *result) {
    if (quad_count >= MAX_QUADS) return;
    quads[quad_count].op     = strdup(op ? op : "");
    quads[quad_count].arg1   = strdup(arg1 ? arg1 : "");
    quads[quad_count].arg2   = strdup(arg2 ? arg2 : "");
    quads[quad_count].result = strdup(result ? result : "");
    quad_count++;
}

/* Pilhas de controle para BREAK e SWITCH aninhados */
char *break_stack[100];
int break_top = -1;

void push_break(char *lbl) { 
    break_stack[++break_top] = lbl; 
}
void pop_break(void) { 
    if(break_top >= 0) break_top--; 
}
char* current_break(void) { 
    return (break_top >= 0) ? break_stack[break_top] : NULL; 
}

typedef struct {
    DataType expr_type;
    char *expr_addr;
    char *l_end;
    char *l_next_test;
} SwitchCtx;

SwitchCtx switch_stack[50];
int switch_top = -1;

/* Auxiliares de geracao e verificacao de expressoes */
ExprAttr gen_arith(const char *op, ExprAttr e1, ExprAttr e2, int line, int col) {
    ExprAttr res = { TYPE_ERROR, strdup("_err") };
    if (e1.type == TYPE_ERROR || e2.type == TYPE_ERROR) return res;

    if (!is_numeric(e1.type) || !is_numeric(e2.type)) {
        erro_semantico(line, col, "operador '%s' incompativel com tipos '%s' e '%s'",
                       op, type_name(e1.type), type_name(e2.type));
        return res;
    }
    res.type = (e1.type == TYPE_FLOAT || e2.type == TYPE_FLOAT) ? TYPE_FLOAT : TYPE_INT;
    res.addr = new_temp();
    emit_quad(op, e1.addr, e2.addr, res.addr);
    return res;
}

ExprAttr gen_mod(ExprAttr e1, ExprAttr e2, int line, int col) {
    ExprAttr res = { TYPE_ERROR, strdup("_err") };
    if (e1.type == TYPE_ERROR || e2.type == TYPE_ERROR) return res;

    if (e1.type != TYPE_INT || e2.type != TYPE_INT) {
        erro_semantico(l
            ine, col, "operador '%%' exige operandos inteiros (recebeu '%s' e '%s')",
            type_name(e1.type), type_name(e2.type)
        );

        return res;
    }
    res.type = TYPE_INT;
    res.addr = new_temp();
    emit_quad("%", e1.addr, e2.addr, res.addr);
    return res;
}

ExprAttr gen_rel(const char *op, ExprAttr e1, ExprAttr e2, int line, int col) {
    ExprAttr res = { TYPE_ERROR, strdup("_err") };
    if (e1.type == TYPE_ERROR || e2.type == TYPE_ERROR) return res;

    if (!is_numeric(e1.type) || !is_numeric(e2.type)) {
        erro_semantico(line, col, "comparacao '%s' exige operandos numericos (recebeu '%s' e '%s')",
                       op, type_name(e1.type), type_name(e2.type));
        return res;
    }
    res.type = TYPE_INT;
    res.addr = new_temp();
    emit_quad(op, e1.addr, e2.addr, res.addr);
    return res;
}

ExprAttr gen_eq(const char *op, ExprAttr e1, ExprAttr e2, int line, int col) {
    ExprAttr res = { TYPE_ERROR, strdup("_err") };
    if (e1.type == TYPE_ERROR || e2.type == TYPE_ERROR) return res;

    int ok = (is_numeric(e1.type) && is_numeric(e2.type)) ||
             (e1.type == TYPE_STRING && e2.type == TYPE_STRING);
    if (!ok) {
        erro_semantico(line, col, "operador '%s' incompativel entre '%s' e '%s'",
                       op, type_name(e1.type), type_name(e2.type));
        return res;
    }
    res.type = TYPE_INT;
    res.addr = new_temp();
    emit_quad(op, e1.addr, e2.addr, res.addr);
    return res;
}

ExprAttr gen_logic(const char *op, ExprAttr e1, ExprAttr e2, int line, int col) {
    ExprAttr res = { TYPE_ERROR, strdup("_err") };
    if (e1.type == TYPE_ERROR || e2.type == TYPE_ERROR) return res;

    if (e1.type != TYPE_INT || e2.type != TYPE_INT) {
        erro_semantico(line, col, "operador logico '%s' exige expressoes booleanas/inteiras", op);
        return res;
    }
    res.type = TYPE_INT;
    res.addr = new_temp();
    emit_quad(op, e1.addr, e2.addr, res.addr);
    return res;
}

void print_quadruples(void) {
    printf("\n=== REPRESENTACAO INTERNA: QUADRUPLAS ===\n");
    printf("%-4s | %-12s | %-15s | %-15s | %-15s\n",
           "No", "op", "arg1", "arg2", "result");
    printf("------------------------------------------------------------------------\n");
    for (int i = 0; i < quad_count; i++) {
        printf("%-4d | %-12s | %-15s | %-15s | %-15s\n",
               i, quads[i].op, quads[i].arg1, quads[i].arg2, quads[i].result);
    }
}

void print_tac_code(void) {
    printf("\n=== CODIGO INTERMEDIARIO DE TRES ENDERECOS ===\n");
    for (int i = 0; i < quad_count; i++) {
        Quadrupla q = quads[i];
        if (strcmp(q.op, "func_begin") == 0) {
            printf("\n%s:\n", q.result);
        } else if (strcmp(q.op, "func_end") == 0) {
            printf("end %s\n", q.result);
        } else if (strcmp(q.op, "formal_param") == 0) {
            printf("    formal_param %s\n", q.result);
        } else if (strcmp(q.op, "label") == 0) {
            printf("%s:\n", q.result);
        } else if (strcmp(q.op, "goto") == 0) {
            printf("    goto %s\n", q.result);
        } else if (strcmp(q.op, "ifFalse") == 0) {
            printf("    ifFalse %s goto %s\n", q.arg1, q.result);
        } else if (strcmp(q.op, "if_neq") == 0) {
            printf("    if %s != %s goto %s\n", q.arg1, q.arg2, q.result);
        } else if (strcmp(q.op, "param") == 0) {
            printf("    param %s\n", q.arg1);
        } else if (strcmp(q.op, "call") == 0) {
            if (strlen(q.result) > 0)
                printf("    %s = call %s, %s\n", q.result, q.arg1, q.arg2);
            else
                printf("    call %s, %s\n", q.arg1, q.arg2);
        } else if (strcmp(q.op, "return") == 0) {
            if (strlen(q.arg1) > 0)
                printf("    return %s\n", q.arg1);
            else
                printf("    return\n");
        } else if (strcmp(q.op, "=") == 0) {
            printf("    %s = %s\n", q.result, q.arg1);
        } else if (strcmp(q.op, "uminus") == 0) {
            printf("    %s = -%s\n", q.result, q.arg1);
        } else if (strcmp(q.op, "!") == 0) {
            printf("    %s = !%s\n", q.result, q.arg1);
        } else {
            printf("    %s = %s %s %s\n", q.result, q.arg1, q.op, q.arg2);
        }
    }
}
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
            insert_symbol($2, SYM_GLOBAL, $1, @2.first_line, @2.first_column);
        }
    ;

tipo:
    INT { $$ = TYPE_INT; }
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
            Symbol *fn = insert_symbol($2, SYM_FUNC, $1, @2.first_line, @2.first_column);
            current_func = fn;
            enter_scope();
            emit_quad("func_begin", "", "", $2);
        }
    parametros ')'
        {
            in_func_header = 1;
        }
    bloco
        {
            emit_quad("func_end", "", "", $2);
            exit_scope();
            current_func = NULL;
        }
    | INT MAIN '(' ')'
        {
            Symbol *fn = insert_symbol("main", SYM_FUNC, TYPE_INT, @2.first_line, @2.first_column);
            current_func = fn;
            enter_scope();
            in_func_header = 1;
            emit_quad("func_begin", "", "", "main");
        }
    bloco
        {
            emit_quad("func_end", "", "", "main");
            exit_scope();
            current_func = NULL;
        }
    | tipo_retorno LOCAL_ID
        {
            erro_em(@2.first_line, @2.first_column, "nome de funcao invalido: use verbo + Termo (ex.: calcularSoma)");
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
            insert_symbol($2, SYM_PARAM, $1, @2.first_line, @2.first_column);
            if (current_func != NULL && current_func->param_count < MAX_PARAMS) {
                current_func->param_types[current_func->param_count++] = $1;
            }
            emit_quad("formal_param", "", "", $2);
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
            char *target = current_break();
            if (target) {
                emit_quad("goto", "", "", target);
            } else {
                erro_semantico(@1.first_line, @1.first_column,
                               "comando 'break' fora de laco ou switch");
            }
        }
    | retorno ';'
    | chamada_funcao ';'
    | bloco
    | error ';'
    ;

var_local_decl:
    tipo LOCAL_ID ';'
        {
            insert_symbol($2, SYM_LOCAL, $1, @2.first_line, @2.first_column);
        }
    ;

declaracao_init:
    tipo LOCAL_ID '=' expressao
        {
            insert_symbol($2, SYM_LOCAL, $1, @2.first_line, @2.first_column);
            if (!is_assignable($1, $4.type)) {
                erro_semantico(@3.first_line, @3.first_column,
                               "tipo incompativel na inicializacao de '%s': esperado '%s', recebido '%s'",
                               $2, type_name($1), type_name($4.type));
            }
            emit_quad("=", $4.addr, "", $2);
        }
    ;

atribuicao:
    LOCAL_ID '=' expressao
        {
            Symbol *sym = lookup_symbol($1);
            if (!sym) {
                erro_semantico(@1.first_line, @1.first_column, "variavel local '%s' nao declarada", $1);
            } else if (sym->kind == SYM_FUNC) {
                erro_semantico(@1.first_line, @1.first_column, "'%s' e uma funcao e nao pode receber atribuicao", $1);
            } else if (!is_assignable(sym->type, $3.type)) {
                erro_semantico(
                    @2.first_line, 
                    @2.first_column, 
                    "atribuicao incompativel para '%s': esperado '%s', recebido '%s'",
                    $1, 
                    type_name(sym->type), type_name($3.type)
                );
            }
            emit_quad("=", $3.addr, "", $1);
        }
    | GLOBAL_ID '=' expressao
        {
            Symbol *sym = lookup_symbol($1);
            if (!sym) {
                erro_semantico(@1.first_line, @1.first_column, "variavel global '%s' nao declarada", $1);
            } else if (!is_assignable(sym->type, $3.type)) {
                erro_semantico(
                    @2.first_line, 
                    @2.first_column,
                    "atribuicao incompativel para '%s': esperado '%s', recebido '%s'",
                    $1, 
                    type_name(sym->type), type_name($3.type)
                );
            }
            emit_quad("=", $3.addr, "", $1);
        }
    ;

if_prefix:
    IF '(' expressao ')'
        {
            if ($3.type != TYPE_ERROR && $3.type != TYPE_INT) {
                erro_semantico(
                    @3.first_line, 
                    @3.first_column,
                    "condicao do 'if' deve ser booleana/inteira (recebeu '%s')",
                    type_name($3.type)
                );
            }
            char *l_false = new_label();
            emit_quad("ifFalse", $3.addr, "", l_false);
            $$ = l_false;
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
            if ($4.type != TYPE_ERROR && $4.type != TYPE_INT) {
                erro_semantico(
                    @4.first_line, 
                    @4.first_column,
                    "condicao do 'while' deve ser booleana/inteira (recebeu '%s')",
                    type_name($4.type)
                );
            }
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
            if ($6.addr != NULL && $6.type != TYPE_ERROR && $6.type != TYPE_INT) {
                erro_semantico(
                    @6.first_line, 
                    @6.first_column,
                    "condicao do 'for' deve ser booleana/inteira (recebeu '%s')",
                    type_name($6.type)
                );
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
            if ($3.type != TYPE_ERROR && $3.type != TYPE_INT && $3.type != TYPE_STRING) {
                erro_semantico(
                    @3.first_line, 
                    @3.first_column,
                    "expressao do 'switch' deve ser 'int' ou 'string' (recebeu '%s')",
                    type_name($3.type)
                );
            }
            switch_top++;
            switch_stack[switch_top].expr_type   = $3.type;
            switch_stack[switch_top].expr_addr   = $3.addr;
            switch_stack[switch_top].l_end       = new_label();
            switch_stack[switch_top].l_next_test = new_label();
            emit_quad("goto", "", "", switch_stack[switch_top].l_next_test);
            push_break(switch_stack[switch_top].l_end);
        }
    '{' cases '}'
        {
            if (switch_stack[switch_top].l_next_test != NULL) {
                emit_quad("label", "", "", switch_stack[switch_top].l_next_test);
            }
            emit_quad("label", "", "", switch_stack[switch_top].l_end);
            pop_break();
            switch_top--;
        }
    ;

cases:
    cases case_stmt
    | /* vazio */
    ;

case_stmt:
    CASE case_value ':'
        {
            DataType sw_t = switch_stack[switch_top].expr_type;
            if (sw_t != TYPE_ERROR && $2.type != sw_t) {
                erro_semantico(@2.first_line, @2.first_column,
                               "tipo do 'case' (%s) incompativel com o 'switch' (%s)",
                               type_name($2.type), type_name(sw_t));
            }
            char *l_body = new_label();
            emit_quad("goto", "", "", l_body);
            emit_quad("label", "", "", switch_stack[switch_top].l_next_test);
            char *l_next = new_label();
            switch_stack[switch_top].l_next_test = l_next;
            emit_quad("if_neq", switch_stack[switch_top].expr_addr, $2.addr, l_next);
            emit_quad("label", "", "", l_body);
        }
    comandos
    | DEFAULT ':'
        {
            char *l_body = new_label();
            emit_quad("goto", "", "", l_body);
            if (switch_stack[switch_top].l_next_test != NULL) {
                emit_quad("label", "", "", switch_stack[switch_top].l_next_test);
                switch_stack[switch_top].l_next_test = NULL;
            }
            emit_quad("label", "", "", l_body);
        }
    comandos
    ;

case_value:
    INT_LIT
        {
            char buf[32];
            snprintf(buf, sizeof(buf), "%d", $1);
            $$.type = TYPE_INT;
            $$.addr = strdup(buf);
        }
    | '-' INT_LIT
        {
            char buf[32];
            snprintf(buf, sizeof(buf), "-%d", $2);
            $$.type = TYPE_INT;
            $$.addr = strdup(buf);
        }
    | STRING_LIT
        {
            $$.type = TYPE_STRING;
            $$.addr = $1;
        }
    ;

retorno:
    RETURN expressao
        {
            if (current_func != NULL) {
                if (current_func->type == TYPE_VOID) {
                    erro_semantico(
                        @1.first_line, 
                        @1.first_column,
                        "funcao void '%s' nao deve retornar valor", 
                        current_func->name
                    );
                } else if (!is_assignable(current_func->type, $2.type)) {
                    erro_semantico(
                        @2.first_line, 
                        @2.first_column,
                        "tipo de retorno incompativel em '%s': esperado '%s', recebido '%s'",
                        current_func->name, type_name(current_func->type), 
                        type_name($2.type)
                    );
                }
            }
            emit_quad("return", $2.addr, "", "");
        }
    | RETURN
        {
            if (current_func != NULL && current_func->type != TYPE_VOID) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "funcao '%s' deve retornar um valor do tipo '%s'",
                    current_func->name, type_name(current_func->type)
                );
            }
            emit_quad("return", "", "", "");
        }
    ;

chamada_funcao:
    FUNC_ID '(' argumentos ')'
        {
            Symbol *fn = lookup_symbol($1);
            char argc_buf[16];
            snprintf(argc_buf, sizeof(argc_buf), "%d", $3.count);

            if (!fn) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "funcao '%s' nao declarada", 
                    $1
                );
                $$.type = TYPE_ERROR;
                $$.addr = strdup("_err");
            } else if (fn->kind != SYM_FUNC) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "'%s' nao e uma funcao", 
                    $1
                );
                $$.type = TYPE_ERROR;
                $$.addr = strdup("_err");
            } else {
                if ($3.count != fn->param_count) {
                    erro_semantico(
                        @1.first_line, 
                        @1.first_column,
                        "numero incorreto de argumentos para '%s': esperado %d, recebido %d",
                        $1, 
                        fn->param_count, 
                        $3.count
                    );
                } else {
                    for (int i = 0; i < $3.count; i++) {
                        if (!is_assignable(fn->param_types[i], $3.types[i])) {
                            erro_semantico(
                                @3.first_line, 
                                @3.first_column,
                                "argumento %d de '%s' incompativel: esperado '%s', recebido '%s'",
                                i + 1, 
                                $1, 
                                type_name(fn->param_types[i]), 
                                type_name($3.types[i])
                            );
                        }
                    }
                }
                $$.type = fn->type;
                if (fn->type == TYPE_VOID) {
                    $$.addr = strdup("");
                    emit_quad("call", $1, argc_buf, "");
                } else {
                    $$.addr = new_temp();
                    emit_quad("call", $1, argc_buf, $$.addr);
                }
            }
        }
    ;

argumentos:
    arg_lista     { $$ = $1; }
    | /* vazio */ { $$.count = 0; }
    ;

arg_lista:
    expressao
        {
            $$.count = 0;
            $$.types[$$.count++] = $1.type;
            emit_quad("param", $1.addr, "", "");
        }
    | arg_lista ',' expressao
        {
            $$ = $1;
            if ($$.count < 32) {
                $$.types[$$.count++] = $3.type;
            }
            emit_quad("param", $3.addr, "", "");
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
    | '-' expressao %prec UMINUS
        {
            if ($2.type != TYPE_ERROR && !is_numeric($2.type)) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "operador unario '-' incompativel com tipo '%s'", 
                    type_name($2.type)
                );
                $$.type = TYPE_ERROR;
                $$.addr = strdup("_err");
            } else {
                $$.type = $2.type;
                $$.addr = new_temp();
                emit_quad("uminus", $2.addr, "", $$.addr);
            }
        }
    | '!' expressao
        {
            if ($2.type != TYPE_ERROR && $2.type != TYPE_INT) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "operador '!' exige expressao booleana/inteira (recebeu '%s')",
                    type_name($2.type)
                );
                $$.type = TYPE_ERROR;
                $$.addr = strdup("_err");
            } else {
                $$.type = TYPE_INT;
                $$.addr = new_temp();
                emit_quad("!", $2.addr, "", $$.addr);
            }
        }
    | '(' expressao ')'
        {
            $$ = $2;
        }
    | LOCAL_ID
        {
            Symbol *sym = lookup_symbol($1);
            if (!sym) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "variavel local '%s' nao declarada", 
                    $1
                );
                $$.type = TYPE_ERROR;
            } else if (sym->kind == SYM_FUNC) {
                erro_semantico
                    (@1.first_line,
                    @1.first_column,
                    "funcao '%s' usada sem parenteses", 
                    $1
                );
                $$.type = TYPE_ERROR;
            } else {
                $$.type = sym->type;
            }
            $$.addr = $1;
        }
    | GLOBAL_ID
        {
            Symbol *sym = lookup_symbol($1);
            if (!sym) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "variavel global '%s' nao declarada", 
                    $1
                );
                $$.type = TYPE_ERROR;
            } else {
                $$.type = sym->type;
            }
            $$.addr = $1;
        }
    | INT_LIT
        {
            char buf[32];
            snprintf(buf, sizeof(buf), "%d", $1);
            $$.type = TYPE_INT;
            $$.addr = strdup(buf);
        }
    | FLOAT_LIT
        {
            char buf[32];
            snprintf(buf, sizeof(buf), "%g", $1);
            $$.type = TYPE_FLOAT;
            $$.addr = strdup(buf);
        }
    | STRING_LIT
        {
            $$.type = TYPE_STRING;
            $$.addr = $1;
        }
    | chamada_funcao
        {
            if ($1.type == TYPE_VOID) {
                erro_semantico(
                    @1.first_line, 
                    @1.first_column,
                    "funcao com retorno 'void' nao pode ser usada em expressao"
                );
                $$.type = TYPE_ERROR;
                $$.addr = strdup("_err");
            } else {
                $$ = $1;
            }
        }
    ;

%%

void erro_em(int l, int c, const char *msg) {
    fprintf(stderr, "Erro sintatico (linha %d, coluna %d): %s\n", l, c, msg);
    syn_errors++;
    syn_suprimido = 0;
}

void erro_semantico(int l, int c, const char *fmt, ...) {
    va_list args;
    fprintf(stderr, "Erro semantico (linha %d, coluna %d): ", l, c);
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fprintf(stderr, "\n");
    sem_errors++;
}

void yyerror(const char *s) {
    if (lex_unclosed_comment || token_line == last_lex_error_line) {
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
    int restante = 0;
    if (rc != 0) {
        while (yylex() != 0) restante++;
    }

    if (lex_errors == 0 && syn_errors == 0 && sem_errors == 0) {
        printf("Analise lexica concluida.\n");
        printf("Analise sintatica concluida.\n");
        printf("Analise semantica concluida.\n");
        printf("Programa reconhecido com sucesso.\n");

        print_symbol_table();
        print_quadruples();
        print_tac_code();
    } else {
        printf("\nForam encontrados %d erro(s) lexico(s), %d erro(s) sintatico(s) e %d erro(s) semantico(s).\n",
               lex_errors, syn_errors, sem_errors);
        if (rc != 0 && syn_suprimido && restante > 0)
            printf("Analise sintatica interrompida por erro lexico: corrija os erros lexicos e execute de novo para verificar o resto do programa (restaram: %d tokens)\n", restante);
    }

    if (yyin && yyin != stdin) fclose(yyin);
    return (lex_errors || syn_errors || sem_errors) ? 1 : 0;
}