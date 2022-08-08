#! /usr/bin/env perl
use Modern::Perl '2015';
###
use FindBin qw/$Bin/;
use DateTime;
use lib "$FindBin::Bin";
use utf8;
use open qw/ :std :encoding(utf8) /;
binmode(STDOUT, ':encoding(UTF-8)');
use HNLOlib qw/get_dbh $sql $feeds get_ua sec_to_dhms sec_to_human_time/;
use URI;

my $dbh=get_dbh;
my $data;
for my $source (qw/lobsters/) {
    say "-- ==> getting data from $source";
    my $stmt = "select id, url from $source";
    my $rows = $dbh->selectall_arrayref( $stmt) or die $dbh->errstr;
    my $count = 0;
    for my $r (@$rows) {
#	say "==> $count" if  $count % 1_000 == 0;
	my ($id, $url) = @$r;
	next unless $url;
	my @ary = split(/\:\/\//, $url);
	my ( $scheme, $rest ) = ($ary[0],$ary[-1]);
	say "~~> $id" unless $rest;
#	say join("|",$source, $rest, $scheme, $id);
        push @{$data->{$source}{$rest}{$scheme}}, $id;
	$count++;
    }
}


my $year = 2012;
my $month = 6;
my $day = 15;

my $datetime= DateTime->new(year=>$year, month=>$month,day=>$day);
my $today = DateTime->today();

while ($datetime<$today) {
    my $last_day = DateTime->last_day_of_month(year=>$datetime->year, month=>$datetime->month);
    my $start_time= sprintf("%04d-%02d-%02dT00:00:00", $datetime->year, $datetime->month, 1);
    my $end_time= sprintf("%04d-%02d-%02dT24:00:00", $datetime->year, $datetime->month, $last_day->day);
#    say "$start_time - $end_time";
    $data->{hackernews}=undef;
    my $stmt = "select id, url from hackernews where created_time between '".$start_time."' and '".$end_time."'" ;
     my $rows = $dbh->selectall_arrayref( $stmt) or die $dbh->errstr;
     my $count = 0;
     for my $r (@$rows) {
 	my ($id, $url) = @$r;
 	next unless $url;
 	my @ary = split(/\:\/\//, $url);
 	my ( $scheme, $rest ) = ($ary[0],$ary[-1]);
         push @{$data->{hackernews}{$rest}{$scheme}}, $id;

    }
    my $current = sprintf("%04d-%02d", $datetime->year,$datetime->month);
    say "-- ##### $current ##### ";
    warn "==> $current\n";

    for my $address ( keys %{$data->{lobsters}}) {
	if (exists $data->{hackernews}{$address}) {
	    next if (exists $data->{lobsters}{$address}{https} and exists $data->{hackernews}{$address}{https}) ;
	    if (exists $data->{lobsters}{$address}{https}) {
		for my $scheme (keys %{$data->{hackernews}{$address}}) {
		    next if $scheme eq 'https';
		    for my $id ( @{$data->{hackernews}{$address}{$scheme}}) {
			say "-- $address";
			say "update hackernews set url='https://".$address."' where id=".$id.";";
		    }
		}
	    } 
	}

    }
    $datetime->add(months=>1);
}



__END__

for my $address (keys %{$data->{lobsters}}) {
    my $schemes = scalar keys %{$data->{lobsters}{$address}};
    if ($schemes>1) {
	say "-- address: $address";
	for my $scheme (sort {$b cmp $a} keys %{$data->{lobsters}{$address}}) {
	    #	    say $scheme.'://'.$address.': '.join(",", @{$data->{lobsters}{$address}{$scheme}});
	    if ($scheme.'://'.$address ne 'https://'.$address) {
		for my $id (@{$data->{lobsters}{$address}{$scheme}}) {
		    say "-- https://lobste.rs/s/$id is not https";
		    say "update lobsters set url='https://".$address."' where id='".$id."';";
		}
	    } else {
		for my $id (@{$data->{lobsters}{$address}{$scheme}}) {
		    say "-- https://lobste.rs/s/$id is https";
		}
	    }
	}
    }

}

say "==> starting to compare";
my $count=0;
for my $address ( keys %{$data->{lobsters}}) {
#    next unless length($address)>0;
#    say "1=> checking $count" if $count % 1000 ==0 ;
#    my $lo_scheme =  (keys %{$data->{lobsters}{$address}})[0] ;
    if (exists $data->{hackernews}{$address}) {
	# for my $site (qw/lobsters hackernews/) {
	#     for my $scheme (keys %{$data->{$site}{$address}}) {
	# 	for my $id (@{$data->{$site}{$address}{$scheme}}) {
	# 	    printf("%10s - %9s - %5s://%s\n" , $site, $id, $scheme,$address);
	# 	}
	#     }
	# }
    	next 	if (exists $data->{lobsters}{$address}{https} and exists $data->{hackernews}{$address}{https}) ;
    	if (exists $data->{lobsters}{$address}{https}) {
    	    for my $scheme (keys %{$data->{hackernews}{$address}}) {
    		next if $scheme eq 'https';
    		for my $id ( @{$data->{hackernews}{$address}{$scheme}}) {
    		    say "-- $address";
    		    say "update hackernews set url='https://".$address."' where id=".$id.";";
    		}
    	    }
    	} else {
    	    if (exists $data->{hackernews}{$address}{https}) {
    	    for my $scheme (keys %{$data->{lobsters}{$address}}) {
    		next if $scheme eq 'https';
    		for my $id (			    @{$data->{lobsters}{$address}{$scheme}}) {
    		    say "-- $address";
    		    say "update lobsters set url='https://".$address."' where id='".$id."';";
    		}
    	    }
    	}
    	}
    }
     $count++;
}
