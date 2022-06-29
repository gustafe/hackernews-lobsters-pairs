#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Template;
use FindBin qw/$Bin/;
use utf8;

use JSON;
use HNLOlib qw/$feeds get_ua get_dbh/;
use List::Util qw/sum/;
use Getopt::Long;
use URI;
binmode(STDOUT, ":encoding(UTF-8)");
my $debug    = 0;
my $template = 'https://lobste.rs/newest/page/';

sub md_entry {
    my ($entry) = @_;
    my ( $id, $created_at, $url, $title, $author, $comments, $score, $tags ) = @$entry;
    my $lo_link = 'https://lobste.rs/s/'.$id;
    say "* [$id]($lo_link) [$title]($url) $author [$tags] $score $comments";
}

sub dump_entry {
    my ($entry) = @_;
    my ( $id, $created_at, $url, $title, $author, $comments, $score, $tags ) = @$entry;
    my $lo_link = 'https://lobste.rs/s/'.$id;
    my $title_space = 80 - ( 14 + sum (map{length($_)}($author, $score, $comments)));
    my $url_space = 80 - 8 - sum(map {length($_)} ($lo_link, $tags)) ;
    
    if (length($title) > $title_space ) {
	$title = substr( $title, 0, $title_space-1) . "\x{2026}";
    }
    if (length($url) > $url_space) {
	$url = substr( $url, 0, $url_space-1) . "\x{2026}";
    }
}
sub usage {
    say "usage: $0 [--help] [--from_page=N]";
    exit 1;

}
sub extract_host {
    my ( $in ) = @_;
    my $uri = URI->new( $in );
    my $host;
    eval {
	$host = $uri->host;
	1;
    } or do {
	my $error = $@;
	$host= 'www';
	};
    $host =~ s/^www\.//;
    return $host;
}

my $from_page;
my $help = '';
GetOptions( 'from_page=i'=>\$from_page,'help'=>\$help);
usage if $help;
my $entries;
my $ua = get_ua();
my @days;
if ($from_page ) {
    @days = ( $from_page .. $from_page + 10 );
} else {
    @days = ( 1 .. 6 );
}
my $load_fail_count  =0 ;
FETCH:
foreach my $day ( @days ) {

    my $url      = $template . $day . '.json';
    my $response = $ua->get($url);
    if ( !$response->is_success ) {
        warn "could not fetch newest entries day $day: $response->status_line";
	$load_fail_count++;
	LAST FETCH if $load_fail_count > 5;
    }

    my $list = decode_json( $response->decoded_content );
    push @{$entries}, @{$list};
    if ($from_page) {
	say "==> fetched page for $day... sleeping 5s";
	sleep 5;
    }
}

my $dbh = get_dbh;

my $all_ids = $dbh->selectall_arrayref("select id from lobsters")
  or die $dbh->errstr;
my %seen_ids;
foreach my $id ( @{$all_ids} ) {
    $seen_ids{ $id->[0] }++;
}
my @updates;
my @inserts;
foreach my $entry ( @{$entries} ) {
    my $current_id = $entry->{short_id};
    if ( exists $seen_ids{$current_id} ) {

        push @updates,
          [
            $entry->{title}, $entry->{score},
            $entry->{comment_count}, join( ',', @{ $entry->{tags} } ),
            $current_id
          ];
    }
    else {

        push @inserts,
          [
            $current_id,
            $entry->{created_at},
            $entry->{url} ? $entry->{url} : '',
            $entry->{title},
            $entry->{submitter_user}->{username},
            $entry->{comment_count},
            $entry->{score},
            @{ $entry->{tags} } ? join( ',', @{ $entry->{tags} } ) : ''
          ];

    }
}

my $sth;
my $count = 0;
$dbh->{PrintError} = 1;

if (@inserts) {
    print "\n";
    $sth = $dbh->prepare( $feeds->{lo}->{insert_sql} ) or die $dbh->errstr;
    foreach my $values (@inserts) {
        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }
    $sth->finish();
    for my $el (@inserts) {
	my $url = $el->[2];
	my $host = extract_host( $url );
	push @$el,$host;
    }

    my %data = (count=>$count, entries=>\@inserts);
    my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
    $tt->process( 'Lo-log.tt', \%data) || die $tt->error;
}

if (@updates) {
    $count = 0;
    $sth = $dbh->prepare( $feeds->{lo}->{update_sql} ) or die $dbh->errstr;
    foreach my $values (@updates) {

        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }

    $sth->finish;
}
