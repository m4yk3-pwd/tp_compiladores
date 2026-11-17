#ifndef UTILS_SYMBOL_TABLE_H
#define UTILS_SYMBOL_TABLE_H

#include "utils/types.h"

#define MAX_SYMBOLS 1000
#define MAX_PARAMS  32

/* Category of a symbol in the table. */
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

/* Symbol table storage and the current scope cursor. */
extern Symbol sym_table[MAX_SYMBOLS];
extern int sym_count;
extern int current_scope;

/* Parsing context shared with the grammar actions. */
extern int in_func_header;       /* next '{' opens a function body, not a new scope */
extern Symbol *current_func;     /* function currently being parsed (for return checks) */

/* Human-readable name of a symbol category. */
const char *kind_name(SymbolKind k);

/* Scope management. */
void enter_scope(void);
void exit_scope(void);

/* Looks a name up only in the current scope (detects redeclaration). */
Symbol *lookup_current_scope(const char *name);

/* Looks a name up from the innermost scope outward to the global scope. */
Symbol *lookup_symbol(const char *name);

/* Inserts a symbol in the current scope; reports a semantic error and returns
 * NULL on a duplicate declaration. */
Symbol *insert_symbol(const char *name, SymbolKind kind, DataType type, int line, int col);

/* Prints the full symbol table to stdout. */
void print_symbol_table(void);

#endif /* UTILS_SYMBOL_TABLE_H */
