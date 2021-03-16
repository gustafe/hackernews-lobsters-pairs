#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;
use List::Util qw/sum/;
use POSIX qw/ceil/;
use URI;
use HNLOlib qw/$feeds get_ua get_dbh get_reddit get_web_items/;
use Data::Dump qw/dump/;
sub usage {
    say "usage: $0 --label={hn,lo,pr} [--sort=s|c]";
    exit 1;

}
my $label;
my $sorting = 's'; # default by score
GetOptions( 'label=s' => \$label , 'sort=s'=>\$sorting);

usage unless exists $feeds->{$label};
usage unless ( $sorting eq 's' or $sorting eq 'c' );

warn "==> getting data... ";
my $dbh = get_dbh();
my $statement
    = "select id,date(created_time),title,url,score,comments from "
    . $feeds->{$label}->{table_name}
  . " where url!='' ";
$statement .= $sorting eq 's' ? ' order by score desc limit 200 ' : ' order by comments desc limit 200';
# . ( $sorting eq 's' ? ' order by score desc ' : ' order by comments desc ' . ' limit 100 ';

my $list = $dbh->selectall_arrayref($statement);
$statement = "select date(min(created_time)), date(max(created_time)) from "
    . $feeds->{$label}->{table_name};
my $dates = $dbh->selectall_arrayref($statement);
my $min_ts = $dates->[0]->[0];
my $max_ts = $dates->[0]->[1];

$statement = "select min(score), max(score) from "
  . $feeds->{$label}->{table_name};
my $score_range = $dbh->selectall_arrayref( $statement );
my $min_score = $score_range->[0][0];
my $score_width = ($score_range->[0][1] - $score_range->[0][0])/25;

$dbh->disconnect();
my %hist;
my %data;
warn "==> processing list..." ;
for my $item (@$list) {

    my ( $id , $timestamp, $title, $url, $score, $comments ) = @$item;
    warn "==> ", dump $item unless $score =~ /\d+/;
    $hist{int (( $score - $min_score ) / $score_width)}++;

    if ($label eq 'lo' ) { # need to key off title because of article folding
	$data{$title} = { title=>$title,id => $id, timestamp=>$timestamp, url=>$url, score=>$score, comments=>$comments, ratio=>$score!=0?$comments/$score:0};
    } else {
	$data{$id} = {id=>$id, title => $title, timestamp=>$timestamp, url=>$url, score=>$score, comments=>$comments,ratio=>$score!=0?$comments/$score:0};
    }
    
}

#say scalar keys %data;
my $limit=25;
my $count=0;
warn "==> output: top $limit by " . $sorting eq 's' ? 'score' : 'comments' . '... ';
sub by_score {
    $data{$b}->{score} <=> $data{$a}->{score}
}

sub by_comments {
    $data{$b}->{comments} <=> $data{$a}->{comments}
}

for my $key ( sort {$sorting eq 's' ? by_score : by_comments}  keys %data) {

    last if $count>$limit;
   printf("%s %s s=%d c=%d r=%.2f\n", map { $data{$key}->{$_}} qw/timestamp title score comments ratio/);
    $count++;
	   
}
#print dump \%hist;
