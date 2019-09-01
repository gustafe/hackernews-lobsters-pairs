#! /usr/bin/env perl
use Modern::Perl '2015';
###

use JSON;
use HNLOlib qw/get_dbh get_ua $feeds $sql/ ;
use Data::Dumper;
use open IO => ':utf8';
#binmode STDOUT, ':utf8';
# read from list
my @failed;
my @items;
my $ua =get_ua();

my $insert_sql = $feeds->{hn}->{insert_sql};

my $latest_sql = qq{select max(id) from hackernews};
my $dbh = get_dbh();
my $sth; # = $dbh->prepare( $latest_sql);

my $latest_id = ($dbh->selectall_arrayref($latest_sql))->[0]->[0] or die $dbh->errstr;


my $newest_url = 'https://hacker-news.firebaseio.com/v0/newstories.json';
my $topview_url = 'https://hacker-news.firebaseio.com/v0/topstories.json';
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
	warn "--> fetch for $id failed\n";
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
	say "~~> $id has no URL, skipping";
	next;
    }
    if (defined $item->{dead}) {
	say "**> $id flagged 'dead', skipping";
	next;
    }
    
    push @items, [ map { $item->{$_}} ('id','time','url','title','by','score','descendants')];
    $count++;
}


# add to store


$sth = $dbh->prepare( $feeds->{hn}->{insert_sql} ) or die $dbh->errstr;
foreach my $item (@items) {
    $sth->execute( @{$item}) or warn $sth->errstr;
}
$sth->finish();
say "\nNew HN items added: $count\n";
if (scalar @failed > 0) {
    say "### ITEMS NOT FOUND ###";
    foreach my $id (@failed) {
	say $id;
    }
}

### update items that are part of sets

$sth = $dbh->prepare( $sql->{get_pairs} );
my %sets = %{ HNLOlib::get_all_sets($sth) };
my @list;
my $days=7;
my $now= time();
foreach my $url (keys %sets) {
    foreach my $ts (keys %{$sets{$url}->{entries}}) {
	my $entries = $sets{$url}->{entries}->{$ts};
	if  ( $entries->{tag} eq 'hn' and $entries->{time}>=($now-$days*24*3600)){
	    push @list, $entries->{id};
	}
    }
}
say "items in store in the last $days days: ", scalar @list;
HNLOlib::update_from_list( 'hn',
			   \@list);
#say join("\n", sort @list);

## grab the current front page
$response = $ua->get($topview_url);
if (!$response->is_success) {
    die $response->status_line;
}
my $top_ids = decode_json($response->decoded_content);
$sth = $dbh->prepare( "insert into hn_frontpage (id, rank, read_time) values (?,?,datetime('now'))") or die $dbh->errstr;;
my $rank = 1;
foreach my $id (@$top_ids) {
    next if $rank > 60; # only first 2 pages
    $sth->execute( $id, $rank) or warn $sth->errstr;
    $rank++;
}
$dbh->disconnect();

