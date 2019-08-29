#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;

use Template;
use Data::Dumper;
use HNLOlib qw/get_dbh get_all_sets $feeds update_scores $sql/;
use List::Util qw/all/;
use open qw/ :std :encoding(utf8) /;

my $update_score;
GetOptions( 'update_score' => \$update_score );

### Definitions and constants
my $debug              = 1;
my $page_title         = 'HN&amp;&amp;LO';
my $no_of_days_to_show = 3;
my $ratio_limit        = 9;

my $ua;

my $dbh = get_dbh;
$dbh->{sqlite_unicode} = 1;

#### CODE ####

my $now   = time();
# get all pairs from the DB
my $sth = $dbh->prepare( $sql->{get_pairs} );
my %sets = %{ get_all_sets($sth) };
# coerce into list
# filter entries older than the retention time
my @pairs;
my $limit_seconds = $no_of_days_to_show * 24 * 3600;

foreach my $url (sort {$sets{$b}->{first_seen} <=> $sets{$a}->{first_seen}} keys %sets) {
    #    next if ( $now - $sets{$url}->{first_seen} > $limit_seconds );
    next if all {$now - $_->{time}>$limit_seconds } @{$sets{$url}->{sequence}};
    # filter single entries
    #    next unless @{$sets{$url}->{sequence}}>1;
    next unless exists $sets{$url}->{sequence};
    push @pairs, $sets{$url};
    
}

# update items if that option is set

if ($update_score) {
    my $list_of_ids;
    #    @pairs = @{update_scores($dbh, \@pairs)};
    foreach my $pair (@pairs) {
	foreach my $entry (@{$pair->{sequence}}) {
#	    print Dumper $entry if $debug;
	    push @{$list_of_ids->{$entry->{tag}}} ,$entry->{id};
	    
	}
    }
#    print Dumper $list_of_ids;
    foreach my $label (sort keys %{$list_of_ids}) {
	say "updating entries from $label. No. of IDs: ", scalar @{$list_of_ids->{$label}};
		HNLOlib::update_from_list( $label, $list_of_ids->{$label} );
	#print Dumper $label;
#	print Dumper $list_of_ids->{$label};
    }
}

# calculate scores

foreach my $pair (@pairs) {
    foreach my $item (@{$pair->{sequence}}) {

#        my $item  = $pair->{entries}->{$ts};
        my $ratio = undef;
        if ( $item->{score} > 0
            and ( $item->{score} + $item->{comments} > $ratio_limit ) )
        {
            $ratio = sprintf( '%.02f', $item->{comments} / $item->{score} );

        }
        $item->{ratio} = $ratio if defined $ratio;

    }
}

# clean up data for presentation

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
  Template->new( { INCLUDE_PATH => '/home/gustaf/prj/HN-Lobsters-Tracker' } );

$tt->process(
    'hourly.tt', \%data,
    '/home/gustaf/public_html/hnlo/index.html',
    { binmode => ':utf8' }
) || die $tt->error;


### SUBS ###

__END__
foreach my $pair (@pairs) {
#next unless ((scalar keys %{$pair->{entries}}) >2 );

    my @times = sort keys %{$pair->{entries}};
    my @shift = (0, @times);
    my @diffs = (0, map {$times[$_]-$shift[$_]} (1..$#times));

    my $seq_idx = 0;
    foreach my $ts (sort keys %{$pair->{entries}}) {
	my $entry = $pair->{entries}->{$ts};
	if ($seq_idx == 0) {
	    push @{$pair->{sequence}}, {first=>1, %{$entry}} ;
	} else {
	    push @{$pair->{sequence}}, {then=>HNLOlib::sec_to_human_time($diffs[$seq_idx]), %{$entry}};
	}

	$seq_idx++;
    }
    if (scalar @{$pair->{sequence}} == 2) { # we can use our logos
	if ($pair->{sequence}->[0]->{tag} eq 'hn' and $pair->{sequence}->[1]->{tag} eq 'lo') {
	    $pair->{logo} = 'hn_lo.png'
	} else {
	    $pair->{logo} = 'lo_hn.png'
	}
    } else {
	$pair->{logo} = 'multi.png'
    }
    $pair->{anchor} = join('_', map {$pair->{sequence}->[$_]->{id}} (0,1));
}
