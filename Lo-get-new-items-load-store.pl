#! /usr/bin/env perl
use Modern::Perl '2015';
###


use JSON;
use Data::Dumper;
use HNLtracker qw/get_dbh get_ua/;
use open IO => ':utf8';
#binmode STDOUT, ':utf8';
my $newest_url = 'https://lobste.rs/newest.json';
my $ua = get_ua();
my $response = $ua->get($newest_url);
if (!$response->is_success) {
    die $response->status_line;
}

my $list = decode_json($response->decoded_content);
my $dbh = get_dbh();
my $latest_sql = qq{select id from lobsters order by created_time desc limit 1};
my $sth = $dbh->prepare( $latest_sql );
$sth->execute();
my $latest_id = $sth->fetchrow_array;
$sth->finish();

my $insert_sql = qq{insert into lobsters (
id, created_time, url, title, submitter, score,comments, tags
)
values
(?, ?,?,?,?,?,?,?)};
$sth = $dbh->prepare( $insert_sql );
my $count = 0;
for my $item (@{$list}) {
    my $current_id = $item->{short_id};
    if ($current_id eq $latest_id) {
	last; 
    }
    #    say join('|', map { $item->{$_} } qw/short_id url created_at/);
    $sth->execute($current_id,
		  $item->{created_at},
		  $item->{url},
		  $item->{title},
		  $item->{submitter_user}->{username},
		  $item->{score},
		  $item->{comment_count},
		  join(',', @{$item->{tags}}),
		 );
    $count++;
}
say "\nNew Lobste.rs items added: $count\n";
$sth->finish();
$dbh->disconnect();
