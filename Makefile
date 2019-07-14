HOME=/home/gustaf
BIN=$(HOME)/prj/HN-Lobsters-Tracker
WWW=$(HOME)/public_html/hnlo
MD=$(HOME)/bin/Markdown_1.0.1/Markdown.pl
.PHONY: build
build:
	perl -I $(BIN) $(BIN)/HN-get-new-items-load-store.pl
	perl -I $(BIN) $(BIN)/Lo-get-new-items-load-store.pl
	perl -I $(BIN) $(BIN)/generate-page.pl --update_score


.PHONY: refresh
refresh:	
	perl -I $(BIN) $(BIN)/generate-page.pl 

.PHONY: scores
scores:
	perl -I $(BIN) $(BIN)/generate-page.pl --update_score 

about.html: about.header common.tt footer.tt about.md todo.md
	cat about.header > $(WWW)/about.html
	cat common.tt > $(WWW)/about.html
	cat about.md | $(MD) >> $(WWW)/about.html
	cat todo.md | $(MD) >> $(WWW)/about.html
	cat footer.tt >> $(WWW)/about.html
