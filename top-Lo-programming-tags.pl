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
    my ($year) = ($item->[1] =~ m/^(\d+)/);
    next unless scalar @tags == 2 and $item->[-1] =~ /programming/;
#    my $payload;
    if ($tags[0] eq 'programming') {
#	$payload = join(', ', @tags)
    } else {
	@tags = reverse @tags;
    }

    $data{$year}->{join(', ', @tags)}++
 #   }
}
my $limit = 5;
for my $year (sort keys %data) {
    say "==> $year";
    my $count = 1;
    for my $t (sort {$data{$year}{$b}<=>$data{$year}{$a}} keys %{$data{$year}}) {
	next if $count>$limit;
	say "$count $t $data{$year}{$t}";
	$count++;
	  
    }
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

