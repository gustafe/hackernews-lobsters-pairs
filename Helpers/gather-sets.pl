#! /usr/bin/env perl
use Modern::Perl '2015';
###

use HNLOlib qw/get_dbh/;
use List::Util qw/any/;

sub timestamp {
    my ( $epoch_seconds ) = @_;
    my @parts = gmtime( $epoch_seconds );
    #    return sprintf("%04d%02d%02dT%02d%02d%02d",		   1900+$parts[5], $parts[4],$parts[3],		   $parts[2],$parts[1],$parts[0]);
    return sprintf("%02d-%02d %02d:%02d",
		   $parts[4],$parts[3],$parts[2],$parts[1]);
}

my $dbh=get_dbh;


my $feeds = {hn => { table => 'hackernews', site=>'Hacker News'},
	     lo=>{table=>'lobsters', site=>'Lobste.rs'},
	     pr=>{table=>'proggit', site=>'/r/Programming'}
	    };
	     

my @all_entries;
foreach my $label (qw/hn lo pr/) {
    my $sql = join(' ', "select strftime('%s', created_time), url,",
		   "'$label',",
		   "title, submitter, score, comments from", $feeds->{$label}->{table}, " where url is not null order by created_time");
    my $sth = $dbh->prepare( $sql ) or die $dbh->errstr;
    $sth->execute(  ) or die $sth->errstr;
    my $tbl_ary_ref = $sth->fetchall_arrayref;
    push @all_entries, @{$tbl_ary_ref};
}

@all_entries = sort {$a->[0] <=> $b->[0]}  @all_entries;
my %sets;
foreach my $row (@all_entries) {
    my ( $ts, $url, $label, $title, $submitter, $score, $comments) = @{$row};
    
    if (!exists $sets{$url}) {
	$sets{$url} = {first_seen => $ts,
			title=>$title};
    }
    push @{$sets{$url}->{sequence}}, {site=>$feeds->{$label}->{site},
				      ts=>$ts,
				      title=>$title,
				      submitter=>$submitter,
				      label=>$label,
			  score=>$score,
			  comments=>$comments};
#    my $time= gmtime( $row->[0] );
#    say join(' ', ($time,@{$row}));
}
foreach my $url (sort {$sets{$a}->{first_seen} <=> $sets{$b}->{first_seen}} keys %sets) {
    next unless scalar @{$sets{$url}->{sequence}}>1;
    next unless any {$_->{label} eq 'lo'} @{$sets{$url}->{sequence}};
    say "==> $sets{$url}->{title}";
    say "    [$url]";
    say join(' ', map {$_->{label}} @{$sets{$url}->{sequence}});
    foreach my $seq (@{$sets{$url}->{sequence}}) {
#	say ' ', join(' ',timestamp($seq->{ts}), map {$seq->{$_}} qw/label title submitter score comments/);
    }
}
