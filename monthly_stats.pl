#! /usr/bin/env perl
use Modern::Perl '2015';
use Data::Dumper;
###

use HNLtracker qw/get_ua get_dbh get_all_pairs update_scores $sql $feeds/;
my $dbh = get_dbh;
# total number of entries
my $sth;
my %stats;
foreach my $tag ('hn','lo') {
    $sth = $dbh->prepare( $sql->{'get_'.$tag.'_count'} );
    $sth->execute;
    my $rv = $sth->fetchrow_arrayref();
    $stats{$tag}->{count} = $rv->[0];
#    say "$tag $stats{$tag}->{count}";
}
$sth = $dbh->prepare( $sql->{get_pairs} );
my @pairs = @{get_all_pairs( $sth )};
#print Dumper \@pairs;

# gather stats
my $pair_count;
foreach my $pair (@pairs) {
	$stats{all}->{domains}->{$pair->{domain}}++;
    foreach my $seq ('first','then') {
#	say "$pair->{$seq}->{tag} $pair->{$seq}->{submitter}";
	$stats{$pair->{$seq}->{tag}}->{submitter}->{$pair->{$seq}->{submitter}}++;

	$stats{$pair->{$seq}->{tag}}->{seq}->{$seq}++;
    }

    $pair_count++;
}
    say $pair_count;

my $ten = 10;
my $count=0;
foreach my $dom (sort {$stats{all}->{domains}->{$b} <=> $stats{all}->{domains}->{$a}}  keys %{$stats{all}->{domains}} ){
    next if $count > $ten;
    say "$dom $stats{all}->{domains}->{$dom}";
    $count++;

}
foreach my $tag ('hn','lo') {
    say $feeds->{$tag}->{site};
    say "Total (%): ", sprintf("%d %.02f%%", $stats{$tag}->{count},100*$pair_count/$stats{$tag}->{count});
    say "First (%): ", sprintf("%d %.02f%%", $stats{$tag}->{seq}->{first},100*$stats{$tag}->{seq}->{first}/$pair_count); 
    my $max = 5;
    my $count = 0;
    foreach my $submitter  ( sort {$stats{$tag}->{submitter}->{$b} <=> $stats{$tag}->{submitter}->{$a} }keys %{$stats{$tag}->{submitter}}) {
	next if $count > $max;
	say "$submitter $stats{$tag}->{submitter}->{$submitter}";
	$count++;
    }
}
