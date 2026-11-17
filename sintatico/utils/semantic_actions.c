#include <stdio.h>
#include <string.h>

#include "utils/semantic_actions.h"
#include "utils/symbol_table.h"
#include "utils/type_system.h"
#include "utils/tac.h"
#include "utils/errors.h"

/* ======================================================================= */
/* Declarations                                                            */
/* ======================================================================= */

void declare_global(const char *name, DataType type, int line, int col) {
    insert_symbol(name, SYM_GLOBAL, type, line, col);
}

void declare_local(const char *name, DataType type, int line, int col) {
    insert_symbol(name, SYM_LOCAL, type, line, col);
}

void declare_param(const char *name, DataType type, int line, int col) {
    insert_symbol(name, SYM_PARAM, type, line, col);
    if (current_func != NULL && current_func->param_count < MAX_PARAMS) {
        current_func->param_types[current_func->param_count++] = type;
    }
    emit_quad("formal_param", "", "", name);
}

void declare_init(const char *name, DataType type, ExprAttr value,
                  int name_line, int name_col, int assign_line, int assign_col) {
    insert_symbol(name, SYM_LOCAL, type, name_line, name_col);
    if (!is_assignable(type, value.type)) {
        report_semantic_error(assign_line, assign_col,
                              "tipo incompativel na inicializacao de '%s': esperado '%s', recebido '%s'",
                              name, type_name(type), type_name(value.type));
    }
    emit_quad("=", value.addr, "", name);
}

/* ======================================================================= */
/* Functions                                                               */
/* ======================================================================= */

void begin_function(const char *name, DataType return_type, int line, int col) {
    Symbol *fn = insert_symbol(name, SYM_FUNC, return_type, line, col);
    current_func = fn;
    enter_scope();
    emit_quad("func_begin", "", "", name);
}

void end_function(const char *name) {
    emit_quad("func_end", "", "", name);
    exit_scope();
    current_func = NULL;
}

void begin_main(int line, int col) {
    Symbol *fn = insert_symbol("main", SYM_FUNC, TYPE_INT, line, col);
    current_func = fn;
    enter_scope();
    in_func_header = 1;
    emit_quad("func_begin", "", "", "main");
}

void end_main(void) {
    emit_quad("func_end", "", "", "main");
    exit_scope();
    current_func = NULL;
}

/* ======================================================================= */
/* Assignments                                                             */
/* ======================================================================= */

void assign_local(const char *name, ExprAttr value,
                  int name_line, int name_col, int op_line, int op_col) {
    Symbol *sym = lookup_symbol(name);
    if (!sym) {
        report_semantic_error(name_line, name_col, "variavel local '%s' nao declarada", name);
    } else if (sym->kind == SYM_FUNC) {
        report_semantic_error(name_line, name_col,
                              "'%s' e uma funcao e nao pode receber atribuicao", name);
    } else if (!is_assignable(sym->type, value.type)) {
        report_semantic_error(op_line, op_col,
                              "atribuicao incompativel para '%s': esperado '%s', recebido '%s'",
                              name, type_name(sym->type), type_name(value.type));
    }
    emit_quad("=", value.addr, "", name);
}

void assign_global(const char *name, ExprAttr value,
                   int name_line, int name_col, int op_line, int op_col) {
    Symbol *sym = lookup_symbol(name);
    if (!sym) {
        report_semantic_error(name_line, name_col, "variavel global '%s' nao declarada", name);
    } else if (!is_assignable(sym->type, value.type)) {
        report_semantic_error(op_line, op_col,
                              "atribuicao incompativel para '%s': esperado '%s', recebido '%s'",
                              name, type_name(sym->type), type_name(value.type));
    }
    emit_quad("=", value.addr, "", name);
}

/* ======================================================================= */
/* Control flow                                                            */
/* ======================================================================= */

char *begin_if(ExprAttr cond, int line, int col) {
    if (cond.type != TYPE_ERROR && cond.type != TYPE_INT) {
        report_semantic_error(line, col,
                              "condicao do 'if' deve ser booleana/inteira (recebeu '%s')",
                              type_name(cond.type));
    }
    char *l_false = new_label();
    emit_quad("ifFalse", cond.addr, "", l_false);
    return l_false;
}

void check_condition(ExprAttr cond, const char *context, int line, int col) {
    if (cond.type != TYPE_ERROR && cond.type != TYPE_INT) {
        report_semantic_error(line, col,
                              "condicao do '%s' deve ser booleana/inteira (recebeu '%s')",
                              context, type_name(cond.type));
    }
}

void emit_break(int line, int col) {
    char *target = current_break();
    if (target) {
        emit_quad("goto", "", "", target);
    } else {
        report_semantic_error(line, col, "comando 'break' fora de laco ou switch");
    }
}

void switch_begin(ExprAttr selector, int line, int col) {
    if (selector.type != TYPE_ERROR && selector.type != TYPE_INT &&
        selector.type != TYPE_STRING) {
        report_semantic_error(line, col,
                              "expressao do 'switch' deve ser 'int' ou 'string' (recebeu '%s')",
                              type_name(selector.type));
    }
    switch_top++;
    switch_stack[switch_top].expr_type   = selector.type;
    switch_stack[switch_top].expr_addr   = selector.addr;
    switch_stack[switch_top].l_end       = new_label();
    switch_stack[switch_top].l_next_test = new_label();
    emit_quad("goto", "", "", switch_stack[switch_top].l_next_test);
    push_break(switch_stack[switch_top].l_end);
}

void switch_case(ExprAttr case_value, int line, int col) {
    DataType sw_t = switch_stack[switch_top].expr_type;
    if (sw_t != TYPE_ERROR && case_value.type != sw_t) {
        report_semantic_error(line, col,
                              "tipo do 'case' (%s) incompativel com o 'switch' (%s)",
                              type_name(case_value.type), type_name(sw_t));
    }
    char *l_body = new_label();
    emit_quad("goto", "", "", l_body);
    emit_quad("label", "", "", switch_stack[switch_top].l_next_test);
    char *l_next = new_label();
    switch_stack[switch_top].l_next_test = l_next;
    emit_quad("if_neq", switch_stack[switch_top].expr_addr, case_value.addr, l_next);
    emit_quad("label", "", "", l_body);
}

void switch_default(void) {
    char *l_body = new_label();
    emit_quad("goto", "", "", l_body);
    if (switch_stack[switch_top].l_next_test != NULL) {
        emit_quad("label", "", "", switch_stack[switch_top].l_next_test);
        switch_stack[switch_top].l_next_test = NULL;
    }
    emit_quad("label", "", "", l_body);
}

void switch_end(void) {
    if (switch_stack[switch_top].l_next_test != NULL) {
        emit_quad("label", "", "", switch_stack[switch_top].l_next_test);
    }
    emit_quad("label", "", "", switch_stack[switch_top].l_end);
    pop_break();
    switch_top--;
}

/* ======================================================================= */
/* Return                                                                  */
/* ======================================================================= */

void check_return_value(ExprAttr value, int ret_line, int ret_col,
                        int expr_line, int expr_col) {
    if (current_func != NULL) {
        if (current_func->type == TYPE_VOID) {
            report_semantic_error(ret_line, ret_col,
                                  "funcao void '%s' nao deve retornar valor", current_func->name);
        } else if (!is_assignable(current_func->type, value.type)) {
            report_semantic_error(expr_line, expr_col,
                                  "tipo de retorno incompativel em '%s': esperado '%s', recebido '%s'",
                                  current_func->name, type_name(current_func->type),
                                  type_name(value.type));
        }
    }
    emit_quad("return", value.addr, "", "");
}

void check_return_void(int line, int col) {
    if (current_func != NULL && current_func->type != TYPE_VOID) {
        report_semantic_error(line, col,
                              "funcao '%s' deve retornar um valor do tipo '%s'",
                              current_func->name, type_name(current_func->type));
    }
    emit_quad("return", "", "", "");
}

/* ======================================================================= */
/* Expressions                                                             */
/* ======================================================================= */

ExprAttr load_variable(char *name, int is_global, int line, int col) {
    ExprAttr e;
    Symbol *sym = lookup_symbol(name);
    if (!sym) {
        report_semantic_error(line, col, "variavel %s '%s' nao declarada",
                              is_global ? "global" : "local", name);
        e.type = TYPE_ERROR;
    } else if (!is_global && sym->kind == SYM_FUNC) {
        report_semantic_error(line, col, "funcao '%s' usada sem parenteses", name);
        e.type = TYPE_ERROR;
    } else {
        e.type = sym->type;
    }
    e.addr = name;
    return e;
}

ExprAttr make_int_lit(int value) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%d", value);
    ExprAttr e = { TYPE_INT, strdup(buf) };
    return e;
}

ExprAttr make_float_lit(float value) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%g", value);
    ExprAttr e = { TYPE_FLOAT, strdup(buf) };
    return e;
}

ExprAttr make_string_lit(char *literal) {
    ExprAttr e = { TYPE_STRING, literal };
    return e;
}

ExprAttr check_call_in_expr(ExprAttr call, int line, int col) {
    if (call.type == TYPE_VOID) {
        report_semantic_error(line, col,
                              "funcao com retorno 'void' nao pode ser usada em expressao");
        ExprAttr e = { TYPE_ERROR, strdup("_err") };
        return e;
    }
    return call;
}

/* ======================================================================= */
/* Function calls                                                          */
/* ======================================================================= */

ExprAttr check_and_emit_call(const char *name, ArgList args,
                             int name_line, int name_col,
                             int args_line, int args_col) {
    ExprAttr result;
    Symbol *fn = lookup_symbol(name);
    char argc_buf[16];
    snprintf(argc_buf, sizeof(argc_buf), "%d", args.count);

    if (!fn) {
        report_semantic_error(name_line, name_col, "funcao '%s' nao declarada", name);
        result.type = TYPE_ERROR;
        result.addr = strdup("_err");
    } else if (fn->kind != SYM_FUNC) {
        report_semantic_error(name_line, name_col, "'%s' nao e uma funcao", name);
        result.type = TYPE_ERROR;
        result.addr = strdup("_err");
    } else {
        if (args.count != fn->param_count) {
            report_semantic_error(name_line, name_col,
                                  "numero incorreto de argumentos para '%s': esperado %d, recebido %d",
                                  name, fn->param_count, args.count);
        } else {
            for (int i = 0; i < args.count; i++) {
                if (!is_assignable(fn->param_types[i], args.types[i])) {
                    report_semantic_error(args_line, args_col,
                                          "argumento %d de '%s' incompativel: esperado '%s', recebido '%s'",
                                          i + 1, name, type_name(fn->param_types[i]),
                                          type_name(args.types[i]));
                }
            }
        }
        result.type = fn->type;
        if (fn->type == TYPE_VOID) {
            result.addr = strdup("");
            emit_quad("call", name, argc_buf, "");
        } else {
            result.addr = new_temp();
            emit_quad("call", name, argc_buf, result.addr);
        }
    }
    return result;
}

ArgList arg_list_empty(void) {
    ArgList list;
    list.count = 0;
    return list;
}

ArgList arg_list_add(ArgList list, ExprAttr arg) {
    if (list.count < MAX_ARGS) {
        list.types[list.count++] = arg.type;
    }
    emit_quad("param", arg.addr, "", "");
    return list;
}
