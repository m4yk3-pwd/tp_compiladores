#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "utils/tac.h"

Quad quads[MAX_QUADS];
int quad_count = 0;

static int temp_count = 0;
static int label_count = 0;

char *new_temp(void) {
    char *temp_name = (char *)malloc(16);
    snprintf(temp_name, 16, "_temp%d", temp_count++);
    return temp_name;
}

char *new_label(void) {
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

/* --- Control-flow label stacks ----------------------------------------- */

char *break_stack[100];
int break_top = -1;

void push_break(char *label) {
    break_stack[++break_top] = label;
}

void pop_break(void) {
    if (break_top >= 0) break_top--;
}

char *current_break(void) {
    return (break_top >= 0) ? break_stack[break_top] : NULL;
}

SwitchCtx switch_stack[50];
int switch_top = -1;

/* --- Output ------------------------------------------------------------ */

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
        Quad q = quads[i];
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
