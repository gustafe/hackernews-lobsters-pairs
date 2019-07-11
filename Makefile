HOME=/home/gustaf
BIN=$(HOME)/prj/HN-Lobsters-Tracker
WWW=$(HOME)/public_html/hnlo

.PHONY: build
build:
	perl -I $(BIN) $(BIN)/HN-get-new-items-load-store.pl
	perl -I $(BIN) $(BIN)/Lo-get-new-items-load-store.pl
	perl -I $(BIN) $(BIN)/generate-page.pl > $(WWW)/index.html


.PHONY: refresh
refresh:	
	perl -I $(BIN) $(BIN)/generate-page.pl > $(WWW)/index.html

.PHONY: scores
scores:
	perl -I $(BIN) $(BIN)/generate-page.pl --update_score > $(WWW)/index.html
