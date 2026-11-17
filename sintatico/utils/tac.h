#ifndef UTILS_TAC_H
#define UTILS_TAC_H

#include "utils/types.h"

/*
 * Three-address code (TAC) generation: quadruples, fresh temporaries/labels,
 * and the control-flow label stacks used by `break`, loops and `switch`.
 */

#define MAX_QUADS 10000

typedef struct {
    char *op;
    char *arg1;
    char *arg2;
    char *result;
} Quad;

extern Quad quads[MAX_QUADS];
extern int quad_count;

/* Fresh temporary / label name generators (heap-allocated). */
char *new_temp(void);
char *new_label(void);

/* Appends a quadruple (NULL fields are stored as empty strings). */
void emit_quad(const char *op, const char *arg1, const char *arg2, const char *result);

/* Stack of break targets for nested loops and switches. */
void push_break(char *label);
void pop_break(void);
char *current_break(void);

/* Per-switch code-generation context. */
typedef struct {
    DataType expr_type;
    char *expr_addr;
    char *l_end;
    char *l_next_test;
} SwitchCtx;

extern SwitchCtx switch_stack[50];
extern int switch_top;

/* Dumps the generated code. */
void print_quadruples(void);
void print_tac_code(void);

#endif /* UTILS_TAC_H */
