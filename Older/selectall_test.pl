#! /usr/bin/env perl
use Modern::Perl '2015';
###
use HNLOlib qw/$feeds get_ua get_dbh get_reddit/;
use Getopt::Long;
use Data::Dumper;
my $dbh=get_dbh;
my $label = 'hn';

my $deletes;
while (<DATA>) {
    chomp;
    push @$deletes, $_;
}
if (@$deletes and $label ne 'pr') {
    my $pholders = join(",", ("?") x @$deletes);
    my $sql = "select id, title from $feeds->{$label}->{table_name} where id in ($pholders)";
    say $sql;
    my $to_deletes = $dbh->selectall_arrayref($sql,{},@$deletes ) or die $dbh->errstr;
    print Dumper $to_deletes;
    say "The following items will be deleted:";
    foreach my $line (@$to_deletes) {
	say join("\t", @$line);
    }
}


  
__DATA__
20976104
20976068
20976065
20976009
20975976
20975964
20975961
20975955
20975942
20975929
