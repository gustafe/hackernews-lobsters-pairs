#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use JSON;
use Template;
use DateTime;
use DateTime::Format::Strptime;

use Data::Dumper;

use HNLtracker qw/get_ua get_dbh get_all_pairs $feeds/;
use open qw/ :std :encoding(utf8) /;

#binmode STDOUT, ':utf8';
#binmode STDERR, ':utf8';
my $update_score;
GetOptions( 'update_score' => \$update_score );

### Definitions and constants
my $debug              = 0;
my $page_title         = 'HN&&LO';
my $no_of_days_to_show = 3;
my $ratio_limit        = 9;

my $ua;

my $sql = {
    get_pairs => "select hn.url, 
strftime('%s',lo.created_time)-strftime('%s',hn.created_time) as diff,
hn.id as hn_id,
strftime('%s',hn.created_time) as hn_time,
hn.title as hn_title , hn.submitter as hn_submitter,hn.score as hn_score, hn.comments as hn_comments,
lo.id as lo_id,
strftime('%s',lo.created_time) as lo_time,
lo.title as lo_title, lo.submitter as lo_submitter,lo.score as lo_score, lo.comments as lo_comments
from hackernews hn
inner join lobsters lo
on lo.url = hn.url
where hn.url is not null
order by hn.created_time",
	   get_hn_count => "select count(*) from hackernews where url is not null",
	   get_lo_count => "select count(*) from lobsters where url is not null",
};
my $dbh = get_dbh;
#my $dbh= HNLtracker->new()  ;
$dbh->{sqlite_unicode} = 1;

#### subs
sub sec_to_human_time;
sub get_item_from_source;
sub get_all_pairs;
#### setup



#### CODE ####

my $now   = time();
# get all pairs from the DB
my $sth = $dbh->prepare( $sql->{get_pairs} );
my @pairs = @{ get_all_pairs($sth) };

# filter entries older than the retention time
my $limit_seconds = $no_of_days_to_show * 24 * 3600;
@pairs = grep {
    ( $now - $_->{first}->{time} <= $limit_seconds )
      and ( $now - $_->{then}->{time} <= $limit_seconds )
} @pairs;

# update items if that option is set
if ($update_score) {
    $ua = get_ua();
    my $lists;

    # find changes, if any
    foreach my $pair (@pairs) {
        foreach my $seq ( 'first', 'then' ) {
            my $item = $pair->{$seq};
            my $res = get_item_from_source( $item->{tag}, $item->{id} );

            if ( !defined $res and $item->{tag} eq 'hn' ) {

                # might be problem accessing the API, try later
                next;
            }

            # if it's Lobsters, assume it's gone
            if ( !defined $res and $item->{tag} eq 'lo' ) {
                say "!! Delete scheduled for $item->{site} ID $item->{id}";
                push @{ $lists->{ $item->{tag} }->{delete} }, $item->{id};
                $pair->{$seq}->{delete} = 1;
                next;
            }
            if ( !defined $res->{title} and $item->{tag} eq 'hn' )
            {    # assume item has been deleted
                say "!! Delete scheduled for $item->{site} ID $item->{id}";
                push @{ $lists->{ $item->{tag} }->{delete} }, $item->{id};
                $pair->{$seq}->{delete} = 1;

                next;
            }
            say "$feeds->{$item->{tag}}->{site} ID $item->{id}" if $debug;
            if (   $res->{title} ne $item->{title}
                or $res->{comments} != $item->{comments}
                or $res->{score} != $item->{score} )
            {

                if ($debug) {

                    say "T: $item->{title} -> $res->{title}";
                    say "S: $item->{score} -> $res->{score}";
                    say "C: $item->{comments} -> $res->{comments}";
                }
                $pair->{$seq}->{title}    = $res->{title};
                $pair->{$seq}->{score}    = $res->{score};
                $pair->{$seq}->{comments} = $res->{comments};
                push @{ $lists->{ $item->{tag} }->{update} },
                  [
                    $res->{title},    $res->{score},
                    $res->{comments}, $item->{id}
                  ];
            }
        }
    }

    # execute changes
    foreach my $tag ( keys %{$feeds} ) {
        if ( defined $lists->{$tag}->{delete} ) {

            my $sth = $dbh->prepare( $feeds->{$tag}->{delete_sql} )
              or die $dbh->errstr;
            foreach my $id ( @{ $lists->{$tag}->{delete} } ) {
                say "!! deleting $tag $id ...";
                my $rv = $sth->execute($id) or warn $sth->errstr;
            }
            $sth->finish();
        }
        if ( defined $lists->{$tag}->{update} ) {
            my $sth = $dbh->prepare( $feeds->{$tag}->{update_sql} )
              or die $dbh->errstr;
            foreach my $item ( @{ $lists->{$tag}->{update} } ) {
                say
                  "updating $feeds->{$tag}->{site} ID $item->[-1] '$item->[0]'";
                my $rv = $sth->execute( @{$item} ) or warn $sth->errstr;
            }
            $sth->finish();
        }
    }
}

# calculate scores - we do this at this stage because the scores and
# comments can have been updated

foreach my $pair (@pairs) {
    foreach my $seq ( 'first', 'then' ) {
        my $item  = $pair->{$seq};
        my $ratio = undef;
        if ( $item->{score} > 0
            and ( $item->{score} + $item->{comments} > $ratio_limit ) )
        {
            $ratio = sprintf( '%.02f', $item->{comments} / $item->{score} );

        }
        $pair->{$seq}->{ratio} = $ratio if defined $ratio;

    }
}

# filter deleted stuff, and reverse time order
@pairs =
  grep { !exists $_->{'first'}->{deleted} and !exists $_->{'then'}->{deleted} }
  reverse @pairs;

# generate the page from the data
my $dt_now =
  DateTime->from_epoch( epoch => $now, time_zone => 'Europe/Stockholm' );
my %data = (
    pairs => \@pairs,
    meta  => {
        generate_time      => $dt_now->strftime('%Y-%m-%d %H:%M:%S'),
        page_title         => $page_title,
        no_of_days_to_show => $no_of_days_to_show,
        ratio_limit        => $ratio_limit,
    },

);
my $tt =
  Template->new( { INCLUDE_PATH => '/home/gustaf/prj/HN-Lobsters-Tracker' } );

$tt->process(
    'page.tt', \%data,
    '/home/gustaf/public_html/hnlo/index.html',
    { binmode => ':utf8' }
) || die $tt->error;

### SUBS ###
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

