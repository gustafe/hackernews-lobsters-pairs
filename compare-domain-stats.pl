#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;

use Template;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use utf8;
use Time::HiRes  qw/gettimeofday tv_interval/;
use Data::Dumper;
use HNLOlib qw/get_dbh  $feeds update_scores $sql sec_to_dhms/;
use List::Util qw/all/;
use Statistics::Basic qw(:all);
use open qw/ :std :encoding(utf8) /;
binmode(STDOUT, ":encoding(UTF-8)");
my $domain = shift;
#GetOptions( 'domain' => \$domain);

die "usage: $0 <domain>" unless $domain;

say $domain;
my $dbh=get_dbh;
for my $tag (qw/lo hn/) {

    my $sql = "select id, title, score, comments from $feeds->{$tag}{table_name} where url like '%$domain%'";
    say $sql;
    my $data = $dbh->selectall_arrayref( $sql ) or die $dbh->errstr;
    my $count; my $scores; my $comments;
    for my $r (@$data) {
	push @$count, $r->[0];
	push @$scores, $r->[2]?$r->[2]:0;
	push @$comments, $r->[3]?$r->[3]:0;
#	say join(' | ', $feeds->{$tag}{title_href}.$r->[0],@$r);
    }
    my $zero_or_neg = scalar grep {$_<=0} @$scores;
    say "Total: ", scalar @$count;
    say "Mean score: ", mean $scores;
    say "Median score: ", median $scores;
    if ($zero_or_neg > 0) {
	printf("Number of items with zero or neg scores: %d (%.2f%%)\n",
	       $zero_or_neg, $zero_or_neg/(scalar @$count)*100 );
    }
#    say "Number of scores <= 0: ", scalar grep { $_<=0 } @$scores;
    say "Mean comments: ", mean $comments;
    say "Median comments: ", median $comments;
}
