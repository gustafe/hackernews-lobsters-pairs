#! /usr/bin/env perl
use Modern::Perl '2015';
###

use DateTime;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use utf8;
use DateTime::Format::Strptime qw/strftime strptime/;
use Data::Dump qw/dd/;
use HNLOlib qw/get_dbh $sql sec_to_dhms/;
use Time::HiRes  qw/gettimeofday tv_interval/;
my $folder = './frontpage-cleanup';
my $dbh;
my ($total_res, $total_time) = (0,0);
my $pause_time=0;
opendir (my $dir, $folder) or die "can't open $folder for listing: $!";
my @sqlfiles = grep {/\.sql$/ && -f "$folder/$_"} readdir($dir);
my $filecount=1;
FILE: while (@sqlfiles) {
    my $t0 = [gettimeofday];
    # pick a file 
    my $file = splice( @sqlfiles, rand @sqlfiles, 1 );
#    printf( "File #%2d working on %s\n", $filecount, $file);
    #    my $filedata = ($file =~ s{^.*/|\.[^.]+$}{}g);
    if ($filecount % 50 == 0) {
	printf "==> %5d files handled, %5d remaining\n", $filecount, scalar @sqlfiles;
#	say "==> $filecount files handled, ".scalar @sqlfiles. " remaining.";
    }
    my ( $id, $expected ) =(split(/\-/, $file))[-2,-1];
    $expected =~ s{^.*/|\.[^.]+$}{}g;
    open( my $fh, "< $folder/$file") or die "can't open $folder/$file for reading: $!";
    my @lines;
    for (<$fh>) {
	chomp;
	push @lines, $_;
    }
    close $fh;
#    say "$id $expected";
    
    my $line_count = scalar @lines;
#    say "file has ", $line_count, " lines";
    my $count=1;
    my $retry=0;
    while (@lines) {
	$dbh=get_dbh;
	my $stmt = shift @lines;
	my $sth = $dbh->prepare( $stmt);
	my ( $id, $rank, $rt );
	if ($stmt=~ m/id\=(\d+).*rank<>(\d+).*read_time<>(.*)$/) {
	    ( $id, $rank, $rt ) = ($1,$2,$3)
	} else {
	    warn "regex failed\n"
	}
	if ($retry) {
	    printf("%3d [%3d/%3d] id=%d rank<>%2d read_time<>%s\n",
		   $retry, $count, $line_count,$id,$rank,$rt);
	} else {
#	    printf("%3s [%3d/%3d] id=%d rank<>%2d read_time<>%s\n",		   ' ',$count, $line_count, $id,$rank,$rt);
	}
	my $res = $sth->execute();
	if ($sth->err) {
	    warn "DBI error: $DBI::err : $DBI::errstr\n";
	    warn sprintf("sleeping for %d s, then taking next file!\n", $pause_time*12*5);
	    sleep (($pause_time==0?5:$pause_time) * 12*5);
	    next FILE; 
	} else {
#	    warn "expected $expected, got $res\n" unless $res==$expected;
	    $count++;
	}
    }
    unlink("$folder/$file") or die "can't unlink $folder/$file: $!";
#    say "$file deleted, ", scalar (@sqlfiles), " remaining";
    my $rc = $dbh->disconnect || warn $dbh->errstr;
    my $elapsed = tv_interval( $t0);
    $total_res += $expected;
    $total_time += $elapsed;
    #    push @times_per_file, [$line_count, $elapsed];
#    say "Lines per second: ". $total_res/$total_time;
    my $remaining_lines =0;

    for my $f (@sqlfiles) {
	if ($f =~ /(\d+)-(\d+).sql$/) {
	    $remaining_lines += $2
	}
    }
    my $processing_time= scalar(@sqlfiles)/($total_res/$total_time);
    $processing_time += $pause_time * scalar( @sqlfiles);
#    say "Time remaining (hours): ", sec_to_dhms( $processing_time );
#    say "sleeping ".$pause_time."s";
#    sleep 10;
    $filecount++;
}
closedir $dir;
