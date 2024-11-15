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
use Data::Dump qw/dump/;

use Time::HiRes qw/gettimeofday tv_interval/;
sub sec_to_hms;


binmode(STDOUT, ":encoding(UTF-8)");
my $debug    = 0;
my $template = 'https://lobste.rs/newest/page/';
my $entry_template='https://lobste.rs/s/';
my $comment_template='https://lobste.rs/c/';
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

sub sec_to_hms {
    my ($s) = @_;
    return sprintf("Duration: %.2f s", $s);
}

my $start_tv = [gettimeofday];
my $start_time= Time::Piece->localtime();
my $from_page;
my $help = '';
my $opt_debug;
GetOptions( 'from_page=i'=>\$from_page,'help'=>\$help, 'debug'=>\$opt_debug);
usage if $help;
$debug = 1 if $opt_debug;
my @Log;
my $entries;
my $ua = get_ua();
my @days;
if ($from_page ) {
    @days = ( $from_page .. $from_page + 10 );
} else {
    @days = ( 1 .. 16 );
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
	push @Log, "==> fetched page for $day... sleeping 5s";
	sleep 5;
    }
}

my $dbh = get_dbh;

my $all_ids = $dbh->selectall_arrayref("select id,comments from lobsters")  or die $dbh->errstr;
my $comment_ids = $dbh->selectall_arrayref("select id,comment_id,updated_at,is_deleted,is_moderated,score,flags from lo_comments") or die $dbh->errstr;

my %seen_ids;
foreach my $row ( @{$all_ids} ) {
    $seen_ids{ $row->[0] }=$row->[1];
}
my %ids_have_comments;
for my $row (@{$comment_ids}) {
    $ids_have_comments{$row->[0]}->{$row->[1]} = {
						  updated_at=>$row->[2],
						  is_deleted=>$row->[3],
						  is_moderated=>$row->[4],
						  score=>$row->[5],
						  flags=>$row->[6],
						 };
}

my @updates;
my @inserts;
my @new_comment_inserts;
my @new_comment_updates;
my %skip_entries_for_comments;
while (<DATA>) {
    chomp;
    $skip_entries_for_comments{$_}++;
}
foreach my $entry ( @{$entries} ) {
    my $current_id = $entry->{short_id};
    if ( exists $seen_ids{$current_id} ) {

        push @updates,
          [
            $entry->{title}, $entry->{score},
            $entry->{comment_count}, join( ',', @{ $entry->{tags} } ),
            $current_id
          ];
	# do we need to update comments?
#	my $comments_in_db = scalar keys %{$ids_have_comments{$current_id}};
					     
		if ($seen_ids{$current_id} != $entry->{comment_count}	and ! exists $skip_entries_for_comments{$current_id}   ) {
	#if (! exists $skip_entries_for_comments{$current_id}  ) {

	    if ($ids_have_comments{$current_id}) {
		push @new_comment_updates, $entry;
	    } 
	}
    }
    else {

        push @inserts,
          [
	   $current_id,
	   $entry->{created_at},
	   $entry->{url} ? $entry->{url} : '',
	   $entry->{title},
	   $entry->{submitter_user},
	   $entry->{comment_count},
	   $entry->{score},
	   @{ $entry->{tags} } ? join( ',', @{ $entry->{tags} } ) : ''
          ];
    }
    # entries with comments we haven't seen before 
    if (!exists $ids_have_comments{$current_id} 	and ! exists $skip_entries_for_comments{$current_id}  ) {
	push @new_comment_inserts, $entry if $entry->{comment_count}>0;
    }
}

my $sth;
my $count = 0;
$dbh->{PrintError} = 1;

if (@inserts) {
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

my @fields = qw/id comment_id created_at updated_at is_deleted is_moderated score flags parent_comment comment_plain depth commenting_user/;
my @placeholders = map{'?'} @fields;
my $sth_insert = $dbh->prepare("insert into lo_comments (".join(',',@fields).") values (".join(',',@placeholders).")") or die $dbh->errstr;


if (@new_comment_inserts) {

    # insert data
    for my $entry (@new_comment_inserts) {
	#	push @Log, "==> getting insert data for submission ".$entry->{short_id}.' "'.$entry->{title}.'"';
	my $host = extract_host( $entry->{url} );
	# push @Log, sprintf("==> getting comment data for submission \"%s\" <%s%s> (%s) (S: %d, C: %d)",
	# 		   $entry->{title}, $entry_template, $entry->{short_id},
	# 		   $host,
	# 		   $entry->{score}, $entry->{comment_count});
	my $item_ref=get_item_from_source('lo', $entry->{short_id});
	for my $comment (@{$item_ref->{comment_list}->[0]}) {
	    my @data=( $entry->{short_id},$comment->{short_id});
	    for my $field_name (@fields[2..$#fields]) {
		push @data, $comment->{$field_name};
	    }

	    #push @Log, "~~> inserting NEW comment ".$comment->{short_id}." by ".$comment->{commenting_user};
	    # push @Log, sprintf("  ++> inserting NEW comment by %s <%s%s>",
	    # 		       $comment->{commenting_user},
	    # 		       $comment_template, $comment->{short_id});
	    
	    $sth_insert->execute(@data) or warn $sth->errstr;
	}

    }
}

my $sth_update = $dbh->prepare("update lo_comments set updated_at=?, is_deleted=?, is_moderated=?, score=?, flags=? where id=? and comment_id=?") or die $dbh->errstr;

if (@new_comment_updates) {
    for my $entry (@new_comment_updates) {
     	#push @Log, "==> getting update data for submission ".$entry->{short_id}.' "'.$entry->{title}.'"';
	my $host = extract_host( $entry->{url} );
	# push @Log, sprintf("==> getting comment data for submission \"%s\" <%s%s> (%s) (S: %d, C: %d)",
	# 		   $entry->{title}, $entry_template,$entry->{short_id},
	# 		   $host,
	# 		    $entry->{score},
	# 		   $entry->{comment_count});

     	my $item_ref=get_item_from_source('lo', $entry->{short_id});
	for my $comment (@{$item_ref->{comment_list}->[0]}) {
	    my ( $is_unseen, $is_changed) = (0,0);
	    if ($ids_have_comments{ $entry->{short_id} }->{ $comment->{short_id}}) {
		my $prev = $ids_have_comments{ $entry->{short_id} }->{ $comment->{short_id}};
		
		if ($comment->{updated_at} ne $prev->{updated_at}) {
		    push @Log, sprintf("~~> \"%s\": comment by %s has new updated_at value\n    <%s%s>", $entry->{title},
		    		       $comment->{commenting_user},
		    		      #  $comment->{updated_at},
		    		       $comment_template, $comment->{short_id});
		    
		    $is_changed++;
		} elsif ($comment->{is_deleted} != $prev->{is_deleted}) {
		    push @Log, sprintf("**> \"%s\"comment by %s has new status 'is_deleted': %d\n    <%s%s>",$entry->{title},
				       $comment->{commenting_user},
				       $comment->{is_deleted}, $comment_template,
				       $comment->{short_id});
		    $is_changed++;
		    
		} elsif ($comment->{is_moderated} != $prev->{is_moderated}) {
		    push @Log, sprintf("!!> \"%s\": comment by %s has new status 'is_moderated': %d\n    <%s%s>", $entry->{title},
				       $comment->{commenting_user},
				       $comment->{is_moderated},$comment_template,$comment->{short_id},);
		    $is_changed++;
		} elsif ($comment->{score} != $prev->{score} ) {
		    if ($comment->{score}<$prev->{score}) {

			push @Log, sprintf("S-> \"%s\": comment by %s has new LOWER values for score: %d -> %d\n    <%s%s>", $entry->{title},
				       $comment->{commenting_user},
				       $prev->{score},
				       $comment->{score},
				       $comment_template,$comment->{short_id});
		}
		    if (($comment->{score}>=10 and $prev->{score}<10) or
			($comment->{score}>=20 and $prev->{score}<20) or
			($comment->{score}>=50 and $prev->{score}<50)  ) {
			push @Log, sprintf("S+> \"%s\": comment by %s has new HIGH values for score: %d -> %d\n    <%s%s>", $entry->{title},
				       $comment->{commenting_user},
				       $prev->{score},
				       $comment->{score},
				       $comment_template,$comment->{short_id});
			
		    }
		    $is_changed++;
		} elsif ($comment->{flags} != $prev->{flags}) {
		    push @Log, sprintf("F+> \"%s\": comment by %s has new values for flags: %d -> %d\n    <%s%s>", $entry->{title},
				       $comment->{commenting_user},
				       $prev->{flags},
				       $comment->{flags},
				       $comment_template,$comment->{short_id});
		    $is_changed++;
		}
	    } else {
		$is_unseen++;
	    }
	    if ($is_unseen ) {
		# push @Log, sprintf("   ++> inserting NEW comment by %s <%s%s>", $comment->{commenting_user},
		# 	       $comment_template, $comment->{short_id});

	    
		my @data=( $entry->{short_id},$comment->{short_id});
		for my $field_name (@fields[2..$#fields]) {
		    push @data, $comment->{$field_name};
		}
		$sth_insert->execute(@data) or warn $sth->errstr;
	    }
	    if ($is_changed) {

		my @data = map {$comment->{$_}} qw/updated_at is_deleted is_moderated score flags/;
		push @data, $entry->{short_id};
		push @data, $comment->{short_id};
		$sth_update->execute(@data) or warn $sth->errstr;
	    
	    }
	} 
    }
}

#my $end_time = Time::Piece->localtime->datetime;
my %data = (count=>$count,
	    entries=>\@inserts,
	    updates=>scalar @updates,
	    commented=>[@new_comment_updates,@new_comment_inserts],
	    starttime=>$start_time->strftime("%Y-%m-%dT%H:%M:%S%z"),
	    #	    endtime=>$end_time->strftime("%Y-%m-%dT%H:%M:%S%z"),
#	    starttime=>$start_time . $tzstring,
#	    endtime=>$end_time,
	    runtime=> sec_to_hms(tv_interval($start_tv)),
	    Log=>\@Log,
	   );

if (@inserts or @new_comment_updates or @new_comment_inserts ) {
    my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
    $tt->process( 'Lo-log-txt.tt', \%data) || die $tt->error;
}

### quick and dirty filter to remove dupes from the feed

__DATA__
idlkrv
