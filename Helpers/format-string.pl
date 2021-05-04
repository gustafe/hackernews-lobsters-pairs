#! /usr/bin/env perl
use Modern::Perl '2015';
use utf8;      # so literals and identifiers can be in UTF-8
use open ':std', ':encoding(UTF-8)';
###

# [24.3%] 20185203 Hackers Infect Businesses with CryptoMiners Using NSA Leaked Tools [hsnewman 3 0]

my $pre = 8+10;
my $submitter = length('hsnewman');
my $score= length(3);
my $comment = length( 0 );
my $post = 2+ $submitter + 1+$score + 1 + $comment;
my $title = 'Hackers Infect Businesses with CryptoMiners Using NSA Leaked Tools';
#$title = 'short title';
my $ellipsis = "\x{2026}";
my $space = 80 - $pre - $post;
if (length( $title) >$space) {
    $title = substr($title, 0, $space-1) . $ellipsis;
}

printf("[%4.1f%%] %d %-*s [%s %d %d]\n",
       24.3, 20185203, $space,$title,'hsnewman', 3 ,0);
