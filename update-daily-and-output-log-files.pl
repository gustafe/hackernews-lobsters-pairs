#! /usr/bin/env perl
use Modern::Perl '2015';
use Time::HiRes  qw/gettimeofday tv_interval/;
use HNLOlib qw/$feeds/;
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
#open( my $fh, ">>", "$BIN/Logs/$filename");
for my $tag (qw/lo hn /) {
    open( my $fh, ">>", "$BIN/Logs/$tag-insert.log");
    my $cmd ="perl -I $BIN  $BIN/$feeds->{$tag}->{bin_prefix}".'-get-new-items-load-store.pl';
    my $output= `$cmd`;
    print $fh $output;
    close $fh;
}
#
