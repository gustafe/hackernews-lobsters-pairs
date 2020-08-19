#! /usr/bin/env perl
use Modern::Perl '2015';
###

use JSON;
use HNLOlib qw/get_dbh get_ua $feeds $sql/ ;
use Data::Dumper;
use Term::ProgressBar 2.00;
use open IO => ':utf8';
#binmode STDOUT, ':utf8';
# read from list
my @failed;
my @items;
my $debug =0;
my $ua =get_ua();

my $insert_sql = $feeds->{hn}->{insert_sql};

my ( $start, $end) = (23309002-500,23309002+500);


my $list = [$start+1 .. $end-1];
my $progress= Term::ProgressBar->new( {name=>'Ids', count => scalar @{$list}, ETA=>'linear'});

$progress->max_update_rate(1);
    my $next_update=0;

my $count=0;
my $inserts=0;
while (@{$list}) {
    
    my $id =shift @{$list};
    say "reading $id..." if $debug;
    $count++;
    $progress->update($count);
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
    # skip non-posts
    if (!defined $item->{url} or defined  $item->{dead} or defined $item->{deleted}) {
#	say "^^> $id has no url, is dead, or is deleted - skipping";
	next;
    }

    
    push @items, [ map { $item->{$_}} ('id','time','url','title','by','score','descendants')];
    $progress->message("found $id ", $item->{title});

    $inserts++;
}
$progress->update($count);

# add to store

my $dbh = get_dbh();
my $sth = $dbh->prepare( $feeds->{hn}->{insert_sql} ) or die $dbh->errstr;
foreach my $item (@items) {
    $sth->execute( @{$item}) or warn $sth->errstr;
}
$sth->finish();
say "\nNew HN items added: $inserts\n";
if (scalar @failed > 0) {
    say "### ITEMS NOT FOUND ###";
    foreach my $id (@failed) {
	say $id;
    }
}

