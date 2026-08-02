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

# target date 2025-04-14T19:27:31.000-05:00
# end date    2019-06-01
my $date_based = '2022-04-01 00:00:00';
#my $date_based = undef;

if ($date_based) {
    my $rv = $dbh->selectall_arrayref("select count(id) from lo_metadata where datetime(update_time, 'unixepoch') >= '$date_based' and check_count==0");
#    say $rv->[0][0];
    if ($rv->[0][0] >= 0 ) {
	$batchsize = $rv->[0][0]
    } elsif ($rv->[0][0] == 0) {

	die "no rows returned for date_based query, check variable value"
    }
}

=pod

 DB fields

 0      id
 1      title
 2 meta.update_time
 3 meta.comments  
 4      comments  
 5 meta.score
 6      score
 7      tags
 8 meta.flags
 9 meta.user_is_author
10 meta.is_deleted
11 meta.check_count
12      submitter
13      url

=cut

my $sql = "select 
lm.id, 
lo.title, 
lm.update_time, 
lm.comments, 
lo.comments, 
lm.score, 
lo.score, 
lo.tags, 
lm.flags, 
lm.user_is_author, 
lm.is_deleted, 
lm.check_count, 
lo.submitter, 
lo.url 
from lo_metadata lm inner join lobsters lo on lo.id=lm.id where lm.check_count == 0 ";
$sql .= $date_based ? "and datetime(lm.update_time,'unixepoch') >= '$date_based' order by lm.update_time desc" : "order by lm.update_time desc limit $batchsize";
my $sth = $dbh->prepare( $sql ) or die $dbh->errstr;

my @updates;
my @removed;
my $exit =0;
$sth->execute();
say "### got $batchsize rows from DB, starting check...";    

my $rownum = 1;
ROWS: while (my $row=$sth->fetchrow_arrayref ) { # and $rownum <= 200) {
    $| = 1; # autoflush
    my $delay;
    if ($rownum==1) { $delay = 0 }  else { $delay = 5 + ($date_based ? int rand(10) : 0) }

    printf("%2d>", $delay);
    sleep $delay;
    printf(" [%4d/%4d] ",  $rownum, $batchsize); 

    my $id = $row->[0];
    my $epoch = $row->[2];
    my $tp = Time::Piece->strptime($epoch, "%s");
    printf("fetching <https://lobste.rs/s/%s> (%s)\n",  $id, $tp->datetime());
    printf("%16s%s | [%s]\n", ' ',$row->[1], $row->[7]);
    printf("%16s<%s>\n",' ', $row->[13]);
    printf("%16ssubmitter: %s | S: %2d | C: %d\n", ' ', map {$row->[$_] } (12,6,4));
    my $res = $ua->get( "https://lobste.rs/s/".$id.".json");
    if (!$res->is_success) {
	printf("%16s-*- issue with ID %s -*-\n", ' ',$id);
	#	say "   -*- issue with ID $id -*-";
	printf("%16sStatus: %s\n", ' ' , $res->status_line);
#	say "   Status: ". $res->status_line;
	push @removed, $id if $res->code == 404;
	if ($res->code == 429) { # too many requests
	    say "Too many requests reported by source, bailing... ";
	    $exit = $res->code;
	    last ROWS;
	}
    } else {
	my $item = decode_json( $res->decoded_content);
	my $ut = Time::Piece->localtime();
	#	printf("update lo_metadata set update_time = %d, comments = %d, score = %d, flags = %d, user_is_author = %d, is_deleted = 0, check_count = %d where id='%s';\n",	       $ut->epoch(), (map{$item->{$_}} qw/comment_count score flags user_is_author/), 1, $id);
	if ($item->{flags}>0) {                     printf("%12s>>>          flags: %s\n", ' ',$item->{flags})	}
	if ($item->{user_is_author} > 0) {          printf("%12s>>> user is author: true\n",' ')	}
	if ($item->{score}         != $row->[6] ) { printf("%12s>>>          score: %d -> %d\n", ' ',$row->[6], $item->{score})	}
	if ($item->{comment_count} != $row->[4] ) { printf("%12s>>>       comments: %d -> %d\n", ' ',$row->[4], $item->{comment_count}) 	}
	push @updates, [$ut->epoch(), (map{$item->{$_}} qw/comment_count score flags user_is_author/), 0, 1, $id];
    }
#    my $delay = 5 + ($date_based ? int rand(10) : 0);
#    say "... sleeping $delay ...";
#    sleep $delay;
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

exit $exit;

