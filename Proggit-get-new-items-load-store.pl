#! /usr/bin/env perl
use Modern::Perl '2015';
###

use HNLOlib qw/get_dbh get_reddit/;
my $debug=0;


my $reddit = get_reddit();

my $dbh = get_dbh;

my $latest_ids = $dbh->selectall_arrayref( "select id from proggit order by created_time desc" ) or die $dbh->errstr;

my %seen;
foreach my $el (@{$latest_ids}) {
    $seen{$el->[0]}++;
}


my $sql = {
	   insert => qq{ insert into proggit 
(id, created_time,             url ,title, submitter, score,comments ) values 
(?,  datetime( ?,'unixepoch'), ?,   ?,     ?,         ?,    ? )},

	   update=>qq{update proggit set score=?, comments=? where id=?},

	   select_older => qq{select id from proggit where id	  }
	  };


	   
my $sth = $dbh->prepare( $sql->{insert} )  or die $dbh->errstr;

my $posts = $reddit->get_links( subreddit=>'programming', limit => undef, view=>'new', );
my $count = 0;
my @updates;
foreach my $post (@{$posts}) {
    next if $post->{is_self};
    my $current_id = $post->{id};
    if ($seen{$current_id}) {
	say "$current_id already seen, pushing to updates" if $debug;
	push @updates, [$post->{score},$post->{num_comments}, $current_id];
    } else {
    say "$current_id $post->{title}" if $debug;
    $sth->execute( $current_id,
		   $post->{created_utc},
		   $post->{url},
		   $post->{title},
		   $post->{author},
		   $post->{score},
		   $post->{num_comments} ) or warn $sth->errstr;
    $count++;
	
    }
}

say "\nNew Proggit items added: $count\n";
$sth->finish();
# update
$count = 0;
$sth = $dbh->prepare( $sql->{update} ) or die $dbh->errstr;
foreach my $item (@updates) {
    $sth->execute( @{$item} ) or warn $sth->errstr;
    $count++;
	     
    
}
say "$count items updated\n";
$dbh->disconnect();

