#! /usr/bin/env perl
use Modern::Perl '2015';
###

use JSON;
use HNLtracker qw/get_dbh get_ua $feeds/;
use IO::Handle;
STDOUT->autoflush(1);
use open qw/ :std :encoding(utf8) /;

my $sql = { all_items => qq/select id, title, score, comments from hackernews order by id/,
	    update_item => qq/update hackernews set title=?, score=?, comments=? where id = ?/,
	    delete_item=> qq/delete from hackernews where id = ?/,
	    };
my $dbh = get_dbh();
$dbh->{sqlite_unicode} = 1;
my $ua = get_ua();
sub  get_item_from_source;


sub read_item {
    my ( $id ) = @_;
    my $url = 'https://hacker-news.firebaseio.com/v0/item/'.$id.'.json';
    my $r = $ua->get( $url );
    return  $r->status_line() unless $r->is_success();
    my $content = $r->decoded_content();
    return decode_json( $content );
}

my $sth = $dbh->prepare( $sql->{all_items} );
my @update_list;
my @failed;
my @not_read;
my @to_delete;
$sth->execute();
while (my @r = $sth->fetchrow_array) {
    my $id = $r[0];
#        say join(',', map {$_?$_:''} @r);

    my $res = get_item_from_source('hn', $id );
#    say join(',', map {$res->{$_}} qw/title score comments/);
    print "status for ID $id: ";
      if (!defined $res) {
	# assume issue with API,
	print "could not read, added to not_read list\n";
	push @not_read, $id;
    }
    elsif (!defined $res->{title}) {
	print "seems to be deleted!\n";
	push @to_delete, $id;
    }
    elsif ($res->{title} ne $r[1] or
	$res->{score} != $r[2] or
	$res->{comments} != $r[3]?$r[3]:0 ) {
	push @update_list, [$r[0], map {$res->{$_}} qw/title score comments/];
	print "will be updated\n";
    } else {
	print "no change\n";
    }
    
    sleep 1;
}

$sth->finish;
say "### Updating database ###";
$sth = $dbh->prepare( $sql->{update_item});
foreach my $a (@update_list ) {
    my $rv = $sth->execute( $a->[1],$a->[2],$a->[3],$a->[0] ) or warn $sth->errstr;
    
}
if (scalar @to_delete>0 ) {
    #   say "### Failed to get info ###";
    $sth = $dbh->prepare( $sql->{delete} );
foreach my $i (@to_delete) {
    my $rv = $sth->execute( $i ) or warn $sth->errstr;
}
}
sub get_item_from_source {
    my ( $tag, $id ) = @_;

    # this is fragile, it relies on all feed APIs having the same structure!
    my $href = $feeds->{$tag}->{api_item_href} . $id . '.json';
    my $r    = $ua->get($href);
    if ( !$r->is_success() ) {

        #	warn "==> fetch failed for $tag $id: ";
        #	warn Dumper $r;
        return undef;
    }
    return undef unless $r->is_success();
    return undef unless $r->header('Content-Type') =~ m{application/json};
    my $content = $r->decoded_content();
    my $json    = decode_json($content);

    # we only return stuff that we're interested in
    return {
        title    => $json->{title},
        score    => $json->{score},
        comments => $json->{ $feeds->{$tag}->{comments} }
    };
}
