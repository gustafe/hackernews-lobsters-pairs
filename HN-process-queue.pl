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
binmode(STDOUT, ':utf8');
sub extract_host {
    my ( $in ) = @_;
    my $uri = URI->new( $in );
    my $host;
    eval {
	$host = $uri->host;
	1;
    } or do {
	my $error = $@;
	$host= 'www';
	};
    $host =~ s/^www\.//;
    return $host;
}
my %status_icons=(
dead_or_deleted =>  '<abbr title="item is dead or deleted">💀</abbr>',
remove_under_cutoff =>  '<abbr title="item is old and unchanged">❌🧟</abbr>',
item_too_old =>  '<abbr title="item is old and unchanged">❌🧟</abbr>',
		  removed_unchanged_after_2_retries =>  '<abbr title="item is unchanged">❌=</abbr>',
retried =>  '<abbr title="item is retried">♻️</abbr>',
retry_low => '<abbr title="item is retried despite being low score">♻️↓</abbr>',
updated =>  '<abbr title="item is updated">🔄</abbr>',);


my $debug = 0;
my $cutoff = 31940335;

my $now = time;
my $dbh = get_dbh;
my $stmt = "select hn.id, title,url, score,comments, strftime('%s','now') - strftime('%s',created_time),q.retries from hackernews hn inner join hn_queue q on q.id=hn.id where q.age <= strftime('%s','now')";
my $rows = $dbh->selectall_arrayref( $stmt ) or die $dbh->errstr;
if (scalar @$rows == 0) {
    say "no items in queue, exiting.";
    exit 0;
}
say "Number of items: ". scalar @$rows if $debug;
my $ua=get_ua();
my @removes;
my @retries;
my @updates;
my $cutoff_shown = 0;
my $dhms;
my %seen;
my $update_data;
for my $row (sort {$a->[0] <=> $b->[0]} @$rows) {
    my ( $id, $title,$url, $score, $comments, $item_age, $retries ) = @$row;
    $update_data->{$id} = {title=>$title, url=>$url, score=>$score, comments=>$comments, item_age=>sec_to_human_time($item_age), retries=>$retries, domain=>extract_host($url)};
      #, domain=>extract_host($url)};
    # fugly hack to deal with duplicates
    if ($seen{$id}) {
	next;
    } else {
	$seen{$id}++
    }
    $dhms = sec_to_dhms( $item_age );
    if ($id>$cutoff and !$cutoff_shown) {
	say "~~> cutoff ID: $cutoff <~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" if $debug;
	$cutoff_shown = 1; 
    }
    my $item_url = $feeds->{hn}->{api_item_href} . $id . '.json';
    my $res = $ua->get( $item_url);
    if (!$res->is_success) {
	warn $res->status_line;
	warn "--> fetch for $id failed\n";
	next;
    }
    my $payload = $res->decoded_content;
    if ($payload eq 'null') {
	say "X0> $id is null" if $debug;
	push @removes, $id;
	$update_data->{$id}->{status} = 'null_content';
	next;

    }
    my $item = decode_json( $payload);
    if (defined $item->{dead} or defined $item->{deleted}) {
	say "XX> $id «$title» dead or deleted, removing [$dhms]" if $debug;
	push @removes, $id;
	$update_data->{$id}->{status} = $status_icons{'dead_or_deleted'} ;
	next;
    }
    if ($item->{title} eq $title and $item->{descendants} == $comments and $item->{score} == $score ) { # no change
	if ($retries == 0 and $score <=2 and $comments == 0) {
	    say "RL> $id «$title» S:$score C:$comments unchanged and low score, bumping retries [$dhms]" if $debug;
	    push @retries, {id=>$id, retries=>2};
	    $update_data->{$id}->{status} = $status_icons{'retry_low'};
	    $update_data->{$id}->{changes}->{retries} = 2;
	} elsif ($id<=$cutoff) {
	    say "XC> $id «$title» S:$score C:$comments unchanged and id under cutoff, removing [$dhms]" if $debug;
	    $update_data->{$id}->{status} = $status_icons{remove_under_cutoff};
	    push @removes, $id;
	} elsif ($retries >=2) {
	    say "XR> $id «$title» S:$score C:$comments unchanged for $retries retries, removing [$dhms]" if $debug;
	    $update_data->{$id}->{status} = $status_icons{'removed_unchanged_after_'.$retries.'_retries'};
	    push @removes, $id
	} else {
	    say "R$retries> $id «$title» S:$score C:$comments added to retries [$dhms]" if $debug;
	    $update_data->{$id}->{status} = $status_icons{'retried'};
	    $update_data->{$id}->{changes}->{retries} = $retries+ 1;
	    push @retries, {id=>$id, retries=>$retries+1}
	}
    } elsif ($item_age >3 * 24 * 3600) {
	$update_data->{$id}->{status} = $status_icons{'item_too_old'};
	push @removes, $id;
    
    } else {
	print "U$retries> $id «$title» metadata changed, adding to updates | " if $debug;
	my @msg ;

	if ($title ne $item->{title}) {
	    push @msg, "T:$title→" . $item->{title};
	    $update_data->{$id}->{changes}->{title} = $item->{title};

	}
	if ($score != $item->{score}) {
	    push @msg, "S:$score→" . $item->{score};
	    $update_data->{$id}->{changes}->{score} = $item->{score};

	}
	if ($comments != $item->{descendants} ) {
	    push @msg, "C:$comments→". $item->{descendants};
	    $update_data->{$id}->{changes}->{comments} = $item->{descendants};

	}
	say join(' | ', @msg). " [$dhms]" if $debug;
	$update_data->{$id}->{status} = $status_icons{'updated'} ;
	$update_data->{$id}->{changes}->{retries}  = 0;
	#	$update_data->{$id}->{changes} = join(' | ' , @msg);
	push @updates, {id=>$id, title=>$item->{title}, score=>$item->{score}, comments=>$item->{descendants}};
	push @retries, {id=>$id, retries=>0};

    }
    my $new_score = defined $update_data->{$id}->{changes}->{score} ?
      $update_data->{$id}->{changes}->{score} :
      $update_data->{$id}->{score};
    my $new_comments = defined $update_data->{$id}->{changes}->{comments} ?
      $update_data->{$id}->{changes}->{comments} :
      $update_data->{$id}->{comments};
    my $percentage = ( $new_score + $new_comments ) / ($update_data->{$id}->{score} + $update_data->{$id}->{comments} ) * 100-100 if ( $new_score + $new_comments )>100;
    $update_data->{$id}->{changes}->{percentage} = sprintf("%.1f",$percentage) if ( defined $percentage and $percentage> 0);
}

if (scalar @removes > 0) {
    say "removing: ".scalar @removes if $debug;

    my $sth = $dbh->prepare("delete from hn_queue where id = ?") or die $dbh->errstr;
    for my $id (@removes) {
	$sth->execute( $id ) or warn $sth->errstr;
    }
}
if (@retries > 0) {
    say "retrying: ".scalar @retries if $debug;

    my $sth = $dbh->prepare("update hn_queue set age = ?, retries= ? where id=?") or die $dbh->errstr;
    my $count = 0;
    for my $item (sort {$a->{retries} <=> $b->{retries}} @retries) {
	$sth->execute($now + 2*3600*$item->{retries} + 5*60*$count, $item->{retries}, $item->{id}) or warn $sth->errstr;
	$count++;
    }
}
if (scalar @updates> 0) {
    say "updating: ".scalar @updates if $debug;
    my $sth = $dbh->prepare("update hackernews set title=?,score=?,comments=? where id=?") or die $dbh->errstr;
    for my $item (@updates) {
	$sth->execute( $item->{title}, $item->{score}, $item->{comments}, $item->{id}) or warn $sth->errstr;
    }
}
my $summary = { removes => scalar @removes, retries => scalar @retries,
		updates => scalar @updates };
my %statuses;
for my $k (keys %$update_data) {
    next unless defined $update_data->{$k}->{status};
   $statuses{ $update_data->{$k}->{status}}++
}
for my $k (sort keys %statuses) {
    say "$k =>  $statuses{$k}," if $debug;
}

$stmt ="select hn.id, url, title, score,comments, q.age-strftime('%s','now'),q.retries,strftime('%s','now') - strftime('%s',created_time) from hackernews hn inner join hn_queue q on q.id=hn.id where q.age<= strftime('%s','now')+1*3600 order by q.age-strftime('%s','now'), id";
$rows = $dbh->selectall_arrayref( $stmt ) or die $dbh->errstr;
my $queue_data;
if (scalar @$rows > 0) {
    for my $r (@$rows) {
	my ( $id, $url, $title, $score,$comments,$age, $retries, $item_age) = @$r;
	push @{$queue_data}, {id=>$id, url=>$url,title=> $title,score=>$score,comments=>$comments,next_run=>$age,retries=>$retries, domain=>extract_host($url),item_age=>sec_to_human_time($item_age)};
#			      ,domain=>extract_host($url)};
	say "$age $id $title <$url> $score $comments $retries" if $debug;
    }
}

my %data = (update_data => $update_data, queue_data=>$queue_data, generation_time=> scalar gmtime($now), summary => $summary);
my $tt = Template->new({INCLUDE_PATH=>"$Bin/templates", ENCODING=>'UTF-8'});
$tt->process( 'HN-queue.tt', \%data,'/home/gustaf/public_html/hnlo/queue.html', {binmode=>':utf8'}) || die $tt->error;
#  
$dbh->disconnect;
