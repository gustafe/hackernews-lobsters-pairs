#! /usr/bin/env perl
use Modern::Perl '2015';
###

use HNLOlib qw/get_dbh get_reddit $feeds/ ;
use List::Util qw/sum/;
use Template;
use FindBin qw/$Bin/;
use utf8;
use URI;
my $debug=0;
sub extract_host {
    my ( $in ) = @_;
    my $uri = URI->new( $in );
    my $host;
    eval {
	$host = $uri->host;
	1;
    } or do {
	my $error = $@;
	$host= 'www';
	};
    $host =~ s/^www\.//;
    return $host;
}


my $reddit = get_reddit();

my $dbh = get_dbh;

my $latest_ids = $dbh->selectall_arrayref( "select id from proggit order by created_time desc" ) or die $dbh->errstr;

my %seen;
foreach my $el (@{$latest_ids}) {
    $seen{$el->[0]}++;
}


my $sth = $dbh->prepare( $feeds->{pr}->{insert_sql} )  or die $dbh->errstr;

my $posts = $reddit->get_links( subreddit=>'programming', limit => undef, view=>'new', );
my $count = 0;
my @updates;
my @entries;
print "\n";
foreach my $post (@{$posts}) {
    next if $post->{is_self};
    my $current_id = $post->{id};
    if ($seen{$current_id}) {
	say "$current_id already seen, pushing to updates" if $debug;
	push @updates, [$post->{title}, $post->{score},$post->{num_comments}, $current_id];
    } else {
	say "$current_id $post->{title}" if $debug;
	my $title = $post->{title} ? $post->{title} : '<NO TITLE>';
	my $title_space = 80 - ( 8 ) - ( 4 + sum (map{length($post->{$_})} qw/author score num_comments/));
	if (length($title)>$title_space) {
	    $title = substr( $title,0,$title_space-1). "\x{2026}";
	}
	# printf("%s %-*s [%s %d %d]\n",
	#        $post->{id},
	#        $title_space,
	#        $title,
	#        map {$post->{$_}} qw/author score num_comments/
	#       );
	my $pr_link = 'https://www.reddit.com/r/programming/comments/'.$post->{id};
#	printf("* [%s](%s) [%s](%s) %s %d %d\n",	      $post->{id}, $pr_link,map{$post->{$_}} qw/title url author score num_comments/);

	$sth->execute( $current_id,
		   $post->{created_utc},
		   $post->{url},
		   $post->{title},
		   $post->{author},
		   $post->{score},
		   $post->{num_comments} ) or warn $sth->errstr;
	$count++;
	my $entry = { map {$_=> $post->{$_}} keys %$post};
	my $host = extract_host( $entry->{url} );
	$entry->{host} = $host;
	push @entries, $entry;
	
    }
}
if (scalar @entries>0) {
    my %data = (entries => \@entries);
    my $tt = Template->new( {INCLUDE_PATH=>"$Bin/templates",ENCODING=>'UTF-8'} );
    $tt->process( 'Proggit-log.tt', \%data) || die $tt->error;

}

#say "\nNew Proggit items added: $count\n";
$sth->finish();
# update
$count = 0;
$sth = $dbh->prepare( $feeds->{pr}->{update_sql} ) or die $dbh->errstr;
foreach my $item (@updates) {
    $sth->execute( @{$item} ) or warn $sth->errstr;
    $count++;
	     
    
}
#say "$count items updated\n";
$dbh->disconnect();

