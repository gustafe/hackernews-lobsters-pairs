#! /usr/bin/env perl
use Modern::Perl '2015';
###
use JSON;
use HNLOlib qw/$feeds get_ua get_dbh/;
my $debug    = 1;
my $template = 'https://lobste.rs/newest/page/';

my $entries;
my $ua = get_ua();
foreach my $day ( 1 .. 6 ) {

    my $url      = $template . $day . '.json';
    my $response = $ua->get($url);
    if ( !$response->is_success ) {
        warn "could not fetch newest entries day $day: $response->status_line";
    }

    my $list = decode_json( $response->decoded_content );
    push @{$entries}, @{$list};
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
        say "new $current_id, inserting" if $debug;
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
if (@inserts) {

    $sth = $dbh->prepare( $feeds->{lo}->{insert_sql} ) or die $dbh->errstr;
    foreach my $values (@inserts) {
        say join( ' ', @{$values} ) if $debug;
        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }
    $sth->finish();
    say "$count items inserted" if $debug;

}

if (@updates) {
    $count = 0;
    $sth = $dbh->prepare( $feeds->{lo}->{update_sql} ) or die $dbh->errstr;
    foreach my $values (@updates) {

        #	say join(' ', @{$values});
        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }
    say "$count items updated" if $debug;

    $sth->finish;
}
