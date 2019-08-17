#! /usr/bin/env perl
use Modern::Perl '2015';
###


use JSON;
use HNLtracker qw/get_dbh get_ua/;
use Data::Dumper;
# get item from STDIN
my $id =20583214;

my $item_url = 'https://hacker-news.firebaseio.com/v0/item/'.$id.'.json';
say $item_url;
my $ua = get_ua();
my $response = $ua->get($item_url);
if (!$response->is_success) {
    die $response->status_line;
}

my $item =decode_json($response->decoded_content);

print Dumper $item;
