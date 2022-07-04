#! /usr/bin/env perl
use Modern::Perl '2015';
###
use utf8;
use DateTime;
use JSON;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use HNLOlib qw/get_dbh $sql $feeds get_ua/;

my $dbh = get_dbh;
my $select = "select id from hackernews where created_time between 
'2022-07-01 00:00:00' and 
'2022-07-02 23:59:59' and score > 1 and comments > 0";
my $rows = $dbh->selectall_arrayref( $select ) or die $dbh->errstr;
my $count = 0;
if (scalar @$rows > 0) {
    my $now = time;

    my $sth = $dbh->prepare( "insert into hn_queue values (?,?,?)" );
    for my $row (@$rows) {
	$sth->execute( $row->[0], $now+3600+5*60*$count, 0);
	$count++;
    }
}
say "$count rows added to queue";
