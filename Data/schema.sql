CREATE TABLE hackernews 
( id integer primary key not null,
created_time DATETIME not null,
url TEXT,
title TEXT,
submitter TEXT, score int, comments int);
CREATE TABLE lobsters
(id text primary key not null,
created_time datetime not null,
url text not null,
title text,
submitter text, comments int, score int, tags TEXT);
CREATE TABLE proggit 
(id text primary key not null,
created_time datetime not null,
url text not null,
title text,
submitter text,
comments int,
score int);
CREATE TABLE hn_frontpage
(id int,
rank int,
read_time datetime);
CREATE INDEX idx_lo_url on lobsters(url);
CREATE INDEX idx_hn_url on hackernews(url);
CREATE INDEX idx_pr_url on proggit(url);

-- lobsters comments

create table lo_comment_count
(id text primary key not null,
no_of_comments int not null,
checked_time datetime not null);

create table lo_comments
(
id text not null,
comment_id text  not null,
created_at datetime,
updated_at datetime,
is_deleted boolean,
is_moderated boolean,
score int,
flags int,
parent_comment text,
comment_plain text,
depth int,
commenting_user text);
