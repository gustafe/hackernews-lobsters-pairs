#! /usr/bin/env perl
use Modern::Perl '2015';
###
use utf8;
use DateTime;
use JSON;
use Template;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use HNLOlib qw/get_dbh $sql $feeds get_ua sec_to_dhms sec_to_human_time/;
use URI;
binmode( STDOUT, ':utf8' );
sub calculate_percentage;
sub extract_host {
    my ($in) = @_;
    my $uri = URI->new($in);
    my $host;
    eval {
        $host = $uri->host;
        1;
    } or do {
        my $error = $@;
        $host = 'www';
    };
    $host =~ s/^www\.//;
    return $host;
}
my %status_icons = (
    dead_or_deleted => '<abbr title="item is dead or deleted">💀</abbr>',
    remove_under_cutoff => '<abbr title="item is old and unchanged">❌🧟</abbr>',
    item_too_old => '<abbr title="item is old and unchanged">❌🧟</abbr>',
    removed_unchanged_after_2_retries => '<abbr title="item is unchanged">❌=</abbr>',
    retried => '<abbr title="item is retried">♻️</abbr>',
    retry_low => '<abbr title="item is retried despite being low score">♻️↓</abbr>',
    updated => '<abbr title="item is updated">🔄</abbr>',
    0 => '<abbr title="retry level 0">🟢</abbr>',
    1 => '<abbr title="retry level 1">🟡</abbr>',
    2 => '<abbr title="retry level 2">🔴</abbr>',
    flagged=>'<abbr title="flagged">🏴‍☠️</abbr>',
    remove_low_percentage=>'<abbr title="old title with low percentage change">❌&percnt;</abbrev>',
);

my $debug  = 0;
my $cutoff = 31940335;

my $now  = time;

my $dbh  = get_dbh;
my $stmt = "select hn.id, title,url, score,comments, 
strftime('%s','now') - strftime('%s',created_time),q.retries 
from hackernews hn inner join hn_queue q on q.id=hn.id 
where q.age <= " . ($now + 15 * 60);

my $rows = $dbh->selectall_arrayref($stmt) or die $dbh->errstr;
if ( scalar @$rows == 0 ) {
    say "no items in queue, exiting.";
    exit 0;
}

my $ua = get_ua();
my @removes;
my @retries;
my @updates;
my $cutoff_shown = 0;
my $dhms;
my %seen;
my $update_data;

for my $row ( sort { $a->[0] <=> $b->[0] } @$rows ) {
    my ( $id, $title, $url, $score, $comments, $item_age, $retries ) = @$row;
    $update_data->{$id} = {
        title    => $title,
        url      => $url,
        score    => $score,
        comments => $comments,
        item_age => sec_to_human_time($item_age),
        retries  => $retries,
        domain   => extract_host($url)
    };

    # fugly hack to deal with duplicates
    if ( $seen{$id} ) {
        next;
    }
    else {
        $seen{$id}++;
    }

    $dhms = sec_to_dhms($item_age);
    if ( $id > $cutoff and !$cutoff_shown ) {
        $cutoff_shown = 1;
    }

    my $item_url = $feeds->{hn}->{api_item_href} . $id . '.json';

    my $res = $ua->get($item_url);

    if ( !$res->is_success ) {
        warn $res->status_line;
        warn "--> fetch for $id failed\n";
        next;
    }

    my $payload = $res->decoded_content;

    if ( $payload eq 'null' ) {
        push @removes, {id=>$id};
        $update_data->{$id}->{status} = 'null_content';
        next;

    }

    my $item = decode_json($payload);

    if ( defined $item->{dead} or defined $item->{deleted} ) {
        push @removes, {id=>$id};
        $update_data->{$id}->{status} = $status_icons{'dead_or_deleted'};
        next;
    } 

    # percentage change
    my $percentage = calculate_percentage($item->{score},$item->{descendants},
					 $score, $comments);
    # decode retry data

    # item is older than 24h and has low change percentage (but is not a catch-up item below cutoff)
    $update_data->{$id}->{changes}->{percentage} = $percentage;
    if ($item_age>24*3600 and abs($percentage)<1.0 and $id>$cutoff) {
            $update_data->{$id}->{status}
                = $status_icons{remove_low_percentage};
            push @removes, {id=>$id};
	    next;
	
    }
    # item is unchanged compared to DB
    if (    $item->{title} eq $title
        and $item->{descendants} == $comments
        and $item->{score} == $score )
    {    

        if ( $retries == 0 and $score <= 2 and $comments == 0 ) {

            push @retries, { id => $id, retries => 2 };
            $update_data->{$id}->{status} = $status_icons{'retry_low'};
            $update_data->{$id}->{changes}->{retries} = 2;
	    next;
        }
        elsif ( $id <= $cutoff ) {

            $update_data->{$id}->{status}
                = $status_icons{remove_under_cutoff};
            push @removes, {id=>$id};
	    next;
        }
        elsif ( $retries >= 2 ) {

            $update_data->{$id}->{status}
                = $status_icons{ 'removed_unchanged_after_'
                    . $retries
                    . '_retries' };
            push @removes, {id=>$id};
	    next;
        } 
        else {

            $update_data->{$id}->{status} = $status_icons{'retried'};
            $update_data->{$id}->{changes}->{retries} = $retries + 1;
            push @retries, { id => $id, retries => $retries + 1 };
	    next;
        }
    }
    else {

        my @msg;

        if ( $title ne $item->{title} ) {
            push @msg, "T:$title→" . $item->{title};
            $update_data->{$id}->{changes}->{title} = $item->{title};
        }
        if ( $score != $item->{score} ) {
            push @msg, "S:$score→" . $item->{score};
            $update_data->{$id}->{changes}->{score} = $item->{score};
        }
        if ( $comments != $item->{descendants} ) {
            push @msg, "C:$comments→" . $item->{descendants};
            $update_data->{$id}->{changes}->{comments} = $item->{descendants};
        }

        $update_data->{$id}->{status} = $status_icons{'updated'};
        $update_data->{$id}->{changes}->{retries} = 0;
	
        push @updates,
            {
            id       => $id,
            title    => $item->{title},
            score    => $item->{score},
            comments => $item->{descendants}
            };
        push @retries, { id => $id, retries => 0 };
	next;
    }
    # should we remove an item because it's too old and not changed enough?
    if ($item_age > 24*3600) {
	$update_data->{$id}->{changes}->{percentage} =  sprintf( "%.1f", $percentage );
    }
    


}

if ( scalar @removes > 0 ) {

    my $sth = $dbh->prepare("delete from hn_queue where id = ?")
        or die $dbh->errstr;
    for my $item (@removes) {
        $sth->execute($item->{id}) or warn $sth->errstr;
    }
}
if ( @retries > 0 ) {

    my $sth
        = $dbh->prepare("update hn_queue set age = ?, retries= ? where id=?")
        or die $dbh->errstr;
    my $count = 0;
    for my $item ( sort { $a->{retries} <=> $b->{retries} } @retries ) {
        $sth->execute( $now + 2 * 3600 * $item->{retries} + 5 * 60 * $count,
            $item->{retries}, $item->{id} )
            or warn $sth->errstr;

        $count++;
    }

}
# update item metadata for display

for my $item (@removes ,@retries) {
	$update_data->{$item->{id}}->{retries} = $status_icons{$update_data->{$item->{id}}->{retries}};
	if ($update_data->{$item->{id}}->{changes}->{retries} or $update_data->{$item->{id}}->{changes}->{retries} == 0) {
	    $update_data->{$item->{id}}->{changes}->{retries} = $status_icons{$update_data->{$item->{id}}->{changes}->{retries}};
    }
    
    
}
if ( scalar @updates > 0 ) {

    my $sth
        = $dbh->prepare(
        "update hackernews set title=?,score=?,comments=? where id=?")
        or die $dbh->errstr;
    for my $item (@updates) {
        $sth->execute(
            $item->{title},    $item->{score},
            $item->{comments}, $item->{id}
        ) or warn $sth->errstr;
    }
}
my $summary = {
    removes => scalar @removes,
    retries => scalar @retries,
    updates => scalar @updates
};

$stmt
    = "select hn.id, url, title, score,comments, q.age-strftime('%s','now'),q.retries,strftime('%s','now') - strftime('%s',created_time) from hackernews hn inner join hn_queue q on q.id=hn.id where q.age<= strftime('%s','now')+1*3600 order by q.age-strftime('%s','now'), q.id";
$rows = $dbh->selectall_arrayref($stmt) or die $dbh->errstr;
my $queue_data;
if ( scalar @$rows > 0 ) {
    for my $r (@$rows) {
        my ( $id, $url, $title, $score, $comments, $age, $retries, $item_age )
            = @$r;
        push @{$queue_data},
            {
            id       => $id,
            url      => $url,
            title    => $title,
            score    => $score,
            comments => $comments,
            next_run => $age,
            retries  => $status_icons{$retries},
            domain   => extract_host($url),
            item_age => sec_to_human_time($item_age)
            };
    }
}

my %data = (
    update_data     => $update_data,
    queue_data      => $queue_data,
    generation_time => scalar gmtime($now),
    summary         => $summary
);
my $tt = Template->new(
    { INCLUDE_PATH => "$Bin/templates", ENCODING => 'UTF-8' } );
$tt->process(
    'HN-queue.tt', \%data,
    '/home/gustaf/public_html/hnlo/queue.html',
    { binmode => ':utf8' }
) || die $tt->error;

$dbh->disconnect;

sub calculate_percentage{
    my ( $new_score, $new_comments, $score,  $comments ) = @_;
    if ($score+$comments !=0) {
	return sprintf("%.1f",( $new_score + $new_comments ) / ($score+$comments) * 100 - 100)
    } else {
	return 0
    }
}
