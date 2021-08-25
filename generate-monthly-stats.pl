#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use DateTime;
use Template;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use utf8;
use DateTime::Format::Strptime qw/strftime strptime/;
use Data::Dump qw/dd/;
use HNLOlib qw/get_dbh get_all_sets $feeds update_scores $sql/;
use List::Util qw/all/;


binmode(STDOUT, ":encoding(UTF-8)");
use open qw/ :std :encoding(utf8) /;
sub usage;

my $update_score;
my $target_month;
#my $dump_output;
GetOptions(
    'update_score'   => \$update_score,
	   'target_month=i' => \$target_month,
#	   dump_output=> \$dump_output,
);
my ( $year, $month ) =( 1980, 1);


usage unless defined $target_month;
usage unless $target_month =~ m/\d{6}/;
( $year, $month ) = $target_month =~ m/(\d{4})(\d{2})/;
usage unless ( $month >= 1 and $month <= 12 );

my $from_dt = DateTime->new(
    year   => $year,
    month  => $month,
    day    => 1,
    hour   => 0,
    minute => 0,
    second => 0
);
my $to_dt = DateTime->last_day_of_month(
    year   => $year,
    month  => $month,
    hour   => 23,
    minute => 59,
    second => 59
);
my @epoch_range = map { $_->strftime('%s') } ( $from_dt, $to_dt );
my @iso_range = map { $_->strftime('%Y-%m-%d %H:%M:%S') } ( $from_dt, $to_dt );
### Definitions and constants
my $debug = 0;
my $page_title =
  "HN&amp;&amp;LO monthly stats for " . $from_dt->month_name . " $year";

#my $no_of_days_to_show = 3;
my $ratio_limit = 9;

my $ua;

my $dbh = get_dbh;
my $tt =
  Template->new( { INCLUDE_PATH => "$Bin/templates",ENCODING=>'UTF-8' } );

$dbh->{sqlite_unicode} = 1;

#### CODE ####

my $now = time();

# get all pairs from the DB
my $sth  = $dbh->prepare( $sql->{get_pairs} );
my $sets = get_all_sets($sth);

# filter entries older than the retention time

my @pairs;
my ( $min_hn_id, $max_hn_id) = (27_076_741+10_000_000,-1);
foreach my $url (
    sort { $sets->{$a}->{first_seen} <=> $sets->{$b}->{first_seen} }
    keys %{$sets}
  )
{

    if (
        all {
            $_->{time} <= $epoch_range[0]
              or $_->{time} >= $epoch_range[1]
        }
        @{ $sets->{$url}->{sequence} }
       )
    {
        next;
    }

    # only include entries that are max 3 days older than the start of the range
    if ( $sets->{$url}->{sequence}->[0]->{time} <=
        ( $epoch_range[0] - ( 3 * 24 * 3600 ) ) )
    {
        next;
    }
    for (@{$sets->{$url}->{sequence}}) {
	if ($_->{tag} eq 'hn') {
	    if ($_->{id}>$max_hn_id) { $max_hn_id=$_->{id}	    }
	    if ($_->{id}<$min_hn_id) { $min_hn_id=$_->{id} }
	}
    }

    push @pairs, $sets->{$url};
}

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

# gather stats

my %stats;
my %dates;
$stats{pair_count} = scalar @pairs;

foreach my $tag ( keys %{$feeds} ) {
    $sth = $dbh->prepare( "select count(*) from $feeds->{$tag}->{table_name} where url is not null and created_time between ? and ?" ) or die $dbh->errstr;
    $sth->execute(@iso_range);
    my $rv = $sth->fetchrow_arrayref();
    $stats{total}->{$tag} = $rv->[0];

}

foreach my $pair (@pairs) {

    next unless ( defined $pair->{sequence} );
    my $chain = join(' &xrarr; ',map {$_->{site}} @{$pair->{sequence}});
    $stats{chains}->{$chain}++;
#    say "$pair->{heading} ", join('-', @chain) if scalar @chain == 1;
    foreach my $item ( @{ $pair->{sequence} } ) {
        my $ratio = undef;
        if ( $item->{score} != 0
            and ( abs($item->{score}) + $item->{comments} > $ratio_limit ) )
        {
            $ratio = sprintf( '%.02f', $item->{comments} / abs($item->{score}) );

        } elsif ($item->{score}==0 and $item->{comments} > $ratio_limit) {
	    $ratio = 100
	}
        $item->{ratio} = $ratio if defined $ratio;
	if ($item->{tag} eq 'hn' and $ranks{$item->{id}}) {
	    $item->{rank} = $ranks{$item->{id}}
	}

        # don't count the item unless it's in the date range
        next
          unless ( $item->{time} >= $epoch_range[0]
            and $item->{time} <= $epoch_range[1] );

        # we will double-count here sometimes?
        $stats{submitters}->{ $item->{tag} }->{ $item->{submitter} }->{count}++;
        $stats{submitters}->{ $item->{tag} }->{ $item->{submitter} }->{href} =
          $item->{submitter_href};

        $stats{first}->{ $item->{tag} }++ if $item->{first};
        $stats{count}->{ $item->{tag} }++;
    }

    $stats{domains}->{ $pair->{domain} }++;
    warn "can't parse date for $pair->{heading_url} "
      unless defined $pair->{sequence}->[0]->{timestamp};
    my $posted_day = ( split( ' ', $pair->{sequence}->[0]->{timestamp} ) )[0];

    my $display_date =
      strftime( '%A, %d %b %Y', strptime( '%F', $posted_day ) );

    push @{ $dates{$posted_day}->{pairs} }, $pair;
    $dates{$posted_day}->{display_date} = $display_date;

}
my $max_subs = 5;
my %submitters;
foreach my $tag ( 'hn', 'lo', 'pr' ) {
    my $count = 0;

    # gather all submitters with the same submit count
    foreach my $name (

        sort {
            $stats{submitters}->{$tag}->{$b}->{count}
              <=> $stats{submitters}->{$tag}->{$a}->{count}
              || $a cmp $b
        } keys %{ $stats{submitters}->{$tag} }
      )
    {
        push
          @{ $submitters{$tag}->{ $stats{submitters}->{$tag}->{$name}->{count} }
          },
          sprintf( '<a href="%s">%s</a>',
            $stats{submitters}->{$tag}->{$name}->{href}, $name );
        $count++;
    }

    # filter the results, collapse the larger lists
    foreach my $rank ( keys %{ $submitters{$tag} } ) {
        if ( scalar @{ $submitters{$tag}->{$rank} } > 9 ) {
            @{ $submitters{$tag}->{$rank} } =
              ( scalar @{ $submitters{$tag}->{$rank} } . " submitters" );

        }
        else {
            @{ $submitters{$tag}->{$rank} } =
              ( join( ', ', @{ $submitters{$tag}->{$rank} } ) );
        }
    }
}

my @domains;

foreach my $domain (
    sort { $stats{domains}->{$b} <=> $stats{domains}->{$a} || $a cmp $b }
    keys %{ $stats{domains} }
  )
{
    next if $stats{domains}->{$domain} <= 2;
    push @domains, { domain => $domain, count => $stats{domains}->{$domain} };
}
my $sites = { map { $_, $feeds->{$_}->{site} } qw/hn lo pr/ };

my $count = 0;
my $sum = 0;
my @chains;
foreach my $chain (sort {

    $stats{chains}->{$b} <=> $stats{chains}->{$a} || $a cmp $b }
		   keys %{$stats{chains}}) {
    if ($count<10 and $stats{chains}->{$chain}>1) {
	push @chains, sprintf("%s - %d",$chain , $stats{chains}->{$chain});
    } else {
	$sum += $stats{chains}->{$chain};
    }
    $count++;

}
push @chains, sprintf("%s - %d", "Others", $sum);
# generate the page from the data
my $dt_now =
  DateTime->from_epoch( epoch => $now, time_zone => 'Europe/Stockholm' );
my %data = (
    dates      => \%dates,
    stats      => \%stats,
    submitters => \%submitters,
	    domains    => \@domains,
	    chains=>\@chains,
    meta       => {
        generate_time => $dt_now->strftime('%Y-%m-%d %H:%M:%S%z'),
        page_title    => $page_title,

        #        no_of_days_to_show => $no_of_days_to_show,
        ratio_limit => $ratio_limit,
    },
    sites => $sites,

	   );

$tt->process(
    'monthly.tt', \%data,
    '/home/gustaf/public_html/hnlo/' . $year . '-' . $month . '.html',
    { binmode => ':utf8' }
) || die $tt->error;

### SUBS ###

sub usage {
    say "usage: $0 [--update_score] --target_month=YYYYMM";
    exit 1;
}
