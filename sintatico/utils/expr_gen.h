#ifndef UTILS_EXPR_GEN_H
#define UTILS_EXPR_GEN_H

#include "utils/types.h"

/*
 * Type checking and three-address code generation for operators. Each function
 * reports a semantic error and yields a TYPE_ERROR result on a type mismatch,
 * otherwise emits a quadruple and returns the resulting temporary.
 */

ExprAttr gen_arith(const char *op, ExprAttr e1, ExprAttr e2, int line, int col);
ExprAttr gen_mod(ExprAttr e1, ExprAttr e2, int line, int col);
ExprAttr gen_rel(const char *op, ExprAttr e1, ExprAttr e2, int line, int col);
ExprAttr gen_eq(const char *op, ExprAttr e1, ExprAttr e2, int line, int col);
ExprAttr gen_logic(const char *op, ExprAttr e1, ExprAttr e2, int line, int col);

ExprAttr gen_unary_minus(ExprAttr e, int line, int col);
ExprAttr gen_not(ExprAttr e, int line, int col);

#endif /* UTILS_EXPR_GEN_H */
