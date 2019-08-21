#! /usr/bin/env perl
use Modern::Perl '2015';
###

use JSON;
use HNLtracker qw/get_dbh get_ua/;
use Data::Dumper;
use open IO => ':utf8';
#binmode STDOUT, ':utf8';
# read from list
my @failed;
my @items;
my $ua =get_ua();
my $insert_sql = qq{insert into hackernews (
id, created_time, url, title, submitter, score, comments)
values
(?, datetime(?,'unixepoch'),?,?,?,?,?)};
my $latest_sql = qq{select max(id) from hackernews};
my $dbh = get_dbh();
my $sth = $dbh->prepare( $latest_sql);
$sth->execute();
my $latest_id = $sth->fetchrow_array;
$sth->finish();  

my $newest_url = 'https://hacker-news.firebaseio.com/v0/newstories.json';
my $response = $ua->get($newest_url);
if (!$response->is_success) {
    die $response->status_line;
}

my $list = decode_json($response->decoded_content);

my $count=0;
while (@{$list}) {
    
    my $id =shift @{$list};

    if ($id<=$latest_id) {
	next;
    }
    my $item_url = 'https://hacker-news.firebaseio.com/v0/item/'.$id.'.json';
    my $res = $ua->get( $item_url );
    if (!$res->is_success) {
	warn $res->status_line;
	warn "~~> fetch for $id failed\n";
	push @failed, $id;
	next;
    }
    
    my $payload = $res->decoded_content;
    
    if ($payload eq 'null') {
	say "++> $id has null content";
	next;
    }
    my $item = decode_json( $payload );
    # skip items without URLs
    if (!defined $item->{url}) {
	say "||> $id has no URL, skipping";
	next;
    }
    
    push @items, [ map { $item->{$_}} ('id','time','url','title','by','score','descendants')];
    $count++;
}


# add to store


$sth = $dbh->prepare( $insert_sql );
foreach my $item (@items) {
    $sth->execute( @{$item});
}
$sth->finish();
$dbh->disconnect();
say "\nNew HN items added: $count\n";
if (scalar @failed > 0) {
    say "### ITEMS NOT FOUND ###";
    foreach my $id (@failed) {
	say $id;
    }
}

