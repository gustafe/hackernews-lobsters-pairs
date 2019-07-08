#! /usr/bin/env perl
use Modern::Perl '2015';
###


use JSON;
use HNLtracker qw/get_dbh get_ua/;
my $debug =1;

my $newest_url = 'https://hacker-news.firebaseio.com/v0/newstories.json';
my $ua = get_ua();
my $response = $ua->get($newest_url);
if (!$response->is_success) {
    die $response->status_line;
}

my $list = decode_json($response->decoded_content);
my $limit = 10;
my $count = 0;
for my $id (@{$list}) {
    if ($debug) {
	say $id
    } else {
    last if $count >= 10;
    my $item_url = 'https://hacker-news.firebaseio.com/v0/item/'.$id.'.json';
    my $res = $ua->get( $item_url );
    next unless $response->is_success; # might need to reprocess this item
    my $content = $res->decoded_content;
    
    if ( $content eq 'null' ) {
	warn "$id: item is dead";
	next;
    }
    my $json = decode_json(  $content );
    say join( '|', map { $json->{$_} } qw/id url time/);
    $count++;
	
    }
}
