#! /usr/bin/env perl
use Modern::Perl '2015';
###
use utf8;
binmode(STDOUT, ':encoding(UTF-8)');
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use HNLOlib qw/get_dbh $sql $feeds get_ua sec_to_dhms sec_to_human_time/;

my $cutoff = 31940335;

my $dbh = get_dbh();
my $rows = $dbh->selectall_arrayref( "select id from hn_queue where id <= $cutoff order by id");

my $now = time;
$now += 30;
my $idx = 0;
my $sth = $dbh->prepare( "update hn_queue set age = ? where id = ?") or die $dbh->errstr;
for my $r (@$rows) {
    my $id = $r->[0];
    my $age = $now + 5 * $idx;
    $sth->execute( $age, $id ) or warn $sth->errstr;
    $idx++;
}
