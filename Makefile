lexer_test: lexer.l tokens.h
	flex -o lex.yy.c lexer.l
	gcc -DLEXER_STANDALONE -Wall -o lexer_test lex.yy.c
clean:
	rm -f lex.yy.c lexer_test
