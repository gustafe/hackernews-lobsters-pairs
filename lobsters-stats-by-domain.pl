#! /usr/bin/env perl
use Modern::Perl '2015';
###

use Getopt::Long;
#use DateTime;
use Template;
use FindBin qw/$Bin/;
use lib "$FindBin::Bin";
use utf8;
#use DateTime::Format::Strptime qw/strftime strptime/;
use Data::Dump qw/dd/;
use HNLOlib qw/get_dbh get_all_sets $feeds update_scores $sql/;
#use List::Util qw/all/;

binmode(STDOUT, ":utf8");
use open qw/ :std :encoding(utf8) /;
sub usage;
my $domain;


GetOptions(
    'domain=s'   => \$domain,
);

usage unless $domain;
my $intro = <<"INTRO";
This is an extract of the most popular submissions with URLs matching the string '$domain'.

Only submissions with a score+comments total exceeding 10 are presented.

A comments/score ratio above 1.25 is deemed 'controversial' and marked in *italic*.

https://gerikson.com/hnlo/

INTRO

say $intro;

my $sql = "select created_time, id, title, submitter, score, comments from lobsters where url like '%".$domain."%'";
#say "$domain";
my $dbh=get_dbh();
my $rows = $dbh->selectall_hashref($sql,('created_time'));
my %seen;
for my $time (sort keys %$rows) {
    my $day = (split("T", $time))[0];
    my $href = $rows->{$time};
    if ($seen{$href->{title}}) {
	next;
    } else {
	$seen{$href->{title}}++
    }
    next unless $href->{score}+$href->{comments} > 9;
    printf("* %s [%s](https://lobste.rs/s/%s) [%s] score: %d comments: %d ",$day, map{$href->{$_}} qw/title id submitter score comments/) ;
    my $ratio = $href->{comments}/$href->{score};
    if ($ratio > 1.25) {
	printf("ratio: *%.2f*\n", $ratio);
    } else {
	printf("ratio: %.2f\n", $ratio);
    }

#    say "* [$href->{title}](https://lobste.rs/s/$href->{id}) score: $href->{score}, comments: $href->{comments}" ;
}

sub usage {
    say "usage: $0 --domain=<domain>";
    exit 1;
}
__END__
