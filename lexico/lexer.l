%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "parser.tab.h"

int lex_errors = 0;                 /* total de erros lexicos           */
int last_lex_error_line = 0;        /* linha do ultimo erro lexico (evita erro sintatico em cascata) */
int line = 1, col = 1;              /* posicao do PROXIMO caractere      */
int token_line, token_col;          /* posicao de INICIO do token atual  */
static int cmt_line, cmt_col;       /* onde o comentario de bloco abriu  */

/* Roda antes de TODA acao: guarda onde o token comecou (para o Bison tambem: yylloc) e avanca a coluna */
#define YY_USER_ACTION { token_line = line; token_col = col; \
                         yylloc.first_line = line;  yylloc.first_column = col; \
                         yylloc.last_line  = line;  yylloc.last_column  = col + yyleng; \
                         col += yyleng; }

static void lex_error_at(int l, int c, const char *msg);
static void lex_error(const char *fmt, ...);
%}

%option noyywrap nounput noinput

DIGIT     [0-9]

/* ID aceita comecar com '_' (ex.: _teste), mas so e usado para REJEITAR: as regras
   GLOBAL, LOCAL e FUNC abaixo e que aceitam identificadores validos. */
ID        [A-Za-z_][A-Za-z0-9_]*
GLOBAL    [A-Z][A-Z0-9_]*
LOCAL     [a-z][a-z0-9_]*
FUNC      [a-z]+(ar|er|ir|or)[A-Z][A-Za-z0-9]*

%x COMMENT

%%

[ \t\r]+                 { /* ignora espacos */ }
\n                       { line++; col = 1; }

"//".*                   { /* comentario de linha */ }
"/*"                     { cmt_line = token_line; cmt_col = token_col; BEGIN(COMMENT); }
<COMMENT>"*/"            { BEGIN(INITIAL); }
<COMMENT>\n              { line++; col = 1; }
<COMMENT>[^*\n]+         { }
<COMMENT>"*"             { }
<COMMENT><<EOF>>         { lex_error_at(cmt_line, cmt_col,
                               "comentario '/*' nao fechado");
                           BEGIN(INITIAL); yyterminate(); }

"int"                    { return INT; }
"float"                  { return FLOAT; }
"void"                   { return VOID; }
"if"                     { return IF; }
"else"                   { return ELSE; }
"while"                  { return WHILE; }
"for"                    { return FOR; }
"return"                 { return RETURN; }
"main"                   { return MAIN; }

"switch"                 { return SWITCH; }
"case"                   { return CASE; }
"default"                { return DEFAULT; }
"break"                  { return BREAK; }

{FUNC}                   { yylval.sval = strdup(yytext); return FUNC_ID; }
{GLOBAL}                 { yylval.sval = strdup(yytext); return GLOBAL_ID; }
{LOCAL}                  { yylval.sval = strdup(yytext); return LOCAL_ID; }
{ID}                     { lex_error("identificador '%s' invalido: use MAIUSCULAS "
                               "(global), minusculas (local) ou verboTermo (funcao)",
                               yytext); }

{DIGIT}+\.{DIGIT}+       { yylval.fval = atof(yytext); return FLOAT_LIT; }
{DIGIT}+                 { yylval.ival = atoi(yytext); return INT_LIT; }
{DIGIT}+[A-Za-z_][A-Za-z0-9_]* {
                           lex_error("numero mal formado '%s'", yytext); }

\"([^"\\\n]|\\.)*\"      { yylval.sval = strdup(yytext); return STRING_LIT; }
\"([^"\\\n]|\\.)*        { lex_error("string nao terminada"); }

"=="                     { return EQ; }
"!="                     { return NEQ; }
"<="                     { return LE; }
">="                     { return GE; }
"&&"                     { return AND; }
"||"                     { return OR; }

[-+*/%=<>!(){};,:]       { return yytext[0]; }

.                        { if (isprint((unsigned char)yytext[0]))
                               lex_error("caractere invalido '%c'", yytext[0]);
                           else
                               lex_error("caractere invalido (byte 0x%02X)",
                                         (unsigned char)yytext[0]); }

%%

#include <stdarg.h>

static void lex_error_at(int l, int c, const char *msg) {
    fprintf(stderr, "Erro lexico (linha %d, coluna %d): %s\n", l, c, msg);
    lex_errors++;
    last_lex_error_line = l;
}

static void lex_error(const char *fmt, ...) {
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    lex_error_at(token_line, token_col, buf);
}