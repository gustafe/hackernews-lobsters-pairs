HOME=/home/gustaf
BIN=$(HOME)/prj/HN-Lobsters-Tracker
WWW=$(HOME)/public_html/hnlo
MD=$(HOME)/bin/Markdown_1.0.1/Markdown.pl
.PHONY: build
build:
	perl -I $(BIN) $(BIN)/HN-get-new-items-load-store.pl
	perl -I $(BIN) $(BIN)/Lo-get-new-items-load-store.pl
	perl -I $(BIN) $(BIN)/Proggit-get-new-items-load-store.pl
	perl -I $(BIN) $(BIN)/generate-hourly.pl


.PHONY: refresh
refresh:	
	perl -I $(BIN) $(BIN)/generate-hourly.pl 

.PHONY: scores
scores:
	perl -I $(BIN) $(BIN)/generate-hourly.pl --update_score 

about.html: about.header common.tt footer.tt changelog.md todo.md hnlo.css
	perl -I $(BIN) $(BIN)/generate-docs.pl
	cp hnlo.css $(HOME)/public_html/stylesheets/hnlo.css

archives.html: archives.header archives.md common.tt footer.tt
	cat archives.header > $(WWW)/archives.html
	cat common.tt >> $(WWW)/archives.html
	cat archives.md | $(MD) >> $(WWW)/archives.html
	cat archives.footer >> $(WWW)/archives.html
