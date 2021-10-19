HOME=/home/gustaf
BIN=$(HOME)/prj/HN-Lobsters-Tracker
TEMPLATES=$(BIN)/templates
CSS=$(BIN)/CSS
WWW=$(HOME)/public_html/hnlo
MD=$(HOME)/bin/Markdown_1.0.1/Markdown.pl
.PHONY: build
build:
	@perl -I $(BIN) $(BIN)/update-daily-and-output-log-files.pl
	@perl -I $(BIN) $(BIN)/generate-hourly.pl 
.PHONY: refresh
refresh:	
	perl -I $(BIN) $(BIN)/generate-hourly.pl 

.PHONY: scores
scores:
	perl -I $(BIN) $(BIN)/generate-hourly.pl --update_score 

topscore.html: $(TEMPLATES)/topscore.tt $(CSS)/hnlo.css
	perl -I $(BIN) $(BIN)/top-score_comments.pl
	cp $(CSS)/hnlo.css $(HOME)/public_html/stylesheets/hnlo.css

about.html: $(TEMPLATES)/common.tt $(TEMPLATES)/footer.tt $(TEMPLATES)/changelog.md $(TEMPLATES)/todo.md $(CSS)/hnlo.css
	perl -I $(BIN) $(BIN)/generate-docs.pl
	cp $(CSS)/hnlo.css $(HOME)/public_html/stylesheets/hnlo.css

archives.html: archives.header archives.md $(TEMPLATES)/common.tt archives.footer
	cat archives.header > $(WWW)/archives.html
	cat $(TEMPLATES)/common.tt >> $(WWW)/archives.html
	cat archives.md | $(MD) >> $(WWW)/archives.html
	cat archives.footer >> $(WWW)/archives.html
