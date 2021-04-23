#! /usr/bin/env perl
use Modern::Perl '2015';
###
use JSON;
use HNLOlib qw/$feeds get_ua get_dbh/;
use Getopt::Long;
my $debug    = 0;
my $template = 'https://lobste.rs/newest/page/';
sub dump_entry {
    my ($entry) = @_;
    print "\n";
    say join(' ',@{$entry}[0, 4, 1,6,7]);
    say $entry->[3];
    say $entry->[2], ' | https://lobste.rs/s/',$entry->[0];
say '-' x 75;
}
sub usage {
    say "usage: $0 [--help] [--from_page=N]";
    exit 1;

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
#        say "new $current_id, inserting" if $debug;
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

    $sth = $dbh->prepare( $feeds->{lo}->{insert_sql} ) or die $dbh->errstr;
    foreach my $values (@inserts) {
#        say join( ' ', @{$values} ) if $debug;
	dump_entry( $values ) unless $from_page;
        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }
    $sth->finish();
    say "$count items inserted" ;

}

if (@updates) {
    $count = 0;
    $sth = $dbh->prepare( $feeds->{lo}->{update_sql} ) or die $dbh->errstr;
    foreach my $values (@updates) {

        #	say join(' ', @{$values});

        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }
    say "$count items updated";

    $sth->finish;
}
