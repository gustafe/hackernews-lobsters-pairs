#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use JSON;
use HNLOlib qw/get_dbh get_ua $feeds get_item_from_source $ua/;
use IO::Handle;
STDOUT->autoflush(1);

use open qw/ :std :encoding(utf8) /;

my $sql = {
    all_items =>
qq/select id, title, score, comments from hackernews where created_time >=?  
and created_time<?/,
    update_item =>
      qq/update hackernews set title=?, score=?, comments=? where id = ?/,
    delete_item => qq/delete from hackernews where id = ?/,
};
my $dbh = get_dbh();
$dbh->{sqlite_unicode} = 1;

#my $ua = get_ua();
#sub  get_item_from_source;
sub usage;
sub read_item;
my $target_day;
my $delete_id;
my $debug;
GetOptions( 'target_day=i' => \$target_day, 'delete_id=i' => \$delete_id );
if ( !defined $target_day and !defined $delete_id ) {
    usage;
}
if ($delete_id) {
    my $sth = $dbh->prepare( $sql->{delete_item} ) or die $dbh->errstr;
    my $rv  = $sth->execute($delete_id)            or warn $sth->errstr;
    $sth->finish;
    exit 0;
}
else {

    my ( $year, $month, $day ) = $target_day =~ m/(\d{4})(\d{2})(\d{2})/;
    usage unless ( $month >= 1 and $month <= 12 );

    my $from_dt = DateTime->new(
        year   => $year,
        month  => $month,
        day    => $day,
        hour   => 0,
        minute => 0,
        second => 0
    );
    my $to_dt = DateTime->new(
        year   => $year,
        month  => $month,
        day    => $day,
        hour   => 0,
        minute => 0,
        second => 0
    )->add( days => 1 );

    say "$from_dt -- $to_dt";

    my $sth = $dbh->prepare( $sql->{all_items} ) or die $dbh->errstr;
    my @update_list;
    my @failed;
    my @not_read;
    my @to_delete;
    my @items;
    $sth->execute( $from_dt->ymd, $to_dt->ymd );
    
    while ( my @r = $sth->fetchrow_array ) {
	push @items, \@r;
    }
    foreach my $item (@items) {
	my @r = @{$item};
        my $id = $r[0];

        #        say join(',', map {$_?$_:''} @r);

        my $res = get_item_from_source( 'hn', $id );

        #    say join(',', map {$res->{$_}} qw/title score comments/);

        if ( !defined $res ) {

            # assume issue with API,
            say "$id could not read, added to delete list" if $debug;
            push @to_delete, $id;
        }
        elsif ( !defined $res->{title} ) {
            say "$id seems to be deleted!" if $debug;
            push @to_delete, $id;
        }
        elsif ($res->{title} ne $r[1]
            or $res->{score} != $r[2]
            or $res->{comments} != $r[3] ? $r[3] : 0 )
        {
            push @update_list,
              [ $r[0], map { $res->{$_} } qw/title score comments/ ];
            say "$id will be updated" if $debug;
        }
        else {
            # nop
        }

    }

    $sth->finish;
    say "### Updating database ###";
    $sth = $dbh->prepare( $sql->{update_item} ) or die $dbh->errstr;
    my $count =0;
    foreach my $a (@update_list) {
        my $rv = $sth->execute( $a->[1], $a->[2], $a->[3], $a->[0] )
          or warn $sth->errstr;
	$count++;

    }
    say "$count items updated";
    $count=0;
    if ( scalar @to_delete > 0 ) {

        #   say "### Failed to get info ###";
        $sth = $dbh->prepare( $sql->{delete_item} ) or die $dbh->errstr;
        foreach my $i (@to_delete) {
            my $rv = $sth->execute($i) or warn $sth->errstr;
	    $count++;
        }
	
    }
    say "$count items deleted";
}

sub usage {
    say "usage: $0 [--delete_id=ID] --target_day=YYYYMMDD";
    exit 1;
}

sub read_item {
    my ($id) = @_;
    my $url  = 'https://hacker-news.firebaseio.com/v0/item/' . $id . '.json';
    my $r    = $ua->get($url);
    return $r->status_line() unless $r->is_success();
    my $content = $r->decoded_content();
    return decode_json($content);
}

__END__ 
sub get_item_from_source {
    my ( $tag, $id ) = @_;

    # this is fragile, it relies on all feed APIs having the same structure!
    my $href = $feeds->{$tag}->{api_item_href} . $id . '.json';
    my $r    = $ua->get($href);
    if ( !$r->is_success() ) {

        #	warn "==> fetch failed for $tag $id: ";
        #	warn Dumper $r;
        return undef;
    }
    return undef unless $r->is_success();
    return undef unless $r->header('Content-Type') =~ m{application/json};
    my $content = $r->decoded_content();
    my $json    = decode_json($content);

    # we only return stuff that we're interested in
    return {
        title    => $json->{title},
        score    => $json->{score},
        comments => $json->{ $feeds->{$tag}->{comments} }
    };
}

