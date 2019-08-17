package HNLOlib;
use Modern::Perl '2015';
use Exporter;

#use Digest::SHA qw/hmac_sha256_hex/;
use Config::Simple;
use DBI;
use LWP::UserAgent;
use JSON;
use DateTime;
use URI;
use open qw/ :std :encoding(utf8) /;

use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;

$VERSION = 1.00;
@ISA     = qw/Exporter/;
@EXPORT  = ();
@EXPORT_OK =
  qw/get_dbh get_ua get_all_sets get_item_from_source $feeds update_scores $debug $sql $ua/;
%EXPORT_TAGS = ( DEFAULT => [qw/&get_dbh &get_ua/] );

#### DBH

my $cfg =
  Config::Simple->new('/home/gustaf/prj/HN-Lobsters-Tracker/hnltracker.ini');

my $driver   = $cfg->param('DB.driver');
my $database = $cfg->param('DB.database');
my $dbuser   = $cfg->param('DB.user');
my $dbpass   = $cfg->param('DB.password');
my $dsn      = "DBI:$driver:dbname=$database";

my %seen;
our $ua;
our $debug = 0;

our $sql = {
    get_pairs => "select hn.url, 
strftime('%s',lo.created_time)-strftime('%s',hn.created_time) as diff,
hn.id as hn_id,
strftime('%s',hn.created_time) as hn_time,
hn.title as hn_title , hn.submitter as hn_submitter,hn.score as hn_score, hn.comments as hn_comments, null as hn_tags,
lo.id as lo_id,
strftime('%s',lo.created_time) as lo_time,
lo.title as lo_title, lo.submitter as lo_submitter,lo.score as lo_score, lo.comments as lo_comments, lo.tags as lo_tags
from hackernews hn
inner join lobsters lo
on lo.url = hn.url
where hn.url is not null
order by hn.created_time",

    # and hn_time >= strftime('%s', date('now','-7 day'))
    # or lo_time >= strftime('%s', date('now','-7 day'))

    get_hn_count =>
"select count(*) from hackernews where url is not null and created_time between ? and ?",
    get_lo_count =>
"select count(*) from lobsters where url is not null and created_time between ? and ?",
};

our $feeds;

$feeds->{lo} = {
    comments       => 'comment_count',
    api_item_href  => 'https://lobste.rs/s/',
    table_name     => 'lobsters',
    site           => 'Lobste.rs',
    title_href     => 'https://lobste.rs/s/',
    submitter_href => 'https://lobste.rs/u/',
    update_sql => "update lobsters set title=?,score=?,comments=? where id=?",
    delete_sql => "delete from lobsters where id=?",
    select_all_sql => "select * from lobsters",

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

sub get_dbh {

    my $dbh = DBI->connect( $dsn, $dbuser, $dbpass, { PrintError => 0 } )
      or die $DBI::errstr;
    return $dbh;
}

#### User agent
my $version = '1.1';

sub get_ua {
    my $ua =
      LWP::UserAgent->new( agent =>
          "HNLO agent $version; http://gerikson.com/hnlo; gerikson on Lobste.rs"
      );
    return $ua;
}

sub get_all_sets {
    my ($sth) = @_;

    $sth->execute;
    my $return;
    my $sets;
    while ( my $r = $sth->fetchrow_hashref ) {

        my $url = $r->{url};    # key

        my $uri  = URI->new( $r->{url} );
        my $host = $uri->host;
        $host =~ s/^www\.//;

        my $title;
	my $tags_string;
        my $current_set;
        foreach my $label ( keys %{$feeds} ) {
            my $data;
            foreach my $field (qw(id time title submitter score comments tags)) {
                $data->{$field} = $r->{ $label . '_' . $field };
            }

            if ( $label eq 'lo' ) {
                $title = $data->{title};
		$tags_string = $data->{tags};
            }
            $data->{title_href} =
              $feeds->{$label}->{title_href} . $data->{id};
            $data->{submitter_href} =
              $feeds->{$label}->{submitter_href} . $data->{submitter};
            $data->{site} = $feeds->{$label}->{site};
            $data->{tag}  = $label;

            # date munging
            my $dt = DateTime->from_epoch( epoch => $data->{time} );

            $data->{timestamp} = $dt->strftime('%Y-%m-%d %H:%M:%SZ');

            $data->{pretty_date} = $dt->strftime('%d %b %Y');
            $current_set->{ $data->{time} } = $data;
        }


        if ( !exists $sets->{$url} ) {

            # initialize new entry
            $sets->{$url} = {
                heading     => $title,
                domain      => $host,
			     heading_url => $url,
			     tags_list => [split(',',$tags_string)],

                # first seen entry
                first_seen => ( sort keys %{$current_set} )[0],
            };

        }
        foreach my $ts ( keys %{$current_set} ) {
            $sets->{$url}->{entries}->{$ts} = $current_set->{$ts};
        }

    }
    $sth->finish();

    # convert link hashref to ordered array
    foreach my $url ( keys %{$sets} ) {
        my $entries = $sets->{$url}->{entries};
        my @times   = sort keys %{$entries};
        my @shift   = ( 0, @times );
        my @diffs   = ( 0, map { $times[$_] - $shift[$_] } ( 1 .. $#times ) );

        my $seq_idx = 0;
        foreach my $ts ( sort keys %{$entries} ) {
            my $entry = $entries->{$ts};
            if ( $seq_idx == 0 ) {
                push @{ $sets->{$url}->{sequence} }, { first => 1, %{$entry} };
            }
            else {
                push @{ $sets->{$url}->{sequence} },
                  { then => sec_to_human_time( $diffs[$seq_idx] ), %{$entry} };
            }
            $seq_idx++;
        }

        # which logo to use?
        if ( scalar @{ $sets->{$url}->{sequence} } == 2 ) {
            if (    $sets->{$url}->{sequence}->[0]->{tag} eq 'hn'
                and $sets->{$url}->{sequence}->[1]->{tag} eq 'lo' )
            {
                $sets->{$url}->{logo} = 'hn_lo.png';
            }
            else {
                $sets->{$url}->{logo} = 'lo_hn.png';
            }
        }
        else {
            $sets->{$url}->{logo} = 'multi.png';
        }
        $sets->{$url}->{anchor} =
          join( '_', map { $sets->{$url}->{sequence}->[$_]->{id} } ( 0, 1 ) );
    }
    return $sets;
}

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

sub get_item_from_source {
    my ( $label, $id ) = @_;
    $ua = get_ua();

    # this is fragile, it relies on all feed APIs having the same structure!
    my $href = $feeds->{$label}->{api_item_href} . $id . '.json';
    my $r    = $ua->get($href);
    if ( !$r->is_success() ) {

        #	warn "==> fetch failed for $label $id: ";
        #	warn Dumper $r;
        return undef;
    }
    return undef unless $r->is_success();
    return undef unless $r->header('Content-Type') =~ m{application/json};
    my $content = $r->decoded_content();
    my $json    = decode_json($content);

# special case for HN, if link is flagged "dead" after it's been included in the DB
    return undef if ( $label eq 'hn' and defined( $json->{dead} ) );

    # we only return stuff that we're interested in
    my $hashref = {
        title    => $json->{title},
        score    => $json->{score},
        comments => $json->{ $feeds->{$label}->{comments} }
    };
    if ( $label eq 'lo' ) {
        $hashref->{tags} = join( ',', @{ $json->{tags} } );
    }
    return $hashref;
}

sub update_scores {
    my ( $dbh, $pairs_ref ) = @_;
    my $lists;

    # find changes, if any
    foreach my $set ( @{$pairs_ref} ) {
        foreach my $item ( @{ $set->{sequence} } ) {
            my $res = get_item_from_source( $item->{tag}, $item->{id} );

            if ( !defined $res and $item->{tag} eq 'hn' ) {

                # might be problem accessing the API, try later
                next;
            }

            # if it's Lobsters, assume it's gone
            if ( !defined $res and $item->{tag} eq 'lo' ) {
                say "!! Delete scheduled for $item->{site} ID $item->{id}";
                push @{ $lists->{ $item->{tag} }->{delete} }, $item->{id};
                $item->{delete} = 1;
                next;
            }
            if ( !defined $res->{title} and $item->{tag} eq 'hn' )
            {    # assume item has been deleted
                say "!! Delete scheduled for $item->{site} ID $item->{id}";
                push @{ $lists->{ $item->{tag} }->{delete} }, $item->{id};
                $item->{delete} = 1;

                next;
            }
            say "$feeds->{$item->{tag}}->{site} ID $item->{id}" if $debug;
            if ( $res->{title} ne $item->{title}
                or ( $res->{comments} ? $res->{comments} : 0 ) !=
                $item->{comments}
                or ( $res->{score} ? $res->{score} : 0 ) != $item->{score} )
            {

                if ($debug) {

                    say "T: >$item->{title}<\n-> >$res->{title}<";
                    say "S: $item->{score} -> $res->{score}";
                    say "C: $item->{comments} -> $res->{comments}";
                }
                $item->{title}    = $res->{title};
                $item->{score}    = $res->{score};
                $item->{comments} = $res->{comments};
                push @{ $lists->{ $item->{tag} }->{update} },
                  [
                    $res->{title},    $res->{score},
                    $res->{comments}, $item->{id}
                  ];
            }
        }
    }

    # execute changes
    foreach my $label ( sort keys %{$feeds} ) {
        if ( defined $lists->{$label}->{delete} ) {

            my $sth = $dbh->prepare( $feeds->{$label}->{delete_sql} )
              or die $dbh->errstr;
            foreach my $id ( @{ $lists->{$label}->{delete} } ) {
                say "!! deleting $label $id ...";
                my $rv = $sth->execute($id) or warn $sth->errstr;
            }
            $sth->finish();
        }
        if ( defined $lists->{$label}->{update} ) {
            my $sth = $dbh->prepare( $feeds->{$label}->{update_sql} )
              or die $dbh->errstr;
            foreach my $item ( @{ $lists->{$label}->{update} } ) {
                printf( "%s %8s %.67s%s\n",
                    $label, $item->[-1], $item->[0],
                    length( $item->[0] ) > 67 ? '\\' : ' ' );

                my $rv = $sth->execute( @{$item} ) or warn $sth->errstr;
            }
            $sth->finish();
        }
    }
    return $pairs_ref;
}

1;
