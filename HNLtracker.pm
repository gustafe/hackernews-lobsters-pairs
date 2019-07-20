package HNLtracker;

use strict;
use Exporter;
#use Digest::SHA qw/hmac_sha256_hex/;
use Config::Simple;
use DBI;
use LWP::UserAgent;

use vars qw/$VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS/;

$VERSION = 1.00;
@ISA = qw/Exporter/;
@EXPORT = ();
@EXPORT_OK = qw/get_dbh get_ua get_all_pairs $feeds/ ;
%EXPORT_TAGS = (DEFAULT => [qw/&get_dbh &get_ua/]);


#### DBH

my $cfg = Config::Simple->new('/home/gustaf/prj/HN-Lobsters-Tracker/hnltracker.ini');

    my $driver = $cfg->param('DB.driver');
my $database = $cfg->param('DB.database');
my $dbuser = $cfg->param('DB.user');
my $dbpass = $cfg->param('DB.password');
my $dsn = "DBI:$driver:dbname=$database";

my %seen;

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

    my $dbh=DBI->connect($dsn, $dbuser, $dbpass, {PrintError=>0}) or die $DBI::errstr;
    return $dbh;
}

#### User agent
sub get_ua {
    my $ua = LWP::UserAgent->new;
    return $ua;
}

sub get_all_pairs {
    my ( $sth ) = @_;
#    my $sth = $dbh->prepare( $sql->{get_pairs} );
    $sth->execute;
    my $return;
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

        if ( $pair->{diff} < 0 ) {
            $pair->{order} = [ 'lo', 'hn' ];
        }
        else {
            $pair->{order} = [ 'hn', 'lo' ];

        }
        $pair->{heading_url} = $pair->{url};
        $pair->{heading}     = $data->{ $pair->{order}->[0] }->{title};
        $pair->{later}       = sec_to_human_time( abs $pair->{diff} );
        $pair->{logo} =
          $pair->{order}->[0] . '_' . $pair->{order}->[1] . '.png';
        $pair->{first} = $data->{ $pair->{order}->[0] };
        $pair->{then}  = $data->{ $pair->{order}->[1] };

        push @{$return}, $pair;
    }
    $sth->finish();
    return $return;
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


1;
