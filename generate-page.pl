#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;
use JSON;
use Template;
use URI::Escape qw/uri_escape_utf8/;
use HNLtracker qw/get_dbh get_ua/;

my $update_score;
GetOptions( 'update_score' => \$update_score );

warn "we will update scores" if $update_score; 

my $sql = qq/select hn.url,
hn.created_time, strftime('%Y-%m-%d %H:%M:%S',lo.created_time),
strftime('%s',lo.created_time)-strftime('%s',hn.created_time),
hn.title, hn.submitter,
lo.title, lo.submitter,
hn.id, lo.id,
hn.score, hn.comments,
lo.score, lo.comments
from hackernews hn
inner join lobsters lo
on lo.url = hn.url
where hn.url is not null
order by hn.created_time desc	/;

my $update_hn = qq/update hackernews set score = ?, comments = ? where id = ?/;
my $update_lo = qq/update lobsters set score=?, comments=? where id = ?/;
my $dbh= get_dbh();
my $ua = get_ua();
my ( $hn_sth , $lo_sth );
if ($update_score) {
    $hn_sth = $dbh->prepare( $update_hn );
    $lo_sth = $dbh->prepare( $update_lo );
}
sub sec_to_hms;
sub read_new_scores;


my $sth=$dbh->prepare($sql);
$sth->execute;
my @pairs;
while (my @r = $sth->fetchrow_array) {
    my $pair;
    my $lobsters;
    my $hackernews;
    $pair->{url} = $r[0];
    $hackernews->{time}= $r[1];
    $lobsters->{time} = $r[2];
    my $diff = $r[3];
    $pair->{diff} = sec_to_hms(abs($diff));
    $hackernews->{title}= $r[4];

    $hackernews->{submitter} = $r[5];
    $hackernews->{submitter_href} = 'https://news.ycombinator.com/user?id='.$hackernews->{submitter};
    $lobsters->{title}= $r[6];
    $lobsters->{submitter} = $r[7];
    $lobsters->{submitter_href} = 'https://lobste.rs/u/'.$lobsters->{submitter};
    $hackernews->{id} = $r[8];
    $hackernews->{title_href} = "https://news.ycombinator.com/item?id=".$hackernews->{id};
    $lobsters->{id} = $r[9];
    $lobsters->{title_href} = "https://lobste.rs/s/".$lobsters->{id};
    $hackernews->{score}= $r[10];
    $hackernews->{comments}=$r[11];
    $lobsters->{score}=$r[12];
    $lobsters->{comments}=$r[13];
    if ($update_score) {
	warn "updating score for HN id ",$hackernews->{id};
	my $hn_scores = read_new_scores( 'hackernews', $hackernews->{id});
	$hackernews->{score} = $hn_scores->{score};
	$hackernews->{comments}=$hn_scores->{comments};
	warn "updating score for Lobsters id ", $lobsters->{id};
	my $lo_scores = read_new_scores('lobsters', $lobsters->{id});
	$lobsters->{score}= $lo_scores->{score};
	$lobsters->{comments}= $lo_scores->{comments};
    }
    my ( $first, $then );
    if ($diff<0) {
	$pair->{first} = $lobsters;
	$pair->{first}->{site}='Lobste.rs';
	$pair->{then} = $hackernews;
	$pair->{then}->{site} = 'Hackernews';

    } else {
	$pair->{first}=$hackernews;
	$pair->{first}->{site} = 'Hackernews';
	$pair->{then}=$lobsters;
	$pair->{then}->{site} = 'Lobste.rs';
    }
    $pair->{heading} = "<a href='".$pair->{url}."'>".$pair->{first}->{title}.'</a>';
    push @pairs, $pair;
}
my $now= gmtime;
my %data = ( pairs=>\@pairs,
	   meta => {generate_time=>$now});
my $tt= Template->new({INCLUDE_PATH => '/home/gustaf/prj/HN-Lobsters-Tracker'});
$tt->process('header.tt') || die $tt->error;
$tt->process('page.tt', \%data) || die $tt->error;
$tt->process('footer.tt') || die $tt->error;

### SUBS

sub sec_to_hms {
    my ($sec) = @_;
    my $days = int($sec/(24*60*60));
    my $hours = ( $sec/(60*60))%24;
    my $mins = ( $sec/60)%60;
    my $seconds = $sec%60;
    my $out;
    if ($days > 0 ) {
	if ($days == 1 ) {
	    $out.= '1 day, ';
	} else {
	    $out .="$days days, ";
	}
    }
#    $out .= $days>0 ? "$days days, ":'';
    $out .= $hours>0 ? $hours.'h':'';
    $out .= $mins.'m'.$seconds.'s';
    
    return $out;
}
sub read_new_scores {
    # IN: source {hackernews|lobsters}, id
    # OUT: hashref new score and comments, undef on failure
    my ( $source, $id ) =@_;
    my $href;
    my $out = undef;
    if ($source eq 'hackernews') {
	$href = 'https://hacker-news.firebaseio.com/v0/item/'.$id.'.json';
	my $res = $ua->get( $href );
	last unless $res->is_success;
	my $data = decode_json( $res->decoded_content );
	$out = {score=>$data->{score}, comments=>$data->{descendants}};
	my $rv = $hn_sth->execute( $data->{score}, $data->{descendants}, $id) or warn $hn_sth->errstr;
    } elsif ($source eq 'lobsters') {
	$href = 'https://lobste.rs/s/'.$id.'.json';
	my $res = $ua->get( $href );
	last unless $res->is_success;
	my $data = decode_json( $res->decoded_content);
	$out = { score=> $data->{score}, comments=> $data->{comment_count}};
	my $rv = $lo_sth->execute( $data->{score}, $data->{comment_count}, $id) or warn $lo_sth->errstr;
    } else {
	die "can't parse source: $source";
    }
    return $out;
}
