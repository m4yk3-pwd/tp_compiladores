#ifndef UTILS_TYPES_H
#define UTILS_TYPES_H

/*
 * Shared value types used by the parser's semantic value stack (%union) and by
 * every helper module. This header is pulled into the generated parser through
 * `%code requires`, so it must stay free of any dependency on the Bison output.
 */

#define MAX_ARGS 32

/* Data types handled by the language's type system. */
typedef enum {
    TYPE_INT,
    TYPE_FLOAT,
    TYPE_STRING,
    TYPE_VOID,
    TYPE_ERROR
} DataType;

/* Synthesized attributes of an expression: its type and its address/operand. */
typedef struct {
    DataType type;
    char *addr;
} ExprAttr;

/* Collected argument types of a function call, in source order. */
typedef struct {
    DataType types[MAX_ARGS];
    int count;
} ArgList;

#endif /* UTILS_TYPES_H */
