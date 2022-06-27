#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;

use Template;
use FindBin qw/$Bin/;
use utf8;
use Time::HiRes  qw/gettimeofday tv_interval/;
use Data::Dumper;
use HNLOlib qw/get_dbh get_all_sets $feeds update_scores $sql sec_to_dhms/;
use List::Util qw/all/;
use open qw/ :std :encoding(utf8) /;
binmode(STDOUT, ":encoding(UTF-8)");
my $update_score;
GetOptions( 'update_score' => \$update_score );

### Definitions and constants
my $debug              = 0;
my $page_title         = 'HN&amp;&amp;LO recent links';
my $no_of_days_to_show = 3;
my $ratio_limit        = 9;

my $ua;

my $dbh = get_dbh;
$dbh->{sqlite_unicode} = 1;

#### CODE ####
my $now=time();
my $t0 = [gettimeofday];
my $generation_log;
say gmtime . " starting, fetching 10d data... " if $debug;
# get all pairs from the DB
my $sth = $dbh->prepare( $sql->{get_pairs_10d} );
my %sets = %{ get_all_sets($sth) };
say gmtime . " got all sets... " if $debug;
$generation_log .= " got all sets after " .sec_to_dhms(tv_interval($t0));
# coerce into list
# filter entries older than the retention time
my @pairs;
my $limit_seconds = $no_of_days_to_show * 24 * 3600;
my ( $min_hn_id, $max_hn_id) = (27_076_741+10_000_000,-1);
foreach my $url (sort {$sets{$b}->{first_seen} <=> $sets{$a}->{first_seen}} keys %sets) {

    next if all {$now - $_->{time}>$limit_seconds } @{$sets{$url}->{sequence}};

    # filter single entries

    next unless exists $sets{$url}->{sequence};
    for (@{$sets{$url}->{sequence}}) {
	if ($_->{tag} eq 'hn') {
	    if ($_->{id}>$max_hn_id) { $max_hn_id=$_->{id}	    }
	    if ($_->{id}<$min_hn_id) { $min_hn_id=$_->{id} }
	}
    }
    push @pairs, $sets{$url};
}
say gmtime . " got all pairs... " if $debug;
$generation_log .= " got all pairs after " .sec_to_dhms(tv_interval($t0));
$sth=$dbh->prepare($sql->{rank_sql});
$sth->execute( $min_hn_id, $max_hn_id);
my $hn_rank = $sth->fetchall_arrayref();
my %ranks;
for my $row (@$hn_rank) {
    if (exists $ranks{$row->[0]}) {
	$ranks{$row->[0]} = $row->[1] if $row->[1] < $ranks{$row->[0]}
    } else {
	$ranks{$row->[0]} = $row->[1]
    }
}

# update items if that option is set

if ($update_score) {
    my $list_of_ids;
    foreach my $pair (@pairs) {
	foreach my $entry (@{$pair->{sequence}}) {
	    push @{$list_of_ids->{$entry->{tag}}} ,$entry->{id};
	    
	}
    }
    foreach my $label (sort keys %{$list_of_ids}) {
	say "updating entries from $label. No. of IDs: ", scalar @{$list_of_ids->{$label}};
		HNLOlib::update_from_list( $label, $list_of_ids->{$label} );
    }
}

# calculate scores

foreach my $pair (@pairs) {
    foreach my $item (@{$pair->{sequence}}) {

        my $ratio = undef;
        if ( $item->{score} != 0
            and ( abs($item->{score}) + $item->{comments} > $ratio_limit ) )
        {
            $ratio = sprintf( '%.02f', $item->{comments} / abs($item->{score}) );
	    
        } elsif ($item->{score}==0 and $item->{comments} > $ratio_limit) {
	    $ratio = 100
	}
        $item->{ratio} = $ratio if defined $ratio;
	if ($item->{tag} eq 'hn' and $ranks{$item->{id}} ) {
	    $item->{rank} = $ranks{$item->{id}}
	}

    }
}
say gmtime . " got all scores... " if $debug;
$generation_log .= " got all scores and done after " .sec_to_dhms(tv_interval($t0));
# clean up data for presentation
$now= time();
# generate the page from the data
my $dt_now =
  DateTime->from_epoch( epoch => $now, time_zone => 'Europe/Stockholm' );
my $elapsed = sec_to_dhms(tv_interval($t0));
my %data = (
    pairs => \@pairs,
    meta  => {
        generate_time      => $dt_now->strftime('%Y-%m-%d %H:%M:%S%z'),
        page_title         => $page_title,
        no_of_days_to_show => $no_of_days_to_show,
	      ratio_limit        => $ratio_limit,
	      generation_log => $generation_log,
    },

);
my $tt =
  Template->new( { INCLUDE_PATH => "$Bin/templates",ENCODING=>'UTF-8' } );

$tt->process(
    'hourly.tt', \%data,
    '/home/gustaf/public_html/hnlo/index.html',
    { binmode => ':utf8' }
) || die $tt->error;
say gmtime . " generated page, done. " if $debug;
