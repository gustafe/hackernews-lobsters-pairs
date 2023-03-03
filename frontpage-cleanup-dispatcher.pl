#! /usr/bin/env perl
use Modern::Perl '2015';
###

use DateTime;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use utf8;
use DateTime::Format::Strptime qw/strftime strptime/;
use Data::Dump qw/dd/;
use HNLOlib qw/get_dbh $sql/;
my $folder = './frontpage-cleanup';
my $dbh = get_dbh;
my $stmt = "select id, rank, read_time from hn_frontpage where read_time < date('now','-30 day') order by id, rank ";
#my $stmt = "select id, rank, read_time from hn_frontpage order by id, rank limit 1000";
say STDERR "-- ==> reading from DB...";
my $rows = $dbh->selectall_arrayref( $stmt ) or die $dbh->errstr;
my %data;
say STDERR "-- ==> collating... ";
for my $row (@$rows) {
    push @{$data{$row->[0]}}, [$row->[1],$row->[2]];
}
my $sth = $dbh->prepare("delete from hn_frontpage where id=? and rank=? and read_time=?");
my $count = 0;
say STDERR "-- ==> creating files...  ";
for my $key (sort {$b<=>$a} keys %data) {
#    say "-- ~~> $count" if $count % 10 == 0 and $count > 0;
 #   last if $count > 100;
    my $keep = shift @{$data{$key}};
    next unless scalar @{$data{$key}};
    my $filename = $folder . '/' . scalar @{$data{$key}} . '-' .$key .'.sql';
    open (my $fh, '>', $filename) or die "can't open $filename for writing: $!";
   for my $el (@{$data{$key}}) {
       printf $fh "delete from hn_frontpage where id=%d and rank=%d and read_time='%s';\n", $key, @$el;
#	say join(',', ($count, $key, @$el));
#	$sth->execute( $key, @$el );
   }
    close $fh;
    $count++;
}

