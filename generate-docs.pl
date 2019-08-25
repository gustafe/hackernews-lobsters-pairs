#! /usr/bin/env perl
use Modern::Perl '2015';
###
use DateTime;
use Template;
use HNLOlib qw/$feeds/;
my $now = time();
my $dt_now =
  DateTime->from_epoch( epoch => $now, time_zone => 'Europe/Stockholm' );


my %data= (meta => { page_title=>'About HN&amp;&amp;LO',
        generate_time => $dt_now->strftime('%Y-%m-%d %H:%M:%S%z'),
		 });

my $tt =
  Template->new( { INCLUDE_PATH => '/home/gustaf/prj/HN-Lobsters-Tracker' } );

$tt->process(
    'about.tt', \%data,
    '/home/gustaf/public_html/hnlo/about.html',
    { binmode => ':utf8' }
) || die $tt->error;
