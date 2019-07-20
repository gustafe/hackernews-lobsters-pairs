#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
use JSON;
use Template;
use DateTime;
use DateTime::Format::Strptime;

use Data::Dumper;

use HNLtracker qw/get_dbh get_ua/;
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
my $feeds;
my $ua;
$feeds->{lo} = {
    comments       => 'comment_count',
    api_item_href  => 'https://lobste.rs/s/',
    table_name     => 'lobsters',
    site           => 'Lobste.rs',
    title_href     => 'https://lobste.rs/s/',
    submitter_href => 'https://lobste.rs/u/',
    update_sql => "update lobsters set title=?,score=?,comments=? where id=?",
    delete_sql => "delete from lobsters where id=?",

};
$feeds->{hn} = {
    comments       => 'descendants',
    api_item_href  => 'https://hacker-news.firebaseio.com/v0/item/',
    table_name     => 'hackernews',
    site           => 'Hacker News',
    title_href     => 'https://news.ycombinator.com/item?id=',
    submitter_href => 'https://news.ycombinator.com/user?id=',
    update_sql => "update hackernews set title=?,score=?,comments=? where id=?",
    delete_sql => "delete from hackernews where id=?",
};

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
};

#### subs
sub sec_to_human_time;

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
#### setup
my $dbh = get_dbh();
$dbh->{sqlite_unicode} = 1;
my @pairs;
my %seen;

#### CODE ####

my $sth = $dbh->prepare( $sql->{get_pairs} );
$sth->execute;
my $now = time();
while ( my $r = $sth->fetchrow_hashref ) {

    #    print Dumper $r;
    my $pair;
    my $data;
    $pair->{url} = $r->{url};
    if ( exists $seen{ $pair->{url} } ) {
        next;
    }
    else {
        $seen{ $pair->{url} }++;
    }
    $pair->{diff} = $r->{diff};

    foreach my $tag ( keys %{$feeds} ) {
        foreach my $field (qw(id time title submitter score comments )) {
            $data->{$tag}->{$field} = $r->{ $tag . '_' . $field };
        }
        $data->{$tag}->{title_href} =
          $feeds->{$tag}->{title_href} . $data->{$tag}->{id};
        $data->{$tag}->{submitter_href} =
          $feeds->{$tag}->{submitter_href} . $data->{$tag}->{submitter};
        $data->{$tag}->{site} = $feeds->{$tag}->{site};
        $data->{$tag}->{tag}  = $tag;

        # date munging
        my $dt = DateTime->from_epoch( epoch => $data->{$tag}->{time} );
        $data->{$tag}->{dt} = $dt;

        $data->{$tag}->{timestamp} = $dt->strftime('%Y-%m-%d %H:%M:%SZ');

        $data->{$tag}->{pretty_date} = $dt->strftime('%d %b %Y');
    }
    # exclude older entries
    if (   $now - $data->{lo}->{time} > $no_of_days_to_show * 24 * 3600
        or $now - $data->{hn}->{time} > $no_of_days_to_show * 24 * 3600 )
    {
        next;
    }

    if ( $pair->{diff} < 0 ) {
        $pair->{order} = [ 'lo', 'hn' ];
    }
    else {
        $pair->{order} = [ 'hn', 'lo' ];

    }
    $pair->{heading_url} = $pair->{url};
    $pair->{heading}     = $data->{ $pair->{order}->[0] }->{title};
    $pair->{later}       = sec_to_human_time( abs $pair->{diff} );
    $pair->{logo}  = $pair->{order}->[0] . '_' . $pair->{order}->[1] . '.png';
    $pair->{first} = $data->{ $pair->{order}->[0] };
    $pair->{then}  = $data->{ $pair->{order}->[1] };

    push @pairs, $pair;
}
$sth->finish();

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
		next              ;
	    }
	    
	    # if it's Lobsters, assume it's gone
            if ( !defined $res and $item->{tag} eq 'lo' ) {
                say "!! Delete scheduled for $item->{site} ID $item->{id}";
                push @{ $lists->{ $item->{tag} }->{delete} }, $item->{id};
		$pair->{$seq}->{delete} = 1;
                next;
            }
            if ( !defined $res->{title} and $item->{tag} eq 'hn' )
            {      # assume item has been deleted
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

# generate the page from the data
# filter deleted stuff, and reverse time order 
@pairs = grep {!exists $_->{'first'}->{deleted} and !exists $_->{'then'}->{deleted} } reverse @pairs;

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
    if ( $hours == 0 and $mins == 0 ) {
        return "less than a minute";
    }

    $out .= $hours > 0 ? $hours . 'h' : '';
    $out .= $mins . 'm';

    return $out;
}
