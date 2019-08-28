#! /usr/bin/env perl
use Modern::Perl '2015';
###

use HNLOlib qw/$feeds get_ua get_dbh get_reddit/;
use Getopt::Long;
use JSON;
sub usage {
    say "usage: $0 --label={hn,lo,pr} --days=N";
    exit 1;

}
my $debug=1;
sub get_reddit_items;
my $get_items = {pr => \&get_reddit_items,
		 hn=>\&get_web_items,
		 lo=>\&get_web_items,
		};
my $no_of_days;
my $label;
GetOptions('label=s'=>\$label,
	   'days=i'=> \$no_of_days);

usage unless defined $no_of_days;
usage unless exists $feeds->{$label};
usage unless exists $get_items->{$label};

my $dbh=get_dbh;
my $ids = [map {$_->[0]} @{$dbh->selectall_arrayref( "select id from $feeds->{$label}->{table_name} where created_time >= datetime('now', '-$no_of_days day') order by created_time desc")}] or die $dbh->errstr;


#exit 0 unless $label eq 'pr';

my ( $updates, $deletes ) = $get_items->{$label}->( $ids );
my $sth = $dbh->prepare( $feeds->{$label}->{update_sql}) or die $dbh->errstr;
my $count = 0;
foreach my $update (@$updates) {
    $sth->execute( @$update ) or warn $sth->errstr;
    #say join(' ', @$update[3,0,1,2]);
    $count++;
}
say "$count items updated";
$sth->finish;
$count=0;
$sth = $dbh->prepare( $feeds->{$label}->{delete_sql}) or die $dbh->errstr;
#say "deletes: ",scalar @$deletes;
foreach my $id (@$deletes) {
    $sth->execute( $id );

    $count++;
}
say "$count items deleted";

sub get_web_items {
    my ( $items ) =@_;
    my %not_seen;
    my @updates;
    my $ua = get_ua();
    foreach my $id (@$items) {
	say "fetching $id" if $debug;
	my $href = $feeds->{$label}->{api_item_href} . $id . '.json';
	my $r = $ua->get( $href );
	if (!$r->is_success() or $r->header('Content-Type') !~ m{application/json}) {
	    $not_seen{$id}++;
	    next;
	}
	my $json = decode_json( $r->decoded_content() );
	if (defined $json->{dead}) {
	    $not_seen{$id}++ ;
	    next;
	}
	my @binds = ( $json->{title},
			$json->{score},
		      $json->{$feeds->{$label}->{comments}});
	if (defined  $json->{tags}) {
	    push @binds, join(',',@{$json->{tags}})
	}
	push @binds, $id;
	push @updates, \@binds;
    }
    my @deletes = keys %not_seen if scalar keys %not_seen > 0;
    return ( \@updates, \@deletes );

}

sub get_reddit_items{
    my ( $items ) = @_;
    my @inputs;
    my $count = 0;
    my %seen;
    my @updates;
    my @deletes;
    my $reddit = get_reddit();
    foreach my $item (@$items) {
	push @{$inputs[int($count/75)]}, $item;
	$seen{$item} = 0;
	$count++;
    }
    foreach my $list (@inputs) {
	#	say scalar @{$list};
	my $posts = $reddit->get_links_by_id(  @{$list} );
	foreach my $post (@$posts) {

	    push @updates, [ $post->{title},
			     $post->{score},
			     $post->{num_comments},
			     $post->{id}
			   ];
	    $seen{$post->{id}}++;
	}
	    foreach my $id (sort keys %seen) {
		push @$deletes, $id if $seen{$id}>0;

	    }
    }
    return ( \@updates, \@deletes );
}
