#! /usr/bin/env perl
use Modern::Perl '2015';
###

use JSON;
use Data::Dumper;
use HNLtracker qw/get_dbh get_ua/;

my $sql = qq/select hn.url,
hn.created_time, strftime('%Y-%m-%d %H:%M:%S',lo.created_time),
strftime('%s',lo.created_time)-strftime('%s',hn.created_time),
hn.title, hn.submitter,
lo.title, lo.submitter
from hackernews hn
inner join lobsters lo
on lo.url = hn.url
where hn.url is not null
order by hn.created_time desc	/;

my $dbh= get_dbh();
my $sth=$dbh->prepare($sql);
$sth->execute;

while (my @r = $sth->fetchrow_array) {
    my $url = $r[0];
    my ($hn_time,$lo_time) = @r[1,2];
    my $diff = $r[3];
    my ( $hn_title, $hn_sub)= @r[4,5];
    my ( $lo_title, $lo_sub) = @r[6,7];

    say "URL: $url";
    my ( $first, $then );
    if ($diff<0) {
	$first = "First submitted to Lobste.rs on $lo_time by $lo_sub: '$lo_title'";
	$then  = "          then to Hackernews on $hn_time by $hn_sub: '$hn_title'";
    } else {
	$first = "First submitted to Hackernews on $hn_time by $hn_sub: '$hn_title'";
	$then =  "            then to Lobste.rs on $lo_time by $lo_sub: '$lo_title'";
       
    }
    say $first;
    say $then;
    say "Difference: $diff\n";
    
}
