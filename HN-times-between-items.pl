#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use JSON;
use HNLOlib qw/get_dbh get_ua $feeds get_item_from_source $ua/;

use open qw/ :std :encoding(utf8) /;

my $dbh = get_dbh();

my $list = $dbh->selectall_arrayref( "select id, strftime('%s',created_time) from hackernews order by id" );
my @pairs;
my %stats;
while (@$list) {
    my $start = shift @$list;
    my $end = $list->[0];
    my $diff = $end->[1] - $start->[1];
    $stats{$diff}++;
    if ($diff >= 15 * 60) {
	push @pairs, [$diff, $start->[0],$end->[0]];
    }

}
foreach my $pair (sort {$a->[0]<=>$b->[0]}  @pairs) {
    say join(',',@$pair);
}
