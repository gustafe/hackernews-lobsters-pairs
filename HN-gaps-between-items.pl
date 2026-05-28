#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use JSON;
use HNLOlib qw/get_dbh get_ua $feeds get_item_from_source $ua/;

use open qw/ :std :encoding(utf8) /;

my $dbh = get_dbh();

my $list = $dbh->selectall_arrayref( "select id from hackernews order by id" );
my @pairs;
my %stats;
while (@$list) {
    my $start = shift @$list;
    my $end = $list->[0];
    my $diff = $end->[0] - $start->[0];
    $stats{$diff}++;

    push @pairs, [$start->[0],$end->[0], $diff] if $diff >= 500;


}
foreach my $pair (sort {$b->[2]<=>$a->[2]}  @pairs) {
    say join(',',@$pair);
}
