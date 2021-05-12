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
use Reddit::Client;
use Carp;
use open qw/ :std :encoding(utf8) /;

use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;

$VERSION = 1.00;
@ISA     = qw/Exporter/;
@EXPORT  = ();
@EXPORT_OK =
  qw/get_dbh get_ua get_all_sets get_item_from_source $feeds update_scores $debug $sql $ua get_reddit get_web_items get_reddit_items/;
%EXPORT_TAGS = ( DEFAULT => [qw/&get_dbh &get_ua/] );

#### DBH

my $cfg =
  Config::Simple->new('/home/gustaf/prj/HN-Lobsters-Tracker/hnltracker.ini');
my $creds =
  Config::Simple->new('/home/gustaf/prj/HN-Lobsters-Tracker/reddit.ini');
my $driver   = $cfg->param('DB.driver');
my $database = $cfg->param('DB.database');
my $dbuser   = $cfg->param('DB.user');
my $dbpass   = $cfg->param('DB.password');

my $dsn = "DBI:$driver:dbname=$database";

my %seen;
our $ua;
our $debug = 0;

our $sql = {
    get_pairs => qq{select lo.url, 
lo.id as lo_id,strftime('%s',lo.created_time) as lo_time,lo.title as lo_title, lo.submitter as lo_submitter,lo.score as lo_score, lo.comments as lo_comments, lo.tags as lo_tags,
hn.id as hn_id,strftime('%s',hn.created_time) as hn_time,hn.title as hn_title , hn.submitter as hn_submitter,hn.score as hn_score, hn.comments as hn_comments, null as hn_tags,
pr.id as pr_id, strftime('%s',pr.created_time) as pr_time,pr.title as pr_title, pr.submitter as pr_submitter,pr.score as pr_score, pr.comments as pr_comments, null as pr_tags
from lobsters  lo
left outer  join hackernews hn
on lo.url = hn.url 
left outer join proggit pr
on pr.url = lo.url 
where (lo.url is not null and lo.url !='')},
	    get_pairs_10d=>qq{select lo.url, 
lo.id as lo_id,strftime('%s',lo.created_time) as lo_time,lo.title as lo_title, lo.submitter as lo_submitter,lo.score as lo_score, lo.comments as lo_comments, lo.tags as lo_tags,
hn.id as hn_id,strftime('%s',hn.created_time) as hn_time,hn.title as hn_title , hn.submitter as hn_submitter,hn.score as hn_score, hn.comments as hn_comments, null as hn_tags,
pr.id as pr_id, strftime('%s',pr.created_time) as pr_time,pr.title as pr_title, pr.submitter as pr_submitter,pr.score as pr_score, pr.comments as pr_comments, null as pr_tags
from lobsters  lo
left outer  join hackernews hn
on lo.url = hn.url 
left outer join proggit pr
on pr.url = lo.url 
where (lo.url is not null and lo.url !='')
    and ( strftime('%s','now') - strftime('%s',lo.created_time) < 10 * 24 * 3600 )
	    or ( strftime('%s','now') - strftime('%s',hn.created_time) < 10 * 24 * 3600 )
or ( strftime('%s','now') - strftime('%s',pr.created_time) < 10 * 24 * 3600 )
},
rank_sql=> qq{select id, rank from hn_frontpage where id between ? and ?},
};

our $feeds;

$feeds->{lo} = {
    comments       => 'comment_count',
    api_item_href  => 'https://lobste.rs/s/',
    table_name     => 'lobsters',
    site           => 'Lobste.rs',
    title_href     => 'https://lobste.rs/s/',
    submitter_href => 'https://lobste.rs/u/',
    insert_sql     => "insert into lobsters 
(id, created_time, url,title,submitter,comments,score,tags) values 
( ?,            ?,   ?,    ?,        ?,       ?,    ?,   ?)",
    update_sql =>
      "update lobsters set title=?,score=?,comments=?,tags=? where id=?",
    delete_sql     => "delete from lobsters where id=?",
    select_all_sql => "select * from lobsters",
hot_level => 28,
cool_level => 2,


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
    insert_sql => qq{insert into hackernews (
id, created_time, url, title, submitter, score, comments)
values
(?, datetime(?,'unixepoch'),?,?,?,?,?)},

hot_level => 10,
cool_level => 1,

};
$feeds->{pr} = {
    comments   => 'num_comments',
    site       => '/r/Programming',
    update_sql => "update proggit set title=?, score=?, comments=? where id=?",
    insert_sql => qq{ insert into proggit 
(id, created_time,             url ,title, submitter, score,comments ) values 
(?,  datetime( ?,'unixepoch'), ?,   ?,     ?,         ?,    ? )},
    delete_sql     => "delete from proggit where id = ?",
    table_name     => 'proggit',
    title_href     => 'https://www.reddit.com/r/programming/comments/',
    submitter_href => 'https://www.reddit.com/user/',

hot_level => 30,
cool_level => 0,

};

sub get_dbh {

    my $dbh = DBI->connect( $dsn, $dbuser, $dbpass, { PrintError => 0 } )
      or croak $DBI::errstr;
    $dbh->{sqlite_unicode} = 1;
    return $dbh;
}

#### User agent

sub get_ua {
    my $ua = LWP::UserAgent->new( agent => $cfg->param('UserAgent.string') );

    return $ua;
}

##### Reddit

sub get_reddit {
    my $reddit = new Reddit::Client(
        user_agent => $cfg->param('UserAgent.string'),
        client_id  => $creds->param('Reddit.client_id'),
        secret     => $creds->param('Reddit.secret'),
        username   => $creds->param('Reddit.username'),
        password   => $creds->param('Reddit.password')
    );
    return $reddit;
}

sub get_all_sets {

    # get all urls submitted from the sources
    # return an ordered list, along with the linked submissions
    my ($sth) = @_;

    $sth->execute;
    my $return;
    my $sets;
    while ( my $r = $sth->fetchrow_hashref ) {
        next unless defined $r->{url};
        my $url = $r->{url};    # key

        my $uri = URI->new( $r->{url} );
        my $host;
        eval {
            $host = $uri->host;
            1;
        } or do {

            # silently discard error, we can't handle the URI
            my $error = $@;
            $host = 'www';

        };

        $host =~ s/^www\.//;

        my $title;
        my $tags_string;
        my $current_set;
        foreach my $label ( keys %{$feeds} ) {
            my $data;
            foreach my $field (qw(id time title submitter score comments tags))
            {
                $data->{$field} = $r->{ $label . '_' . $field };
            }

            if ( $label eq 'lo' ) {
                $title       = $data->{title};
                $tags_string = $data->{tags};
            }
            if ( defined $data->{time} ) {

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

		# hot or not?
		if ($data->{score} + $data->{comments} >= $feeds->{$label}->{hot_level}) {
		    $data->{hotness} = 'hot'
		} elsif ($data->{score}+$data->{comments}<=$feeds->{$label}->{cool_level}) {
		    $data->{hotness} = 'cool'
		} else {
		    $data->{hotness} = '';
		}
            }
        }

        if ( !exists $sets->{$url} ) {

            # initialize new entry
            $sets->{$url} = {
                heading     => $title,
                domain      => $host,
                heading_url => $url,
                tags_list   => [ split( ',', $tags_string ) ],

                # first seen entry
                first_seen => ( sort keys %{$current_set} )[0],
            };

        }

        # add entries, keyed by timestamp
        foreach my $ts ( keys %{$current_set} ) {
            $sets->{$url}->{entries}->{$ts} = $current_set->{$ts};
        }

    }
    $sth->finish();

    # convert link hashref to ordered array
    foreach my $url ( keys %{$sets} ) {
        my $entries = $sets->{$url}->{entries};
        my @times   = sort keys %{$entries};

        # skip single entries
        next unless scalar @times > 1;
        my @shift = ( 0, @times );
        my @diffs = ( 0, map { $times[$_] - $shift[$_] } ( 1 .. $#times ) );

        my $seq_idx = 0;
        foreach my $ts ( sort keys %{$entries} ) {
            my $entry = $entries->{$ts};
            if ( $seq_idx == 0 ) {
                push @{ $sets->{$url}->{sequence} }, { first => 1, %{$entry} };
            }
            else {
                push @{ $sets->{$url}->{sequence} },
                  { then => sec_to_human_time( $diffs[$seq_idx] ),
		    then_s => $diffs[$seq_idx],
		    %{$entry} };
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
            elsif ( $sets->{$url}->{sequence}->[0]->{tag} eq 'lo'
                and $sets->{$url}->{sequence}->[1]->{tag} eq 'hn' )
            {

                $sets->{$url}->{logo} = 'lo_hn.png';
            }
            else {
                $sets->{$url}->{logo} = 'multi.png';
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
        } elsif ($days >=365 and $days < 365 + 3 * 30) {
	    $out .= "1 year";
	} elsif ($days > 395 + 3 * 30 ) {
	    my $years = sprintf( "%.1f", $days/365);
	    $out .= "$years years"
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

    return undef unless $r->is_success();
    return undef unless $r->header('Content-Type') =~ m{application/json};
    my $content = $r->decoded_content();
    my $json    = decode_json($content);

    # special case for HN, if link is flagged "dead" after it's been
    # included in the DB
    return undef if ( $label eq 'hn' and defined( $json->{dead} ) );

    # returns stuff common to both sources
    my $hashref = {
        title    => $json->{title},
        score    => $json->{score},
        comments => $json->{ $feeds->{$label}->{comments} }
    };

    # lobsters has the tags
    if ( $label eq 'lo' ) {
        $hashref->{tags} = join( ',', @{ $json->{tags} } );
    }
    return $hashref;
}

sub update_scores {
    my ( $dbh, $pairs_ref ) = @_;
    my $lists;

    # find changes, if any
    my @proggit_changes;
    foreach my $set ( @{$pairs_ref} ) {
        foreach my $item ( @{ $set->{sequence} } ) {


            next
              unless $item->{tag} eq
              'hn';    # we've moved the reload to the load script

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
            my @bind_vars = ( $res->{title}, $res->{score}, $res->{comments} );
            push @bind_vars, $res->{tags} if $item->{tag} eq 'lo';
            push @bind_vars, $item->{id};

            push @{ $lists->{ $item->{tag} }->{update} }, \@bind_vars;
        }
    }

    # execute changes
    foreach my $label ( sort keys %{$feeds} ) {
        if ( defined $lists->{$label}->{delete} ) {

            my $sth = $dbh->prepare( $feeds->{$label}->{delete_sql} )
              or croak $dbh->errstr;
            foreach my $id ( @{ $lists->{$label}->{delete} } ) {

                say
"select * from $feeds->{$label}->{table_name} where id='$id';";
                say
                  "delete from $feeds->{$label}->{table_name} where id='$id;'";


            }
            $sth->finish();
        }
        if ( defined $lists->{$label}->{update} ) {


            my $sth = $dbh->prepare( $feeds->{$label}->{update_sql} )
              or croak $dbh->errstr;
            my $count = 0;
            foreach my $item ( @{ $lists->{$label}->{update} } ) {
                my $rv = $sth->execute( @{$item} ) or carp $sth->errstr;
                $count++;
            }
            say "$label: $count items updated";
            $sth->finish();
        }
    }

    # handle Reddit stuff

    return $pairs_ref;
}
my $get_items = {pr => \&get_reddit_items,
		 hn=>\&get_web_items,
		 lo=>\&get_web_items,
		};

sub update_from_list {
    my ( $label, $ids ) = @_;
    my ( $updates, $deletes ) = $get_items->{$label}->($label, $ids );
    my $dbh= get_dbh();
my $sth = $dbh->prepare( $feeds->{$label}->{update_sql}) or croak $dbh->errstr;
my $count = 0;
foreach my $update (@$updates) {
    $sth->execute( @$update ) or carp $sth->errstr;
    #say join(' ', @$update[3,0,1,2]);
    $count++;
}
say "$count items updated";
$sth->finish;
$count=0;
$sth = $dbh->prepare( $feeds->{$label}->{delete_sql}) or croak $dbh->errstr;
#say "deletes: ",scalar @$deletes;
foreach my $id (@$deletes) {
    $sth->execute( $id );

    $count++;
}
say "$count items deleted";

}
sub get_web_items {
    my ($label, $items ) =@_;
    my %not_seen;
    my @updates;
    my $ua = get_ua();
    foreach my $id (@$items) {
	say "fetching $id" if $debug;
	my $href = $feeds->{$label}->{api_item_href} . $id . '.json';
	my $r = $ua->get( $href );
	if (!$r->is_success() or $r->header('Content-Type') !~ m{application/json}) {
	    $not_seen{$id}++;
	    next;
	}
	my $json = decode_json( $r->decoded_content() );
	if (defined $json->{dead} or defined $json->{deleted}) {
	    $not_seen{$id}++ ;
	    next;
	}
	my @binds = ( $json->{title},
			$json->{score},
		      $json->{$feeds->{$label}->{comments}});
	if (defined  $json->{tags}) {
	    push @binds, join(',',@{$json->{tags}})
	}
	push @binds, $id;
	push @updates, \@binds;
    }
    my @deletes = keys %not_seen if scalar keys %not_seen > 0;
    return ( \@updates, \@deletes );

}

sub get_reddit_items{
    my ($label, $items ) = @_;
    my @inputs;
    my $count = 0;
    my %seen;
    my @updates;
    my @deletes;
    my $reddit = get_reddit();
    foreach my $item (@$items) {
	push @{$inputs[int($count/75)]}, $item;
	$seen{$item} = 0;
	$count++;
    }
    foreach my $list (@inputs) {
	#	say scalar @{$list};
	my $posts = $reddit->get_links_by_id(  @{$list} );
	foreach my $post (@$posts) {

	    push @updates, [ $post->{title},
			     $post->{score},
			     $post->{num_comments},
			     $post->{id}
			   ];
	    $seen{$post->{id}}++;
	}
    }
    foreach my $id (sort keys %seen) {
	push @deletes, $id if $seen{$id} == 0;
    }

    return ( \@updates, \@deletes );
}

1;
