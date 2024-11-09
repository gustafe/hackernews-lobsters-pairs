#! /usr/bin/env perl
use Modern::Perl '2015';
###
use utf8;
binmode(STDOUT, ':encoding(UTF-8)');

use Getopt::Long;

use HNLOlib qw/$feeds get_dbh/;
use Data::Dump qw/dump/;
use DateTime;
use Template;
use Time::Piece;
use FindBin qw/$Bin/;

sub convert_to_local {
    my ($time_in) = @_;
    $time_in =~ s/\.\d{3}//;
    $time_in =~ s/:(\d+)$/$1/;
    my $obj_time = Time::Piece->strptime($time_in,"%FT%T%z");
    return Time::Piece->localtime($obj_time)->strftime("%FT%T%z");
}

my $dbh=get_dbh();
my $comments=$dbh->selectall_arrayref("select lo.id, title,lo.url, lo.created_time,co.comment_id,
co.created_at,co.commenting_user,co.is_deleted,co.is_moderated,co.score,co.flags,co.comment_plain 
from lobsters lo inner join lo_comments co on lo.id=co.id
order by lo.created_time desc, co.created_at desc") or warn $dbh->errstr;


#my @fields = qw/id title  created_time comment_id created_at commenting_user is_deleted is_moderated comment_plain/;
my @report;
my %entries;
my %commenters;
my $curr_id='';
my $latest_comment = '1900-01-01T00:00:00.000+00:00';
my $deleted_count = 0;
#dump $comments;
for my $row (@$comments) {
    my ($id,$title,$url, $created_time,$comment_id,$created_at,$commenting_user,$is_deleted,$is_moderated,$score,$flags,$comment_plain)= @$row;
    $entries{$id}->{comment_count}++;
    $entries{$id}->{created_time} = $created_time;
    $entries{$id}->{title} = $title;
    $entries{$id}->{url} = $url;
    if ($entries{$id}->{first_comment}) {
	$entries{$id}->{first_comment} = $created_at if $created_at lt  $entries{$id}->{first_comment} 
    } else {
	$entries{$id}->{first_comment} = $created_at;
    }
    if ($entries{$id}->{last_comment}) {
	$entries{$id}->{last_comment} = $created_at if $created_at gt $entries{$id}->{last_comment}
    } else {
	$entries{$id}->{last_comment} = $created_at;
    }
    if (!$commenters{$commenting_user}) {
	$commenters{$commenting_user} = {count=>0, max_score=>-100,flags=>0,min_score=>100}
    }
    $commenters{$commenting_user}->{count}++;
    $commenters{$commenting_user}->{max_score} = $score if $commenters{$commenting_user}->{max_score} < $score;
    $commenters{$commenting_user}->{min_score} = $score if $commenters{$commenting_user}->{min_score} > $score;
    $commenters{$commenting_user}->{flags} = $flags if $commenters{$commenting_user}->{flags} < $flags;
    if ($is_deleted or $is_moderated) {
	my $reason = "deleted" if $is_deleted;
	$reason .= ' and moderated' if $is_moderated;

	push @{$entries{$id}->{removed}}, {comment_id=>$comment_id, commenting_user=>$commenting_user, created_at=>convert_to_local($created_at), is_deleted=>$is_deleted,is_moderated=>$is_moderated, score=>$score,flags=>$flags, comment_plain=>$comment_plain, reason=>$reason} unless $comment_plain =~ m/Comment removed by author/;
	$deleted_count++;
    }
    
    $latest_comment = $created_at if $created_at gt $latest_comment;
    
}


my $index;
$index->{meta}->{page_title} = 'Lobste.rs recent deleted comments';
$index->{meta}->{generate_time} = Time::Piece->localtime()->strftime("%FT%T%z");
$index->{meta}->{latest_comment} = convert_to_local($latest_comment);
$index->{meta}->{deleted_count}= $deleted_count;
my $pages;
#$index->{report} = \@report;
#$index->{stats} = \%results;
my $tt = Template->new(
    { INCLUDE_PATH => "$Bin/templates", ENCODING => 'UTF-8' } );

for my $id (sort {$entries{$b}->{created_time} cmp $entries{$a}->{created_time}}keys %entries) {
    if ( defined $entries{$id}->{removed} ) {
	push @{$index->{entries}}, {id=>$id, title=>$entries{$id}->{title},
				    comment_count=>$entries{$id}->{comment_count},
				    url=> $entries{$id}->{url},
				    first_comment=>convert_to_local($entries{$id}->{first_comment}),
				    last_comment=>convert_to_local($entries{$id}->{last_comment}),
				    deleted_comment_count=> scalar @{$entries{$id}->{removed}}
				   };
#	say "Entry $id with title $entries{$id}->{title} has $entries{$id}->{comment_count} comments";
	# say "Number of deleted or moderated comments: " . scalar @{$entries{$id}->{removed}};
	for my $comment (@{$entries{$id}->{removed}}) {
	    
	    push @{$pages->{$id}{comments}}, {map {$_ => $comment->{$_}} qw/comment_id commenting_user score flags reason created_at comment_plain is_deleted is_moderated/};
#	    $pages->{$id}{comments}{created_at} = convert_to_local($pages->{$id}{comments}{created_at});
#	    say join(' ', $comment->{comment_id}, $comment->{commenting_user}, $comment->{score}, $comment->{flags});
#	    say $comment->{comment_plain};
	}
    }  else {
	next;
    }
}

$tt->process(
    'Lo-deleted-comments-index.tt', $index, 'Deleted/index.html',     { binmode => ':utf8' } ) || die $tt->error;

for my $id (keys %{$pages}) {
    my $data;
    $data->{meta}{entry_id} = $id;
    $data->{meta}->{generate_time} = Time::Piece->localtime()->strftime("%FT%T%z");
    $data->{meta}{title} = $entries{$id}{title};
    $data->{comments} = $pages->{$id}{comments};

    $tt->process('Lo-deleted-comments-content.tt', $data, "Deleted/$id.html", { binmode => ':utf8' })||die $tt->error;

}



__END__
for my $user (sort {$commenters{$a}->{min_score} <=> $commenters{$b}->{min_score}}keys %commenters) {
    say join('|',$user, map{$commenters{$user}->{$_}} qw/count min_score max_score flags/);
}



my %entries;
for my $row (@$comments) {
    $entries{$row->[0]} = {title=>$row->[1], created_time=>$row->[2]};
    push @{$entries{$row->[0]}{comments}} ,{comment_id=>$row->[3],created_at=>$row->[4],
					    commenting_user=>$row->[5], is_deleted=>$row->[6],
					    is_moderated=>$row->[7],comment_plain=>$row->[8]};
    
}
dump %entries;
for my $entry (sort {$entries{$b}{created_time} cmp $entries{$a}{created_time} }keys %entries) {
 #   say join('|', $entry,$entries{$entry}{title},$entries{$entry}{created_time});
  #  say "--> " . scalar @{$entries{$entry}{comments}};
    
    for my $comment_id (sort { $entries{$entry}{comments}{$b}{created_at} cmp
						 $entries{$entry}{comments}{$a}{created_at}} @{$entries{$entry}{comments}}) {
#	my $comment = $entries{$entry}{comments}{$comment_id};
#		say join('*',$comment_id,$comment->{commenting_user}, $comment->{created_at});
#	dump $comment;
    }
}


