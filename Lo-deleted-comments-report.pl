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
use FindBin qw/$Bin/;


my $dbh=get_dbh();
my $comments=$dbh->selectall_arrayref("select lo.id, title, created_time,co.comment_id,co.created_at,co.commenting_user,co.is_deleted,co.is_moderated,co.score,co.flags,co.comment_plain 
from lobsters lo inner join lo_comments co on lo.id=co.id 
where (co.is_deleted=1 or co.is_moderated=1) and comment_plain <> 'Comment removed by author'
order by lo.created_time desc, co.created_at desc") or warn $dbh->errstr;


#my @fields = qw/id title  created_time comment_id created_at commenting_user is_deleted is_moderated comment_plain/;
my @report;
my $curr_id='';
my $latest_comment = '1900-01-01T00:00:00.000+00:00';
my $comment_count = 0;
#dump $comments;
for my $row (@$comments) {
    my ($id,$title,$created_time,$comment_id,$created_at,$commenting_user,$is_deleted,$is_moderated,$score,$flags,$comment_plain)= @$row;
    if ($id ne $curr_id) {
	push @report, sprintf("## [%s](%s)\n", $title, $feeds->{lo}{title_href}.$id);
	push @report, sprintf("*First posted on %s*\n", $created_time);
	$curr_id=$id;
    }
    my $reason = "deleted" if $is_deleted;
    $reason .= ' and moderated' if $is_moderated;
    
    push @report, sprintf("### [Comment by %s](%s) is %s (score: %d, flags: %d)\n",$commenting_user,$feeds->{lo}{comment_href}.$comment_id,$reason, $score, $flags );
    push @report, sprintf("*Originally posted on %s*\n", $created_at);
    push @report, $comment_plain;
    $comment_count++;
    $latest_comment = $created_at if $created_at gt $latest_comment;
    
}

#### stats

my $common_sql = 'select lo.id, lo.title,lo.score,lo.comments, co.comment_id, co.commenting_user, co.score, co.flags,is_deleted,is_moderated from lo_comments co inner join lobsters lo on lo.id=co.id';

my @fields = qw/entry_id entry_title entry_score entry_comments comment_id commenting_user comment_score comment_flags is_deleted is_moderated/;

my %results = (1=> { sql => 'order by co.score desc limit 20',
			      res => undef,
			    label=> "Top scored comments",},
	       2 => { sql => 'where flags>1 order by flags desc, co.score,is_deleted desc',
			      res => undef,
			    label=>"Most flagged comments",},
	       3 => {sql=>'where co.score<0 order by co.score',
				res=>undef,
			       label=>"Bottom scored comments",},);


for my $id (sort keys %results) {
    my $aryref = $dbh->selectall_arrayref( $common_sql . ' ' . $results{$id}->{sql}) or warn $dbh->errstr;
    my $res;
#    say "==> ",$results{$id}->{label}, " <==";
    for my $r (@$aryref) {
	my $hashref;
	for my $p (0..$#fields) {
	    $hashref->{$fields[$p]} = $r->[$p];
	}
	push @$res, $hashref;
    }
    $results{$id}->{res} = $res;
#    dump $res;
}


my $data;
$data->{meta}->{page_title} = 'Lobste.rs recent comment stats';
$data->{meta}->{generate_time}
  = DateTime->now()->strftime('%Y-%m-%d %H:%M:%S%z');
$data->{meta}->{latest_comment} = $latest_comment;
$data->{meta}->{comment_count}= $comment_count;
$data->{report} = \@report;
$data->{stats} = \%results;
my $tt = Template->new(
    { INCLUDE_PATH => "$Bin/templates", ENCODING => 'UTF-8' } );

$tt->process(
    'Lo-comments-report.tt', $data
) || die $tt->error;


__END__
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


