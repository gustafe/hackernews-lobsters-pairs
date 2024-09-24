#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Template;
use FindBin qw/$Bin/;
use utf8;

use JSON;
use HNLOlib qw/$feeds get_ua get_dbh extract_host get_item_from_source/;
use List::Util qw/sum/;
use Getopt::Long;
use URI;
use Time::Piece;
use Time::Seconds;
binmode(STDOUT, ":encoding(UTF-8)");
my $debug    = 0;
my $template = 'https://lobste.rs/newest/page/';
my $entry_template='https://lobste.rs/s/';
sub md_entry {
    my ($entry) = @_;
    my ( $id, $created_at, $url, $title, $author, $comments, $score, $tags ) = @$entry;
    my $lo_link = 'https://lobste.rs/s/'.$id;
    say "* [$id]($lo_link) [$title]($url) $author [$tags] $score $comments";
}

sub dump_entry {
    my ($entry) = @_;
    my ( $id, $created_at, $url, $title, $author, $comments, $score, $tags ) = @$entry;
    my $lo_link = 'https://lobste.rs/s/'.$id;
    my $title_space = 80 - ( 14 + sum (map{length($_)}($author, $score, $comments)));
    my $url_space = 80 - 8 - sum(map {length($_)} ($lo_link, $tags)) ;
    
    if (length($title) > $title_space ) {
	$title = substr( $title, 0, $title_space-1) . "\x{2026}";
    }
    if (length($url) > $url_space) {
	$url = substr( $url, 0, $url_space-1) . "\x{2026}";
    }
}
sub usage {
    say "usage: $0 [--debug] [--help] [--from_page=N]";
    exit 1;

}
my $start_time= localtime;
my $from_page;
my $help = '';
my $opt_debug;
GetOptions( 'from_page=i'=>\$from_page,'help'=>\$help, 'debug'=>\$opt_debug);
usage if $help;
$debug = 1 if $opt_debug;
my $entries;
my $ua = get_ua();
my @days;
if ($from_page ) {
    @days = ( $from_page .. $from_page + 10 );
} else {
    @days = ( 1 .. 6 );
}
my $load_fail_count  =0 ;
FETCH:
foreach my $day ( @days ) {

    my $url      = $template . $day . '.json';
    my $response = $ua->get($url);
    if ( !$response->is_success ) {
        warn "could not fetch newest entries day $day: $response->status_line";
	$load_fail_count++;
	LAST FETCH if $load_fail_count > 5;
    }

    my $list = decode_json( $response->decoded_content );
    push @{$entries}, @{$list};
    if ($from_page) {
	say "==> fetched page for $day... sleeping 5s";
	sleep 5;
    }
}

my $dbh = get_dbh;

my $all_ids = $dbh->selectall_arrayref("select id,comments from lobsters")  or die $dbh->errstr;
#my $commented_id = $dbh->selectall_arrayref("select id,no_of_comments from lo_comment_count") or die $dbh->errstr;

my %seen_ids;
foreach my $row ( @{$all_ids} ) {
    $seen_ids{ $row->[0] }=$row->[1];
}
# my %previous_comments;
# foreach my $row (@{$commented_id}) {
#     $previous_comments{$row->[0]} = $row->[1];
# }
my @updates;
my @inserts;
my @commented;

foreach my $entry ( @{$entries} ) {
    my $current_id = $entry->{short_id};
    if ( exists $seen_ids{$current_id} ) {

        push @updates,
          [
            $entry->{title}, $entry->{score},
            $entry->{comment_count}, join( ',', @{ $entry->{tags} } ),
            $current_id
          ];
	if ($seen_ids{$current_id} != $entry->{comment_count}) {
	    push @commented, $entry;
	}
    }
    else {

        push @inserts,
          [
            $current_id,
            $entry->{created_at},
            $entry->{url} ? $entry->{url} : '',
            $entry->{title},
	   #            $entry->{submitter_user}->{username},
	   $entry->{submitter_user},
            $entry->{comment_count},
            $entry->{score},
            @{ $entry->{tags} } ? join( ',', @{ $entry->{tags} } ) : ''
          ];
	push @commented, $entry if $entry->{comment_count}>0;

    }
    # my $created_at = $entry->{created_at};
    # # strip colon from TZ, remove fractional seconds
    # $created_at =~ s/:(\d+)$/$1/;
    # $created_at =~ s/\.(\d{3})//;
    # my $dt_created_at = Time::Piece->strptime($created_at,"%FT%T%z");
    # # only grab the last 48 hours of comments, skip 'ask' submissions
    # if ($entry->{comment_count}>0 # and	($start_time->epoch - $dt_created_at->epoch <= 48 * 3600)
    #    ) {
    # 	# next if (grep {'ask'} @{$entry->{tags}});
    # 	push @commented, {id=>$current_id,
    # 			  comment_count=>sprintf("%3d",$entry->{comment_count}),
    # 			  title=>$entry->{title}};
    # }
}

my $sth;
my $count = 0;
$dbh->{PrintError} = 1;

if (@inserts) {
    print "\n";
    $sth = $dbh->prepare( $feeds->{lo}->{insert_sql} ) or die $dbh->errstr;
    foreach my $values (@inserts) {
        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }
    $sth->finish();
    for my $el (@inserts) {
	my $url = $el->[2];
	my $host = extract_host( $url );
	push @$el,$host;
    }

}

if (@updates) {
    $count = 0;
    $sth = $dbh->prepare( $feeds->{lo}->{update_sql} ) or die $dbh->errstr;
    foreach my $values (@updates) {

        $sth->execute( @{$values} ) or warn $sth->errstr;
        $count++;
    }

    $sth->finish;
}

### Handle comments
my %comments_report;
#if (@commented) {
if (0) {

    my @new_comment_inserts;
    my @new_comment_updates;
    my $comment_ids = $sth->selectall_arrayref("select distinct id from lo_comments");
    my %ids_have_comments;
    for my $id (@{$comment_ids}) {
	$ids_have_comments{$id}++;
    }
    for my $entry (@commented) {
	if (exists $ids_have_comments{$entry->{short_id}}) {
	    push @new_comment_updates, $entry->{short_id}
	} else {
	    push @new_comment_inserts, $entry->{short_id}
	}
    }
    my $sth_insert=$dbh->prepare("insert into lo_comments (id,comment_id,created_at,updated_at,is_deleted,is_moderated,score,flags,parent_comment,comment_plain,depth,commenting_user) values (?,?,?,?,?,?,?,?,?,?,?,?)") or die $dbh->errstr;
    # insert data
    for my $id (@new_comment_inserts) {
	say "==> gettting insert data for submission $id...";
	my $item_ref=get_item_from_source('lo', $id);
	for my $comment (@{$item_ref->{comment_list}->[0]}) {
	    my ($comment_id, $created_at, $updated_at, $is_deleted, $is_moderated,	$score, $flags, $parent_comment, $comment_plain, $depth, $commenting_user ) = map { $comment->{$_}} qw/short_id created_at updated_at is_deleted is_moderated score flags parent_comment comment_plain depth commenting_user/;
	    $sth_insert->execute($id,$comment_id, $created_at, $updated_at, $is_deleted, $is_moderated,	$score, $flags, $parent_comment, $comment_plain, $depth, $commenting_user ) or warn $sth->errstr;
	
	}
	say "... sleeping 5s...";
	sleep 5;
#	$sth->finish;
    }
    #    my $sth_insert=$dbh->prepare("insert into lo_comments (id,comment_id,created_at,updated_at,is_deleted,is_moderated,score,flags,parent_comment,comment_plain,depth,commenting_user) values (?,?,?,?,?,?,?,?,?,?,?,?)") or die $dbh->errstr;
    my $sth_update=$dbh->prepare("update lo_comments set updated_at=?, is_deleted=?, is_moderated=?, score=?, flags=? where id=? and comment_id=?") or die $dbh->errstr;

    for my $id (@new_comment_updates) {
	my %existing_comments;
	my $comments_for_id = $sth->fetchall_arrayref("select * from lo_comments where id=?",$id) or warn $sth->errstr;
	# gather existing info, for comparison

	for my $row (@$comments_for_id) {
	    my ( $db_id, $comment_id, $created_at, $updated_at, $is_deleted, $is_moderated, $score, $flags, $parent_comment, $comment_plain, $depth, $commenting_user) = @$row;
	    $existing_comments{$comment_id} = {updated_at=>$updated_at , is_deleted=>$is_deleted, is_moderated=>$is_moderated, score=>$score,flags=>$flags};
	    
	}
	
	say "==> gettting update data for submission $id...";
	my $item_ref=get_item_from_source('lo', $id);
	for my $comment (@{$item_ref->{comment_list}->[0]}) {
	    my ($comment_id, $created_at, $updated_at, $is_deleted, $is_moderated,	$score, $flags, $parent_comment, $comment_plain, $depth, $commenting_user ) = map { $comment->{$_}} qw/short_id created_at updated_at is_deleted is_moderated score flags parent_comment comment_plain depth commenting_user/;
	    if (exists $existing_comments{$comment_id}) { # update
		if ($existing_comments{$comment_id}->{is_deleted} != $is_deleted) {
		    $comments_report{$comment_id}->{is_deleted} = $is_deleted;
		    $comments_report{$comment_id}->{comment_plain}=$comment_plain;
		}
		if ($existing_comments{$comment_id}->{is_moderated} != $is_moderated) {
		    $comments_report{$comment_id}->{is_moderated} = $is_moderated;
		    $comments_report{$comment_id}->{comment_plain}=$comment_plain;
		}
		if ($existing_comments{$comment_id}->{updated_at} != $updated_at) {
		    $comments_report{$comment_id}->{updated_at}= $updated_at;
		    $comments_report{$comment_id}->{comment_plain}=$comment_plain;
		}

		$sth_update->execute($updated_at, $is_deleted, $is_moderated, $score, $flags, $id, $comment_id) or warn $sth_update->errstr;
	    } else {
		$sth_insert->execute($id,$comment_id, $created_at, $updated_at, $is_deleted, $is_moderated,	$score, $flags, $parent_comment, $comment_plain, $depth, $commenting_user ) or warn $sth->errstr;
	    }
	}
	say "... sleeping 5s...";
	sleep 5;
    }
}


# my @handled_commented;
# if (@commented) {
#     my $checked_time = gmtime;
#     my $sth_insert=$dbh->prepare("insert into lo_comment_count values(?,?,?)") or die $dbh->errstr;
#     my $sth_update=$dbh->prepare("update lo_comment_count set no_of_comments=?, checked_time=? where id=?") or die $dbh->errstr;
#     for my $entry (@commented) {
# 	if (exists $previous_comments{$entry->{id}} and $previous_comments{$entry->{id}} != $entry->{comment_count}) {
# 	    $sth_update->execute($entry->{comment_count},$checked_time->strftime("%Y-%m-%dT%H:%M:%S%z"), $entry->{id} ) or warn $sth_update->errstr;
# 	    push @handled_commented, $entry;
# 	} elsif (!$previous_comments{$entry->{id}}) {

# 	    $sth_insert->execute($entry->{id},$entry->{comment_count},$checked_time->strftime("%Y-%m-%dT%H:%M:%S%z")) or warn $sth_insert->errstr;
# 	    push @handled_commented, $entry;
# 	} else { # unchanged
# 	    next;
# 	}
#     }
#     $sth_insert->finish;
#     $sth_update->finish;
# }
my $end_time = localtime;
#my $tz = $time->tzoffset;
my %data = (count=>$count,
	    entries=>\@inserts,
	    updates=>scalar @updates,
	    commented=>\@commented,
	    starttime=>$start_time->strftime("%Y-%m-%dT%H:%M:%S%z"),
	    endtime=>$end_time->strftime("%Y-%m-%dT%H:%M:%S%z"),
	    runtime=> $end_time->epoch - $start_time->epoch,
	   );
#if (scalar @inserts) {
if ($count) {

    my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
    $tt->process( 'Lo-log-txt.tt', \%data) || die $tt->error;
}
