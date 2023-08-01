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
my $dbh;

opendir (my $dir, $folder) or die "can't open $folder for listing: $!";
my @sqlfiles = grep {/\.sql$/ && -f "$folder/$_"} readdir($dir);
while (@sqlfiles) {
    # pick a file 
    my $file = splice( @sqlfiles, rand @sqlfiles, 1 );
    say "working on $file";
    open( my $fh, "< $folder/$file") or die "can't open $folder/$file for reading: $!";
    my @lines;
    for (<$fh>) {
	chomp;
	push @lines, $_;
    }
    close $fh;
    my $line_count = scalar @lines;
    say "file has ", $line_count, " lines";
    my $count=1;
    my $retry=0;
    while (@lines) {
	$dbh=get_dbh;
	my $stmt = shift @lines;
	my $sth = $dbh->prepare( $stmt);
	my ( $id, $rank, $rt );
	if ($stmt=~ m/id\=(\d+).*rank=(\d+).*read_time=(.*)$/) {
	    ( $id, $rank, $rt ) = ($1,$2,$3)
	} else {
	    warn "regex failed\n"
	}
	if ($retry) {
	    printf("%2d [%2d/%2d] id=%d rank=%2d read_time=%s\n",
		   $retry, $count, $line_count,$id,$rank,$rt);
	} else {
	    printf("[%2d/%2d] id=%d rank=%2d read_time=%s\n",
		   $count, $line_count, $id,$rank,$rt);
	}
	$sth->execute();
	if ($sth->err) {
	    warn "DBI error: $DBI::err : $DBI::errstr\n";
	    push @lines, $stmt;
	    sleep 10;
	    $retry++;
	} else {
	    $count++;
	}
    }
    unlink("$folder/$file") or die "can't unlink $folder/$file: $!";
    say "$file deleted, ", scalar (@sqlfiles), " remaining";
    my $rc = $dbh->disconnect || warn $dbh->errstr;
    say "sleeping 10s";
    sleep 10;


}
closedir $dir;
