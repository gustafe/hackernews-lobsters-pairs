#! /usr/bin/env perl
use Modern::Perl '2015';
###

use HNLOlib qw/$feeds get_ua get_dbh get_reddit get_reddit_items / ;
use DateTime;
use Getopt::Long;
use JSON;
use Term::ProgressBar 2.00;
sub usage {
    my ( $msg ) = @_;
    say $msg if $msg;
    say "usage: $0 --label={hn,lo,pr} --days=N | --month=YYYYMM";
    exit 1;

}
my $debug=1;
#sub get_reddit_items;
my $get_items = {pr => \&get_reddit_items,
		 hn=>\&get_web_items,
		 lo=>\&get_web_items,
		};
my $no_of_days;
my $label;
my $ym;
GetOptions('label=s'=>\$label,
	   'days=i'=> \$no_of_days,
	  'month=i' => \$ym);

usage unless ( defined $no_of_days or defined $ym );
if (defined $ym) {
    usage("Not a valid YYYYMM") unless $ym =~ m/\d{6}/;
}
#usage("Not a valid YYYYMM") if (defined $ym and $ym !~ m/\d{6}/);

usage("$label does not exist") unless exists $feeds->{$label};
usage("$label does not exist") unless exists $get_items->{$label};

my $sql;
if ($no_of_days ) {
    $sql = "select id from $feeds->{$label}->{table_name} where created_time >= datetime('now', '-$no_of_days day') order by created_time desc";
} elsif ($ym) {
    my ( $year, $month ) = $ym =~ m/(\d{4})(\d{2})/;
    usage("invalid month: $month") unless ( $month >=1 and $month <= 12);
    usage("no data earlier than 2019") if $year < 2019;
    my $from_dt = DateTime->new(
    year   => $year,
    month  => $month,
    day    => 1,
    hour   => 0,
    minute => 0,
    second => 0
			       );
    my $to_dt = DateTime->last_day_of_month(
    year   => $year,
    month  => $month,
    hour   => 23,
    minute => 59,
    second => 59

					   );
    $from_dt->subtract( days=>1);
    $to_dt->add( days=>1 );
    # select * from lobsters where  datetime(created_time) between datetime('2019-07-05T15:28:35') and datetime('2019-07-30T23:59:59')
    $sql = "select id from $feeds->{$label}->{table_name} where datetime(created_time) between '". $from_dt->iso8601() . "' and '".$to_dt->iso8601() ."'";
    printf("==> updating items from  %s between %s and %s\n",
       $label, map { $_->strftime('%Y-%m-%d %H:%M:%S') } ( $from_dt, $to_dt ));
    say "==> $sql";
}
#exit 0;
my $dbh=get_dbh;
my $ids = [map {$_->[0]} @{$dbh->selectall_arrayref( $sql )}] or die $dbh->errstr;
say "==> no. of items: ", scalar @$ids;

#exit 0 unless $label eq 'pr';

my ( $updates, $deletes ) = $get_items->{$label}->( $label, $ids );
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
if (@$deletes and $label ne 'pr') {
#if (@$deletes) {

    my $pholders = join(",", ("?") x @$deletes);
    my $to_deletes = $dbh->selectall_arrayref( "select id, title from $feeds->{$label}->{table_name} where id in ($pholders)",{},@$deletes) or die $dbh->errstr;
    say "The following items will be deleted:";
    foreach my $line (@$to_deletes) {
	say join("|", @$line);
    }


$sth = $dbh->prepare( $feeds->{$label}->{delete_sql}) or die $dbh->errstr;
say "deletes: ",join(' ', @$deletes);

foreach my $id (@$deletes) {
    $sth->execute( $id );

    $count++;
}
say "$count items deleted";
}

sub get_web_items {
    my ( $label,$items ) =@_;
    my %not_seen;
    my @updates;
    my $ua = get_ua();
    my $progress = Term::ProgressBar->new({name=>'Items',
					   count=>scalar @$items,
					   ETA=>'linear'});
    $progress->max_update_rate(1);
    my $next_update=0;
    my $count=0;
    foreach my $id (@$items) {
#	say "fetching $id" if $debug;
	my $href = $feeds->{$label}->{api_item_href} . $id . '.json';
	my $r = $ua->get( $href );
	if (!$r->is_success() ) {
	    $not_seen{$id}++;
	    $progress->message("no response for $id");
	    next;
	}
	my $json = decode_json( $r->decoded_content() );
	if (defined $json->{dead} or defined $json->{deleted}) {
	    $not_seen{$id}++ ;
	    $progress->message("$id is dead or deleted");
	    next;
	}


	my @binds = ( $json->{title},
			$json->{score},
		      $json->{$feeds->{$label}->{comments}});
	if (defined  $json->{tags}) {
	    push @binds, join(',',@{$json->{tags}}) }
#	    $progress->message("no relevant data for URL: \n".$feeds->{$label}->{title_href}.$id."\n".$feeds->{$label}->{api_item_href}.$id.'.json');

	$next_update = $progress->update( $count ) if $count >= $next_update;

	push @binds, $id ;
	push @updates, \@binds if scalar @binds > 1;
	$count++;
    }
    $progress->update( scalar @$items) if scalar @$items >= $next_update;
    my @deletes = keys %not_seen if scalar keys %not_seen > 0;
    return ( \@updates, \@deletes );

}
