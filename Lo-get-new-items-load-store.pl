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
my $start_time= localtime;
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
	my $comments_in_db = scalar keys %{$ids_have_comments{$current_id}};
					     
	if ($seen_ids{$current_id} != $entry->{comment_count}
	   ) {
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
    if (!exists $ids_have_comments{$current_id}) {
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
	push @Log, sprintf("==> getting insert data for submission \"%s\" <%s%s>", $entry->{title}, $entry_template, $entry->{short_id});
	my $item_ref=get_item_from_source('lo', $entry->{short_id});
	for my $comment (@{$item_ref->{comment_list}->[0]}) {
	    my @data=( $entry->{short_id},$comment->{short_id});
	    for my $field_name (@fields[2..$#fields]) {
		push @data, $comment->{$field_name};
	    }

	    #push @Log, "~~> inserting NEW comment ".$comment->{short_id}." by ".$comment->{commenting_user};
	    push @Log, sprintf("  --> inserting NEW comment by %s <%s%s>", $comment->{commenting_user},
			       $comment_template, $comment->{short_id});
	    
	    $sth_insert->execute(@data) or warn $sth->errstr;
	}

    }
}

my $sth_update = $dbh->prepare("update lo_comments set updated_at=?, is_deleted=?, is_moderated=?, score=?, flags=? where id=? and comment_id=?") or die $dbh->errstr;

if (@new_comment_updates) {
    for my $entry (@new_comment_updates) {
     	#push @Log, "==> getting update data for submission ".$entry->{short_id}.' "'.$entry->{title}.'"';
	push @Log, sprintf("==> getting insert data for submission \"%s\" <%s%s>", $entry->{title}, $entry_template, $entry->{short_id});

     	my $item_ref=get_item_from_source('lo', $entry->{short_id});
	for my $comment (@{$item_ref->{comment_list}->[0]}) {
	    my ( $is_unseen, $is_changed) = (0,0);
	    if ($ids_have_comments{ $entry->{short_id} }->{ $comment->{short_id}}) {
		my $prev = $ids_have_comments{ $entry->{short_id} }->{ $comment->{short_id}};
		
		if ($comment->{updated_at} ne $prev->{updated_at}) {
		    push @Log, sprintf("      > comment by %s has new updated_at value: %s <%s%s>",
				       $comment->{commenting_user},
				       $comment->{updated_at},
				       $comment_template, $comment->{short_id});
		    
		    $is_changed++;
		} elsif ($comment->{is_deleted} != $prev->{is_deleted}) {
		    push @Log, sprintf("   ++> comment by %s has new flag is_deleted: %d <%s%s>",
				       $comment->{commenting_user},
				       $comment->{is_deleted}, $comment_template, $comment->{short_id});
		    $is_changed++;
		    
		} elsif ($comment->{is_moderated} != $prev->{is_moderated}) {
		    push @Log, sprintf("   !!> comment by %s has new flag is_moderated: %d <%s%s>",
				       $comment->{commenting_user},
				       $comment->{is_moderated},$comment_template,$comment->{short_id},);
		    $is_changed++;
		}
	    } else {
		$is_unseen++;
	    }
	    if ($is_unseen ) {
#		push @Log, "~~> inserting UPD comment ".$comment->{short_id}." by ".$comment->{commenting_user};
		push @Log, sprintf("   --> inserting UPD comment by %s <%s%s>", $comment->{commenting_user},
			       $comment_template, $comment->{short_id});

	    
		my @data=( $entry->{short_id},$comment->{short_id});
		for my $field_name (@fields[2..$#fields]) {
		    push @data, $comment->{$field_name};
		}
		$sth_insert->execute(@data) or warn $sth->errstr;
	    }
	    if ($is_changed) {
		push @Log, sprintf("   ..> updating comment by %s with new info <%s%s>",
				   $comment->{commenting_user},
				   $comment_template, $comment->{short_id}
				  );
		my @data = map {$comment->{$_}} qw/updated_at is_deleted is_moderated score flags/;
		push @data, $entry->{short_id};
		push @data, $comment->{short_id};
		$sth_update->execute(@data) or warn $sth->errstr;
	    
	    }
	} 
    }
}

my $end_time = localtime;
my %data = (count=>$count,
	    entries=>\@inserts,
	    updates=>scalar @updates,
	    commented=>[@new_comment_updates,@new_comment_inserts],
	    starttime=>$start_time->strftime("%Y-%m-%dT%H:%M:%S%z"),
	    endtime=>$end_time->strftime("%Y-%m-%dT%H:%M:%S%z"),
	    runtime=> $end_time->epoch - $start_time->epoch,
	    Log=>\@Log,
	   );
my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
$tt->process( 'Lo-log-txt.tt', \%data) || die $tt->error;
