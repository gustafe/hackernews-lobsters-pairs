#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;

use Template;
use FindBin qw/$Bin/;
use HNLtracker qw/get_dbh get_all_pairs $feeds update_scores $sql/;
use utf8;
use open qw/ :std :encoding(utf8) /;
binmode(STDOUT, ":utf8");

my $update_score;
GetOptions( 'update_score' => \$update_score );

### Definitions and constants
my $debug              = 0;
my $page_title         = 'HN&amp;&amp;LO - show links shared between lobste.rs, Hacker News, and Proggit';
my $no_of_days_to_show = 3;
my $ratio_limit        = 9;

my $ua;

my $dbh = get_dbh;
$dbh->{sqlite_unicode} = 1;

#### CODE ####

my $now   = time();
# get all pairs from the DB
my $sth = $dbh->prepare( $sql->{get_pairs} );
my @pairs = @{ get_all_pairs($sth) };

# filter entries older than the retention time
my $limit_seconds = $no_of_days_to_show * 24 * 3600;
@pairs = grep {
    ( $now - $_->{first}->{time} <= $limit_seconds )
      and ( $now - $_->{then}->{time} <= $limit_seconds )
} @pairs;

# update items if that option is set

if ($update_score) {
    @pairs = @{update_scores($dbh, \@pairs)};
}

# calculate scores - we do this at this stage because the scores and
# comments can have been updated

foreach my $pair (@pairs) {
    foreach my $seq ( 'first', 'then' ) {
        my $item  = $pair->{$seq};
        my $ratio = undef;
        if ( $item->{score} > 0
            and ( $item->{score} + $item->{comments} > $ratio_limit ) )
        {
            $ratio = sprintf( '%.02f', $item->{comments} / $item->{score} );

        }
        $pair->{$seq}->{ratio} = $ratio if defined $ratio;

    }
}

# filter deleted stuff, and reverse time order
@pairs =
  grep { !exists $_->{'first'}->{deleted} and !exists $_->{'then'}->{deleted} }
  reverse @pairs;

# generate the page from the data
my $dt_now =
  DateTime->from_epoch( epoch => $now, time_zone => 'Europe/Stockholm' );
my %data = (
    pairs => \@pairs,
    meta  => {
        generate_time      => $dt_now->strftime('%Y-%m-%d %H:%M:%S%z'),
        page_title         => $page_title,
        no_of_days_to_show => $no_of_days_to_show,
        ratio_limit        => $ratio_limit,
    },

);
my $tt =
  Template->new( { INCLUDE_PATH => "$Bin/templates", ENCODING=>'UTF-8' } );

$tt->process(
    'page.tt', \%data,
    '/home/gustaf/public_html/hnlo/index.html',
    { binmode => ':utf8' }
) || die $tt->error;

### SUBS ###

