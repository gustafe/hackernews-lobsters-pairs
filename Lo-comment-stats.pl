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

my $common_sql = 'select lo.id, lo.title,lo.score,lo.comments, co.comment_id, co.commenting_user, co.score, co.flags,is_deleted,is_moderated from lo_comments co inner join lobsters lo on lo.id=co.id';

my @fields = qw/entry_id entry_title entry_score entry_comments comment_id commenting_user comment_score comment_flags is_deleted is_moderated/;

my %results = (1=> { sql => 'order by co.score desc limit 20',
			      res => undef,
			    label=> "Top scored comments",},
	       2 => { sql => 'where flags>1 order by flags desc, co.score,is_deleted desc',
			      res => undef,
			    label=>"Most flagged comments",},
	       3 => {sql=>'where co.score<=0 order by co.score',
				res=>undef,
			       label=>"Bottom scored comments",},);


for my $id (sort keys %results) {
    my $aryref = $dbh->selectall_arrayref( $common_sql . ' ' . $results{$id}->{sql}) or warn $dbh->errstr;
    my $res;
    say "==> ",$results{$id}->{label}, " <==";
    for my $r (@$aryref) {
	my $hashref;
	for my $p (0..$#fields) {
	    $hashref->{$fields[$p]} = $r->[$p];
	}
	push @$res, $hashref;
    }
    $results{$id}->{res} = $res;
    dump $res;
}



__END__

my $comments = $dbh->selectall_arrayref(
		"select comment_id,commenting_user,co.score,flags,co.id,lo.title from lo_comments co inner join lobsters lo on co.id=lo.id") or warn $dbh->errstr;

my @top = (sort {$b->[2] <=> $a->[2] }@$comments)[0..19];
my @bottom = grep {$_->[2]<=0} sort {$a->[2] <=> $b->[2] } @$comments;
my @flagged = grep {$_->[3]>1} sort {$b->[3] <=> $a->[3]} @$comments;
my $count=1;
for my $r (@top) {
#    last if $count>9;
    say join(' ', $count,@$r);
    $count++;
}
$count=1;
for my $r (@bottom) {
#    last if $r->[2] >0;
    say join(' ', $count,@$r);
    $count++;
}
$count=1;
for  my $r (@flagged) {
#    last if $r->[3]<=0;
    say join(' ',$count,@$r);
    $count++;
}
