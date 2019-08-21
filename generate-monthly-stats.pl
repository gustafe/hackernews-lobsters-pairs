#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use DateTime;
use Template;
use DateTime::Format::Strptime qw/strftime strptime/;
use Data::Dumper;
use HNLOlib qw/get_dbh get_all_sets $feeds update_scores $sql/;
use List::Util qw/all/;
use open qw/ :std :encoding(utf8) /;
sub usage;

my $update_score;
my $target_month;
GetOptions( 'update_score' => \$update_score, 'target_month=i'=>\$target_month );

usage unless defined $target_month;
usage unless $target_month =~ m/\d{6}/;
my ( $year, $month ) = $target_month =~ m/(\d{4})(\d{2})/;
usage unless ($month >=1  and $month<=12);


my $from_dt = DateTime->new(year=>$year,month=>$month,day=>1,hour=>0,minute=>0,second=>0);
my $to_dt = DateTime->last_day_of_month(year=>$year, month=>$month,hour=>23,minute=>59,second=>59);


### Definitions and constants
my $debug              = 0;
my $page_title         = "HN&amp;&amp;LO monthly stats for ".$from_dt->month_name." $year";
#my $no_of_days_to_show = 3;
my $ratio_limit        = 9;

my $ua;

my $dbh = get_dbh;
$dbh->{sqlite_unicode} = 1;

#### CODE ####

my $now   = time();
# get all pairs from the DB
my $sth = $dbh->prepare( $sql->{get_pairs} );
my $sets = get_all_sets($sth) ;

# filter entries older than the retention time

my @pairs;
foreach my $url (sort { $sets->{$a}->{first_seen} <=> $sets->{$b}->{first_seen} }
		 keys %{$sets}) {
    #    if ($sets->{$url}->{first_seen} <= $from_dt->strftime('%s') or	$sets->{$url}->{first_seen} >= $to_dt->strftime( '%s' )) {
    if ( all {$_->{time}<=$from_dt->strftime('%s') or
	      $_->{time}>=$to_dt->strftime('%s') } @{$sets->{$url}->{sequence}}) {
	next;
    }
    push @pairs, $sets->{$url};
}

# update items if that option is set

if ($update_score) {
    @pairs = @{update_scores($dbh, \@pairs)};
}

# gather stats

my %stats;
my %dates;
$stats{pair_count} = scalar @pairs;
if ($debug) {
    say $from_dt->strftime('%Y-%m-%d %H:%M:%S');
    say $to_dt->strftime('%Y-%m-%d %H:%M:%S');
}
foreach my $tag (keys %{$feeds}) {
    if ($debug ) {      say $tag;
    say $sql->{'get_'.$tag.'_count'};
   }
    $sth = $dbh->prepare( $sql->{'get_'.$tag.'_count'} );
    $sth->execute($from_dt->strftime('%Y-%m-%d %H:%M:%S'),
		 $to_dt->strftime('%Y-%m-%d %H:%M:%S'));
    my $rv = $sth->fetchrow_arrayref();
    $stats{total}->{$tag} = $rv->[0];

}
print Dumper \@pairs if $debug;

foreach my $pair (@pairs) {
    #    next if ( exists $pair->{}->{deleted} or exists $pair->{then}->{deleted});
#
    next unless ( defined $pair->{sequence});
    foreach my $item ( @{$pair->{sequence}} ) {
	#        my $item  = $pair->{$seq};
	# we will double-count here sometimes
	$stats{submitters}->{$item->{tag}}->{$item->{submitter}}++;

        my $ratio = undef;
        if ( $item->{score} > 0
            and ( $item->{score} + $item->{comments} > $ratio_limit ) )
        {
            $ratio = sprintf( '%.02f', $item->{comments} / $item->{score} );

        }
        $item->{ratio} = $ratio if defined $ratio;
	$stats{first}->{$item->{tag}}++ if $item->{first};
    }
    $stats{domains}->{$pair->{domain}}++;
    warn "can't parse date for $pair->{heading_url} " unless defined $pair->{sequence}->[0]->{timestamp};
    my $posted_day = (split(' ',$pair->{sequence}->[0]->{timestamp}))[0];
    #    my ( $year, $month, $day ) = split('-',$posted_day);
#    my $strp = DateTime::Format::Strptime->new(pattern=>'%F');
#    my $dt = strptime('%F',$posted_day);
    my $display_date = strftime('%A, %d %b %Y', strptime('%F',$posted_day));
#    say $display_date;
    push @{$dates{$posted_day}->{pairs}}, $pair;
    $dates{$posted_day}->{display_date} = $display_date;
    

}
my $max_subs= 5;
my %submitters;
foreach my $tag ('hn','lo') {
    my $count = 0;
    foreach my $name (sort { $stats{submitters}->{$tag}->{$b} <=>
			       $stats{submitters}->{$tag}->{$a} || $a cmp $b
			   } keys %{$stats{submitters}->{$tag}}) {
	next if $count > $max_subs;
	push @{$submitters{$tag}}, {name=>$name,count=>$stats{submitters}->{$tag}->{$name}};
	$count++;
    }
}
my @domains;

foreach my $domain (sort {$stats{domains}->{$b}<=>$stats{domains}->{$a}} keys %{$stats{domains}}) {
    next if $stats{domains}->{$domain} <= 2;
    push @domains, {domain=>$domain,count=> $stats{domains}->{$domain}};
}


# generate the page from the data
my $dt_now =
  DateTime->from_epoch( epoch => $now, time_zone => 'Europe/Stockholm' );
my %data = (
	    dates => \%dates,
	    stats=>\%stats,
	    submitters=>\%submitters,
	    domains=>\@domains,
    meta  => {
        generate_time      => $dt_now->strftime('%Y-%m-%d %H:%M:%S%z'),
        page_title         => $page_title,
#        no_of_days_to_show => $no_of_days_to_show,
        ratio_limit        => $ratio_limit,
    },

);
my $tt =
  Template->new( { INCLUDE_PATH => '/home/gustaf/prj/HN-Lobsters-Tracker' } );

$tt->process(
    'monthly.tt', \%data,
    '/home/gustaf/public_html/hnlo/'.$year.'-'.$month.'.html',
    { binmode => ':utf8' }
) || die $tt->error;

### SUBS ###

sub usage {
    say "usage: $0 [--update_score] --target_month=YYYYMM";
    exit 1;
}
__END__
foreach my $tag ('hn','lo') {
    my %rankings;
    foreach my $user (sort {$stats{submitters}->{$tag}->{$b} <=>
			      $stats{submitters}->{$tag}->{$a} ||
			      $a cmp $b }
		      keys %{$stats{submitters}->{$tag}}) {
	#	say "$tag $user $stats{submitters}->{$tag}->{$user}";
	push @{$rankings{$stats{submitters}->{$tag}->{$user}}}, $user;
    }
    foreach my $rank (sort {$b<=>$a} keys %rankings) {
	say "$rank ", join(',', @{$rankings{$rank}});
    }

}
