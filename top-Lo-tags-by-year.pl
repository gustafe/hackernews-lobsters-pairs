#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;
use FindBin qw/$Bin/;
use List::Util qw/sum/;
use POSIX qw/ceil/;
use URI;
use HNLOlib qw/$feeds get_ua get_dbh get_reddit get_web_items/;

my $dbh = get_dbh();
my $statement
    = "select id, created_time, tags from "
   . $feeds->{'lo'}->{table_name};

my $list = $dbh->selectall_arrayref($statement);
$statement = "select date(min(created_time)), date(max(created_time)) from "
    . $feeds->{'lo'}->{table_name};
my $dates = $dbh->selectall_arrayref($statement);

my $min_ts = $dates->[0]->[0];
my $max_ts = $dates->[0]->[1];

my %data;
my $total = 0;
foreach my $item ( @{$list} ) {
    #    say join(' ',@$item);
    my @tags = split(/\,/, $item->[-1]);
#    $data{$item->[-1]} = {els => scalar @tags}
    $data{scalar @tags}->{join(', ', sort @tags)}++
 #   }
}
for my $elems (1..4) {
    my @list = sort {$data{$elems}->{$b}<=>$data{$elems}->{$a}} keys %{$data{$elems}};
    if ($elems == 2) {
	my @rust = grep {/programming/} @list;
	while (@rust) {

	    my $t = shift @rust;
	    say "$t $data{$elems}->{$t}";
	}
    }
    my @top = @list[0..9];
    my @bottom = @list[-10..-1];
    say "\# number of tags: $elems";
    say "";
    my $line;

    while (@top ) {
	my $t = shift @top;
	$line .= "$t - $data{$elems}{$t}\n";
#	my $b = shift @bottom;
#	$line .= "$b $data{$elems}{$b}\n";

    }
    say $line;
}
__END__
my $limit = 10;
my $count = 1;
for my $t (sort {$data{$b}<=>$data{$a}} keys %data) {
#    next unless $count <=10;
    next if $t =~ m/\,/;
    say "$count $t $data{$t}";
    $count++;
}
$count = 1;

for my $t (sort {$data{$b}<=>$data{$a}} keys %data) {
    next unless $count <=10;
    next unless $t =~ m/\,/;
    say "$count $t $data{$t}";
    $count++;
}

