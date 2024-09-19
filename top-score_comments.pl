#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;

use HNLOlib qw/$feeds get_ua get_dbh get_reddit get_web_items/;
use Data::Dump qw/dump/;
use DateTime;
use Template;
use FindBin qw/$Bin/;
use utf8;
binmode( STDOUT, ":utf8" );

my $tt = Template->new(
    { INCLUDE_PATH => "$Bin/templates", ENCODING => 'UTF-8' } );

my $data->{meta}->{page_title} = 'Top links by score and comments';

#my $dt_now = Date
$data->{meta}->{generate_time}
    = DateTime->now()->strftime('%Y-%m-%d %H:%M:%S%z');
my %content;
my @by_score;
my @by_comments;

for my $label ( 'hn', 'lo', ) {
    my $dbh = get_dbh();

    #warn "==> getting data for $label... ";
    for my $sorting ( 's', 'c' ) {

        #warn "==> sorting = $sorting";

        my $statement
            = "select id,date(created_time) ,title,url,score,comments from "
            . $feeds->{$label}->{table_name}
            . " where url!='' ";
#		$statement .= "and date(created_time) between '2022-01-01' and '2022-06-30' ";
        $statement .=
            $sorting eq 's'
            ? ' order by score desc '
            : ' order by comments desc ';


        $statement .= ' limit 200';

        say "$statement" . ';';

# . ( $sorting eq 's' ? ' order by score desc ' : ' order by comments desc ' . ' limit 100 ';
        my $list = $dbh->selectall_arrayref($statement);

        $statement
            = "select date(min(created_time)), date(max(created_time)) from "
            . $feeds->{$label}->{table_name};
#	$statement .= " where date(created_time) between '2022-01-01' and '2022-06-30' ";
        my $dates  = $dbh->selectall_arrayref($statement);
        my $min_ts = $dates->[0]->[0];
        my $max_ts = $dates->[0]->[1];
        $data->{dates}->{$label} = { min_ts => $min_ts, max_ts => $max_ts };

        # $statement = "select min(score), max(score) from "
        #     . $feeds->{$label}->{table_name};
        # my $score_range = $dbh->selectall_arrayref($statement);
        # my $min_score   = $score_range->[0][0];
        # my $score_width
        #     = ( $score_range->[0][1] - $score_range->[0][0] ) / 25;
        my %links;
        for my $item (@$list) {

            my ( $id, $timestamp, $title, $url, $score, $comments ) = @$item;

            # warn "==> ", dump $item unless $score =~ /\d+/;

            #    $hist{int (( $score - $min_score ) / $score_width)}++;

            if ( $label eq 'lo' )
            {    # need to key off title because of article folding
                $links{$title} = {
                    title     => $title,
                    id        => $id,
                    timestamp => $timestamp,
                    url       => $url,
                    score     => $score,
                    comments  => $comments
                };
            }
            else {
                $links{$id} = {
                    id        => $id,
                    title     => $title,
                    timestamp => $timestamp,
                    url       => $url,
                    score     => $score,
                    comments  => $comments
                };
            }

        }

        my $limit = 25;
        my $count;
        if ( $sorting eq 's' ) {

            $count = 1;

            # sort by score
            for my $key (
                sort {
                           $links{$b}->{score} <=> $links{$a}->{score}
                        || $links{$b}->{comments} <=> $links{$a}->{comments}
                }
                keys %links
                )
            {

                next if $count > $limit;
                push @{ $content{$label}->{$sorting} },
                    {
                    rank       => $count,
                    title_href => $feeds->{$label}->{title_href}
                        . $links{$key}->{id},
                    map { $_ => $links{$key}->{$_} }
                        qw/timestamp url title score comments/
                    };

                $by_score[ $count - 1 ]->{$label} = {
                    rank       => $count,
                    title_href => $feeds->{$label}->{title_href}
                        . $links{$key}->{id},
                    map { $_ => $links{$key}->{$_} }
                        qw/timestamp url title score comments/

                };
                $count++;
            }
        }
        elsif ( $sorting eq 'c' ) {

            # sort by comments
            $count = 1;
            for my $key (
                sort {
                           $links{$b}->{comments} <=> $links{$a}->{comments}
                        || $links{$b}->{score} <=> $links{$a}->{score}
                }
                keys %links
                )
            {

                next if $count > $limit;
                push @{ $content{$label}->{$sorting} },
                    {
                    rank       => $count,
                    title_href => $feeds->{$label}->{title_href}
                        . $links{$key}->{id},
                    map { $_ => $links{$key}->{$_} }
                        qw/timestamp url title score comments/
                    };
                $by_comments[ $count - 1 ]->{$label} = {
                    rank       => $count,
                    title_href => $feeds->{$label}->{title_href}
                        . $links{$key}->{id},
                    map { $_ => $links{$key}->{$_} }
                        qw/timestamp url title score comments/
                };
                $count++;
            }
        }
        else {
            die "unknown sorting: $sorting";
        }
    }
    $dbh->disconnect();
}

#print dump \%data;

$data->{content}     = \%content;
$data->{by_score}    = \@by_score;
$data->{by_comments} = \@by_comments;

#print dump $data;
$tt->process(
    'topscore.tt', $data,
    '/home/gustaf/public_html/hnlo/topscore.html',
    { binmode => ':utf8' }
) || die $tt->error;
