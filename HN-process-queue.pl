#! /usr/bin/env perl
use Modern::Perl '2015';
###
use utf8;
use DateTime;
use JSON;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use HNLOlib qw/get_dbh $sql $feeds get_ua/;
my $debug = 1;
my $cutoff = 31940335;
binmode(STDOUT, ':encoding(UTF-8)');

my $dbh = get_dbh;
my $stmt = "select hn.id, title, score,comments,q.retries from hackernews hn inner join hn_queue q on q.id=hn.id where q.age <= strftime('%s','now')";
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
for my $row (@$rows) {
    my ( $id, $title, $score, $comments, $retries ) = @$row;
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
	next;
    }
    my $item = decode_json( $payload);
    if (defined $item->{dead} or defined $item->{deleted}) {
	say "XX> $id «$title» dead or deleted, removing" if $debug;
	push @removes, $id;
	next;
    }
    if ($item->{title} eq $title and $item->{descendants} == $comments and $item->{score} == $score ) { # no change
	if ($retries == 0 and $score == 1 and $comments == 0) {
	    say "X1> $id «$title» unchanged and low score, removing" if $debug;
	    push @removes, $id
	} elsif ($id<=$cutoff) {
	    say "XC> $id «$title» S:$score C:$comments unchanged and id under cutoff, removing" if $debug;
	    push @removes, $id;
	} elsif ($retries > 2) {
	    say "XR> $id «$title» S:$score C:$comments unchanged for $retries retries, removing" if $debug;
	    push @removes, $id
	} else {
	    say "R$retries> $id «$title» S:$score C:$comments added to retries" if $debug;
	    push @retries, {id=>$id, retries=>$retries+1}
	}
    } else {
	say "U$retries> $id «$title» metadata changed, adding to updates" if $debug;
	my @msg ;

	if ($title ne $item->{title}) { push @msg, "T: $title → " . $item->{title}  }
	if ($score != $item->{score}) { push @msg, "S:$score→" . $item->{score} }
	if ($comments != $item->{descendants} ) { push @msg, "C:$comments→". $item->{descendants} }
	say '    '. join(' | ', @msg) if $debug;
	push @updates, {id=>$id, title=>$item->{title}, score=>$item->{score}, comments=>$item->{descendants}};
	push @retries, {id=>$id, retries=>0};

    }
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
    my $now = time;
    my $sth = $dbh->prepare("update hn_queue set age = ?, retries= ? where id=?") or die $dbh->errstr;
    my $delay = $now + 3600;
    my $count = 0;
    for my $item (@retries) {
	$sth->execute($delay + 5*60*$count, $item->{retries}, $item->{id}) or warn $sth->errstr;
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
