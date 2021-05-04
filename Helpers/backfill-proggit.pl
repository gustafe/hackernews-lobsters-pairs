#! /usr/bin/env perl
use Modern::Perl '2015';
###

use HNLOlib qw/get_dbh get_reddit $feeds/;
use Data::Dumper;
#my $start_id = 'ckhyxo';
my $start_date = 1564624932;
my   $end_date = 1562284800; # 2019-07-05 00:00:00

my $reddit = get_reddit();

my $dbh = get_dbh;
my $ids = $dbh->selectall_arrayref( "select id from $feeds->{pr}->{table_name} order by created_time desc") or die $dbh->errstr;
my $start_id =$ids->[0]->[0];
my %seen;
foreach my $id (@{$ids}) {
    $seen{$id->[0]}++
}


my $sth = $dbh->prepare( $feeds->{pr}->{insert_sql} )  or die $dbh->errstr;
my $count=0;
my @all;
open ( my $fh, '>:utf8', "proggit.out") or die $!;
while ($count <= 100) {

    say "$count reading after $start_id ...";
    my $posts = $reddit->get_links( subreddit=>'programming', limit=>undef,
				    view=>'new', after=>'t3_'.$start_id);
    #   my ( $current_id, $current_date );
    #    say "no posts!" unless @{$posts};
    say "$count no of posts: ", scalar @{$posts};
    $start_id = $posts->[-1]->{id};
    #    push @all, @{$posts};
    foreach my $post (@{$posts}) {
	my $current_id= $post->{id};
	if ($seen{$current_id}) {
	    say "$current_id in DB, skipping...";
	    next;
	}
	say "adding $current_id";
	$sth->execute( $current_id,
		       map {$post->{$_}} qw/created_utc url title author score num_comments/) or warn $sth->errstr;
	    
	print $fh join('|', map {$post->{$_}} qw/id created_utc url title author score num_comments/), "\n";
    }
    $count++;
}
