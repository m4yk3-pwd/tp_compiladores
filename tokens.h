/* tokens.h - usado SOMENTE no teste isolado do lexer.
   Na etapa do Bison, este arquivo e substituido por parser.tab.h */
#ifndef TOKENS_H
#define TOKENS_H

enum {
    TK_INT = 258, TK_FLOAT, TK_VOID,
    TK_IF, TK_ELSE, TK_WHILE, TK_RETURN, TK_PRINCIPAL,
    TK_GLOBAL_ID, TK_LOCAL_ID, TK_FUNC_ID,
    TK_INT_LIT, TK_FLOAT_LIT, TK_STRING_LIT,
    TK_EQ, TK_NEQ, TK_LE, TK_GE, TK_AND, TK_OR
};

typedef union { int ival; double fval; char *sval; } YYSTYPE;
extern YYSTYPE yylval;

#endif
