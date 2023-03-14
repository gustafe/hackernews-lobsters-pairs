#! /usr/bin/env perl
use Modern::Perl '2015';
###
use Getopt::Long;
use FindBin qw/$Bin/;
use List::Util qw/sum/;
use POSIX qw/ceil/;
use URI;
use HNLOlib qw/$feeds get_ua get_dbh get_reddit get_web_items/;

my $dbh = get_dbh();
my $statement
    = "select id, created_time,score,comments, tags from "
   . $feeds->{'lo'}->{table_name};

my $list = $dbh->selectall_arrayref($statement);
$statement = "select date(min(created_time)), date(max(created_time)) from "
    . $feeds->{'lo'}->{table_name};
my $dates = $dbh->selectall_arrayref($statement);

my $min_ts = $dates->[0]->[0];
my $max_ts = $dates->[0]->[1];
my %exclude;
while (<DATA>) {
    chomp;
    s/^\s+//;
    $exclude{$_}++;
}
my %data;
my $total = 0;
foreach my $item ( @{$list} ) {
    #    say join(' ',@$item);
    my ($id, $created_time,$score,$comments, $tags ) = @$item;
    my @tags = split(/\,/, $tags);
    my ($year) = ($created_time =~ m/^(\d+)/);
    next unless scalar @tags == 2 and $tags =~ /programming/;
#    my $payload;
    if ($tags[0] eq 'programming') {
#	$payload = join(', ', @tags)
    } else {
	@tags = reverse @tags;
    }
    my $lang = $tags[-1];
    next if exists $exclude{$tags[1]};
    $data{$year}->{$lang}->{count}++;
    $data{$year}->{$lang}->{sum} += ( $score + $comments )
 #   }
}
my $limit = 10;
for my $year (sort keys %data) {
#    say "==> $year";
    my $count = 1;
    for my $t (sort {$data{$year}{$b}->{sum}<=>$data{$year}{$a}->{sum} ||
		       $data{$year}{$b}->{count}<=>$data{$year}{$a}->{count} ||
		       $a cmp $b} keys %{$data{$year}}) {
	next if $count>$limit;
	say join(',',$year,$count,$t,$data{$year}{$t}{sum} ,$data{$year}{$t}{count});
#	say "$count $t $data{$year}{$t}{sum} ($data{$year}{$t}{count})";
	$count++;
	  
    }
}
__DATA__
practices
  video
  compsci
  hardware
  games
  web
  release
  vcs
  devops
  philosophy
  culture
  linux
  android
  distributed
  browsers
  person
  mobile
  reversing
  networking
  cogsci
  book
  databases
  design
  pdf
  security
  math
  ml
  compilers
  testing
  unix
  ask
  historical
  education
  performance
  formalmethods
  graphics
  api
  show
  plt
  rant
  visualization
  ai
  debugging
  cryptography
  scaling
  law
  vim
  emacs
  windows
  openbsd
  satire
  event
  art
  ios
  finance
  email
  
