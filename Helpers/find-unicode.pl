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
my $statement = "select title  from ".$feeds->{$label}->{table_name};
my $list = $dbh->selectall_arrayref( $statement );
my $total =0;
my $has_unicode= 0;
foreach my $title (@$list) {
    $total++;
    my $high_char = undef;
    foreach my $chr (split(//, $title->[0])) {
	$high_char =1 if ord( $chr )  > 127
    }
    $has_unicode++ if defined $high_char;
    
}
say "Total: $total";
say "Has unicode: $has_unicode";
printf("Ratio: %.2f%%\n", $has_unicode/$total * 100);
