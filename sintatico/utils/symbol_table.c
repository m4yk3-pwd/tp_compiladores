#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "utils/symbol_table.h"
#include "utils/type_system.h"
#include "utils/errors.h"

Symbol sym_table[MAX_SYMBOLS];
int sym_count = 0;
int current_scope = 0;
int in_func_header = 0;
Symbol *current_func = NULL;

const char *kind_name(SymbolKind k) {
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

Symbol *lookup_current_scope(const char *name) {
    for (int i = sym_count - 1; i >= 0; i--) {
        if (sym_table[i].active && sym_table[i].scope == current_scope &&
            strcmp(sym_table[i].name, name) == 0) {
            return &sym_table[i];
        }
    }
    return NULL;
}

Symbol *lookup_symbol(const char *name) {
    for (int i = sym_count - 1; i >= 0; i--) {
        if (sym_table[i].active && strcmp(sym_table[i].name, name) == 0) {
            return &sym_table[i];
        }
    }
    return NULL;
}

Symbol *insert_symbol(const char *name, SymbolKind kind, DataType type, int line, int col) {
    (void)col; /* position kept for a uniform call signature */
    if (lookup_current_scope(name) != NULL) {
        report_semantic_error(line, col, "declaracao duplicada de '%s' no mesmo escopo", name);
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
