# Database schema

## table hackernews 

CREATE TABLE hackernews 
( id integer primary key not null,
created_time DATETIME not null,
url TEXT,
title TEXT,
submitter TEXT);

## table lobsters

CREATE TABLE lobsters
(id text primary key not null,
created_time datetime not null,
url text not null,
title text,
submitter text);
