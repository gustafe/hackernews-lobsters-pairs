#! /usr/bin/env perl
use Modern::Perl '2015';
###

use JSON;
use HNLtracker qw/get_dbh get_ua/;
use IO::Handle;
STDOUT->autoflush(1);
binmode STDOUT, ":utf8";

my $sql = { all_items => qq/select id, title, score, comments from hackernews order by id/,
	    update_item => qq/update hackernews set title=?, score=?, comments=? where id = ?/,
	    };
my $dbh = get_dbh();
my $ua = get_ua();


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
$sth->execute();
while (my @r = $sth->fetchrow_array) {
    
    #    say join(',', map {$_?$_:''} @row);
    my $item = read_item( $r[0] );
    print "$r[0]: ";
    if (!defined $item->{title}) {
	# error in read from API
	print "can't get info from API!\n";
	push @failed, $r[0];
    }
    elsif ($item->{title} ne $r[1] or
	$item->{score} != $r[2] or
	$item->{descendants} != $r[3] ) {
	push @update_list, [$r[0], map {$item->{$_}} qw/title score descendants/];
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
    my $rv = $sth->execute( $a->[1],$a->[2],$a->[3],$a->[0] );
    
}
if (scalar @failed>0 ) {
   say "### Failed to get info ###";
foreach my $i (@failed) {

 
    say "$i |  https://news.ycombinator.com/item?id=$id";
    say "delete from hackernews where id = $id;";
}
}
