#! /usr/bin/env perl
use Modern::Perl '2015';
use Time::HiRes  qw/gettimeofday tv_interval/;
use HNLOlib qw/$feeds/;
#$t0 = [gettimeofday];
#      ($seconds, $microseconds) = gettimeofday;
#      $elapsed = tv_interval ( $t0, [$seconds, $microseconds]);
#      $elapsed = tv_interval ( $t0, [gettimeofday]);
#      $elapsed = tv_interval ( $t0 );

###
sub sec_to_dhms {
    my ($sec) = @_;
    my $days = int( $sec / ( 24 * 60 * 60 ) );
    my $hours   = ( $sec / ( 60 * 60 ) ) % 24;
    my $mins    = ( $sec / 60 ) % 60;   
    my $seconds = $sec % 60;

    my $out;
    $out = sprintf("%dD", $days) if $days;
    $out .= sprintf("%02d:", $hours?$hours:0);
    $out .= sprintf("%02d:",$mins?$mins:0) ;
    $out .= sprintf("%02d",$seconds?$seconds:0);
    return $out;
}
my $today = DateTime->now();
my $filename= sprintf("%04d-%02d-%02dT%02dZ", map{$today->$_}qw/year month day hour/);

my $HOME = '/home/gustaf';
my $BIN = $HOME.'/prj/HN-Lobsters-Tracker';
my $t0 = [gettimeofday];
#say "==> outputting to $BIN/Logs/$filename";
open( my $fh, ">>", "$BIN/Logs/$filename");
#printf $fh ("<h2>%s  %02dH UTC</h2>\n", $today->ymd(), $today->hour());
for my $tag (qw/lo hn pr/) {

    my $cmd ="perl -I $BIN  $BIN/$feeds->{$tag}->{bin_prefix}".'-get-new-items-load-store.pl';
#    say $fh "==> getting new items from $feeds->{$tag}->{site}";
    my $output= `$cmd`;

    say $fh $output;
    say $fh "<!-- elapsed time: ", sec_to_dhms(tv_interval($t0)), " -->";
    #    say $fh "Elapsed time: ",sec_to_dhms( tv_interval( $t0));
}
close $fh;
#                my @args = ("command", "arg1", "arg2");
 #               system(@args) == 0
  #                  or die "system @args failed: $?";


#my @cmd=('perl', '-I', "$BIN",  "$BIN/generate-hourly.pl");
#system( @cmd ) == 0 or die "system @cmd failed: $?";
#say "Elapsed time: ",sec_to_dhms( tv_interval( $t0));

