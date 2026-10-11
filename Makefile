lexer_test: lex/lexer.l
	flex -o lex.yy.c lex/lexer.l
	gcc -DLEXER_STANDALONE -Wall -o lexer_test lex.yy.c

clean:
	rm -f lex.yy.c win_flex.yy.c parser.tab.c parser.tab.h lexer_test compilador compilador.exe

compileLinux:
	bison -d sintatico/parser.y -o parser.tab.c
	flex -o lex.yy.c lexico/lexer.l
	gcc parser.tab.c lex.yy.c -o compilador -Wall

compileWin:
	bison -d sintatico/parser.y -o parser.tab.c
	flex -o win_flex.yy.c lexico/lexer.l
	gcc parser.tab.c win_flex.yy.c -o compilador.exe -Wall