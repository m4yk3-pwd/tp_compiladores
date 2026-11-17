#include <string.h>

#include "utils/expr_gen.h"
#include "utils/type_system.h"
#include "utils/tac.h"
#include "utils/errors.h"

ExprAttr gen_arith(const char *op, ExprAttr e1, ExprAttr e2, int line, int col) {
    ExprAttr res = { TYPE_ERROR, strdup("_err") };
    if (e1.type == TYPE_ERROR || e2.type == TYPE_ERROR) return res;

    if (!is_numeric(e1.type) || !is_numeric(e2.type)) {
        report_semantic_error(line, col, "operador '%s' incompativel com tipos '%s' e '%s'",
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
        report_semantic_error(line, col,
                              "operador '%%' exige operandos inteiros (recebeu '%s' e '%s')",
                              type_name(e1.type), type_name(e2.type));
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
        report_semantic_error(line, col,
                              "comparacao '%s' exige operandos numericos (recebeu '%s' e '%s')",
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
        report_semantic_error(line, col, "operador '%s' incompativel entre '%s' e '%s'",
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
        report_semantic_error(line, col,
                              "operador logico '%s' exige expressoes booleanas/inteiras", op);
        return res;
    }
    res.type = TYPE_INT;
    res.addr = new_temp();
    emit_quad(op, e1.addr, e2.addr, res.addr);
    return res;
}

ExprAttr gen_unary_minus(ExprAttr e, int line, int col) {
    ExprAttr res;
    if (e.type != TYPE_ERROR && !is_numeric(e.type)) {
        report_semantic_error(line, col,
                              "operador unario '-' incompativel com tipo '%s'", type_name(e.type));
        res.type = TYPE_ERROR;
        res.addr = strdup("_err");
    } else {
        res.type = e.type;
        res.addr = new_temp();
        emit_quad("uminus", e.addr, "", res.addr);
    }
    return res;
}

ExprAttr gen_not(ExprAttr e, int line, int col) {
    ExprAttr res;
    if (e.type != TYPE_ERROR && e.type != TYPE_INT) {
        report_semantic_error(line, col,
                              "operador '!' exige expressao booleana/inteira (recebeu '%s')",
                              type_name(e.type));
        res.type = TYPE_ERROR;
        res.addr = strdup("_err");
    } else {
        res.type = TYPE_INT;
        res.addr = new_temp();
        emit_quad("!", e.addr, "", res.addr);
    }
    return res;
}
