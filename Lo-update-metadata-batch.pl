#! /usr/bin/env perl
use Modern::Perl '2015';
###
use JSON;
use Time::Piece;
use HNLOlib qw/$feeds get_dbh get_ua/;
my $ua = get_ua;

my $dbh = get_dbh;
$dbh->{sqlite_unicode} = 1;

my $batchsize = $ARGV[0] // 25;

my $sth = $dbh->prepare( "select lm.id, lo.title, lm.update_time, lm.comments,lm.score,lm.flags, lm.user_is_author, lm.is_deleted, lm.check_count from lo_metadata lm inner join lobsters lo on lo.id=lm.id where lm.check_count == 0 order by lm.update_time desc limit $batchsize") or die $dbh->errstr;
my @updates;
my @removed;
$sth->execute();
my $rownum = 1;
while (my $row=$sth->fetchrow_hashref) {
    my $id = $row->{'id'};
    printf("~~> [ %2d / %2d ] fetching submission %s: '%s' ...\n",  $rownum, $batchsize, $id, $row->{'title'});
    my $res = $ua->get( "https://lobste.rs/s/".$id.".json");
    if (!$res->is_success) {
	say "   -*- issue with ID $id -*-";
	say "   Status: ". $res->status_line;
	say "     Code: ". $res->code;
	push @removed, $id if $res->code == 404;
    } else {
	my $item = decode_json( $res->decoded_content);
	my $ut = Time::Piece->localtime();
	#	printf("update lo_metadata set update_time = %d, comments = %d, score = %d, flags = %d, user_is_author = %d, is_deleted = 0, check_count = %d where id='%s';\n",	       $ut->epoch(), (map{$item->{$_}} qw/comment_count score flags user_is_author/), 1, $id);
	push @updates, [$ut->epoch(), (map{$item->{$_}} qw/comment_count score flags user_is_author/), 0, 1, $id];
    }
    sleep 5;
    $rownum++;
}
$sth->finish;

if (@updates) {
    my $count=0;
    $sth=$dbh->prepare("update lo_metadata set update_time= ?,comments=?, score=?, flags=?,user_is_author=?,is_deleted=?, check_count=? where id=?") or die $dbh->errstr;
    for my $values (@updates) {
	$sth->execute(@{$values}) or warn $sth->errstr;
	$count++;
    }
    $sth->finish;

    say "==> $count statements executed";
}

if (@removed) {
    my $count = 0;
    $sth= $dbh->prepare("update lo_metadata set is_deleted=1, check_count = 1 where id=?") or die $dbh->errstr;
    for my $id (@removed) {
	$sth->execute( $id ) or warn $sth->errstr;
	$count++;
    }
    $sth->finish;
    say "==> $count entries marked as deleted";
}
