#ifndef UTILS_SEMANTIC_ACTIONS_H
#define UTILS_SEMANTIC_ACTIONS_H

#include "utils/types.h"

/*
 * Semantic actions: the bridge between the grammar rules and the lower-level
 * modules (symbol table, type system, TAC generator). Each function performs
 * the semantic checks and code generation for one grammar construct, keeping
 * the grammar actions in parser.y down to a single call.
 */

/* --- Declarations ------------------------------------------------------ */
void declare_global(const char *name, DataType type, int line, int col);
void declare_local(const char *name, DataType type, int line, int col);
void declare_param(const char *name, DataType type, int line, int col);
void declare_init(const char *name, DataType type, ExprAttr value,
                  int name_line, int name_col, int assign_line, int assign_col);

/* --- Functions --------------------------------------------------------- */
void begin_function(const char *name, DataType return_type, int line, int col);
void end_function(const char *name);
void begin_main(int line, int col);
void end_main(void);

/* --- Assignments ------------------------------------------------------- */
void assign_local(const char *name, ExprAttr value,
                  int name_line, int name_col, int op_line, int op_col);
void assign_global(const char *name, ExprAttr value,
                   int name_line, int name_col, int op_line, int op_col);

/* --- Control flow ------------------------------------------------------ */
char *begin_if(ExprAttr cond, int line, int col);
void check_condition(ExprAttr cond, const char *context, int line, int col);
void emit_break(int line, int col);

void switch_begin(ExprAttr selector, int line, int col);
void switch_case(ExprAttr case_value, int line, int col);
void switch_default(void);
void switch_end(void);

/* --- Return ------------------------------------------------------------ */
void check_return_value(ExprAttr value, int ret_line, int ret_col,
                        int expr_line, int expr_col);
void check_return_void(int line, int col);

/* --- Expressions ------------------------------------------------------- */
ExprAttr load_variable(char *name, int is_global, int line, int col);
ExprAttr make_int_lit(int value);
ExprAttr make_float_lit(float value);
ExprAttr make_string_lit(char *literal);
ExprAttr check_call_in_expr(ExprAttr call, int line, int col);

/* --- Function calls ---------------------------------------------------- */
ExprAttr check_and_emit_call(const char *name, ArgList args,
                             int name_line, int name_col,
                             int args_line, int args_col);
ArgList arg_list_empty(void);
ArgList arg_list_add(ArgList list, ExprAttr arg);

#endif /* UTILS_SEMANTIC_ACTIONS_H */
