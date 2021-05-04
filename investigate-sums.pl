#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;
use List::Util qw/sum/;
use HNLOlib qw/$feeds get_ua get_dbh get_reddit get_web_items/;
sub usage {
    say "usage: $0 --label={hn,lo,pr}";
    exit 1;

}

my $label;
GetOptions('label=s'=>\$label);
usage unless exists $feeds->{$label};
my $dbh = get_dbh();
my $statement = "select score, comments from ".$feeds->{$label}->{table_name}." where score+comments>=0";
my $list = $dbh->selectall_arrayref( $statement );
my %sums;
my $count;
foreach my $line(@$list) {
    #    next if (sum @$line < 0);
    if (sum @$line>=0) {
	$sums{sum @$line}++ 
    } else {
	next;
    }

    $count++;
}
my $upper = $count * 0.85;
my $lower = $count * 0.25;
my $running;
#say "$lower $upper" ;
foreach my $sum (sort {$a<=>$b} keys %sums) {
    my $append;
    $running += $sums{$sum};
    if ($running<=$lower) {
	$append='_'
    } elsif ($running>=$upper) {
	$append='*'
    } else {
	$append=''
    }
    say "$sum;$sums{$sum};$append"
}
