#! /usr/bin/env perl
use Modern::Perl '2015';
###

use HNLtracker qw/get_dbh get_all_pairs $feeds update_scores $sql/;
use Data::Dumper;
use open qw/ :std :encoding(utf8) /;
my $dbh = get_dbh;
$dbh->{sqlite_unicode} = 1;
my $sth = $dbh->prepare( $sql->{get_pairs} );
my @pairs = @{ get_all_pairs($sth) };
my %stats;
my $threshold=9;
foreach my $pair (@pairs) {
    foreach my $seq (qw/first then/) {
	my $item = $pair->{$seq};
	if ($item->{score}>0) {
#	if (($item->{comments}+$item->{score}>$threshold) and $item->{score}>0) {
	    $stats{$item->{tag}}->{has_ratio}++;
	    if ($item->{comments}==0) {
		$stats{$item->{tag}}->{zero}++;
	    } else {
		my $pos = sprintf("%d",$item->{comments}/$item->{score}*10);
		$stats{$item->{tag}}->{hist}->[$pos]++;
	    }
	} else {
	    $stats{$item->{tag}}->{no_ratio}++;
	}
    }
}
#print Dumper \@pairs;
foreach my $tag (sort keys %stats) {
    say "$tag  no ratio : $stats{$tag}->{no_ratio}";
    say "$tag  has ratio: $stats{$tag}->{has_ratio}";
    say "$tag zero ratio: $stats{$tag}->{zero}";
    my $idx =0;
    foreach my $el (@{$stats{$tag}->{hist}}) {
	printf( " %2d: %2d\n", $idx, $stats{$tag}->{hist}->[$idx]) if defined $stats{$tag}->{hist}->[$idx];
#	printf (" %2d", $idx) if defined $stats{$tag}->{hist}->[$idx];
	$idx++;
    }
    # print "\n";
    # $idx=0;
    # foreach my $el (@{$stats{$tag}->{hist}}) {
    # 	printf(" %2d", $stats{$tag}->{hist}->[$idx]) if defined $stats{$tag}->{hist}->[$idx];
    # 	$idx++;
    # }
    # print "\n";
#    print Dumper $stats{$tag}->{hist};
}
