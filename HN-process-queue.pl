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
sub decode_retry;
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
    dead_or_deleted => '<abbr title="item is dead or deleted">."\N{SKULL}".</abbr>',
    remove_under_cutoff => '<abbr title="item is old and unchanged">'."\N{CROSS MARK}\N{ZOMBIE}".'</abbr>',
    item_too_old => '<abbr title="item is old and unchanged">'."\N{CROSS MARK}\N{ZOMBIE}".'</abbr>',
    removed_unchanged_after_3_retries => '<abbr title="item is unchanged">'."\N{CROSS MARK}".'=</abbr>',
    retried => "<abbr title='item is retried'>\N{BLACK UNIVERSAL RECYCLING SYMBOL}</abbr>",
    retry_low => "<abbr title='item is retried despite being low score'>\N{U+267B}↓</abbr>",
    updated => "<abbr title='item is updated'>\N{U+1F504}</abbr>",
    1 => "<abbr title='retry level 1'>\N{LARGE GREEN CIRCLE}</abbr>",
    2 => "<abbr title='retry level 2'>\N{LARGE YELLOW CIRCLE}</abbr>",
    3 => "<abbr title='retry level 3'>\N{LARGE RED CIRCLE}</abbr>",
    remove_low_percentage=>'<abbr title="old title with low percentage change">'."\N{CROSS MARK}".'&percnt;</abbrev>',
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
my $current;
my $new;

for my $row ( sort { $a->[0] <=> $b->[0] } @$rows ) {
    my ( $id, $title, $url, $score, $comments, $item_age, $retries ) = @$row;
    my $retry_data = decode_retry( $retries );
    $current->{$id} = {
        title    => $title,
        url      => $url,
        score    => $score,
        comments => $comments,
        item_age => sec_to_human_time($item_age),
			   retry_count  => $retry_data->{count},
			   retry_level=> $status_icons{$retry_data->{level}},
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
        $current->{$id}->{status} = 'null_content';
        next;

    }

    my $item = decode_json($payload);

    if ( defined $item->{dead} or defined $item->{deleted} ) {
        push @removes, {id=>$id};
        $current->{$id}->{status} = $status_icons{'dead_or_deleted'};
        next;
    } 

    # percentage change
    my $percentage = calculate_percentage($item->{score},$item->{descendants},
					 $score, $comments);

    # item is older than 24h and has low change percentage (but is not a catch-up item below cutoff)
    $new->{$id}->{percentage} = $percentage if $percentate>0.0;
    if ($item_age>2*24*3600 and abs($percentage)<=1.0 and $id>$cutoff) {
            $current->{$id}->{status}
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

            push @retries, { id => $id, level => 3, count=>$retry_data->{count}+1 };
            $current->{$id}->{status} = $status_icons{'retry_low'};
            $new->{$id}->{retry_level} = $status_icons{3};
	    $new->{$id}->{retry_count} = $retry_data->{count}+1;
	    next;
        }
        elsif ( $id <= $cutoff ) {

            $current->{$id}->{status}
                = $status_icons{remove_under_cutoff};
            push @removes, {id=>$id};
	    next;
        }
        elsif ( $retry_data->{level} >= 3 ) {

            $current->{$id}->{status}
                = $status_icons{ 'removed_unchanged_after_'
                    . 3
                    . '_retries' };
            push @removes, {id=>$id};
	    next;
        } 
        else {

            $current->{$id}->{status} = $status_icons{'retried'};
            $new->{$id}->{retry_count} = $retry_data->{count}+1;
	    $new->{$id}->{retry_level} = $status_icons{$retry_data->{level}+1};
            push @retries, { id => $id,
			     level => $retry_data->{level} + 1,
			     count=>$retry_data->{count}+1 };
	    next;
        }
    }
    else {

        my @msg;

        if ( $title ne $item->{title} ) {
            push @msg, "T:$title→" . $item->{title};
            $new->{$id}->{title} = $item->{title};
        }
        if ( $score != $item->{score} ) {
            push @msg, "S:$score→" . $item->{score};
            $new->{$id}->{score} = $item->{score};
        }
        if ( $comments != $item->{descendants} ) {
            push @msg, "C:$comments→" . $item->{descendants};
            $new->{$id}->{comments} = $item->{descendants};
        }

        $current->{$id}->{status} = $status_icons{'updated'};
        $new->{$id}->{retry_level} = $status_icons{1};
	$new->{$id}->{retry_count} = $retry_data->{count}+1;
	
        push @updates,
            {
            id       => $id,
            title    => $item->{title},
            score    => $item->{score},
            comments => $item->{descendants}
            };
        push @retries, { id => $id, level => 1, count=>$retry_data->{count}+1 };
	next;
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
    for my $item ( sort { $a->{level} <=> $b->{level} } @retries ) {
        $sth->execute( $now + 2 * 3600 * $item->{level} + 5 * 60 * $count,
            $item->{level}*1_000+$item->{count}, $item->{id} )
            or warn $sth->errstr;

        $count++;
    }
}

# update item metadata for display
# {
#     no warnings 'uninitialized';
#     for my $item (@removes ,@retries) {
# 	$current->{$item->{id}}->{retry_level} = $status_icons{$current->{$item->{id}}->{retry_level}};
# 	if (defined $new->{$item->{id}} and ($new->{$item->{id}}->{retry_level} )) {
# 	    $new->{$item->{id}}->{retry_level} = $status_icons{$new->{$item->{id}}->{retry_level}};
# 	}
#     }
# }
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
	my $retry_data = decode_retry( $retries );
        push @{$queue_data},
            {
            id       => $id,
            url      => $url,
            title    => $title,
            score    => $score,
            comments => $comments,
            next_run => $age,
	     retry_level  => $status_icons{$retry_data->{level}},
	     retry_count => $retry_data->{count},
            domain   => extract_host($url),
            item_age => sec_to_human_time($item_age)
            };
    }
}

my %data = (
	    current     => $current,
	    new=>$new,
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

sub decode_retry {
    my ( $in ) = @_;
    my ( $level, $count );
    if ($in >=0 and $in <= 2) { # old format
	$level = $in+1;
	$count = 1;
    } elsif ($in >= 1_000) {
	$count = $in % 1_000;
	$level = ($in - $count)/1_000;
    } else {
	warn "invalid input: $in";
    }
    return { level=>$level, count=>$count };
}
