#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;
use JSON;
use Template;
use DateTime;
use DateTime::Format::Strptime;
use Encode;
use URI::Escape qw/uri_escape_utf8/;
use HNLtracker qw/get_dbh get_ua/;
binmode STDOUT, ':utf8';
#binmode STDERR, ':utf8';
my $debug = 0;

#use open IO => ':utf8';
my $update_score;
GetOptions( 'update_score' => \$update_score );

say "we will update scores" if $update_score;

my $sql = {get_pairs=>qq/select hn.url, 
strftime('%s',lo.created_time)-strftime('%s',hn.created_time),
hn.id,
hn.created_time,
hn.title, hn.submitter,hn.score, hn.comments,
lo.id,
strftime('%Y-%m-%d %H:%M:%S',lo.created_time),
lo.title, lo.submitter,lo.score, lo.comments
from hackernews hn
inner join lobsters lo
on lo.url = hn.url
where hn.url is not null
order by hn.created_time /,
	   update_hn => qq/update hackernews set title=?,score = ?, comments = ? where id = ?/,
	  update_lo => qq/update lobsters set title=?, score=?, comments=? where id = ?/,};

#my $update_hn = qq/update hackernews set score = ?, comments = ? where id = ?/;
#my $update_lo = qq/update lobsters set score=?, comments=? where id = ?/;
my $dbh       = get_dbh();
$dbh->{sqlite_unicode}=1;
my $ua        = get_ua();
my ( $hn_sth, $lo_sth );
if ($update_score) {
    $hn_sth = $dbh->prepare($sql->{update_hn});
    $lo_sth = $dbh->prepare($sql->{update_lo});
}
sub pretty_date;
sub sec_to_human_time;
sub read_new_scores;
sub get_item;
sub hexdump_string {
    my $str = shift;
    my $flag = Encode::is_utf8($str)? 1: 0;
    use bytes;
    my @internal_rep_bytes = unpack('C*', $str);
    return $flag . '('.join(' ',map {sprintf("%02x", $_) } @internal_rep_bytes).')';
}

my $parser = DateTime::Format::Strptime->new(
    pattern  => '%Y-%m-%d %H:%M:%S',
    on_error => 'croak'
);

### CODE ###

my $sth = $dbh->prepare($sql->{get_pairs});
$sth->execute;

my @pairs;
my @hn_updates;
my @lo_updates;
my %seen;
my ( $total_count, $hn_count, $lo_count ) = ( 0, 0, 0 );
while ( my @r = $sth->fetchrow_array ) {

    my $pair;
    my $lobsters;
    my $hackernews;
    $pair->{url} = $r[0];

    # we do this to exclude any later submissions to HN with the same URL
    if ( !exists $seen{ $pair->{url} } ) {
        $seen{ $pair->{url} }++;
    }
    else {
        next;
    }

    my $diff = $r[1];
    $pair->{diff} = sec_to_human_time( abs($diff) );
    $hackernews = {
        id        => $r[2],
        time      => $r[3],
        title     => $r[4],
        submitter => $r[5],
        score     => $r[6],
        comments  => $r[7]
    };
    $lobsters = {
        id        => $r[8],
        time      => $r[9],
        title     => $r[10],
        submitter => $r[11],
        score     => $r[12],
        comments  => $r[13]
		};

    if ($debug and ($lobsters->{id} eq 'haeedo' or $hackernews->{id} == 20374873)) {
	foreach my $hash ($lobsters, $hackernews) {
	    say $hash->{id};
	    say $hash->{title};
	    say hexdump_string( $hash->{title} );
	}
    }
    $hackernews->{title_href} =
      "https://news.ycombinator.com/item?id=" . $hackernews->{id};
    $lobsters->{title_href} = "https://lobste.rs/s/" . $lobsters->{id};

    $hackernews->{submitter_href} =
      'https://news.ycombinator.com/user?id=' . $hackernews->{submitter};
    $lobsters->{submitter_href} =
      'https://lobste.rs/u/' . $lobsters->{submitter};
    my $dt_today = DateTime->today();
    $hackernews->{dt} = $parser->parse_datetime( $hackernews->{time} )->truncate(to=>'day');
    $lobsters->{dt}   = $parser->parse_datetime( $lobsters->{time} )->truncate(to=>'day');
    
   
#    say "$hackernews->{title} $hackernews->{id} ", $hackernews->{dt};
#    say "$lobsters->{title} $lobsters->{id} ",$lobsters->{dt};
    if ($update_score) {

	my $hn_update = get_item( 'https://hacker-news.firebaseio.com/v0/item/' . $hackernews->{id} . '.json');
	
	if (defined $hn_update) {
	    # should we delete?
	    if (!defined $hn_update->{title}) { # assume deleted
		$pair->{is_deleted} += 1;
		say $hackernews->{href};
		say "delete from hackernews where id=$hackernews->{id}";
	    }
	    elsif ($hn_update->{title} ne $hackernews->{title} or
		     $hn_update->{score} != $hackernews->{score} or
		     $hn_update->{descendants} != $hackernews->{comments})  {
		say "update queued for $hackernews->{id}";
		say "T: $hackernews->{title} -> $hn_update->{title}";
		say "S: $hackernews->{score} -> $hn_update->{score}";
		say "C: $hackernews->{comments} -> $hn_update->{descendants}";
		push @hn_updates, [$hn_update->{title},
				   $hn_update->{score},
				   $hn_update->{descendants},
				   $hackernews->{id}];
		$hackernews->{title} = $hn_update->{title};
		$hackernews->{score} = $hn_update->{score};
		$hackernews->{comments} = $hn_update->{descendants};
	    }
	}

        my $lo_update = get_item('https://lobste.rs/s/' . $lobsters->{id} . '.json' );
	if ( defined $lo_update) {
	    if (!defined $lo_update->{title}) {
		$pair->{is_deleted}++;
		say $lobsters->{href};
		say "delete from lobsters where id = '".$lobsters->{id}."'";
	    } elsif ($lo_update->{title} ne $lobsters->{title} or
		     $lo_update->{score} != $lobsters->{score} or
		     $lo_update->{comment_count} != $lobsters->{comments} ){
		say "update queued for $lobsters->{id}";
		say "T: $lobsters->{title} -> $lo_update->{title}";
		say "S: $lobsters->{score} -> $lo_update->{score}";
		say "C: $lobsters->{comments} -> $lo_update->{comment_count}";

		push @lo_updates, [$lo_update->{title},
				   $lo_update->{score},
				   $lo_update->{comment_count},
				   $lobsters->{id}];
		$lobsters->{title} = $lo_update->{title};
		$lobsters->{score} = $lo_update->{score};
		$lobsters->{comments} = $lo_update->{comment_count};

	    }
	}
    }
	

    # comment/score ratio
    if ( $lobsters->{score} >0 and $lobsters->{comments} + $lobsters->{score} > 9 ) {
	
        $lobsters->{ratio} =
          sprintf( "%.02f", $lobsters->{comments} / $lobsters->{score} );
    }
    if ( $lobsters->{score} > 0 and $hackernews->{comments} + $hackernews->{score} > 9 ) {

        $hackernews->{ratio} =
          sprintf( "%.02f", $hackernews->{comments} / $hackernews->{score} );
    }

    my ( $first, $then );
    if ( $diff < 0 ) {
        $pair->{first} = $lobsters;
        $pair->{first}->{site} = 'Lobste.rs';

        $pair->{then}         = $hackernews;
        $pair->{then}->{site} = 'Hackernews';
        $pair->{logo}         = 'lo_hn.png';
        $lo_count++;
    }
    else {
        $pair->{first}         = $hackernews;
        $pair->{first}->{site} = 'Hackernews';
        $pair->{then}          = $lobsters;
        $pair->{then}->{site}  = 'Lobste.rs';
        $pair->{logo}          = 'hn_lo.png';
        $hn_count++;
    }
    $pair->{heading} =
      "<a href='" . $pair->{url} . "'>" . $pair->{first}->{title} . '</a>';
    $pair->{first}->{pretty_date} = join( ' ',
        $pair->{first}->{dt}->day(),
        $pair->{first}->{dt}->month_abbr(),
        $pair->{first}->{dt}->year() );

    push @pairs, $pair;
    $total_count++;
}
$sth->finish;
# we want reverse chronological order
@pairs = reverse @pairs;
my $now  = gmtime;
my %data = (
    pairs => \@pairs,
    meta  => {
        generate_time => $now,
        total         => $total_count,
        hn_count      => $hn_count,
        lo_count      => $lo_count
    },
);
my $tt =
  Template->new( { INCLUDE_PATH => '/home/gustaf/prj/HN-Lobsters-Tracker' } );
#$tt->process('header.tt') || die $tt->error;
$tt->process( 'page.tt', \%data, '/home/gustaf/public_html/hnlo/index.html',{binmode=>':utf8'} ) || die $tt->error;
#$tt->process('footer.tt') || die $tt->error;

# update DB
if (scalar @hn_updates>0) {
    say "updating Hackernews...";
    my $sth = $dbh->prepare( $sql->{update_hn} ) or die $dbh->errstr;
    foreach my $update (@hn_updates) {
	my $rv = $sth->execute( @{$update} ) or warn $sth->errstr;
    }
    $sth->finish;
}
if (scalar @lo_updates>0) {
    say "updating Lobsters...";
    my $sth = $dbh->prepare( $sql->{update_lo} ) or die $dbh->errstr;
    foreach my $update (@lo_updates) {
	my $rv = $sth->execute( @{$update} ) or warn $sth->errstr;;
    }
    $sth->finish;
}

### SUBS

sub sec_to_human_time {
    my ($sec) = @_;
    my $days = int( $sec / ( 24 * 60 * 60 ) );
    my $hours   = ( $sec / ( 60 * 60 ) ) % 24;
    my $mins    = ( $sec / 60 ) % 60;
    my $seconds = $sec % 60;
    my $out;
    if ( $days > 0 ) {
        if ( $days == 1 ) {
            $out .= '1 day';
        }
        else {
            $out .= "$days days";
        }
	return $out; 
    }
    if ($hours == 0 and $mins == 0 ) {
	return "less than a minute";
    }

    $out .= $hours > 0 ? $hours . 'h' : '';
    $out .= $mins . 'm' ;

    return $out;
}

sub get_item {
    # IN: URL for API
    # OUT: JSON object on success, otherwise undef

    my ( $href ) = @_;
    my $r = $ua->get( $href );
    return undef unless $r->is_success();

    my $json = decode_json( $r->decoded_content());
    return $json;
}

__END__
sub read_new_scores {

    # IN: source {hackernews|lobsters}, id
    # OUT: hashref new score and comments, undef on failure

    my ( $source, $id ) = @_;
    my $href;
    my $out = undef;
    if ( $source eq 'hackernews' ) {
        $href = 'https://hacker-news.firebaseio.com/v0/item/' . $id . '.json';
        my $res = $ua->get($href);
        last unless $res->is_success;
        my $data = decode_json( $res->decoded_content );
        $out = { score => $data->{score}, comments => $data->{descendants} };
        my $rv = $hn_sth->execute( $data->{score}, $data->{descendants}, $id )
          or warn $hn_sth->errstr;
    }
    elsif ( $source eq 'lobsters' ) {
        $href = 'https://lobste.rs/s/' . $id . '.json';
        my $res = $ua->get($href);
        last unless $res->is_success;
        my $data = decode_json( $res->decoded_content );
        $out = { score => $data->{score}, comments => $data->{comment_count} };
        my $rv = $lo_sth->execute( $data->{score}, $data->{comment_count}, $id )
          or warn $lo_sth->errstr;
    }
    else {
        die "can't parse source: $source";
    }
    return $out;
}
