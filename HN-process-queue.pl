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
use List::Util qw/max/;
use Data::Dump qw/dump/;
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
    1 => "\N{LARGE GREEN CIRCLE}",
    2 => "\N{LARGE YELLOW CIRCLE}",
    3 => "\N{LARGE RED CIRCLE}",
    dead_or_deleted => "\N{U+1F480}",
    item_too_old => "\N{CROSS MARK}\N{ZOMBIE}",
    remove_low_percentage=>"\N{CROSS MARK}&percnt;",
    remove_under_cutoff => "\N{CROSS MARK}\N{ZOMBIE}",
    removed_unchanged_after_3_retries => "\N{CROSS MARK}=",
    retried => "\N{BLACK UNIVERSAL RECYCLING SYMBOL}\N{U+FE0F}",
    retry_low => "\N{U+267B}\N{U+FE0F}↓",
		    updated => "\N{U+1F504}",
		    star=>"\N{U+2B50}",
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
my @deads;
my $cutoff_shown = 0;
my $dhms;
my %seen;
my $current;
my $new;
my %frontpage;
# get current front page
my $topview_url = 'https://hacker-news.firebaseio.com/v0/topstories.json';
my    $response = $ua->get($topview_url);
if ( !$response->is_success ) {
    warn $response->status_line;
}
my $top_ids = decode_json( $response->decoded_content );
my $rank = 1;
foreach my $id (@$top_ids) {
    $frontpage{$id}=$rank;
    $rank++;
}


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
    if (exists $frontpage{$id} and $frontpage{$id}<=30) {
	say "==> $id $title on frontpage: $frontpage{$id}";
	$current->{$id}->{frontpage} = "$status_icons{star}($frontpage{$id})";
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
	push @deads, {id=>$id};
        $current->{$id}->{status} = $status_icons{'dead_or_deleted'};
	say "==> $id $title <$url> S:$score C:$comments is dead or deleted";
        next;
    } 

    # percentage change
    my $percentage = calculate_percentage($item->{score},$item->{descendants},
					 $score, $comments);

    # item is older than 24h and has low change percentage (but is not a catch-up item below cutoff)
    $new->{$id}->{percentage} = $percentage if $percentage>0.0;
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

        if ( $retry_data->{level} == 1 and $score <= 2 and $comments == 0 ) {

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

if (scalar @deads > 0) {
    my $sth=$dbh->prepare("delete from hackernews where id = ?") or die $dbh->errstr;
    for my $item (@deads) {
	$sth->execute( $item->{id} ) or warn $sth->errstr;
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

	my $retry_count = $item->{count};
	if ($retry_count>999) {
	    warn "!!> retry count for ID $item->{id} exceeds 3 digits, capping to 999";
	    $retry_count=999;
	}

	$sth->execute( $now + 15 * $item->{count} + 5 * 60 * $count,
            $item->{level}*1_000+$retry_count, $item->{id} )
            or warn $sth->errstr;

        $count++;
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
	       updates => scalar @updates,
	       deads=>scalar @deads,
};
# my $key_hash;
# for my $val (values %status_icons) {
#     $key_hash->{$val}++;
# }

$stmt
    = "select hn.id, url, title, score,comments, q.age,q.retries,
strftime('%s','now') - strftime('%s',created_time) 
from hackernews hn 
inner join hn_queue q on q.id=hn.id 
 order by q.age, q.id";
$rows = $dbh->selectall_arrayref($stmt) or die $dbh->errstr;
$summary->{items_in_queue} = scalar @$rows;
$now = time;
my $queue_data;
my $retry_summary;
if ( scalar @$rows > 0 ) {
    for my $r (@$rows) {
        my ( $id, $url, $title, $score, $comments, $age, $retries, $item_age )
	  = @$r;

	my $retry_data = decode_retry( $retries );
	if ($age <= $now+3600 ) {
	    my $data =             {
            id       => $id,
            url      => $url,
            title    => $title,
            score    => $score,
            comments => $comments,
            next_run => $age,
	     retry_level  => $status_icons{$retry_data->{level}},
	     retry_count => $retry_data->{count},
            domain   => extract_host($url),
            item_age => sec_to_human_time($item_age),
				   };
	    if (exists $frontpage{$id} and $frontpage{$id}<=30) {
		say "==> $id $title on frontpage: $frontpage{$id}";
		$data->{frontpage} = "$status_icons{star}($frontpage{$id})";
	    }

	    push @{$queue_data}, $data;
	}
	$retry_summary->{$retry_data->{level}}->{$retry_data->{count}}++;
    }
}
#dump $retry_summary;
my $max_retry_count= max(map {keys %{$retry_summary->{$_}}} keys %$retry_summary );
my $retry_table = 'L\C|';

$retry_table .= join('', map {sprintf(" %2d|", $_)} (1..$max_retry_count));

$retry_table .= "\n";
$retry_table.= '---+';
$retry_table.= '---+' x $max_retry_count . "\n";
for my $level (sort keys %$retry_summary) {
    $retry_table .=sprintf(' %d |', $level);
    for my $count (1..$max_retry_count) {
	if (defined $retry_summary->{$level}->{$count}) {
	    $retry_table.=sprintf("%3d|", $retry_summary->{$level}->{$count});
	} else {
	    $retry_table.=sprintf("%3s|",' ');
	}
    }
    $retry_table.= "\n";
}
my %data = (
	    current     => $current,
	    new=>$new,
    queue_data      => $queue_data,
    generation_time => scalar gmtime($now),
	    summary         => $summary,
	    #	    key_hash=>$key_hash,
	    retry_summary => $retry_summary,
	    max_retry_count=>[1 .. $max_retry_count],
	    retry_table=>$retry_table,
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
